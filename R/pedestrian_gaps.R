# Inventory-based pedestrian network completion; no implied ADA/route certification.
pedestrian_classes <- function(type) {
  out <- rep('unknown',length(type))
  out[type %in% c('EXISTING_SIDEWALK','DRIVEWAY','SHARED_USE_PATH','SHARED_STREET','PROTECTED_STREET_PATH')] <- 'completed'
  out[type %in% c('PLANNED_SIDEWALK','PLANNED_SHARED_STREET')] <- 'planned'
  out[type %in% 'POTENTIAL_SIDEWALK'] <- 'potential'
  out
}
pedestrian_inventory_files <- function(spec) {
  p <- file.path(spec$snapshot_dir,'manifest.json')
  if(!file.exists(p))stop('Run python3 scripts/pedestrian/fetch_inventory.py first.')
  m <- jsonlite::read_json(p,simplifyVector=TRUE)
  c(p,file.path(spec$snapshot_dir,m$files$path))
}
read_pedestrian_inventory <- function(files,spec) {
  m <- jsonlite::read_json(files[basename(files)=='manifest.json'],simplifyVector=TRUE)
  if(m$source_url!=spec$url)stop('Pedestrian source mismatch')
  for(i in seq_len(nrow(m$files))) {
    p <- files[basename(files)==m$files$path[i]]
    if(length(p)!=1 || digest::digest(file=p,algo='sha256')!=m$files$sha256[i])stop('Pedestrian checksum mismatch')
  }
  x <- dplyr::bind_rows(lapply(files[grepl('geojson$',files)],function(p) {
    z<-sf::st_read(p,quiet=TRUE)
    for(k in setdiff(names(z),attr(z,'sf_column')))z[[k]]<-as.character(z[[k]])
    z$OBJECTID<-as.integer(z$OBJECTID);z
  }))
  expected <- unlist(jsonlite::read_json(files[basename(files)=='source_ids.json']))
  if(anyDuplicated(x$OBJECTID)||!setequal(x$OBJECTID,expected)||nrow(x)!=m$feature_count)stop('Incomplete pedestrian source')
  if(any(!sf::st_is_valid(x)))stop('Invalid pedestrian geometry; inspect source')
  empty_ids<-x$OBJECTID[sf::st_is_empty(x)]
  # A retained source audit identifies records with no locatable geometry.
  x<-x[!sf::st_is_empty(x),]
  known <- c('EXISTING_SIDEWALK','DRIVEWAY','SHARED_USE_PATH','SHARED_STREET','PROTECTED_STREET_PATH','PLANNED_SIDEWALK','PLANNED_SHARED_STREET','POTENTIAL_SIDEWALK')
  if(any(!is.na(x$PEDESTRIAN_FACILITY_TYPE)&!x$PEDESTRIAN_FACILITY_TYPE %in% known))stop('Unexpected pedestrian category')
  x <- sf::st_zm(sf::st_transform(x,spec$crs)); x$classification <- pedestrian_classes(x$PEDESTRIAN_FACILITY_TYPE)
  list(lines=x,manifest=m,empty_geometry_ids=empty_ids)
}
# Retain only one-dimensional overlap; crossing points do not create shared length.
pedestrian_lines <- function(g) {
  g <- g[as.character(sf::st_geometry_type(g)) %in% c('LINESTRING','MULTILINESTRING','GEOMETRYCOLLECTION')]
  if(!length(g))return(g)
  g <- suppressWarnings(sf::st_collection_extract(g,'LINESTRING'))
  g <- suppressWarnings(sf::st_cast(g,'LINESTRING'))
  g[!sf::st_is_empty(g)&as.numeric(sf::st_length(g))>0]
}
pedestrian_union <- function(x) {
  if(!length(x))return(sf::st_sfc(sf::st_multilinestring(list()),crs=sf::st_crs(x)))
  sf::st_union(x)
}
prepare_pedestrian_network <- function(source,city,spec) {
  x <- source$lines
  city <- sf::st_union(sf::st_geometry(sf::st_transform(city,spec$crs)))
  cat('Selecting inventory in City footprint\n')
  hit <- unique(unlist(sf::st_intersects(city,x,prepared=TRUE)))
  inside <- unique(unlist(sf::st_covers(city,x,prepared=TRUE)))
  edge <- setdiff(hit,inside)
  cat(length(inside),'contained lines;',length(edge),'boundary lines to clip\n')
  raw <- dplyr::bind_rows(x[inside,],suppressWarnings(sf::st_intersection(x[edge,],city)))
  raw <- raw[as.numeric(sf::st_length(raw))>0,]
  raw$source_m <- as.numeric(sf::st_length(raw))
  raw$category <- ifelse(is.na(raw$PEDESTRIAN_FACILITY_TYPE),'UNKNOWN',raw$PEDESTRIAN_FACILITY_TYPE)
  category <- aggregate(source_m~category, sf::st_drop_geometry(raw),sum)
  category$features <- as.integer(table(raw$category)[category$category])
  # Dissolve same-category duplicates and overlaps, preserving parallel street sides.
  cat('Dissolving source overlaps by facility type\n')
  groups <- lapply(split(sf::st_geometry(raw),raw$category),pedestrian_union)
  category$unique_m <- vapply(category$category,function(k)sum(as.numeric(sf::st_length(groups[[k]]))),numeric(1))
  category$overlapping_m_removed <- pmax(0,category$source_m-category$unique_m)
  cat('Checking overlap between completed, planned, and potential facilities\n')
  merged <- lapply(c('completed','planned','potential','unknown'),function(k) {
    keys <- names(groups)[pedestrian_classes(names(groups))==k]
    if(!length(keys))return(sf::st_sfc(sf::st_multilinestring(list()),crs=spec$crs))
    pedestrian_union(do.call(c,groups[keys]))
  }); names(merged)<-c('completed','planned','potential','unknown')
  conflict <- pedestrian_lines(sf::st_intersection(merged$completed,merged$planned))
  conflict_m <- sum(as.numeric(sf::st_length(conflict)))
  if(length(conflict)) {
    merged$completed <- sf::st_difference(merged$completed,pedestrian_union(conflict))
    merged$planned <- sf::st_difference(merged$planned,pedestrian_union(conflict))
    merged$unknown <- pedestrian_union(c(merged$unknown,conflict))
  }
  # Potential is an alternative additional requirement, never a second copy of known length.
  merged$potential <- sf::st_difference(merged$potential,pedestrian_union(c(merged$completed,merged$planned,merged$unknown)))
  parts <- do.call(rbind,lapply(names(merged),function(k) {
    g<-pedestrian_lines(merged[[k]]);sf::st_sf(classification=rep(k,length(g)),geometry=g)
  }))
  # Diagnostic variants: source type lengths, separately dissolved and city-clipped.
  type_parts <- do.call(rbind,lapply(names(groups),function(k){g<-pedestrian_lines(groups[[k]]);sf::st_sf(category=rep(k,length(g)),geometry=g)}))
  list(lines=parts,type_lines=type_parts,category_audit=category,conflicting_completed_planned_m=conflict_m,
       city=city,source_manifest=source$manifest,empty_geometry_ids=source$empty_geometry_ids)
}
pedestrian_scores <- function(completed,planned,potential=0,unknown=0) {
  denom<-completed+planned; valid<-denom>0 & unknown<=1e-6
  bounded<-function(v)pmin(100,pmax(0,v))
  data.frame(completed_m=completed,planned_m=planned,potential_m=potential,unknown_m=unknown,
    denominator_m=denom,gap_score=ifelse(valid,bounded(100*planned/denom),NA_real_),
    known_inventory_gap_score=ifelse(denom>0,100*planned/denom,NA_real_),
    unknown_lower_score=ifelse(denom+unknown>0,100*planned/(denom+unknown),NA_real_),
    unknown_upper_score=ifelse(denom+unknown>0,100*(planned+unknown)/(denom+unknown),NA_real_),
    completeness_score=ifelse(valid,bounded(100*completed/denom),NA_real_),
    potential_included_score=ifelse(denom+potential>0 & unknown<=1e-6,bounded(100*(planned+potential)/(denom+potential)),NA_real_),
    status=ifelse(unknown>1e-6,'unclassified_inventory',ifelse(denom<=0,'no_classified_network','available_inventory')))
}
measure_pedestrian_windows <- function(windows,network,id='h3_id') {
  if(anyDuplicated(windows[[id]]))stop('Duplicate pedestrian window IDs')
  windows <- sf::st_transform(windows,sf::st_crs(network$lines))
  hits <- sf::st_intersects(windows,network$lines)
  out <- matrix(0,nrow(windows),4,dimnames=list(NULL,c('completed','planned','potential','unknown')))
  for(i in seq_len(nrow(windows))) {
    if(length(hits[[i]])) {
      p<-suppressWarnings(sf::st_intersection(network$lines[hits[[i]],],sf::st_geometry(windows[i,])))
      sums<-tapply(as.numeric(sf::st_length(p)),p$classification,sum);out[i,names(sums)]<-sums
    }
    if(i%%100==0)cat('Measured',i,'of',nrow(windows),'windows\n')
  }
  cbind(data.frame(h3_id=as.character(windows[[id]])),pedestrian_scores(out[,1],out[,2],out[,3],out[,4]))
}
build_pedestrian_measure <- function(source,hexes,city,spec) {
  network<-prepare_pedestrian_network(source,city,spec)
  full<-sf::st_transform(hexes,spec$crs)
  clipped<-suppressWarnings(sf::st_intersection(full,network$city))
  centers<-sf::st_sf(h3_id=full$h3_id,geometry=sf::st_transform(h3jsr::cell_to_point(full$h3_id),spec$crs))
  whole_windows<-sf::st_buffer(centers,dist=spec$buffer_m,nQuadSegs=90)
  windows<-suppressWarnings(sf::st_intersection(whole_windows,network$city))
  cat('Measuring city portions of hexes\n');h<-measure_pedestrian_windows(clipped,network)
  h$observed_area_share<-as.numeric(sf::st_area(clipped))/as.numeric(sf::st_area(full))[match(h$h3_id,full$h3_id)]
  cat('Measuring city portions of one-mile neighborhoods\n');w<-measure_pedestrian_windows(windows,network)
  w$observed_area_share<-as.numeric(sf::st_area(windows))/as.numeric(sf::st_area(whole_windows))[match(w$h3_id,whole_windows$h3_id)]
  h$boundary_partial<-h$observed_area_share<1-1e-6;w$boundary_partial<-w$observed_area_share<1-1e-6
  result<-list(network=network,hex=h,neighborhood=w,hex_geometry=full,windows=windows,spec=spec)
  audit_pedestrian_dates(source,result)
}
audit_pedestrian_dates <- function(source,result) {
  x<-sf::st_as_sf(source$lines)
  date<-suppressWarnings(as.numeric(x$DATE_CONSTRUCTION_COMPLETED))
  use<-x$classification=='planned' & !is.na(date) & date<=source$manifest$source_edit_ms
  dated<-x[use,]
  result$network$planned_with_completion_date_ids<-dated$OBJECTID
  for(k in c('hex','neighborhood')) {
    windows<-if(k=='hex')result$hex_geometry else result$windows
    amounts<-rep(0,nrow(windows))
    if(nrow(dated)) {
      g<-pedestrian_union(sf::st_geometry(dated))
      planned<-pedestrian_union(sf::st_geometry(result$network$lines[result$network$lines$classification=='planned',]))
      g<-pedestrian_lines(sf::st_intersection(g,planned))
      if(length(g)) {
        parts<-suppressWarnings(sf::st_intersection(windows,sf::st_sf(geometry=g)))
        sums<-tapply(as.numeric(sf::st_length(parts)),parts$h3_id,sum)
        amounts<-as.numeric(sums[match(windows$h3_id,names(sums))]);amounts[is.na(amounts)]<-0
      }
    }
    d<-result[[k]];d$dated_planned_m<-amounts[match(d$h3_id,windows$h3_id)]
    d$completion_date_review<-d$dated_planned_m>1e-6
    d$dated_as_completed_score<-ifelse(is.finite(d$gap_score),100*pmax(0,d$planned_m-d$dated_planned_m)/d$denominator_m,NA_real_)
    result[[k]]<-d
  }
  result
}
write_pedestrian_measure <- function(result,directory='output/components/pedestrian-gaps') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  for(k in c('hex','neighborhood'))write.csv(result[[k]],file.path(directory,paste0(k,'.csv')),row.names=FALSE,na='')
  write.csv(result$network$category_audit,file.path(directory,'category_audit.csv'),row.names=FALSE)
  for(k in c('hex','neighborhood')) {
    g<-sf::st_as_sf(if(k=='hex')result$hex_geometry else result$windows)
    g<-merge(g,result[[k]],by='h3_id',sort=FALSE)
    sf::st_write(g,file.path(directory,'pedestrian_gaps.gpkg'),layer=k,delete_layer=TRUE,quiet=TRUE)
  }
  jsonlite::write_json(list(schema_version=1,source=result$network$source_manifest,spec=result$spec,
    conflicting_completed_planned_m=result$network$conflicting_completed_planned_m,
    empty_geometry_ids=result$network$empty_geometry_ids,
    planned_with_completion_date_ids=result$network$planned_with_completion_date_ids,
    qualification='Inventory completion only. City-clipped observation area; inventory completeness not certified; no ADA, crossing or route-continuity assessment.'),
    file.path(directory,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,na='null',digits=15)
  sf::st_write(result$network$type_lines,file.path(directory,'pedestrian_gaps.gpkg'),layer='inventory_by_type',delete_layer=TRUE,quiet=TRUE)
  saveRDS(result,file.path(directory,'analysis.rds'))
  file.path(directory,c('hex.csv','neighborhood.csv','category_audit.csv','pedestrian_gaps.gpkg','metadata.json','analysis.rds'))
}
