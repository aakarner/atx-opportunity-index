# Build the City of Austin recreation center GeoPackage
#
# Runs after destinations/recreation_centers/01_pull_austin_open_data_recreation_centers.R.
#
# Reads the saved point records, screens coordinates, and keeps locations
# inside the 2024 City boundary buffered by destination_buffer_miles.
#
# Writes data/destinations/recreation_centers/processed/:
#   recreation_centers_austin_open_data.gpkg   layer: recreation_centers
#   recreation_centers_austin_open_data.csv
#
# Run from the repository root:
#   Rscript destinations/recreation_centers/04_build_austin_open_data_recreation_centers_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "jsonlite", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/socrata_helpers.R")
options(tigris_use_cache = TRUE)

raw_path <- file.path(destination_dir("recreation_centers", "raw", "austin_open_data", create = FALSE), "recreation_centers.json")
if (!file.exists(raw_path)) stop("Missing ", raw_path, ". Run 01_pull_austin_open_data_recreation_centers.R first.")

points <- normalize_socrata_points(raw_path, "recreation_centers", category = "recreation_centers", dataset_id = "8dff-2vkt",
                                   location_field = "location_1", name_field = "recreation_centers")
build_austin_open_data_layer(points, "recreation_centers", "recreation_centers")
