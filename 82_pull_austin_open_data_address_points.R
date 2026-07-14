# Pull and QA/QC the public City of Austin address-point reference
#
# This reference supports privacy-preserving local matching of court-supplied
# correspondence addresses. Only public address text and point geometry are
# downloaded; locally supplied eviction addresses are never sent to the API.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "httr2", "scales"))

options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

dataset_id <- "9s7j-tygf"
dataset_page_url <- paste0(
  "https://data.austintexas.gov/Locations-and-Maps/Addresses/",
  dataset_id
)
soda2_csv_endpoint <- paste0(
  "https://data.austintexas.gov/resource/", dataset_id, ".csv"
)
soda2_json_endpoint <- paste0(
  "https://data.austintexas.gov/resource/", dataset_id, ".json"
)
page_size <- 50000L

raw_dir <- "data/raw/austin_open_data_address_points"
processed_dir <- "data/processed/address_reference"
qaqc_dir <- "data/qaqc/address_reference"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")

# ---- Helpers -----------------------------------------------------------------

add_optional_token <- function(request_object) {
  if (nzchar(app_token)) {
    request_object %>% req_headers(`X-App-Token` = app_token)
  } else {
    request_object
  }
}

perform_request <- function(endpoint, select, limit, offset = 0L, order = NULL) {
  request_object <- request(endpoint) %>%
    req_url_query(
      `$select` = select,
      `$limit` = as.integer(limit),
      `$offset` = as.integer(offset)
    )

  if (!is.null(order)) {
    request_object <- request_object %>% req_url_query(`$order` = order)
  }

  request_object %>%
    add_optional_token() %>%
    req_retry(max_tries = 4) %>%
    req_timeout(seconds = 180) %>%
    req_perform()
}

# ---- Download paginated public reference ------------------------------------

cat("Querying expected Austin address-point count...\n")

count_response <- perform_request(
  soda2_json_endpoint,
  select = "count(*) AS expected_records",
  limit = 1L
)
count_body <- resp_body_json(count_response, simplifyVector = TRUE)
expected_records <- as.integer(count_body$expected_records[[1]])

if (is.na(expected_records) || expected_records < 1) {
  stop("Address-point count query returned an invalid value.")
}

cat("Expected address points: ", scales::comma(expected_records), "\n", sep = "")

pages <- list()
page_manifest <- list()
offset <- 0L
page_number <- 1L

repeat {
  cat("Downloading public address-point page ", page_number, "...\n", sep = "")

  response <- perform_request(
    soda2_csv_endpoint,
    select = "objectid, full_street_name, the_geom",
    limit = page_size,
    offset = offset,
    order = "objectid"
  )

  page <- read_csv(
    I(resp_body_string(response)),
    col_types = cols(.default = col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
  page_records <- nrow(page)

  page_manifest[[page_number]] <- tibble(
    page_number = page_number,
    offset = offset,
    page_size_requested = page_size,
    records_returned = page_records,
    first_objectid = if (page_records > 0) first(page$objectid) else NA,
    last_objectid = if (page_records > 0) last(page$objectid) else NA
  )

  if (page_records == 0) {
    break
  }

  pages[[page_number]] <- page

  if (page_records < page_size) {
    break
  }

  offset <- offset + page_size
  page_number <- page_number + 1L

  if (page_number > 20L) {
    stop("Address-point pagination exceeded 20 pages.")
  }
}

address_points_raw <- bind_rows(pages)
page_manifest <- bind_rows(page_manifest)

if (nrow(address_points_raw) != expected_records) {
  stop(
    "Address pagination QA failed: expected ", expected_records,
    " rows but downloaded ", nrow(address_points_raw), "."
  )
}

if (anyDuplicated(address_points_raw$objectid) > 0) {
  stop("Public address-point object IDs are not unique.")
}

required_columns <- c("objectid", "full_street_name", "the_geom")
missing_columns <- setdiff(required_columns, names(address_points_raw))

if (length(missing_columns) > 0) {
  stop(
    "Address-point response is missing: ",
    str_c(missing_columns, collapse = ", ")
  )
}

write_csv(
  address_points_raw,
  file.path(raw_dir, "austin_public_address_points.csv")
)
write_csv(
  page_manifest,
  file.path(raw_dir, "address_point_pagination_manifest.csv")
)

# ---- Create spatial reference and QA/QC -------------------------------------

address_points_valid <- address_points_raw %>%
  filter(
    !is.na(full_street_name),
    nzchar(full_street_name),
    !is.na(the_geom),
    str_detect(the_geom, "^POINT")
  )

address_points_sf <- st_as_sf(
  address_points_valid,
  wkt = "the_geom",
  crs = 4326,
  remove = TRUE
) %>%
  mutate(
    address_reference_id = as.character(objectid),
    full_street_name = str_squish(str_to_upper(full_street_name))
  ) %>%
  select(address_reference_id, full_street_name)

if (any(st_is_empty(address_points_sf))) {
  stop("Address-point conversion produced empty geometries.")
}

output_gpkg <- file.path(
  processed_dir,
  "austin_public_address_points.gpkg"
)

st_write(
  address_points_sf,
  output_gpkg,
  layer = "austin_address_points",
  delete_dsn = TRUE,
  quiet = TRUE
)

qaqc_summary <- tibble(
  metric = c(
    "dataset_id", "dataset_page_url", "retrieved_at_utc", "app_token_used",
    "api_expected_records", "api_downloaded_records",
    "records_with_valid_address_and_geometry", "duplicate_object_ids",
    "source_update_frequency", "privacy_use"
  ),
  value = c(
    dataset_id, dataset_page_url,
    format(Sys.time(), tz = "UTC", usetz = TRUE),
    as.character(nzchar(app_token)), as.character(expected_records),
    as.character(nrow(address_points_raw)), as.character(nrow(address_points_sf)),
    as.character(anyDuplicated(address_points_raw$objectid)), "Daily",
    "local reference matching; no confidential addresses transmitted"
  )
)

write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "austin_address_points_qaqc_summary.csv")
)

cat("\n=== Austin Address-Point Pull Complete ===\n")
cat("Valid address points: ", scales::comma(nrow(address_points_sf)), "\n", sep = "")
cat("Processed spatial output: ", output_gpkg, "\n", sep = "")
