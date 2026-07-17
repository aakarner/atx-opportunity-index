# Pull and QA/QC development-pressure inputs from Austin issued permits
#
# This step-20 experimental measure uses geocoded Building Permit records
# issued during 2020-2024. It is retained for method development but does not
# enter the submitted step-22 clusters. The script retains identifiable new
# housing and residential demolition permits while excluding trade permits,
# repairs, accessory structures, hotels, and other records whose housing-unit
# fields do not represent new or removed homes reliably.
#
# Authentication is optional for this public Socrata query. If available, set
# AUSTIN_OPEN_DATA_APP_TOKEN in the process environment. Never place a token or
# secret directly in this script or commit one to the repository.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "sf", "tigris", "httr2", "scales", "curl"
))

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

dataset_id <- "3syk-w9eu"
dataset_page_url <- paste0(
  "https://data.austintexas.gov/Building-and-Development/",
  "Issued-Construction-Permits/", dataset_id
)
soda2_endpoint <- paste0(
  "https://data.austintexas.gov/resource/", dataset_id, ".json"
)

analysis_years <- 2020:2024
city_boundary_year <- 2024
page_size <- 20000L
use_census_geocoder_fallback <- TRUE

raw_dir <- "data/raw/austin_open_data_development_permits"
processed_dir <- "data/processed/development_pressure"
qaqc_dir <- "data/qaqc/development_pressure"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")

# ---- Query definition --------------------------------------------------------

analysis_start <- sprintf("%d-01-01T00:00:00.000", min(analysis_years))
analysis_end_exclusive <- sprintf(
  "%d-01-01T00:00:00.000",
  max(analysis_years) + 1L
)

date_filter <- paste0(
  "issue_date >= '", analysis_start,
  "' AND issue_date < '", analysis_end_exclusive, "'"
)

record_filter <- paste0(
  date_filter,
  " AND permit_type_desc = 'Building Permit'",
  " AND work_class IN ('New', 'Demolition')"
)

selected_fields <- c(
  "project_id", "permit_number", "permit_type_desc", "permit_class_mapped",
  "permit_class", "work_class", "issue_date", "calendar_year_issued",
  "status_current", "housing_units", "total_new_add_sqft",
  "total_job_valuation", "permit_location", "original_address1",
  "original_city", "original_state", "original_zip", "jurisdiction",
  "latitude", "longitude"
)

# ---- Helpers -----------------------------------------------------------------

perform_soda2_query <- function(
  select,
  where,
  order = NULL,
  limit = page_size,
  offset = 0L
) {
  request_object <- request(soda2_endpoint) %>%
    req_url_query(
      `$select` = select,
      `$where` = where,
      `$limit` = as.integer(limit),
      `$offset` = as.integer(offset)
    )

  if (!is.null(order)) {
    request_object <- request_object %>% req_url_query(`$order` = order)
  }

  if (nzchar(app_token)) {
    request_object <- request_object %>%
      req_headers(`X-App-Token` = app_token)
  }

  response <- request_object %>%
    req_retry(max_tries = 4) %>%
    req_timeout(seconds = 180) %>%
    req_perform()

  body <- resp_body_json(response, simplifyVector = TRUE)

  if (length(body) == 0) {
    return(tibble())
  }

  as_tibble(body)
}

as_number <- function(x) {
  suppressWarnings(as.numeric(x))
}

geocode_missing_addresses <- function(data) {
  missing_coordinates <- data %>%
    filter(is.na(latitude) | is.na(longitude)) %>%
    mutate(
      geocode_street = str_squish(str_remove(
        coalesce(original_address1, ""),
        regex(
          "\\s+(UNIT|BLDG|BUILDING|STE|SUITE|APT|#)\\s*.*$",
          ignore_case = TRUE
        )
      )),
      geocode_city = coalesce(original_city, "Austin"),
      geocode_state = coalesce(original_state, "TX"),
      geocode_zip = as.character(original_zip)
    ) %>%
    filter(nzchar(geocode_street)) %>%
    distinct(geocode_street, geocode_city, geocode_state, geocode_zip) %>%
    mutate(address_key = row_number())

  if (nrow(missing_coordinates) == 0) {
    return(tibble())
  }

  if (nrow(missing_coordinates) > 10000) {
    stop("Census batch-geocoder input exceeds the 10,000-address limit.")
  }

  batch_input_path <- file.path(
    raw_dir,
    paste0("census_geocoder_input_", min(analysis_years), "_", max(analysis_years), ".csv")
  )
  batch_output_path <- file.path(
    raw_dir,
    paste0("census_geocoder_output_", min(analysis_years), "_", max(analysis_years), ".csv")
  )

  batch_input <- missing_coordinates %>%
    select(
      address_key, geocode_street, geocode_city, geocode_state, geocode_zip
    )

  write.table(
    batch_input,
    batch_input_path,
    sep = ",",
    row.names = FALSE,
    col.names = FALSE,
    quote = TRUE,
    na = ""
  )

  cat(
    "Submitting ", nrow(batch_input),
    " unique addresses to the Census batch geocoder...\n",
    sep = ""
  )

  response <- request(
    "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
  ) %>%
    req_body_multipart(
      addressFile = curl::form_file(batch_input_path),
      benchmark = "Public_AR_Current"
    ) %>%
    req_retry(max_tries = 4) %>%
    req_timeout(seconds = 300) %>%
    req_perform()

  writeBin(resp_body_raw(response), batch_output_path)

  # No_Match rows contain only three fields, while matched rows contain eight.
  # readr fills the absent trailing fields correctly; suppress the expected
  # variable-column-count warning for unmatched addresses.
  geocoder_results <- suppressWarnings(read_csv(
      batch_output_path,
      col_names = c(
        "address_key", "input_address", "match_status", "match_type",
        "matched_address", "coordinates", "tigerline_id", "side"
      ),
      col_types = cols(.default = col_character()),
      show_col_types = FALSE,
      progress = FALSE
    )) %>%
    mutate(
      address_key = as.integer(address_key),
      geocoder_longitude = as_number(str_extract(coordinates, "^-?[0-9.]+")),
      geocoder_latitude = as_number(str_extract(coordinates, "(?<=,)-?[0-9.]+")),
      census_geocoder_match = match_status == "Match"
    ) %>%
    select(
      address_key, match_status, match_type, matched_address,
      geocoder_longitude, geocoder_latitude, census_geocoder_match
    )

  missing_coordinates %>%
    left_join(geocoder_results, by = "address_key")
}

# ---- Pull paginated permit records ------------------------------------------

cat("Querying expected Austin building-permit count...\n")

count_result <- perform_soda2_query(
  select = "count(*) AS expected_records",
  where = record_filter,
  limit = 1L
)

if (!"expected_records" %in% names(count_result) || nrow(count_result) != 1) {
  stop("Permit count query did not return one expected_records value.")
}

expected_records <- as.integer(count_result$expected_records[[1]])

if (is.na(expected_records) || expected_records < 1) {
  stop("Permit count query returned an invalid count: ", expected_records)
}

cat("Expected records: ", scales::comma(expected_records), "\n", sep = "")

pages <- list()
page_manifest <- list()
offset <- 0L
page_number <- 1L

repeat {
  cat("Downloading permit page ", page_number, "...\n", sep = "")

  page <- perform_soda2_query(
    select = str_c(selected_fields, collapse = ", "),
    where = record_filter,
    order = "project_id",
    limit = page_size,
    offset = offset
  )

  page_records <- nrow(page)
  page_manifest[[page_number]] <- tibble(
    page_number = page_number,
    offset = offset,
    page_size_requested = page_size,
    records_returned = page_records,
    first_project_id = if (page_records > 0) first(page$project_id) else NA,
    last_project_id = if (page_records > 0) last(page$project_id) else NA
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
    stop("Permit pagination exceeded 20 pages; stopping as a safeguard.")
  }
}

permits_api_raw <- bind_rows(pages)
page_manifest <- bind_rows(page_manifest)

missing_fields <- setdiff(selected_fields, names(permits_api_raw))
if (length(missing_fields) > 0) {
  stop(
    "Austin permit response is missing required fields: ",
    str_c(missing_fields, collapse = ", ")
  )
}

if (nrow(permits_api_raw) != expected_records) {
  stop(
    "Pagination QA failed: expected ", expected_records,
    " permit records but downloaded ", nrow(permits_api_raw), "."
  )
}

if (anyDuplicated(permits_api_raw$project_id) > 0) {
  stop("Permit API returned duplicate project_id values.")
}

retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
analysis_year_label <- paste0(min(analysis_years), "_", max(analysis_years))

write_csv(
  permits_api_raw,
  file.path(
    raw_dir,
    paste0("austin_issued_building_permits_", analysis_year_label, ".csv")
  )
)
write_csv(
  page_manifest,
  file.path(raw_dir, paste0("permit_pagination_manifest_", analysis_year_label, ".csv"))
)

# ---- Classify housing development and demolition ----------------------------

new_housing_class_pattern <- regex(
  paste(
    "Single Family Houses?", "Secondary Apartment", "Two Family Bldgs?",
    "Three & Four Family Bldgs?", "Five or More Family Bldgs?", "Mixed Use",
    "^Residential$",
    sep = "|"
  ),
  ignore_case = TRUE
)

demolition_housing_class_pattern <- regex(
  "Demolition.*(Family|Residential|Bldgs Res)",
  ignore_case = TRUE
)

permits_clean <- permits_api_raw %>%
  mutate(
    permit_id = as.character(project_id),
    issue_date = as.Date(issue_date),
    permit_year = as.integer(calendar_year_issued),
    housing_units_reported = as_number(housing_units),
    latitude = as_number(latitude),
    longitude = as_number(longitude),
    permit_class = coalesce(permit_class, ""),
    new_housing_permit = work_class == "New" &
      str_detect(permit_class, new_housing_class_pattern),
    residential_demolition_permit = work_class == "Demolition" &
      str_detect(permit_class, demolition_housing_class_pattern),
    new_housing_units = if_else(
      new_housing_permit,
      pmax(coalesce(housing_units_reported, 0), 1),
      0
    ),
    residential_units_demolished = if_else(
      residential_demolition_permit,
      pmax(coalesce(housing_units_reported, 0), 1),
      0
    ),
    coordinate_status = case_when(
      is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
      longitude < -99 | longitude > -96 | latitude < 29 | latitude > 32 ~
        "outside_austin_region_bbox",
      TRUE ~ "valid_coordinate"
    )
  )

classified_permits <- permits_clean %>%
  filter(new_housing_permit | residential_demolition_permit)

if (nrow(classified_permits) < 1) {
  stop("No new-housing or residential-demolition permits were classified.")
}

# Austin's latitude/longitude fields are incomplete, particularly for some
# multifamily records. Recover missing coordinates from the original address
# using the public Census batch geocoder where possible.
census_geocodes <- tibble()

if (use_census_geocoder_fallback) {
  census_geocodes <- tryCatch(
    geocode_missing_addresses(classified_permits),
    error = function(error) {
      warning(
        "Census geocoder fallback failed; continuing with Austin coordinates: ",
        conditionMessage(error)
      )
      tibble()
    }
  )
}

if (nrow(census_geocodes) > 0) {
  classified_permits <- classified_permits %>%
    mutate(
      geocode_street = str_squish(str_remove(
        coalesce(original_address1, ""),
        regex(
          "\\s+(UNIT|BLDG|BUILDING|STE|SUITE|APT|#)\\s*.*$",
          ignore_case = TRUE
        )
      )),
      geocode_city = coalesce(original_city, "Austin"),
      geocode_state = coalesce(original_state, "TX"),
      geocode_zip = as.character(original_zip)
    ) %>%
    left_join(
      census_geocodes %>%
        select(
          geocode_street, geocode_city, geocode_state, geocode_zip,
          match_status, match_type, matched_address,
          geocoder_longitude, geocoder_latitude, census_geocoder_match
        ),
      by = c(
        "geocode_street", "geocode_city", "geocode_state", "geocode_zip"
      )
    ) %>%
    mutate(
      coordinate_source = case_when(
        !is.na(latitude) & !is.na(longitude) ~ "austin_open_data",
        census_geocoder_match ~ "census_batch_geocoder",
        TRUE ~ "missing_coordinate"
      ),
      latitude = coalesce(latitude, geocoder_latitude),
      longitude = coalesce(longitude, geocoder_longitude),
      coordinate_status = case_when(
        is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
        longitude < -99 | longitude > -96 | latitude < 29 | latitude > 32 ~
          "outside_austin_region_bbox",
        TRUE ~ "valid_coordinate"
      )
    )
} else {
  classified_permits <- classified_permits %>%
    mutate(
      coordinate_source = if_else(
        coordinate_status == "valid_coordinate",
        "austin_open_data",
        "missing_coordinate"
      ),
      census_geocoder_match = FALSE,
      match_type = NA_character_,
      matched_address = NA_character_
    )
}

# ---- Clip valid permit points to Austin -------------------------------------

cat("Pulling City of Austin boundary...\n")

austin_boundary <- places(state = "TX", year = city_boundary_year) %>%
  filter(NAME == "Austin") %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(austin_boundary) != 1) {
  stop("Expected one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

valid_permit_points <- classified_permits %>%
  filter(coordinate_status == "valid_coordinate") %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

inside_city <- lengths(st_intersects(valid_permit_points, austin_boundary)) > 0

permit_points_austin <- valid_permit_points %>%
  mutate(in_city_of_austin = inside_city) %>%
  filter(in_city_of_austin) %>%
  select(
    permit_id, permit_number, issue_date, permit_year, permit_class_mapped,
    permit_class, work_class, status_current, new_housing_permit,
    residential_demolition_permit, housing_units_reported,
    new_housing_units, residential_units_demolished, total_new_add_sqft,
    total_job_valuation, permit_location, original_address1, original_zip,
    original_city, original_state, jurisdiction, latitude, longitude,
    coordinate_source, coordinate_status, census_geocoder_match, match_type,
    matched_address, in_city_of_austin
  )

if (nrow(permit_points_austin) < 1) {
  stop("No classified development permits fell inside the Austin boundary.")
}

# ---- Save processed data and QA/QC ------------------------------------------

processed_csv <- file.path(
  processed_dir,
  "austin_development_pressure_permits_2020_2024.csv"
)
processed_gpkg <- file.path(
  processed_dir,
  "austin_development_pressure_permits_2020_2024.gpkg"
)

write_csv(st_drop_geometry(permit_points_austin), processed_csv)
st_write(
  permit_points_austin,
  processed_gpkg,
  layer = "development_pressure_permits",
  delete_dsn = TRUE,
  quiet = TRUE
)

classification_summary <- permits_clean %>%
  count(
    permit_class_mapped,
    permit_class,
    work_class,
    new_housing_permit,
    residential_demolition_permit,
    name = "records",
    sort = TRUE
  )

coordinate_qaqc <- classified_permits %>%
  count(coordinate_source, coordinate_status, name = "records", sort = TRUE)

qaqc_summary <- tibble(
  metric = c(
    "dataset_id", "dataset_page_url", "analysis_years", "retrieved_at_utc",
    "app_token_used", "api_expected_records", "api_downloaded_records",
    "classified_new_housing_permits", "classified_new_housing_units",
    "classified_residential_demolition_permits",
    "classified_residential_units_demolished",
    "classified_records_with_valid_coordinates",
    "unique_addresses_submitted_to_census_geocoder",
    "unique_addresses_matched_by_census_geocoder",
    "classified_records_geocoded_by_census",
    "classified_records_inside_austin",
    "austin_new_housing_permits", "austin_new_housing_units",
    "austin_residential_demolition_permits",
    "austin_residential_units_demolished"
  ),
  value = c(
    dataset_id, dataset_page_url,
    paste0(min(analysis_years), "-", max(analysis_years)), retrieved_at_utc,
    as.character(nzchar(app_token)), as.character(expected_records),
    as.character(nrow(permits_api_raw)),
    as.character(sum(classified_permits$new_housing_permit)),
    as.character(sum(classified_permits$new_housing_units)),
    as.character(sum(classified_permits$residential_demolition_permit)),
    as.character(sum(classified_permits$residential_units_demolished)),
    as.character(sum(classified_permits$coordinate_status == "valid_coordinate")),
    as.character(nrow(census_geocodes)),
    as.character(sum(census_geocodes$census_geocoder_match, na.rm = TRUE)),
    as.character(sum(
      classified_permits$coordinate_source == "census_batch_geocoder"
    )),
    as.character(nrow(permit_points_austin)),
    as.character(sum(permit_points_austin$new_housing_permit)),
    as.character(sum(permit_points_austin$new_housing_units)),
    as.character(sum(permit_points_austin$residential_demolition_permit)),
    as.character(sum(permit_points_austin$residential_units_demolished))
  )
)

write_csv(
  classification_summary,
  file.path(qaqc_dir, "development_permit_classification_summary.csv")
)
write_csv(
  coordinate_qaqc,
  file.path(qaqc_dir, "development_permit_coordinate_qaqc.csv")
)
write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "development_pressure_qaqc_summary.csv")
)

cat("\n=== Development-Pressure Pull Complete ===\n")
cat("API building permits reviewed: ", scales::comma(nrow(permits_api_raw)), "\n", sep = "")
cat("Austin new-housing permits: ", scales::comma(sum(permit_points_austin$new_housing_permit)), "\n", sep = "")
cat("Austin permitted housing units: ", scales::comma(sum(permit_points_austin$new_housing_units)), "\n", sep = "")
cat("Austin residential demolitions: ", scales::comma(sum(permit_points_austin$residential_demolition_permit)), "\n", sep = "")
cat("Processed spatial output: ", processed_gpkg, "\n", sep = "")
