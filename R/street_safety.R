# Higher scores mean greater burden. Fixed anchors are policy, not recalculated quantiles.
score_street_safety <- function(x, policy) {
  s <- policy$scoring; weights <- unlist(policy$weights)
  stopifnot(is.finite(s$crash_full_burden_density), s$crash_full_burden_density>0,
    s$crash_high_burden_density>0, s$crash_high_burden_density<=s$crash_full_burden_density,
    s$pedestrian_high_burden_score>=0,s$pedestrian_high_burden_score<=100,
    all(is.finite(weights)), all(weights>=0), abs(sum(weights)-1)<1e-12)
  if(any(x$annual_ksi_density<0,na.rm=TRUE) || any(x$gap_score<0 | x$gap_score>100,na.rm=TRUE))
    stop('Invalid raw street-safety measure')
  density <- x$annual_ksi_density; gap <- x$gap_score
  density[!is.finite(density)]<-NA_real_;gap[!is.finite(gap)]<-NA_real_
  x$crash_score <- pmin(100,100*density/s$crash_full_burden_density)
  x$pedestrian_gap_score <- gap
  x$street_safety_score <- weights[['crash_density']]*x$crash_score + weights[['pedestrian_gaps']]*gap
  x$crash_high <- density>=s$crash_high_burden_density
  x$pedestrian_high <- gap>=s$pedestrian_high_burden_score
  # R's three-valued OR retains known warnings but never infers a pass from missing data.
  x$any_high <- x$crash_high | x$pedestrian_high
  x$score_status <- ifelse(is.finite(x$street_safety_score),'available','unavailable')
  x$flag_status <- ifelse(is.na(x$any_high),'Incomplete assessment',
    ifelse(x$any_high,'High component burden','Below both flags'))
  both_known <- !is.na(x$crash_high)&!is.na(x$pedestrian_high)
  x$flag_detail <- 'Incomplete assessment'
  x$flag_detail[which(both_known & !x$any_high)] <- 'Below both flags'
  x$flag_detail[which(both_known & x$crash_high & !x$pedestrian_high)] <- 'Crash only'
  x$flag_detail[which(both_known & !x$crash_high & x$pedestrian_high)] <- 'Gaps only'
  x$flag_detail[which(both_known & x$crash_high & x$pedestrian_high)] <- 'Both components'
  x$flag_detail[which(!both_known & x$any_high)] <- 'High; other component unavailable'
  x$scoring_version <- s$version
  x
}

build_street_safety <- function(pedestrian, inventory, crashes, population, policy) {
  s <- policy$scoring; crs <- sf::st_crs(pedestrian$hex_geometry)
  crashes <- sf::st_transform(crashes,crs)
  years <- seq(s$crash_first_year,s$crash_last_year)
  if(anyNA(crashes$crash_id)||anyDuplicated(crashes$crash_id)||anyNA(crashes$ksi_crash)||
     !all(crashes$ksi_crash)||anyNA(crashes$crash_year)||!all(crashes$crash_year %in% years))
    stop('Crash records do not match the configured KSI observation period')
  centers <- sf::st_sf(h3_id=pedestrian$hex_geometry$h3_id,
    geometry=sf::st_transform(h3jsr::cell_to_point(pedestrian$hex_geometry$h3_id),crs))
  population <- as.data.frame(population)
  stopifnot(!anyDuplicated(centers$h3_id),!anyDuplicated(population$h3_id))
  results<-list(); windows_out<-list()
  radii<-c(primary=policy$spatial_review$adopted_radius_miles,sensitivity=policy$spatial_review$sensitivity_radius_miles)
  for(k in names(radii)) {
    radius<-radii[[k]];cat('Street safety:',k,radius,'mile\n')
    full<-sf::st_buffer(centers,radius*1609.344,nQuadSegs=90)
    windows<-suppressWarnings(sf::st_intersection(full,pedestrian$network$city))
    windows<-windows[!sf::st_is_empty(windows)&as.numeric(sf::st_area(windows))>0,]
    stopifnot(!anyDuplicated(windows$h3_id))
    gaps<-measure_pedestrian_windows(windows,pedestrian$network)
    # Preserve the source's planned-with-completion-date review flag at each radius.
    audited<-audit_pedestrian_dates(inventory,list(network=pedestrian$network,
      hex=pedestrian$hex,hex_geometry=pedestrian$hex_geometry,neighborhood=gaps,windows=windows))
    gaps<-audited$neighborhood
    hits<-sf::st_intersects(windows,crashes)
    count<-function(flag=rep(TRUE,nrow(crashes)))vapply(hits,function(i)sum(flag[i]),integer(1))
    area<-as.numeric(sf::st_area(windows))/2589988.110336
    raw<-data.frame(h3_id=windows$h3_id,observed_area_sqmi=area,
      observed_area_share=as.numeric(sf::st_area(windows))/as.numeric(sf::st_area(full))[match(windows$h3_id,full$h3_id)],
      ksi_count=count(),vru_ksi_count=count(crashes$vulnerable_road_user_ksi_crash),
      observation_years=length(years))
    raw$annual_ksi_density<-raw$ksi_count/(length(years)*area)
    raw<-merge(raw,gaps,by='h3_id',all.x=TRUE,sort=FALSE)
    raw<-merge(data.frame(h3_id=centers$h3_id),raw,by='h3_id',all.x=TRUE,sort=FALSE)
    raw$status[is.na(raw$observed_area_sqmi)]<-'no_city_observation_area'
    raw<-merge(raw,population[,c('h3_id','total_population','children_under_18')],by='h3_id',all.x=TRUE,sort=FALSE)
    raw$radius_miles<-radius;raw$scenario<-k
    results[[k]]<-score_street_safety(raw,policy);windows_out[[k]]<-windows
  }
  list(results=results,windows=windows_out,geometry=pedestrian$hex_geometry,policy=policy,
    provenance=list(pedestrian_source=pedestrian$network$source_manifest,
      pedestrian_policy=pedestrian$spec,crash_point_count=nrow(crashes),
      crash_data_sha256=digest::digest(crashes,algo='sha256'),
      hex_geometry_sha256=digest::digest(pedestrian$hex_geometry,algo='sha256'),
      reference='Frozen quantiles of all 1,029 half-mile origins; 2020–2024 KSI; R type 7, unweighted',
      interpretation='Area density, not exposure-adjusted crash risk. Zero history does not establish safety.'))
}

write_street_safety <- function(result,directory='output/components/street-safety') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  files<-character()
  for(k in names(result$results)) {
    path<-file.path(directory,paste0(k,'.csv'))
    utils::write.csv(result$results[[k]],path,row.names=FALSE,na='');files<-c(files,path)
    g<-merge(sf::st_as_sf(result$geometry),result$results[[k]],by='h3_id',all.x=TRUE,sort=FALSE)
    sf::st_write(g,file.path(directory,'street_safety.gpkg'),layer=paste0(k,'_hex'),delete_layer=TRUE,quiet=TRUE)
    w<-merge(sf::st_as_sf(result$windows[[k]]),result$results[[k]],by='h3_id',all.x=TRUE,sort=FALSE)
    sf::st_write(w,file.path(directory,'street_safety.gpkg'),layer=paste0(k,'_windows'),delete_layer=TRUE,quiet=TRUE)
  }
  jsonlite::write_json(list(policy=result$policy,provenance=result$provenance),file.path(directory,'metadata.json'),
    auto_unbox=TRUE,pretty=TRUE,na='null',digits=17)
  saveRDS(result,file.path(directory,'analysis.rds'))
  c(files,file.path(directory,c('street_safety.gpkg','metadata.json','analysis.rds')))
}
