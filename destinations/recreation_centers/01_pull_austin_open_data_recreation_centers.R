# Download City of Austin recreation centers
#
# Source: City of Austin Open Data (Socrata), dataset 8dff-2vkt
#         https://data.austintexas.gov/d/8dff-2vkt
# City-operated recreation and community centers.
#
# Writes data/destinations/recreation_centers/raw/austin_open_data/recreation_centers.json + recreation_centers_manifest.json
#
# Run from the repository root:
#   Rscript destinations/recreation_centers/01_pull_austin_open_data_recreation_centers.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "httr2", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")
source("destinations/R/socrata_helpers.R")

pull_austin_open_data("recreation_centers", layer_name = "recreation_centers", dataset_id = "8dff-2vkt", format = "json")
