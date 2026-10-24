# Build standardized ParkServe polygon layers for the five-county Austin metro.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "jsonlite"))
source("destinations/R/destination_paths.R")
raw_dir <- destination_dir("parks", "raw", "parkserve", create = FALSE)
files <- sort(list.files(raw_dir, pattern = "parkserve_metro_page_[0-9]+[.]geojson$", full.names = TRUE))
if (!length(files)) stop("Run destinations/parks/01_pull_parkserve_parks.py first")
keep <- c("objectid","parkid","park_name","park_designation","park_local_owner","park_local_manager",
          "park_access","park_size_acres","park_address_1","park_place","park_owner_type","park_manager_type",
          "park_status","park_state","park_county","park_county_fips","park_zip","park_boundary_source",
          "park_source_agency","park_dateadded","trails_yn","playground_count")
prep <- function(path) st_read(path, quiet=TRUE) |>
  select(all_of(keep), geometry) |>
  mutate(across(-geometry, as.character))
parks <- bind_rows(lapply(files, prep)) |>
  st_make_valid() |>
  mutate(open_access = park_access == "3" & grepl("^OPEN", toupper(coalesce(park_status,""))))
stopifnot(!anyDuplicated(parks$objectid), !anyDuplicated(parks$parkid))
out <- destination_dir("parks", "processed")
target <- file.path(out, "parks_parkserve_austin_metro.gpkg")
if (file.exists(target)) file.remove(target)
st_write(parks, target, layer="all_parkserve_records", quiet=TRUE)
st_write(filter(parks, open_access), target, layer="open_access_parks", quiet=TRUE)
write_csv(st_drop_geometry(parks), file.path(out,"parks_parkserve_austin_metro.csv"), na="")
summary <- st_drop_geometry(parks) |> count(park_county, open_access, name="parks")
write_csv(summary, file.path(destination_dir("parks","qaqc","parkserve"),"county_access_summary.csv"))
message("ParkServe: ",nrow(parks)," records; open-access operational parks: ",sum(parks$open_access))
