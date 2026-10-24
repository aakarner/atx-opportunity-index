# Standardize and screen Data Axle healthcare exports
#
# Source: Data Axle Reference Solutions, manual CSV exports (licensed; kept
#         out of git under data/). Put every export batch, unchanged, in
#         data/destinations/healthcare/raw/dataaxle/
#
# Reads all batches, merges repeated records, applies the NAICS screening rules
# in destinations/R/dataaxle_config.R, and applies documented manual decisions
# from data/destinations/manual/. No downloads or geocoding.
#
# Writes:
#   data/destinations/healthcare/interim/dataaxle/dataaxle_standardized.{rds,csv}
#   data/destinations/healthcare/qaqc/dataaxle/  (review, geocoding, duplicate queues)
#
# Run from the repository root:
#   Rscript destinations/healthcare/02_clean_dataaxle_healthcare.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_clean_destination("healthcare")
