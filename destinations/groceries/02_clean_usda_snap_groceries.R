# Standardize the USDA SNAP retailer download
#
# Runs after destinations/groceries/01_pull_usda_snap_groceries.R. No network calls.
#
# County attributes, not supplied coordinates, define the study universe, so a
# bad coordinate cannot silently add or drop a store. grocery_subset marks the
# store types comparable to grocery stores (Supermarket, Super Store, Grocery
# Store); other SNAP types stay in the table for review.
#
# Writes:
#   data/destinations/groceries/interim/usda_snap/snap_retailers_standardized.csv
#   data/destinations/groceries/qaqc/usda_snap/store_type_by_county.csv
#
# Run from the repository root:
#   Rscript destinations/groceries/02_clean_usda_snap_groceries.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "jsonlite"))
source("destinations/R/destination_paths.R")

raw_path <- file.path(destination_dir("groceries", "raw", "usda_snap", create = FALSE), "metro_records.json")
interim_dir <- destination_dir("groceries", "interim", "usda_snap")
qa_dir <- destination_dir("groceries", "qaqc", "usda_snap")
if (!file.exists(raw_path)) stop("Missing ", raw_path, ". Run 01_pull_usda_snap_groceries.R first.")

grocery_types <- c("Supermarket", "Super Store", "Grocery Store")

records <- jsonlite::fromJSON(raw_path)
snap <- as_tibble(records$attributes) |>
  transmute(
    snap_id = as.character(Record_ID), object_id = as.character(ObjectId),
    name = Store_Name, address = Store_Street_Address, address2 = Additonal_Address,
    city = City, state = State, zip = as.character(Zip_Code), county = toupper(County),
    store_type = Store_Type, incentive_program = Incentive_Program,
    latitude = as.numeric(Latitude), longitude = as.numeric(Longitude)
  ) |>
  mutate(
    grocery_subset = store_type %in% grocery_types,
    coordinate_source = "USDA SNAP retailer locator",
    coordinate_status = destination_coordinate_status(latitude, longitude)
  )
stopifnot(!anyDuplicated(snap$object_id), all(snap$county %in% toupper(destination_metro_counties)))

write_csv(snap, file.path(interim_dir, "snap_retailers_standardized.csv"), na = "")
type_counts <- count(snap, county, store_type, grocery_subset, name = "retailers")
write_csv(type_counts, file.path(qa_dir, "store_type_by_county.csv"))
print(count(snap, store_type, grocery_subset, coordinate_status), n = Inf)
