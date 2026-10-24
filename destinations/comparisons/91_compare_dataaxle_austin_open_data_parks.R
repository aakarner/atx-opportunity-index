# Compare saved Data Axle park points to saved City park boundaries.
# Spatial proximity is a coverage proxy, not confirmed business identity.
#
# Inputs: data/destinations/parks/raw/dataaxle/*.csv and
#         data/destinations/parks/raw/austin_open_data/parks.geojson
# Writes: data/destinations/comparisons/parks_dataaxle_austin_open_data/
#
#   Rscript destinations/comparisons/91_compare_dataaxle_austin_open_data_parks.R
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "digest", "ggplot2"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_helpers.R")
out <- destination_comparison_dir("parks_dataaxle_austin_open_data")
city_path <- file.path(destination_dir("parks", "raw", "austin_open_data", create = FALSE), "parks.geojson")
boundary_path <- "accessibility/data/cache/tigris/tl_2024_48_place.shp"
files <- sort(list.files(destination_dir("parks", "raw", "dataaxle", create = FALSE),pattern="[.]csv$",full.names=TRUE,ignore.case=TRUE))
stopifnot(length(files)>0, file.exists(city_path), file.exists(boundary_path))
raw <- bind_rows(lapply(files, ax_read, collection="parks"))
a <- ax_consolidate(raw)
a$valid_coordinates <- is.finite(a$latitude) & is.finite(a$longitude) &
  abs(a$latitude)<=90 & abs(a$longitude)<=180
readr::write_csv(a[!a$valid_coordinates,],file.path(out,"invalid_dataaxle_coordinates.csv"))
p <- st_as_sf(a[a$valid_coordinates,],coords=c("longitude","latitude"),crs=4326,remove=FALSE) %>% st_transform(26914)
boundary <- st_read(boundary_path,quiet=TRUE) %>% filter(NAME=="Austin") %>% st_make_valid() %>% st_transform(26914)
stopifnot(nrow(boundary)==1)
c <- st_read(city_path,quiet=TRUE) %>% st_make_valid() %>% st_transform(26914)
c$park_id <- coalesce(na_if(as.character(c$asset_mgmt_id),""), paste0("object_",c$objectid))
# Merge repeated geometry records for a City asset to avoid polygon-part inflation.
c <- c %>% group_by(park_id) %>% summarise(
 name=paste(sort(unique(location_name)),collapse=" / "),
 park_type=paste(sort(unique(park_type)),collapse=" / "),
 development_status=paste(sort(unique(development_status)),collapse=" / "),
 asset_status=paste(sort(unique(asset_status)),collapse=" / "), .groups="drop")
c$intersects_austin <- lengths(st_intersects(c,boundary))>0
c$open_developed <- grepl("^Level [1-4] Developed$",c$development_status,ignore.case=TRUE) &
 tolower(c$asset_status)=="open" & !c$park_type %in%
 c("Cemetery","Golf Course","Nature Preserve","Planting Strips/Triangles","Button","Button Park")
p$inside_austin <- lengths(st_intersects(p,boundary))>0
city_ref <- c[c$intersects_austin,]
pts <- p[p$inside_austin,]
stopifnot(nrow(city_ref)>0,nrow(pts)>0)
d <- matrix(as.numeric(st_distance(pts,city_ref)),nrow=nrow(pts),ncol=nrow(city_ref))
# Normalize punctuation and common facility suffixes, preserving distinctive names.
name_key <- function(z) {
 z <- iconv(z,to="ASCII//TRANSLIT"); z[is.na(z)] <- ""
 z <- tolower(gsub("[^[:alnum:] ]"," ",z))
 z <- gsub("\\b(neighborhood|metropolitan|district|pocket|public|park|parks)\\b"," ",z)
 trimws(gsub(" +"," ",z))
}
pkeys <- name_key(pts$name); ckeys <- name_key(city_ref$name)
name_distance <- adist(pkeys,ckeys)
name_similarity <- 1-name_distance/outer(nchar(pkeys),nchar(ckeys),pmax)
name_similarity[!is.finite(name_similarity)] <- 0
# Search names across all Data Axle points, including those whose supplied
# coordinates place them outside Austin. Avoid silently calling these omissions.
all_sim <- 1-adist(name_key(p$name),ckeys)/outer(nchar(name_key(p$name)),nchar(ckeys),pmax)
all_sim[!is.finite(all_sim)] <- 0
all_best <- max.col(all_sim,ties.method="first")
all_name_audit <- st_drop_geometry(p) %>% mutate(
  candidate_city_park=city_ref$name[all_best],
  candidate_name_similarity=all_sim[cbind(seq_len(nrow(p)),all_best)],
  candidate_polygon_distance_m=as.numeric(st_distance(p,city_ref[all_best,],by_element=TRUE)))
readr::write_csv(all_name_audit,file.path(out,"all_dataaxle_name_candidates.csv"))

nearest <- max.col(-d,ties.method="first")
idx <- cbind(seq_len(nrow(pts)),nearest)
point_review <- pts %>% st_drop_geometry() %>% mutate(
 nearest_city_park_id=city_ref$park_id[nearest],nearest_city_park=city_ref$name[nearest],
 nearest_city_park_type=city_ref$park_type[nearest],distance_to_boundary_m=d[idx],
 nearest_name_similarity=name_similarity[idx],
 city_parks_within_100m=rowSums(d<=100),city_parks_within_250m=rowSums(d<=250),
 spatial_relation=case_when(d[idx]<=0.001~"inside_or_on_city_park",d[idx]<=100~"within_100m",
 d[idx]<=250~"within_250m",d[idx]<=500~"within_500m",TRUE~"beyond_500m"))
# Include all nearby candidates; nearest polygons can be ambiguous in park complexes.
pairs <- which(d<=500,arr.ind=TRUE)
candidates <- tibble(destination_id=pts$destination_id[pairs[,1]],dataaxle_name=pts$name[pairs[,1]],
 park_id=city_ref$park_id[pairs[,2]],city_name=city_ref$name[pairs[,2]],park_type=city_ref$park_type[pairs[,2]],
 distance_m=d[pairs],name_similarity=name_similarity[pairs],
 review_decision="",review_notes="") %>% arrange(destination_id,distance_m,desc(name_similarity))
# Independent strongest-name candidates can expose apparently misplaced coordinates.
best_name <- max.col(name_similarity,ties.method="first")
point_review$best_name_city_park <- city_ref$name[best_name]
point_review$best_name_similarity <- name_similarity[cbind(seq_len(nrow(pts)),best_name)]
point_review$best_name_distance_m <- d[cbind(seq_len(nrow(pts)),best_name)]
point_review$manual_match_decision <- ""
point_review$manual_match_notes <- ""
city_review <- city_ref %>% st_drop_geometry() %>% mutate(
 nearest_dataaxle_name=pts$name[max.col(-t(d),ties.method="first")],
 nearest_dataaxle_distance_m=apply(d,2,min),
 points_inside=colSums(d<=0.001),points_within_100m=colSums(d<=100),
 points_within_250m=colSums(d<=250),points_within_500m=colSums(d<=500))
metrics <- bind_rows(lapply(c("all_city_parks","open_developed_subset"), function(scope) {
 use <- if(scope=="all_city_parks") rep(TRUE,nrow(city_ref)) else city_ref$open_developed
 if(!any(use)) stop("Empty City reference subset")
 bind_rows(lapply(c(0,100,250,500),function(threshold) {
 hit <- d[,use,drop=FALSE]<=max(threshold,0.001)
 tibble(reference_scope=scope,threshold_m=threshold,dataaxle_points_in_austin=nrow(pts),
 city_reference_parks=sum(use),dataaxle_points_near_reference=sum(rowSums(hit)>0),
 percent_dataaxle_near_reference=100*mean(rowSums(hit)>0),
 city_parks_with_dataaxle_point=sum(colSums(hit)>0),
 percent_city_parks_covered=100*mean(colSums(hit)>0))
 }))
}))
by_type <- city_review %>% group_by(park_type) %>% summarise(city_parks=n(),
 parks_with_point_inside=sum(points_inside>0),parks_with_point_within_100m=sum(points_within_100m>0),
 percent_covered_100m=100*mean(points_within_100m>0),.groups="drop") %>% arrange(desc(city_parks))
for(z in list(list(metrics,"coverage_sensitivity.csv"),list(point_review,"dataaxle_point_review.csv"),
 list(city_review,"city_park_review.csv"),list(candidates,"candidate_matches_within_500m.csv"),
 list(by_type,"coverage_by_park_type.csv"),list(st_drop_geometry(p[!p$inside_austin,]),"dataaxle_outside_austin.csv")))
 readr::write_csv(z[[1]],file.path(out,z[[2]]))
manifest_paths <- c(files,city_path,boundary_path)
readr::write_csv(tibble(path=manifest_paths,sha256=vapply(manifest_paths,function(f) digest::digest(file=f,algo="sha256"),character(1)),
 comparison_date=as.character(Sys.Date())),file.path(out,"input_manifest.csv"))
city_ref$coverage <- ifelse(city_review$points_within_100m>0,"City park with nearby Data Axle point","City park without nearby Data Axle point")
pts$relation <- ifelse(point_review$distance_to_boundary_m<=100,"Within 100 m of City park","More than 100 m from City park")
map <- ggplot()+geom_sf(data=boundary,fill="white",colour="grey65",linewidth=.25)+
 geom_sf(data=city_ref,aes(fill=coverage),colour=NA)+
 geom_sf(data=pts,aes(colour=relation),size=1.3,alpha=.8)+
 scale_fill_manual(values=c("City park with nearby Data Axle point"="#5db59b","City park without nearby Data Axle point"="#d9d9d9"),name=NULL)+
 scale_colour_manual(values=c("Within 100 m of City park"="#07594b","More than 100 m from City park"="#d34a32"),name=NULL)+
 labs(title="Data Axle parks compared with City of Austin park boundaries",
 subtitle="Common Austin geography; proximity within 100 metres is a candidate match, not confirmed identity",
 caption="Saved local snapshots. City polygons include all park types and development statuses. Points outside Austin are evaluated separately.")+
 theme_void(base_size=11)+theme(legend.position="bottom",legend.box="vertical",plot.title=element_text(face="bold"),plot.caption=element_text(size=8))
ggsave(file.path(out,"parks_source_comparison.png"),map,width=12,height=11,dpi=160,bg="white")
gpkg <- file.path(out,"parks_source_comparison.gpkg")
st_write(city_ref,gpkg,layer="city_reference",delete_layer=TRUE,quiet=TRUE)
st_write(pts,gpkg,layer="dataaxle_inside_austin",delete_layer=TRUE,quiet=TRUE)
st_write(p[!p$inside_austin,],gpkg,layer="dataaxle_outside_austin",delete_layer=TRUE,quiet=TRUE)
stopifnot(nrow(point_review)==nrow(pts),nrow(city_review)==nrow(city_ref),
 all(metrics$city_parks_with_dataaxle_point<=metrics$city_reference_parks),
 all(metrics$dataaxle_points_near_reference<=nrow(pts)))
for(scope in unique(metrics$reference_scope)) {
 m<-metrics[metrics$reference_scope==scope,]
 stopifnot(all(diff(m$city_parks_with_dataaxle_point)>=0),all(diff(m$dataaxle_points_near_reference)>=0))
}
lines <- c("# Data Axle parks source assessment","",
 paste0("Data Axle: ",nrow(raw)," source rows, ",nrow(a)," consolidated records, ",nrow(pts)," points in Austin, ",sum(!p$inside_austin)," valid points outside Austin."),"",
 paste0("City: ",nrow(c)," distinct park assets after dissolving repeated asset IDs; ",nrow(city_ref)," intersect Austin; ",sum(city_ref$open_developed)," meet the open/developed subset definition."),"",
 "## Coverage sensitivity","",
 "| Reference | Distance (m) | Data Axle near reference | Share of Data Axle | City parks represented | Share of City parks |",
 "|---|---:|---:|---:|---:|---:|")
for(i in seq_len(nrow(metrics))) {m<-metrics[i,];lines<-c(lines,sprintf("| %s | %d | %d / %d | %.1f%% | %d / %d | %.1f%% |",m$reference_scope,m$threshold_m,m$dataaxle_points_near_reference,m$dataaxle_points_in_austin,m$percent_dataaxle_near_reference,m$city_parks_with_dataaxle_point,m$city_reference_parks,m$percent_city_parks_covered))}
lines<-c(lines,"","## Main findings","",
 "The supplied Data Axle extract should not be used as the sole park inventory or trusted as routing-ready coordinates. Spatial overlap with this City reference is low, and some same-name listings are kilometres from the corresponding polygon. These findings apply to this extract, query scope, and saved snapshots, not every Data Axle product or export.","",
 "For Austin municipal parks, use the City asset inventory as the starting reference and establish suitable public entrances for routing. Keep Data Axle as a supplementary candidate inventory for parks outside City ownership/coverage, subject to classification and location checks.","",
 "Name-based discrepancy examples (candidate identities require review):")
for (label in c("Bull Creek District Park","Balcones District Park","Mayfield Park")) {
 ex<-point_review[point_review$name==label,]
 if(nrow(ex)) lines<-c(lines,sprintf("- %s: %.2f km from the City polygon named %s.",label,ex$best_name_distance_m[1]/1000,ex$best_name_city_park[1]))
}
lines<-c(lines,"","## Interpretation and next checks","",
 "These are spatial coverage proxies, not validated precision or recall. A nearby listing can name another facility, while a genuine park listing can sit at an entrance or office outside its polygon. Many-to-many matches and adjacent parks can inflate represented-park counts. Review candidate pairs and names before reporting definitive source accuracy.","",
 "Because coordinate errors can also move points across the Austin boundary, the 44-point common-geography comparison is conditional on the supplied coordinates; all_dataaxle_name_candidates.csv includes name checks for all records. The comparison uses Data Axle points inside/on the cached 2024 Austin boundary and City park assets intersecting that boundary. Data Axle points outside Austin are reported separately, not labeled false positives. The City inventory is an administrative reference, not a complete census of every public/private/regional recreational opportunity. Reference assets retain their full polygons, including portions outside the boundary.","",
 "Open/developed subset: exact Level 1–4 Developed statuses, asset status Open, excluding Cemetery, Golf Course, Nature Preserve, Planting Strips/Triangles, Button and Button Park. This follows the project's earlier substantive exclusions but explicitly excludes Undeveloped. This is one sensitivity definition, not a universal definition of parks.","",
 "Distances are point-to-polygon distances in NAD83 / UTM zone 14N (metres), not point-to-centroid errors. Zero means inside/on the polygon. Name similarity is normalized edit similarity after removing common park suffixes; it suggests review candidates and does not establish identity.","",
 "The download vintages may differ. The manifest hashes the supplied snapshots; current source completeness and temporal differences have not been independently verified. Missing City matches therefore require review of geography, ownership, status, and name before interpreting them as source errors.","",
 "Files: coverage_sensitivity.csv, coverage_by_park_type.csv, dataaxle_point_review.csv, city_park_review.csv, candidate_matches_within_500m.csv, dataaxle_outside_austin.csv, parks_source_comparison.gpkg, parks_source_comparison.png. Copy review tables before editing; rerunning regenerates these outputs.","",
 "![Source comparison](parks_source_comparison.png)")
writeLines(lines,file.path(out,"parks_source_assessment.md"))
print(metrics,width=Inf);print(by_type,width=Inf)
