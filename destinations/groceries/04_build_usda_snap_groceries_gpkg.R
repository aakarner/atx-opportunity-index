# Build the USDA SNAP retailer GeoPackage
#
# Runs after destinations/groceries/02_clean_usda_snap_groceries.R. No network calls.
#
# Writes data/destinations/groceries/processed/:
#   groceries_usda_snap.gpkg   layers: all_retailers, grocery_retailers
#   groceries_usda_snap.csv    every retailer with H3 cells
#
# Run from the repository root:
#   Rscript destinations/groceries/04_build_usda_snap_groceries_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")

interim_path <- file.path(destination_dir("groceries", "interim", "usda_snap", create = FALSE),
                          "snap_retailers_standardized.csv")
qa_dir <- destination_dir("groceries", "qaqc", "usda_snap")
if (!file.exists(interim_path)) stop("Missing ", interim_path, ". Run 02_clean_usda_snap_groceries.R first.")

snap <- read_csv(interim_path, col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(latitude = as.numeric(latitude), longitude = as.numeric(longitude),
         grocery_subset = as.logical(grocery_subset))
mappable <- snap$coordinate_status == "plausible_unverified"
snap <- add_h3_cells(snap, keep = mappable)

write_csv(snap, destination_output_path("groceries", "usda_snap", "csv"), na = "")
write_csv(snap[!mappable, ], file.path(qa_dir, "unmapped_retailers.csv"), na = "")

target <- destination_output_path("groceries", "usda_snap", "gpkg")
write_point_layer(snap[mappable, ], target, "all_retailers", "object_id")
write_point_layer(snap[mappable & snap$grocery_subset, ], target, "grocery_retailers", "object_id")

message("All retailers mapped: ", sum(mappable), " of ", nrow(snap),
        "; grocery subset: ", sum(mappable & snap$grocery_subset))
message("Saved ", target)
