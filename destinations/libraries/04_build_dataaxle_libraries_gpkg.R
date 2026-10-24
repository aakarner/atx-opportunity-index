# Build the Data Axle libraries GeoPackage
#
# Runs after destinations/libraries/02_clean_dataaxle_libraries.R.
#
# Writes to data/destinations/libraries/processed/:
#   libraries_dataaxle.gpkg                    one layer per proposed type, all
#                                         map-ready candidates
#   libraries_dataaxle_analysis_ready.csv      screened-in records only
#   libraries_dataaxle_h7_counts.csv / _h8_counts.csv
#
# Run from the repository root:
#   Rscript destinations/libraries/04_build_dataaxle_libraries_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_build_destination("libraries")
