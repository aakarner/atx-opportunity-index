# Build the Data Axle pharmacies GeoPackage
#
# Runs after destinations/pharmacies/02_clean_dataaxle_pharmacies.R.
#
# Writes to data/destinations/pharmacies/processed/:
#   pharmacies_dataaxle.gpkg                    one layer per proposed type, all
#                                         map-ready candidates
#   pharmacies_dataaxle_analysis_ready.csv      screened-in records only
#   pharmacies_dataaxle_h7_counts.csv / _h8_counts.csv
#
# Run from the repository root:
#   Rscript destinations/pharmacies/04_build_dataaxle_pharmacies_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_build_destination("pharmacies")
