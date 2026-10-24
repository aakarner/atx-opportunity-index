# Standardize and screen Data Axle parks exports
#
# Source: Data Axle Reference Solutions, manual CSV exports (licensed; kept
#         out of git under data/). Put every export batch, unchanged, in
#         data/destinations/parks/raw/dataaxle/
#
# Reads all batches, merges repeated records, applies the NAICS screening rules
# in destinations/R/dataaxle_config.R, and applies documented manual decisions
# from data/destinations/manual/. No downloads or geocoding.
#
# Writes:
#   data/destinations/parks/interim/dataaxle/dataaxle_standardized.{rds,csv}
#   data/destinations/parks/qaqc/dataaxle/  (review, geocoding, duplicate queues)
#
# Run from the repository root:
#   Rscript destinations/parks/02_clean_dataaxle_parks.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_clean_destination("parks")
