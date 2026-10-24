# Build the Data Axle groceries GeoPackage
#
# Runs after destinations/groceries/02_clean_dataaxle_groceries.R.
#
# Writes to data/destinations/groceries/processed/:
#   groceries_dataaxle.gpkg                    one layer per proposed type, all
#                                         map-ready candidates
#   groceries_dataaxle_analysis_ready.csv      screened-in records only
#   groceries_dataaxle_h7_counts.csv / _h8_counts.csv
#
# Run from the repository root:
#   Rscript destinations/groceries/04_build_dataaxle_groceries_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_build_destination("groceries")
