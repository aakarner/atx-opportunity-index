# Download City of Austin park boundaries
#
# Source: City of Austin Open Data (Socrata), dataset v8hw-gz65
#         https://data.austintexas.gov/d/v8hw-gz65
# City-managed park polygons (Austin Parks and Recreation). Covers City parks only, not other municipalities in the metro.
#
# Writes data/destinations/parks/raw/austin_open_data/parks.geojson + parks_manifest.json
#
# Run from the repository root:
#   Rscript destinations/parks/01_pull_austin_open_data_parks.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "httr2", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")
source("destinations/R/socrata_helpers.R")

pull_austin_open_data("parks", layer_name = "parks", dataset_id = "v8hw-gz65", format = "geojson")
