# Build the final reviewed USDA SNAP grocery inventory.
#
# Inclusion rule:
#   1. retain every SNAP Supermarket, Super Store, and Grocery Store; and
#   2. add records explicitly marked include_full_service or
#      include_small_grocery in the durable manual decision file.
#
# The final attribute table retains the standardized SNAP fields and adds only
# inclusion_basis. Manual review evidence remains in the separate QA file.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf"))
source("destinations/R/destination_paths.R")

interim_path <- file.path(destination_dir("groceries", "interim", "usda_snap", create = FALSE),
                          "snap_retailers_standardized.csv")
decision_path <- file.path(destination_manual_dir(), "snap_grocery_decisions.csv")
out_dir <- destination_dir("groceries", "processed")

if (!file.exists(interim_path)) stop("Missing ", interim_path)
if (!file.exists(decision_path)) stop("Missing ", decision_path)

snap <- read_csv(interim_path, col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(latitude = as.numeric(latitude), longitude = as.numeric(longitude),
         grocery_subset = as.logical(grocery_subset))
decisions <- read_csv(decision_path, col_types = cols(.default = col_character()), show_col_types = FALSE)

allowed <- c("include_full_service", "include_small_grocery", "exclude_convenience", "exclude_other", "unresolved")
stopifnot(!anyDuplicated(decisions$snap_id), all(decisions$manual_decision %in% allowed))
if (any(!decisions$snap_id %in% snap$snap_id)) stop("Manual decisions contain SNAP IDs absent from the current source")

included_manual <- decisions |>
  filter(manual_decision %in% c("include_full_service", "include_small_grocery")) |>
  select(snap_id, manual_decision)

final <- snap |>
  left_join(included_manual, by = "snap_id") |>
  filter(grocery_subset | !is.na(manual_decision)) |>
  mutate(inclusion_basis = case_when(
    grocery_subset ~ "SNAP grocery type",
    manual_decision == "include_full_service" ~ "Manual review - full service",
    manual_decision == "include_small_grocery" ~ "Manual review - small grocery"
  )) |>
  select(-grocery_subset, -manual_decision)

stopifnot(!anyDuplicated(final$snap_id), nrow(final) == sum(snap$grocery_subset) + nrow(included_manual))

csv_path <- file.path(out_dir, "groceries_usda_snap_final.csv")
write_csv(final, csv_path, na = "")

gpkg_path <- file.path(out_dir, "groceries_usda_snap_final.gpkg")
if (file.exists(gpkg_path)) file.remove(gpkg_path)
sf_final <- st_as_sf(final, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
st_write(sf_final, gpkg_path, layer = "snap_groceries_final", quiet = TRUE)

message("Final SNAP grocery inventory: ", nrow(final),
        " (SNAP type: ", sum(final$inclusion_basis == "SNAP grocery type"),
        "; manual full service: ", sum(final$inclusion_basis == "Manual review - full service"),
        "; manual small grocery: ", sum(final$inclusion_basis == "Manual review - small grocery"), ")")
message("Saved ", csv_path, " and ", gpkg_path)
