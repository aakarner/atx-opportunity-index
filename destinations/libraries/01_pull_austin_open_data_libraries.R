# Download City of Austin public library locations
#
# Source: City of Austin Open Data (Socrata), dataset tc36-hn4j
#         https://data.austintexas.gov/d/tc36-hn4j
# Austin Public Library branches. Other library systems in the metro need separate sources.
#
# Writes data/destinations/libraries/raw/austin_open_data/libraries.json + libraries_manifest.json
#
# Run from the repository root:
#   Rscript destinations/libraries/01_pull_austin_open_data_libraries.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "httr2", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")
source("destinations/R/socrata_helpers.R")

pull_austin_open_data("libraries", layer_name = "libraries", dataset_id = "tc36-hn4j", format = "json")
