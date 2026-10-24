# Join geocoded coordinates to childcare operations and build H8 opportunities
#
# Runs after:
#   destinations/childcare/01_pull_texas_hhsc_childcare.R   (writes childcare_normalized.rds)
#   destinations/childcare/03_geocode_texas_hhsc_childcare.R (writes childcare_geocoded.csv)
#
# Also validates the Census coordinates against the small set of coordinates
# HHSC supplied directly. Those 73 records skew heavily toward Listed Family
# Homes, which is unexplained, so they are treated as a check rather than as a
# trusted source.
#
#   Rscript destinations/childcare/04_build_texas_hhsc_childcare_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")

compact <- purrr::compact

# ---- Settings ----------------------------------------------------------------

analysis_equal_area_crs <- 5070
h3_resolution           <- 8
metro_boundary_path <- file.path(
  "data", "Karner, Alex - austin_msa_h3_r8_share_2026-10-02", "input",
  "austin_msa_cbsa_12420_boundary.geojson"
)
matrix_cells_path <- file.path(
  "data", "Karner, Alex - austin_msa_h3_r8_share_2026-10-02", "input",
  "austin_msa_h3_r8_cells.csv"
)

# Median offset above this between HHSC and Census coordinates for the same
# address suggests one source is generalizing rather than geocoding, and needs
# investigation before the layer is used.
offset_warning_metres <- 100

interim_dir   <- destination_dir("childcare", "interim", "texas_hhsc")
processed_dir <- destination_dir("childcare", "processed")
qaqc_dir      <- destination_dir("childcare", "qaqc", "texas_hhsc")

# ---- Load inputs -------------------------------------------------------------

normalized_path <- file.path(interim_dir, "childcare_normalized.rds")
geocoded_path   <- file.path(interim_dir, "childcare_geocoded.csv")
geocoded_path <- Sys.getenv("CHILDCARE_GEOCODE_PATH", unset = geocoded_path)

walk(c(processed_dir, qaqc_dir), ~ dir.create(.x, recursive = TRUE, showWarnings = FALSE))

walk(c(normalized_path, geocoded_path, metro_boundary_path, matrix_cells_path), function(path) {
  if (!file.exists(path)) {
    stop("Missing required input: ", path, ". Run scripts 02 and 03 first.")
  }
})

childcare_normalized <- read_rds(normalized_path)

geocoded <- read_csv(geocoded_path, col_types = cols(.default = col_character())) %>%
  mutate(across(c(latitude, longitude), as.numeric))

if (anyDuplicated(childcare_normalized$destination_id) ||
    anyDuplicated(geocoded$unique_id)) {
  stop("Childcare operation and geocode IDs must be unique before joining.")
}

cat("Normalized records: ", nrow(childcare_normalized), "\n", sep = "")
cat("Geocoded records:   ", nrow(geocoded), "\n", sep = "")

# ---- Join --------------------------------------------------------------------

childcare_joined <- childcare_normalized %>%
  left_join(
    geocoded %>%
      select(
        destination_id = unique_id,
        latitude, longitude,
        geocode_match_type, geocode_source, geocode_benchmark
      ),
    by = "destination_id"
  ) %>%
  mutate(
    coordinate_source = case_when(
      !is.na(latitude)      ~ "census_batch",
      !is.na(hhsc_latitude) ~ "hhsc_supplied",
      TRUE                  ~ "none"
    ),
    # Census coordinates preferred throughout for uniform provenance; the HHSC
    # value is a fallback only where geocoding failed outright.
    latitude  = coalesce(latitude,  hhsc_latitude),
    longitude = coalesce(longitude, hhsc_longitude)
  )

cat("\nCoordinate source breakdown:\n")
print(count(childcare_joined, coordinate_source, name = "records"))

# ---- Validate Census against HHSC coordinates --------------------------------

comparison_base <- childcare_joined %>%
  filter(
    !is.na(hhsc_latitude), !is.na(hhsc_longitude),
    coordinate_source == "census_batch"
  )

if (nrow(comparison_base) > 0) {
  hhsc_points <- comparison_base %>%
    st_as_sf(coords = c("hhsc_longitude", "hhsc_latitude"), crs = 4326) %>%
    st_transform(analysis_equal_area_crs) %>%
    st_geometry()

  census_points <- comparison_base %>%
    st_as_sf(coords = c("longitude", "latitude"), crs = 4326) %>%
    st_transform(analysis_equal_area_crs) %>%
    st_geometry()

  coordinate_comparison <- comparison_base %>%
    st_drop_geometry() %>%
    select(destination_id, operation_type) %>%
    mutate(
      offset_metres = as.numeric(
        st_distance(hhsc_points, census_points, by_element = TRUE)
      )
    )

  cat("\nHHSC vs Census coordinate offset (metres):\n")
  print(summary(coordinate_comparison$offset_metres))

  offset_by_type <- coordinate_comparison %>%
    group_by(operation_type) %>%
    summarise(
      records       = n(),
      median_offset = round(median(offset_metres, na.rm = TRUE), 1),
      max_offset    = round(max(offset_metres, na.rm = TRUE), 1),
      .groups = "drop"
    )

  cat("\nOffset by operation type:\n")
  print(offset_by_type, n = Inf)

  write_csv(
    coordinate_comparison,
    file.path(qaqc_dir, "childcare_coordinate_comparison.csv")
  )
  write_csv(
    offset_by_type,
    file.path(qaqc_dir, "childcare_coordinate_offset_by_type.csv")
  )

  median_offset <- median(coordinate_comparison$offset_metres, na.rm = TRUE)

  if (median_offset > offset_warning_metres) {
    warning(
      "Median HHSC-Census offset is ", round(median_offset, 1), " m, above the ",
      offset_warning_metres, " m threshold. One source may be generalizing ",
      "rather than geocoding. Inspect before relying on this layer."
    )
  } else {
    cat(
      "\nMedian offset ", round(median_offset, 1),
      " m is consistent with normal street-interpolation error.\n", sep = ""
    )
  }
} else {
  cat("\nNo overlapping records available for coordinate validation.\n")
}

# ---- Spatial filtering -------------------------------------------------------

cat("\nLoading five-county Austin metro boundary...\n")

destination_catchment <- st_read(metro_boundary_path, quiet = TRUE) %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(destination_catchment) != 1) {
  stop("Expected one Austin metro boundary feature; found ",
       nrow(destination_catchment), ".")
}

childcare_joined <- childcare_joined %>%
  mutate(
    coordinate_status = case_when(
      is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
      longitude < -99 | longitude > -96 |
        latitude < 29 | latitude > 32   ~ "outside_austin_region_bbox",
      TRUE                              ~ "valid_coordinate"
    )
  )

childcare_points <- childcare_joined %>%
  filter(coordinate_status == "valid_coordinate") %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

childcare_in_catchment <- childcare_points[
  lengths(st_intersects(childcare_points, destination_catchment)) > 0,
]

if (nrow(childcare_in_catchment) < 1) {
  stop("No childcare operations remained inside the metro boundary.")
}

# ---- Geocoding non-response check --------------------------------------------
#
# Whether match rates differ across operation types determines whether the
# resulting surface is biased. Home-based operations concentrate in different
# neighbourhoods than centers, so a lower match rate for them would understate
# access in exactly those places.

match_rate_by_type <- childcare_joined %>%
  group_by(operation_type) %>%
  summarise(
    records      = n(),
    geocoded     = sum(coordinate_source == "census_batch"),
    match_rate   = round(mean(coordinate_source == "census_batch"), 3),
    .groups = "drop"
  ) %>%
  arrange(match_rate)

cat("\nGeocode match rate by operation type:\n")
print(match_rate_by_type, n = Inf)

write_csv(
  match_rate_by_type,
  file.path(qaqc_dir, "childcare_match_rate_by_type.csv")
)

if (min(match_rate_by_type$match_rate) < 0.85) {
  warning(
    "At least one operation type matched below 85%. Differential geocoding ",
    "success biases the accessibility surface; report this rather than ",
    "treating coverage as complete."
  )
}

# ---- H8 assignment -----------------------------------------------------------

childcare_in_catchment <- childcare_in_catchment %>%
  mutate(
    h3_address = h3jsr::point_to_cell(
      st_geometry(childcare_in_catchment),
      res = h3_resolution
    )
  )

matrix_h8 <- read_csv(
  matrix_cells_path,
  col_types = cols(h3_id = col_character(), .default = col_skip())
) %>%
  distinct(h3_id)

childcare_in_catchment <- childcare_in_catchment %>%
  mutate(od_matrix_eligible = h3_address %in% matrix_h8$h3_id)

matrix_edge_exclusions <- childcare_in_catchment %>%
  filter(!od_matrix_eligible) %>%
  st_drop_geometry() %>%
  transmute(
    destination_id, destination_name, city, county, h3_address,
    exclusion_reason = "Point is inside the metro boundary, but its H8 cell is absent from the supplied OD matrix grid"
  )

# Which measure is primary is a methodological choice to state explicitly:
#   facilities        - comparable to the other amenity categories
#   facilities_center - excludes home-based operations entirely
#   slots             - the measure childcare access literature generally uses
#   slots_subsidized  - access conditioned on affordability
#   slots_licensed    - excludes Listed Family Homes, registered but not
#                       licensed or routinely inspected
h8_childcare <- childcare_in_catchment %>%
  filter(od_matrix_eligible) %>%
  st_drop_geometry() %>%
  group_by(h3_address) %>%
  summarise(
    childcare_facilities        = n(),
    childcare_facilities_center = sum(!is_home_based),
    childcare_slots             = sum(capacity, na.rm = TRUE),
    childcare_slots_subsidized  = sum(
      if_else(accepts_subsidies, capacity, 0), na.rm = TRUE
    ),
    childcare_slots_licensed = sum(
      if_else(!is_listed_family_home, capacity, 0), na.rm = TRUE
    ),
    .groups = "drop"
  )

# ---- Outputs -----------------------------------------------------------------

# Point file includes home-based operations at residential addresses.
# Keep local; add to .gitignore rather than committing.
st_write(
  childcare_in_catchment,
  file.path(processed_dir, "childcare_texas_hhsc.gpkg"),
  layer      = "childcare_destinations",
  delete_dsn = TRUE,
  quiet      = TRUE
)

# H8 aggregate carries no addresses and is safe to commit.
write_csv(
  h8_childcare,
  file.path(processed_dir, "childcare_texas_hhsc_h8_opportunities.csv")
)

write_csv(
  matrix_edge_exclusions,
  file.path(qaqc_dir, "childcare_od_matrix_edge_exclusions.csv")
)

# ---- QA/QC -------------------------------------------------------------------

qaqc_summary <- tibble(
  metric = c(
    "built_at_utc",
    "normalized_records", "geocoded_records",
    "coordinate_source_census", "coordinate_source_hhsc", "coordinate_source_none",
    "valid_coordinates", "in_catchment",
    "od_matrix_eligible", "od_matrix_edge_excluded",
    "catchment_definition",
    "home_based_share", "capacity_missing",
    "inventory_total_slots", "matrix_total_slots",
    "matrix_total_slots_subsidized", "matrix_total_slots_licensed",
    "distinct_h8_cells"
  ),
  value = c(
    format(Sys.time(), tz = "UTC", usetz = TRUE),
    as.character(nrow(childcare_normalized)),
    as.character(nrow(geocoded)),
    as.character(sum(childcare_joined$coordinate_source == "census_batch")),
    as.character(sum(childcare_joined$coordinate_source == "hhsc_supplied")),
    as.character(sum(childcare_joined$coordinate_source == "none")),
    as.character(sum(childcare_joined$coordinate_status == "valid_coordinate")),
    as.character(nrow(childcare_in_catchment)),
    as.character(sum(childcare_in_catchment$od_matrix_eligible)),
    as.character(sum(!childcare_in_catchment$od_matrix_eligible)),
    "Austin-Round Rock-San Marcos five-county metro boundary (CBSA 12420; January 1, 2025 vintage)",
    as.character(round(mean(childcare_in_catchment$is_home_based), 3)),
    as.character(sum(is.na(childcare_in_catchment$capacity) |
                       childcare_in_catchment$capacity <= 0)),
    as.character(sum(childcare_in_catchment$capacity, na.rm = TRUE)),
    as.character(sum(h8_childcare$childcare_slots)),
    as.character(sum(h8_childcare$childcare_slots_subsidized)),
    as.character(sum(h8_childcare$childcare_slots_licensed)),
    as.character(nrow(h8_childcare))
  )
)

write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "childcare_qaqc_summary.csv")
)

type_summary <- childcare_in_catchment %>%
  st_drop_geometry() %>%
  group_by(operation_type) %>%
  summarise(
    facilities    = n(),
    total_slots   = sum(capacity, na.rm = TRUE),
    median_slots  = median(capacity, na.rm = TRUE),
    subsidy_share = round(mean(accepts_subsidies), 3),
    .groups = "drop"
  ) %>%
  arrange(desc(facilities))

write_csv(
  type_summary,
  file.path(qaqc_dir, "childcare_type_summary.csv")
)

county_summary <- childcare_in_catchment %>%
  st_drop_geometry() %>%
  count(county, name = "facilities", sort = TRUE)

write_csv(
  county_summary,
  file.path(qaqc_dir, "childcare_county_summary.csv")
)

cat("\n=== Childcare Opportunities Built ===\n")
print(qaqc_summary, n = Inf)
cat("\nBy operation type:\n")
print(type_summary, n = Inf)
cat("\nBy source county:\n")
print(county_summary, n = Inf)
