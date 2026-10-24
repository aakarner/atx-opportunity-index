# Build a private ArcGIS Online review package from finalized destination layers.
# Run from the repository root:
#   Rscript destinations/90_build_arcgis_online_review_package.R

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
})

output_dir <- file.path("data", "sharing", "arcgis_online_review")
output_dir_abs <- normalizePath(output_dir, mustWork = FALSE)
gdb_path <- file.path(output_dir, "austin_metro_destinations_review.gdb")
zip_path <- file.path(output_dir, "austin_metro_destinations_review.zip")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
if (dir.exists(gdb_path)) unlink(gdb_path, recursive = TRUE)
if (file.exists(zip_path)) unlink(zip_path)

read_layer <- function(path, layer) {
  x <- st_read(path, layer = layer, quiet = TRUE) |>
    st_transform(4326) |>
    st_make_valid()
  if (any(st_is_empty(x))) stop(layer, " contains empty geometry.")
  x
}

write_review_layer <- function(x, layer) {
  st_write(x, gdb_path, layer = layer, driver = "OpenFileGDB", quiet = TRUE)
  message(layer, ": ", nrow(x), " records")
}

groceries <- read_layer(
  "data/destinations/groceries/processed/groceries_usda_snap_final.gpkg",
  "snap_groceries_final"
) |>
  transmute(
    facility_id = snap_id,
    facility_name = name,
    address = trimws(paste(address, address2)), city, state, zip, county,
    store_type, incentive_program, coordinate_status, inclusion_basis,
    inventory_source = "USDA SNAP retailer inventory; manually reviewed"
  )

pharmacies <- read_layer(
  "data/destinations/pharmacies/processed/pharmacies_final.gpkg",
  "pharmacies"
) |>
  transmute(
    facility_id = pharmacy_id,
    facility_name = pharmacy_name,
    address = trimws(paste(address, address_2)), city, state, zip, county,
    phone, ownership, pharmacy_class, home_delivery, disabled_access, medicaid,
    coordinate_source,
    inventory_source = "Texas State Board of Pharmacy; coordinates supplemented during review"
  )

parks <- read_layer(
  "data/destinations/parks/processed/parks_final.gpkg", "parks"
) |>
  transmute(
    facility_id = park_id,
    facility_name = park_name,
    county, acreage, park_designation, park_manager_type, park_local_manager,
    park_access, specialized_access, source, source_addition,
    austin_park_type, austin_development_status, austin_asset_status,
    austin_restrictions, austin_owner_name, austin_managing_name
  )

childcare <- read_layer(
  "data/destinations/childcare/processed/childcare_texas_hhsc.gpkg",
  "childcare_destinations"
) |>
  transmute(
    facility_id = destination_id,
    facility_name = destination_name,
    category, operation_type, is_home_based, capacity, accepts_subsidies,
    ages_served, hours_of_operation, days_of_operation,
    address = street_address, city, state = "TX", zip, county,
    coordinate_source, coordinate_status, od_matrix_eligible,
    inventory_source = "Texas HHSC child-care operations"
  )

libraries <- read_layer(
  "data/destinations/libraries/processed/libraries_final.gpkg", "libraries"
) |>
  transmute(
    facility_id = library_id,
    facility_name = library_name,
    library_type, address, city, county, state, zip, website, phone,
    inventory_source, screening_basis
  )

centers <- read_layer(
  "data/destinations/recreation_centers/processed/regional_public_centers.gpkg",
  "regional_centers"
) |>
  transmute(
    facility_id, facility_name, facility_type, operator, programs,
    address, city, state, zip, county, phone, hours, access_notes,
    review_status, review_notes, source_url, source_checked,
    wheelchair_access, fee_amount, coverage_note,
    inventory_source = "Regional government and public-facility sources"
  )

# The city boundary is included for context. The metro boundary is the same
# January 1, 2025 CBSA geography used to build the supplied H8 OD matrix.
places <- st_read(
  "accessibility/data/cache/tigris/tl_2024_48_place.shp", quiet = TRUE
) |>
  filter(NAME == "Austin") |>
  st_transform(4326) |>
  transmute(boundary_name = "City of Austin", boundary_year = 2024L)

metro <- st_read(
  file.path(
    "data", "Karner, Alex - austin_msa_h3_r8_share_2026-10-02", "input",
    "austin_msa_cbsa_12420_boundary.geojson"
  ),
  quiet = TRUE
) |>
  st_transform(4326) |>
  transmute(
    boundary_name = "Austin-Round Rock-San Marcos metro area",
    cbsa_code = "12420",
    boundary_vintage = "January 1, 2025"
  )

layers <- list(
  groceries = groceries,
  pharmacies = pharmacies,
  parks = parks,
  childcare = childcare,
  libraries = libraries,
  public_centers = centers,
  austin_boundary = places,
  metro_boundary = metro
)

for (layer in names(layers)) {
  x <- layers[[layer]]
  if (!"facility_id" %in% names(x) && !grepl("boundary$", layer)) {
    stop(layer, " lacks facility_id.")
  }
  if ("facility_id" %in% names(x) && anyDuplicated(x$facility_id)) {
    stop(layer, " has duplicate facility_id values.")
  }
  write_review_layer(x, layer)
}

old <- setwd(output_dir)
on.exit(setwd(old), add = TRUE)
utils::zip(
  zipfile = basename(zip_path),
  files = file.path(basename(gdb_path), list.files(basename(gdb_path))),
  flags = "-r9Xq"
)

manifest <- data.frame(
  layer = names(layers),
  records = vapply(layers, nrow, integer(1)),
  geometry = vapply(layers, function(x) as.character(unique(st_geometry_type(x)))[1], character(1)),
  stringsAsFactors = FALSE
)
write.csv(manifest, "layer_manifest.csv", row.names = FALSE)

message("Created ", file.path(output_dir_abs, basename(zip_path)))
print(manifest)
