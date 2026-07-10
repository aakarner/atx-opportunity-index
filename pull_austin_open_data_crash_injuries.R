# Pull and QA/QC crash-injury data from the City of Austin Open Data API
#
# PRIMARY WORKFLOW
#
# The City of Austin publishes crash-level records derived from TxDOT's Crash
# Records Information System (CRIS). The dataset covers crashes within current
# City of Austin full-purpose boundaries across public-safety jurisdictions and
# includes the location, severity, and mode-specific counts needed for the
# opportunity-index crash-injury exposure measure.
#
# This script:
#   1. Queries the Austin Open Data SODA3 API for the 2020-2024 analysis window.
#   2. Uses stable, authenticated pagination and validates the returned count.
#   3. Saves a dated raw-data snapshot and pagination manifest.
#   4. Derives fatal, suspected-serious-injury, KSI, and mode-specific flags.
#   5. Clips valid crash points to the 2024 Census City of Austin boundary.
#   6. Writes processed spatial files and QA/QC summaries.
#
# Authentication:
#   Set AUSTIN_OPEN_DATA_APP_TOKEN in the process environment before running.
#   The Socrata application secret is not needed for this public-data query.
#   Never place the token or secret directly in this script or commit them.
#
# The full CRIS public-extract workflow is retained separately in
# pull_txdot_cris_public_extract.R for future validation or regional expansion.

source("setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "httr2", "scales"))

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

dataset_id <- "y2wy-tgr5"
dataset_page_url <- paste0(
  "https://data.austintexas.gov/Transportation-and-Mobility/",
  "Austin-Crash-Report-Data-Crash-Level-Records/",
  dataset_id,
  "/about_data"
)
soda3_endpoint <- paste0(
  "https://data.austintexas.gov/api/v3/views/",
  dataset_id,
  "/query.json"
)

city_name <- "Austin"
state_abbr <- "TX"
city_boundary_year <- 2024

# This window matches the 2024 ACS five-year estimates used by the current
# proof of concept.
analysis_years <- 2020:2024

# SODA3 permits larger pages, but 25,000 rows keeps each response manageable
# while requiring only a few requests for the analysis window.
page_size <- 25000L

raw_dir <- "data/raw/austin_open_data_crashes"
processed_dir <- "data/processed/crash_injuries"
qaqc_dir <- "data/qaqc/crash_injuries"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")

if (!nzchar(app_token)) {
  stop(
    "AUSTIN_OPEN_DATA_APP_TOKEN is not set. Set it in the process environment ",
    "and rerun this script. Do not add the token to the script or repository."
  )
}

# ---- Query definition --------------------------------------------------------

analysis_start <- sprintf("%d-01-01T00:00:00", min(analysis_years))
analysis_end_exclusive <- sprintf("%d-01-01T00:00:00", max(analysis_years) + 1L)

date_filter <- paste0(
  "crash_timestamp_ct >= '", analysis_start,
  "' AND crash_timestamp_ct < '", analysis_end_exclusive, "'"
)

selected_fields <- c(
  "id",
  "cris_crash_id",
  "crash_fatal_fl",
  "crash_sev_id",
  "sus_serious_injry_cnt",
  "nonincap_injry_cnt",
  "poss_injry_cnt",
  "non_injry_cnt",
  "unkn_injry_cnt",
  "tot_injry_cnt",
  "death_cnt",
  "units_involved",
  "latitude",
  "longitude",
  "crash_timestamp_ct",
  "motor_vehicle_death_count",
  "motor_vehicle_serious_injury_count",
  "bicycle_death_count",
  "bicycle_serious_injury_count",
  "pedestrian_death_count",
  "pedestrian_serious_injury_count",
  "motorcycle_death_count",
  "motorcycle_serious_injury_count",
  "other_death_count",
  "other_serious_injury_count",
  "micromobility_death_count",
  "micromobility_serious_injury_count",
  "onsys_fl",
  "private_dr_fl",
  "is_deleted",
  "is_temp_record"
)

data_query <- paste0(
  "SELECT ", str_c(selected_fields, collapse = ", "),
  " WHERE ", date_filter,
  " ORDER BY id"
)

count_query <- paste0(
  "SELECT count(*) AS expected_records WHERE ",
  date_filter
)

# ---- Helpers -----------------------------------------------------------------

perform_soda3_query <- function(query, page_number = 1L, requested_page_size = page_size) {
  response <- request(soda3_endpoint) %>%
    req_headers(
      `X-App-Token` = app_token,
      Accept = "application/json"
    ) %>%
    req_body_json(
      list(
        query = query,
        page = list(
          pageNumber = as.integer(page_number),
          pageSize = as.integer(requested_page_size)
        ),
        includeSystem = FALSE,
        includeSynthetic = FALSE
      ),
      auto_unbox = TRUE
    ) %>%
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

as_flag <- function(x) {
  if (is.logical(x)) {
    return(replace_na(x, FALSE))
  }

  str_to_lower(as.character(x)) %in% c("true", "t", "yes", "y", "1")
}

coalesce_count <- function(x) {
  coalesce(as_number(x), 0)
}

# ---- Pull paginated SODA3 records -------------------------------------------

cat("Querying expected Austin crash record count...\n")

count_result <- perform_soda3_query(
  count_query,
  page_number = 1L,
  requested_page_size = 1L
)

if (!"expected_records" %in% names(count_result) || nrow(count_result) != 1) {
  stop("SODA3 count query did not return one expected_records value.")
}

expected_records <- as.integer(count_result$expected_records[[1]])

if (is.na(expected_records) || expected_records < 1) {
  stop("SODA3 count query returned an invalid record count: ", expected_records)
}

cat("Expected records: ", scales::comma(expected_records), "\n", sep = "")

pages <- list()
page_manifest <- list()
page_number <- 1L

repeat {
  cat("Downloading SODA3 page ", page_number, "...\n", sep = "")

  page <- perform_soda3_query(
    data_query,
    page_number = page_number,
    requested_page_size = page_size
  )

  page_records <- nrow(page)

  page_manifest[[page_number]] <- tibble(
    page_number = page_number,
    page_size_requested = page_size,
    records_returned = page_records,
    first_id = if (page_records > 0) as.character(first(page$id)) else NA_character_,
    last_id = if (page_records > 0) as.character(last(page$id)) else NA_character_
  )

  if (page_records == 0) {
    break
  }

  pages[[page_number]] <- page

  if (page_records < page_size) {
    break
  }

  page_number <- page_number + 1L

  if (page_number > 100L) {
    stop("Pagination exceeded 100 pages; stopping to prevent an unbounded pull.")
  }
}

crashes_api_raw <- bind_rows(pages)
page_manifest <- bind_rows(page_manifest)

missing_fields <- setdiff(selected_fields, names(crashes_api_raw))

if (length(missing_fields) > 0) {
  stop(
    "Austin Open Data response is missing required fields: ",
    str_c(missing_fields, collapse = ", ")
  )
}

if (nrow(crashes_api_raw) != expected_records) {
  stop(
    "Pagination QA failed: expected ", expected_records,
    " records but downloaded ", nrow(crashes_api_raw), "."
  )
}

if (anyDuplicated(crashes_api_raw$id) > 0) {
  stop("Pagination QA failed: duplicate Austin Vision Zero id values were returned.")
}

retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
raw_snapshot_path <- file.path(
  raw_dir,
  paste0(
    "austin_open_data_crash_level_records_",
    min(analysis_years),
    "_",
    max(analysis_years),
    ".csv"
  )
)

cat("Writing raw API snapshot...\n")
readr::write_csv(crashes_api_raw, raw_snapshot_path)
readr::write_csv(
  page_manifest,
  file.path(qaqc_dir, "austin_open_data_pagination_manifest.csv")
)

# ---- Standardize fields and derive crash flags ------------------------------

numeric_fields <- c(
  "crash_sev_id",
  "sus_serious_injry_cnt",
  "nonincap_injry_cnt",
  "poss_injry_cnt",
  "non_injry_cnt",
  "unkn_injry_cnt",
  "tot_injry_cnt",
  "death_cnt",
  "latitude",
  "longitude",
  "motor_vehicle_death_count",
  "motor_vehicle_serious_injury_count",
  "bicycle_death_count",
  "bicycle_serious_injury_count",
  "pedestrian_death_count",
  "pedestrian_serious_injury_count",
  "motorcycle_death_count",
  "motorcycle_serious_injury_count",
  "other_death_count",
  "other_serious_injury_count",
  "micromobility_death_count",
  "micromobility_serious_injury_count"
)

crashes <- crashes_api_raw %>%
  mutate(across(all_of(numeric_fields), as_number)) %>%
  transmute(
    austin_crash_id = as.character(id),
    crash_id = as.character(cris_crash_id),
    crash_timestamp_local = as.POSIXct(
      crash_timestamp_ct,
      format = "%Y-%m-%dT%H:%M:%OS",
      tz = "America/Chicago"
    ),
    crash_date = as.Date(str_sub(crash_timestamp_ct, 1, 10)),
    crash_year = as.integer(str_sub(crash_timestamp_ct, 1, 4)),
    latitude,
    longitude,
    units_involved = as.character(units_involved),
    crash_sev_id,
    death_count = coalesce_count(death_cnt),
    suspected_serious_injury_count = coalesce_count(sus_serious_injry_cnt),
    nonincapacitating_injury_count = coalesce_count(nonincap_injry_cnt),
    possible_injury_count = coalesce_count(poss_injry_cnt),
    not_injured_count = coalesce_count(non_injry_cnt),
    unknown_injury_count = coalesce_count(unkn_injry_cnt),
    total_injury_count = coalesce_count(tot_injry_cnt),
    motor_vehicle_death_count = coalesce_count(motor_vehicle_death_count),
    motor_vehicle_serious_injury_count = coalesce_count(motor_vehicle_serious_injury_count),
    bicycle_death_count = coalesce_count(bicycle_death_count),
    bicycle_serious_injury_count = coalesce_count(bicycle_serious_injury_count),
    pedestrian_death_count = coalesce_count(pedestrian_death_count),
    pedestrian_serious_injury_count = coalesce_count(pedestrian_serious_injury_count),
    motorcycle_death_count = coalesce_count(motorcycle_death_count),
    motorcycle_serious_injury_count = coalesce_count(motorcycle_serious_injury_count),
    other_death_count = coalesce_count(other_death_count),
    other_serious_injury_count = coalesce_count(other_serious_injury_count),
    micromobility_death_count = coalesce_count(micromobility_death_count),
    micromobility_serious_injury_count = coalesce_count(micromobility_serious_injury_count),
    crash_fatal_flag = as_flag(crash_fatal_fl),
    on_state_system = as_flag(onsys_fl),
    private_road = as_flag(private_dr_fl),
    is_deleted = as_flag(is_deleted),
    is_temp_record = as_flag(is_temp_record)
  ) %>%
  mutate(
    coordinate_status = case_when(
      is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
      longitude < -107 | longitude > -93 | latitude < 25 | latitude > 37 ~
        "outside_texas_bbox",
      TRUE ~ "valid_coordinate"
    ),
    fatal_crash = death_count > 0 |
      crash_sev_id == 4 |
      crash_fatal_flag,
    suspected_serious_injury_crash = suspected_serious_injury_count > 0 |
      crash_sev_id == 1,
    ksi_crash = fatal_crash | suspected_serious_injury_crash,
    pedestrian_ksi_count = pedestrian_death_count + pedestrian_serious_injury_count,
    bicycle_ksi_count = bicycle_death_count + bicycle_serious_injury_count,
    micromobility_ksi_count = micromobility_death_count +
      micromobility_serious_injury_count,
    motorcycle_ksi_count = motorcycle_death_count +
      motorcycle_serious_injury_count,
    vulnerable_road_user_ksi_count = pedestrian_ksi_count +
      bicycle_ksi_count +
      micromobility_ksi_count,
    vulnerable_road_user_ksi_crash = vulnerable_road_user_ksi_count > 0,
    pedestrian_involved = str_detect(
      str_to_upper(coalesce(units_involved, "")),
      "PEDESTRIAN"
    ) | pedestrian_ksi_count > 0,
    bicycle_involved = str_detect(
      str_to_upper(coalesce(units_involved, "")),
      "BICYCLE|PEDALCYCL"
    ) | bicycle_ksi_count > 0,
    micromobility_involved = str_detect(
      str_to_upper(coalesce(units_involved, "")),
      "MICROMOBILITY|SCOOTER"
    ) | micromobility_ksi_count > 0,
    pedestrian_or_bike_involved = pedestrian_involved |
      bicycle_involved |
      micromobility_involved
  )

# Exclude any soft-deleted or temporary records before spatial processing. The
# raw snapshot retains them for auditing should the source behavior change.
crashes_analysis <- crashes %>%
  filter(!is_deleted, !is_temp_record)

# ---- Spatial filter to the common Austin boundary ---------------------------

cat("Pulling the 2024 Census City of Austin boundary...\n")

austin_boundary <- tigris::places(
  state = state_abbr,
  year = city_boundary_year
) %>%
  filter(NAME == city_name) %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(austin_boundary) != 1) {
  stop("Expected one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

valid_points <- crashes_analysis %>%
  filter(coordinate_status == "valid_coordinate") %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

crashes_austin <- valid_points %>%
  st_filter(austin_boundary, .predicate = st_intersects)

ksi_austin <- crashes_austin %>%
  filter(ksi_crash)

# ---- Write processed outputs -------------------------------------------------

cat("Writing processed crash-injury outputs...\n")

readr::write_csv(
  crashes_austin %>% st_drop_geometry(),
  file.path(processed_dir, "austin_open_data_crashes.csv")
)

readr::write_csv(
  ksi_austin %>% st_drop_geometry(),
  file.path(processed_dir, "austin_open_data_ksi_crashes.csv")
)

if (nrow(crashes_austin) > 0) {
  st_write(
    crashes_austin,
    file.path(processed_dir, "austin_open_data_crashes.gpkg"),
    layer = "austin_open_data_crashes",
    delete_dsn = TRUE,
    quiet = TRUE
  )
}

if (nrow(ksi_austin) > 0) {
  st_write(
    ksi_austin,
    file.path(processed_dir, "austin_open_data_ksi_crashes.gpkg"),
    layer = "austin_open_data_ksi_crashes",
    delete_dsn = TRUE,
    quiet = TRUE
  )
}

# ---- QA/QC summaries ---------------------------------------------------------

cat("Writing crash-injury QA/QC summaries...\n")

duplicate_cris_ids <- crashes %>%
  filter(!is.na(crash_id), crash_id != "") %>%
  summarise(duplicates = sum(duplicated(crash_id))) %>%
  pull(duplicates)

qaqc_summary <- tibble(
  metric = c(
    "source_dataset_page",
    "source_dataset_id",
    "source_soda3_endpoint",
    "retrieved_at_utc",
    "raw_snapshot_path",
    "analysis_years",
    "city_boundary_year",
    "expected_api_records",
    "downloaded_api_records",
    "pagination_pages_with_records",
    "duplicate_austin_ids",
    "duplicate_cris_crash_ids",
    "missing_cris_crash_ids",
    "soft_deleted_records",
    "temporary_records",
    "valid_coordinate_records",
    "missing_coordinate_records",
    "outside_texas_bbox_records",
    "valid_points_outside_2024_austin_boundary",
    "austin_crash_records",
    "austin_ksi_crash_records",
    "austin_fatal_crash_records",
    "austin_suspected_serious_injury_crash_records",
    "austin_vulnerable_road_user_ksi_crash_records",
    "austin_pedestrian_ksi_count",
    "austin_bicycle_ksi_count",
    "austin_micromobility_ksi_count"
  ),
  value = c(
    dataset_page_url,
    dataset_id,
    soda3_endpoint,
    retrieved_at_utc,
    raw_snapshot_path,
    str_c(range(analysis_years), collapse = "-"),
    as.character(city_boundary_year),
    as.character(expected_records),
    as.character(nrow(crashes_api_raw)),
    as.character(sum(page_manifest$records_returned > 0)),
    as.character(sum(duplicated(crashes$austin_crash_id))),
    as.character(duplicate_cris_ids),
    as.character(sum(is.na(crashes$crash_id) | crashes$crash_id == "")),
    as.character(sum(crashes$is_deleted)),
    as.character(sum(crashes$is_temp_record)),
    as.character(sum(crashes_analysis$coordinate_status == "valid_coordinate")),
    as.character(sum(crashes_analysis$coordinate_status == "missing_coordinate")),
    as.character(sum(crashes_analysis$coordinate_status == "outside_texas_bbox")),
    as.character(nrow(valid_points) - nrow(crashes_austin)),
    as.character(nrow(crashes_austin)),
    as.character(nrow(ksi_austin)),
    as.character(sum(crashes_austin$fatal_crash)),
    as.character(sum(crashes_austin$suspected_serious_injury_crash)),
    as.character(sum(crashes_austin$vulnerable_road_user_ksi_crash)),
    as.character(sum(crashes_austin$pedestrian_ksi_count)),
    as.character(sum(crashes_austin$bicycle_ksi_count)),
    as.character(sum(crashes_austin$micromobility_ksi_count))
  )
)

readr::write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "austin_open_data_qaqc_summary.csv")
)

annual_counts <- crashes_austin %>%
  st_drop_geometry() %>%
  group_by(crash_year) %>%
  summarise(
    crashes = n(),
    ksi_crashes = sum(ksi_crash),
    fatal_crashes = sum(fatal_crash),
    suspected_serious_injury_crashes = sum(suspected_serious_injury_crash),
    deaths = sum(death_count),
    suspected_serious_injuries = sum(suspected_serious_injury_count),
    vulnerable_road_user_ksi_crashes = sum(vulnerable_road_user_ksi_crash),
    pedestrian_ksi = sum(pedestrian_ksi_count),
    bicycle_ksi = sum(bicycle_ksi_count),
    micromobility_ksi = sum(micromobility_ksi_count),
    .groups = "drop"
  ) %>%
  arrange(crash_year)

readr::write_csv(
  annual_counts,
  file.path(qaqc_dir, "austin_open_data_annual_counts.csv")
)

coordinate_qaqc <- crashes_analysis %>%
  count(coordinate_status, sort = TRUE, name = "records")

readr::write_csv(
  coordinate_qaqc,
  file.path(qaqc_dir, "austin_open_data_coordinate_qaqc.csv")
)

cat("\nAustin Open Data crash ingest complete.\n")
cat("Downloaded API records: ", scales::comma(nrow(crashes_api_raw)), "\n", sep = "")
cat("Crashes within the 2024 Austin boundary: ", scales::comma(nrow(crashes_austin)), "\n", sep = "")
cat("Austin KSI crashes: ", scales::comma(nrow(ksi_austin)), "\n", sep = "")
cat("Processed files written to: ", processed_dir, "\n", sep = "")
cat("QA/QC files written to: ", qaqc_dir, "\n", sep = "")
