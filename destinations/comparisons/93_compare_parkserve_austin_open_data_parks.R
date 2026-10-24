# Compare ParkServe open-access polygons with City of Austin park assets.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "digest", "ggplot2"))
source("destinations/R/destination_paths.R")
out <- destination_comparison_dir("parks_parkserve_austin_open_data")
ps_path <- file.path(destination_dir("parks","processed"),"parks_parkserve_austin_metro.gpkg")
city_path <- file.path(destination_dir("parks","raw","austin_open_data",create=FALSE),"parks.geojson")
boundary_path <- "accessibility/data/cache/tigris/tl_2024_48_place.shp"
stopifnot(file.exists(ps_path),file.exists(city_path),file.exists(boundary_path))
crs_work <- 26914
boundary <- st_read(boundary_path,quiet=TRUE) |> filter(NAME=="Austin") |> st_make_valid() |> st_transform(crs_work)
city <- st_read(city_path,quiet=TRUE) |> st_make_valid() |> st_transform(crs_work) |>
 mutate(city_park_id=coalesce(na_if(as.character(asset_mgmt_id),""),paste0("object_",objectid))) |>
 group_by(city_park_id) |> summarise(city_name=paste(sort(unique(location_name)),collapse=" / "),
 city_park_type=paste(sort(unique(park_type)),collapse=" / "),
 development_status=paste(sort(unique(development_status)),collapse=" / "),
 asset_status=paste(sort(unique(asset_status)),collapse=" / "),.groups="drop")
city <- city[lengths(st_intersects(city,boundary))>0,]
ps_all <- st_read(ps_path,layer="all_parkserve_records",quiet=TRUE) |> st_make_valid() |> st_transform(crs_work)
ps_open <- filter(ps_all,open_access)
ps_open <- ps_open[lengths(st_intersects(ps_open,boundary))>0,]

name_key <- function(z) {
 z<-iconv(z,to="ASCII//TRANSLIT"); z[is.na(z)]<-""; z<-tolower(gsub("[^[:alnum:] ]"," ",z))
 z<-gsub("\\b(neighborhood|metropolitan|district|regional|pocket|public|park|parks|preserve|greenbelt)\\b"," ",z)
 trimws(gsub(" +"," ",z))
}
# Candidate pairs are intersecting or within 100 metres. Distances are polygon-to-polygon.
hits <- st_is_within_distance(city,ps_open,dist=100)
pairs <- tibble(city_i=rep(seq_len(nrow(city)),lengths(hits)),ps_i=unlist(hits))
if (!nrow(pairs)) stop("No candidate pairs")
pairs <- pairs |> mutate(
 city_park_id=city$city_park_id[city_i],city_name=city$city_name[city_i],
 parkid=ps_open$parkid[ps_i],parkserve_name=ps_open$park_name[ps_i],
 distance_m=as.numeric(st_distance(city[city_i,],ps_open[ps_i,],by_element=TRUE)),
 intersects=distance_m<0.001,
 name_similarity={a<-name_key(city$city_name[city_i]);b<-name_key(ps_open$park_name[ps_i]);
  d<-diag(adist(a,b)); den<-pmax(nchar(a),nchar(b)); ifelse(den>0,1-d/den,0)},
 match_class=case_when(name_similarity>=0.60 & distance_m<=100~"likely_same_park",
                       intersects~"spatial_review",TRUE~"nearby_review"),
 match_score=if_else(intersects,1,0)+name_similarity-distance_m/1000) |>
 arrange(city_park_id,desc(match_score)) |> group_by(city_park_id) |> mutate(best_for_city=row_number()==1) |> ungroup()
# Best candidate for each ParkServe feature as a reciprocal diagnostic.
pairs <- pairs |> group_by(parkid) |> arrange(desc(match_score),.by_group=TRUE) |> mutate(best_for_parkserve=row_number()==1) |> ungroup()
city_best <- pairs |> filter(best_for_city) |> select(city_park_id,parkid,parkserve_name,distance_m,name_similarity,match_class)
ps_best <- pairs |> filter(best_for_parkserve) |> select(parkid,city_park_id,city_name,distance_m,name_similarity,match_class)
city_review <- city |> left_join(st_drop_geometry(city_best),by="city_park_id") |>
 mutate(comparison_status=case_when(is.na(parkid)~"no_parkserve_within_100m",match_class=="likely_same_park"~"likely_match",TRUE~"manual_review"))
ps_review <- ps_open |> left_join(st_drop_geometry(ps_best),by="parkid") |>
 mutate(comparison_status=case_when(is.na(city_park_id)~"no_city_park_within_100m",match_class=="likely_same_park"~"likely_match",TRUE~"manual_review"))
summary <- bind_rows(
 tibble(measure=c("City assets intersecting Austin","ParkServe open-access records intersecting Austin",
                  "City assets with likely ParkServe match","City assets needing spatial/name review","City assets with no ParkServe within 100m",
                  "ParkServe records with likely City match","ParkServe records needing spatial/name review","ParkServe records with no City park within 100m"),
        records=c(nrow(city),nrow(ps_open),sum(city_review$comparison_status=="likely_match"),sum(city_review$comparison_status=="manual_review"),sum(city_review$comparison_status=="no_parkserve_within_100m"),sum(ps_review$comparison_status=="likely_match"),sum(ps_review$comparison_status=="manual_review"),sum(ps_review$comparison_status=="no_city_park_within_100m"))))
write_csv(summary,file.path(out,"comparison_summary.csv"))
write_csv(st_drop_geometry(city_review),file.path(out,"city_park_review.csv"),na="")
write_csv(st_drop_geometry(ps_review),file.path(out,"parkserve_austin_review.csv"),na="")
write_csv(select(pairs,-city_i,-ps_i,-match_score),file.path(out,"candidate_matches_within_100m.csv"),na="")
county_summary <- st_drop_geometry(ps_all) |> count(park_county,open_access,name="records")
write_csv(county_summary,file.path(out,"parkserve_county_summary.csv"))
manifest_paths<-c(ps_path,city_path,boundary_path)
write_csv(tibble(path=manifest_paths,sha256=vapply(manifest_paths,function(p)digest::digest(file=p,algo="sha256"),character(1)),comparison_date=as.character(Sys.Date())),file.path(out,"input_manifest.csv"))
gpkg<-file.path(out,"parkserve_austin_comparison.gpkg");if(file.exists(gpkg))file.remove(gpkg)
st_write(city_review,gpkg,layer="austin_city_parks_review",quiet=TRUE)
st_write(ps_review,gpkg,layer="parkserve_open_access_austin",quiet=TRUE)
st_write(ps_all,gpkg,layer="parkserve_all_metro",quiet=TRUE)
st_write(filter(ps_all,open_access),gpkg,layer="parkserve_open_access_metro",quiet=TRUE)
map<-ggplot()+geom_sf(data=boundary,fill="white",colour="grey55",linewidth=.25)+
 geom_sf(data=ps_open,fill="#e7a64a55",colour="#b66b00",linewidth=.2)+
 geom_sf(data=city,fill="#2f78b755",colour="#1f4e79",linewidth=.25)+
 labs(title="ParkServe compared with City of Austin park assets",subtitle="Open-access ParkServe polygons in Austin; overlapping polygons may represent the same park",
 caption="Blue: City of Austin assets | Orange: ParkServe open-access parks. Matching uses polygon proximity and normalized names.")+theme_void(base_size=11)+theme(plot.title=element_text(face="bold"))
ggsave(file.path(out,"parkserve_austin_comparison.png"),map,width=10,height=10,dpi=160,bg="white")
lines<-c("# ParkServe and City of Austin park comparison","",
 paste0("ParkServe supplied ",nrow(ps_all)," metro records; ",sum(ps_all$open_access)," meet its documented open-access and operational rule."),"",
 paste0("Within Austin, the comparison includes ",nrow(ps_open)," open-access ParkServe records and ",nrow(city)," distinct City park assets."),"",
 "A likely match requires polygons within 100 metres and normalized name similarity of at least 0.60. Spatially overlapping records with dissimilar names remain review candidates because adjacent facilities, nested assets, and alternate names can create ambiguity.","",
 "## Summary","","| Measure | Records |","|---|---:|")
for(i in seq_len(nrow(summary)))lines<-c(lines,sprintf("| %s | %d |",summary$measure[i],summary$records[i]))
lines<-c(lines,"","## Interpretation","",
 "ParkServe is a useful standardized metro-wide baseline, but it should not replace the current City source inside Austin. It contains private, HOA, unknown-access, undeveloped, and closed records in the complete layer; only the documented open-access subset is used for opportunity screening.","",
 "City records without a likely ParkServe match do not automatically indicate ParkServe omissions, and ParkServe-only records do not automatically indicate City omissions. Review alternate names, ownership, park type, parcel subdivision, and access before merging.","",
 "Use ParkServe to extend coverage into municipalities outside Austin. Retain City and county government inventories as preferred records where they are current, then deduplicate ParkServe records against them.")
writeLines(lines,file.path(out,"parkserve_austin_assessment.md"))
print(summary,n=Inf)
