# Run after rebuilding scoring_schools/school_coverage. Audit the complete
# municipal district inventory, including districts with no prototype origin.
source("scripts/prepare/packages.R")
setup_project_packages(c("sf", "dplyr", "readr", "targets", "h3jsr"))
source("R/pipeline_sites.R")
raw <- "data/raw/elementary_boundaries/2026_27"
qa <- "data/qaqc/elementary_access"
districts <- st_transform(st_read(file.path(raw,"district_inventory.geojson"),quiet=TRUE),5070)
city <- st_transform(tar_read(city_boundary),5070)
h <- tar_read(h8_geometry)
origins <- st_sf(site_id=h$h3_id,geometry=st_transform(cell_to_point(h$h3_id),5070))
zones <- st_read("data/processed/school_indicators/elementary_growth_assignments_2026_27.gpkg",quiet=TRUE)
full <- school_at_sites(origins,zones)
old_ids <- c("227901","246909","227904","227910","227907")
old <- school_at_sites(origins,zones[zones$district_id %in% old_ids,])
hits <- st_intersects(districts,origins)
inventory <- st_drop_geometry(districts)["NAME"]
inventory$city_area_sq_km <- vapply(seq_len(nrow(districts)),function(i)
  sum(as.numeric(st_area(suppressWarnings(st_intersection(districts[i,],city)))))/1e6,numeric(1))
inventory$origins <- lengths(hits)
inventory$assigned_origins <- vapply(hits,function(ix)sum(!is.na(full$campus_id[ix])),integer(1))
inventory$previously_assigned_origins <- vapply(hits,function(ix)sum(!is.na(old$campus_id[ix])),integer(1))
inventory$attendance_source <- ifelse(inventory$NAME=="Hays Cons ISD","Hays CISD",inventory$NAME) %in% unique(zones$district_name)
write_csv(inventory,file.path(qa,"district_footprint_inventory.csv"))
origin_districts <- st_intersects(origins,districts)
full$district_footprint <- vapply(origin_districts,function(ix)paste(districts$NAME[ix],collapse="; "),character(1))
full$previous_campus_id <- old$campus_id
full$previous_status <- old$status
write_csv(full,file.path(qa,"origin_assignment_audit.csv"),na="")
write_csv(full[is.na(full$campus_id),],file.path(qa,"remaining_assignment_gaps.csv"),na="")

# Document source-footprint disagreement and within-district geometry overlaps;
# do not snap, clip, or fill any district locator to the independent inventory.
projected <- st_transform(zones,5070)
geometry <- bind_rows(lapply(split(seq_len(nrow(zones)),zones$district_name),function(ix) {
  x <- projected[ix,]
  data.frame(district=zones$district_name[ix[1]], area_sq_km=as.numeric(st_area(st_union(x)))/1e6,
    overlap_excess_sq_m=max(0,sum(as.numeric(st_area(x)))-as.numeric(st_area(st_union(x)))))
}))
write_csv(geometry,file.path(qa,"district_geometry.csv"))
print(inventory)
print(table(full$status))
