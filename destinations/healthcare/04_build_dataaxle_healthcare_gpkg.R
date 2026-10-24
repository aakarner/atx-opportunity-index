# Build the Data Axle healthcare GeoPackage
#
# Runs after destinations/healthcare/02_clean_dataaxle_healthcare.R.
#
# Writes to data/destinations/healthcare/processed/:
#   healthcare_dataaxle.gpkg                    one layer per proposed type, all
#                                         map-ready candidates
#   healthcare_dataaxle_analysis_ready.csv      screened-in records only
#   healthcare_dataaxle_h7_counts.csv / _h8_counts.csv
#
# Run from the repository root:
#   Rscript destinations/healthcare/04_build_dataaxle_healthcare_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_build_destination("healthcare")
