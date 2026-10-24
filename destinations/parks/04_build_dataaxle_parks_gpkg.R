# Build the Data Axle parks GeoPackage
#
# Runs after destinations/parks/02_clean_dataaxle_parks.R.
#
# Writes to data/destinations/parks/processed/:
#   parks_dataaxle.gpkg                    one layer per proposed type, all
#                                         map-ready candidates
#   parks_dataaxle_analysis_ready.csv      screened-in records only
#   parks_dataaxle_h7_counts.csv / _h8_counts.csv
#
# Run from the repository root:
#   Rscript destinations/parks/04_build_dataaxle_parks_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_build_destination("parks")
