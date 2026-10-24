# Build the City of Austin parks GeoPackage
#
# Runs after destinations/parks/01_pull_austin_open_data_parks.R.
#
# Each park polygon becomes one representative point (st_point_on_surface) so
# it can be counted in an H3 cell. Points are kept when they fall inside the
# 2024 City boundary buffered by destination_buffer_miles.
# No park-type filter is applied yet (the earlier plan was to keep developed,
# open parks and exclude cemeteries, golf courses, and preserves).
#
# Writes data/destinations/parks/processed/:
#   parks_austin_open_data.gpkg   layers: parks (points), parks_polygons
#   parks_austin_open_data.csv
#
# Run from the repository root:
#   Rscript destinations/parks/04_build_austin_open_data_parks_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "jsonlite", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/socrata_helpers.R")
options(tigris_use_cache = TRUE)

raw_path <- file.path(destination_dir("parks", "raw", "austin_open_data", create = FALSE), "parks.geojson")
if (!file.exists(raw_path)) stop("Missing ", raw_path, ". Run 01_pull_austin_open_data_parks.R first.")

polygons <- sf::st_read(raw_path, quiet = TRUE)
points <- normalize_socrata_polygons(polygons, "parks", "parks", "v8hw-gz65")
build_austin_open_data_layer(points, "parks", "parks", polygons = polygons)
