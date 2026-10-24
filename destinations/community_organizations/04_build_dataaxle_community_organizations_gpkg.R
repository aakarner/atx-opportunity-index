# Build the Data Axle community_organizations GeoPackage
#
# Runs after destinations/community_organizations/02_clean_dataaxle_community_organizations.R.
#
# Writes to data/destinations/community_organizations/processed/:
#   community_organizations_dataaxle.gpkg                    one layer per proposed type, all
#                                         map-ready candidates
#   community_organizations_dataaxle_analysis_ready.csv      screened-in records only
#   community_organizations_dataaxle_h7_counts.csv / _h8_counts.csv
#
# Run from the repository root:
#   Rscript destinations/community_organizations/04_build_dataaxle_community_organizations_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
source("destinations/R/dataaxle_helpers.R")

ax_build_destination("community_organizations")
