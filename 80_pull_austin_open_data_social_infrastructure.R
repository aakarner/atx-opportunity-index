# Pull and QA/QC family-serving public infrastructure from Austin Open Data
#
# This retired candidate measure uses three public-resource categories:
# developed/open parkland, public libraries, and recreation centers. It is
# retained for possible future work but does not enter the active step-20
# specifications or the submitted step-22 analysis.
#
# Authentication is optional for these public Socrata queries. If available,
# set AUSTIN_OPEN_DATA_APP_TOKEN in the process environment. Never place a token
# or secret directly in this script or commit one to the repository.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "httr2", "jsonlite"))

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

park_dataset_id <- "v8hw-gz65"
library_dataset_id <- "tc36-hn4j"
recreation_dataset_id <- "8dff-2vkt"
city_boundary_year <- 2024
analysis_equal_area_crs <- 5070
city_buffer_miles <- 1

raw_dir <- "data/raw/austin_open_data_social_infrastructure"
processed_dir <- "data/processed/social_infrastructure"
qaqc_dir <- "data/qaqc/social_infrastructure"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")
retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

# ---- Helpers -----------------------------------------------------------------

add_optional_token <- function(request_object) {
  if (nzchar(app_token)) {
    request_object %>% req_headers(`X-App-Token` = app_token)
  } else {
    request_object
  }
}

perform_json_pull <- function(dataset_id, limit = 5000L) {
  endpoint <- paste0(
    "https://data.austintexas.gov/resource/", dataset_id, ".json"
  )

  response <- request(endpoint) %>%
    req_url_query(`$limit` = as.integer(limit)) %>%
    add_optional_token() %>%
    req_retry(max_tries = 4) %>%
    req_timeout(seconds = 180) %>%
    req_perform()

  list(
    body = resp_body_json(response, simplifyVector = FALSE),
    text = resp_body_string(response)
  )
}

pull_geojson <- function(dataset_id, output_path, limit = 5000L) {
  endpoint <- paste0(
    "https://data.austintexas.gov/resource/", dataset_id, ".geojson"
  )

  response <- request(endpoint) %>%
    req_url_query(`$limit` = as.integer(limit)) %>%
    add_optional_token() %>%
    req_retry(max_tries = 4) %>%
    req_timeout(seconds = 180) %>%
    req_perform()

  writeBin(resp_body_raw(response), output_path)
  st_read(output_path, quiet = TRUE)
}

parse_location_records <- function(records, resource_type, location_field) {
  map_dfr(
    records,
    function(record) {
      location <- pluck(record, location_field, .default = list())

      if (resource_type == "library") {
        resource_name <- pluck(record, "name", .default = NA_character_)
        resource_id <- pluck(record, "term_id", "url", .default = resource_name)
        street_address <- pluck(
          location,
          "human_address",
          .default = NA_character_
        )
      } else {
        resource_name <- pluck(
          record,
          "recreation_centers",
          .default = NA_character_
        )
        resource_id <- pluck(record, "website", .default = resource_name)
        street_address <- pluck(record, "address", .default = NA_character_)
      }

      tibble(
        resource_id = as.character(resource_id),
        resource_name = as.character(resource_name),
        resource_type = resource_type,
        street_address = as.character(street_address),
        latitude = suppressWarnings(as.numeric(
          pluck(location, "latitude", .default = NA_character_)
        )),
        longitude = suppressWarnings(as.numeric(
          pluck(location, "longitude", .default = NA_character_)
        )),
        source_dataset_id = if_else(
          resource_type == "library",
          library_dataset_id,
          recreation_dataset_id
        )
      )
    }
  )
}

# ---- Pull source datasets ----------------------------------------------------

cat("Pulling Austin park polygons...\n")

park_raw_path <- file.path(raw_dir, "austin_park_boundaries.geojson")
parks_raw <- pull_geojson(park_dataset_id, park_raw_path)

cat("Pulling Austin public-library locations...\n")
libraries_pull <- perform_json_pull(library_dataset_id)
writeLines(
  libraries_pull$text,
  file.path(raw_dir, "austin_public_library_locations.json"),
  useBytes = TRUE
)

cat("Pulling Austin recreation-center locations...\n")
recreation_pull <- perform_json_pull(recreation_dataset_id)
writeLines(
  recreation_pull$text,
  file.path(raw_dir, "austin_recreation_centers.json"),
  useBytes = TRUE
)

required_park_fields <- c(
  "objectid", "asset_mgmt_id", "location_name", "park_type",
  "development_status", "asset_status"
)
missing_park_fields <- setdiff(required_park_fields, names(parks_raw))

if (length(missing_park_fields) > 0) {
  stop(
    "Austin park data are missing required fields: ",
    str_c(missing_park_fields, collapse = ", ")
  )
}

libraries_raw <- parse_location_records(
  libraries_pull$body,
  resource_type = "library",
  location_field = "address"
)
recreation_raw <- parse_location_records(
  recreation_pull$body,
  resource_type = "recreation_center",
  location_field = "location_1"
)

if (nrow(libraries_raw) < 1 || nrow(recreation_raw) < 1) {
  stop("Library or recreation-center API pull returned no records.")
}

write_csv(libraries_raw, file.path(raw_dir, "austin_public_libraries.csv"))
write_csv(recreation_raw, file.path(raw_dir, "austin_recreation_centers.csv"))

# ---- Classify and spatially filter resources --------------------------------

excluded_park_types <- c(
  "Cemetery", "Golf Course", "Nature Preserve",
  "Planting Strips/Triangles", "Button", "Button Park"
)

family_serving_parks <- parks_raw %>%
  st_make_valid() %>%
  mutate(
    park_resource_id = coalesce(
      as.character(asset_mgmt_id),
      as.character(objectid),
      as.character(location_name)
    ),
    developed_open_park = str_detect(
      coalesce(development_status, ""),
      regex("Developed", ignore_case = TRUE)
    ) &
      str_to_lower(coalesce(asset_status, "")) == "open" &
      !park_type %in% excluded_park_types
  ) %>%
  filter(developed_open_park)

public_resource_points <- bind_rows(libraries_raw, recreation_raw) %>%
  mutate(
    coordinate_status = case_when(
      is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
      longitude < -99 | longitude > -96 | latitude < 29 | latitude > 32 ~
        "outside_austin_region_bbox",
      TRUE ~ "valid_coordinate"
    )
  )

if (anyDuplicated(public_resource_points$resource_id) > 0) {
  stop("Library/recreation resource IDs are not unique.")
}

valid_resource_points <- public_resource_points %>%
  filter(coordinate_status == "valid_coordinate") %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

cat("Pulling City of Austin boundary...\n")

austin_boundary <- places(state = "TX", year = city_boundary_year) %>%
  filter(NAME == "Austin") %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(austin_boundary) != 1) {
  stop("Expected one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

austin_buffer <- austin_boundary %>%
  st_transform(analysis_equal_area_crs) %>%
  st_buffer(city_buffer_miles * 1609.344) %>%
  st_transform(4326)

family_serving_parks_austin <- family_serving_parks[
  lengths(st_intersects(family_serving_parks, austin_buffer)) > 0,
]
public_resource_points_austin <- valid_resource_points[
  lengths(st_intersects(valid_resource_points, austin_buffer)) > 0,
]

if (nrow(family_serving_parks_austin) < 1 ||
    nrow(public_resource_points_austin) < 1) {
  stop("No family-serving parks or public-resource points remained near Austin.")
}

family_serving_parks_austin <- family_serving_parks_austin %>%
  select(
    park_resource_id, location_name, park_type, development_status,
    asset_status, service_area, level_of_service, management_priority,
    asset_size, owner_name, source_objectid = objectid
  )

public_resource_points_austin <- public_resource_points_austin %>%
  select(
    resource_id, resource_name, resource_type, street_address, latitude,
    longitude, source_dataset_id, coordinate_status
  )

# ---- Save processed data and QA/QC ------------------------------------------

park_gpkg <- file.path(
  processed_dir,
  "austin_family_serving_parkland.gpkg"
)
resource_gpkg <- file.path(
  processed_dir,
  "austin_libraries_recreation_centers.gpkg"
)

st_write(
  family_serving_parks_austin,
  park_gpkg,
  layer = "family_serving_parkland",
  delete_dsn = TRUE,
  quiet = TRUE
)
st_write(
  public_resource_points_austin,
  resource_gpkg,
  layer = "libraries_recreation_centers",
  delete_dsn = TRUE,
  quiet = TRUE
)

write_csv(
  st_drop_geometry(family_serving_parks_austin),
  file.path(processed_dir, "austin_family_serving_parkland.csv")
)
write_csv(
  st_drop_geometry(public_resource_points_austin),
  file.path(processed_dir, "austin_libraries_recreation_centers.csv")
)

park_classification_summary <- parks_raw %>%
  st_drop_geometry() %>%
  count(
    park_type,
    development_status,
    asset_status,
    name = "records",
    sort = TRUE
  )

resource_coordinate_qaqc <- public_resource_points %>%
  count(resource_type, coordinate_status, name = "records")

qaqc_summary <- tibble(
  metric = c(
    "retrieved_at_utc", "app_token_used", "park_dataset_id",
    "library_dataset_id", "recreation_dataset_id", "raw_park_records",
    "developed_open_family_serving_parks_near_austin", "raw_libraries",
    "raw_recreation_centers", "valid_public_resource_coordinates",
    "public_resource_points_near_austin", "city_buffer_miles"
  ),
  value = c(
    retrieved_at_utc, as.character(nzchar(app_token)), park_dataset_id,
    library_dataset_id, recreation_dataset_id, as.character(nrow(parks_raw)),
    as.character(nrow(family_serving_parks_austin)),
    as.character(nrow(libraries_raw)), as.character(nrow(recreation_raw)),
    as.character(nrow(valid_resource_points)),
    as.character(nrow(public_resource_points_austin)),
    as.character(city_buffer_miles)
  )
)

write_csv(
  park_classification_summary,
  file.path(qaqc_dir, "social_infrastructure_park_classification.csv")
)
write_csv(
  resource_coordinate_qaqc,
  file.path(qaqc_dir, "social_infrastructure_coordinate_qaqc.csv")
)
write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "social_infrastructure_qaqc_summary.csv")
)

cat("\n=== Social-Infrastructure Pull Complete ===\n")
cat("Family-serving park polygons: ", nrow(family_serving_parks_austin), "\n", sep = "")
cat("Libraries: ", sum(public_resource_points_austin$resource_type == "library"), "\n", sep = "")
cat("Recreation centers: ", sum(public_resource_points_austin$resource_type == "recreation_center"), "\n", sep = "")
cat("Processed park output: ", park_gpkg, "\n", sep = "")
cat("Processed point output: ", resource_gpkg, "\n", sep = "")
