# Ingest and QA/QC a TxDOT CRIS public extract for Austin
#
# BACKUP WORKFLOW: The project's primary crash-injury pull now uses the City of
# Austin Open Data API; see pull_austin_open_data_crash_injuries.R. Retain this script
# for future validation, regional expansion, or full CRIS extract ingestion.
#
# TxDOT CRIS is the authoritative source for Texas crash records. Unlike EPA
# FRS, the public bulk crash extract is not an anonymous one-click API download:
# TxDOT provides public extracts through the CRIS Query tool, request form, or
# the automated extract process after registration. This script therefore does
# two things:
#
#   1. Pulls the official public-extract specification workbook into data/raw.
#   2. Ingests a CRIS public extract zip/CSV that has been placed in
#      data/raw/txdot_cris, performs QA/QC, filters to the City of Austin, and
#      writes processed crash and KSI (fatal or suspected-serious injury) files.
#
# Optional: if you receive a direct, time-limited download URL from TxDOT, set
# TXDOT_CRIS_PUBLIC_EXTRACT_URL before running the script and it will download
# that file into data/raw/txdot_cris.

source("setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "readxl"))

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

city_name <- "Austin"
state_abbr <- "TX"
city_boundary_year <- 2024
analysis_equal_area_crs <- 5070

# The current proof-of-concept uses 2024 ACS 5-year data. A 2020-2024 crash
# window aligns with that period. Update this window if the main model adopts a
# different temporal alignment.
analysis_years <- 2020:2024

target_county_names <- c("HAYS", "TRAVIS", "WILLIAMSON")
target_city_name <- "AUSTIN"

raw_dir <- "data/raw/txdot_cris"
processed_dir <- "data/processed/crash_injuries"
qaqc_dir <- "data/qaqc/crash_injuries"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

spec_url <- paste0(
  "https://www.txdot.gov/content/dam/docs/division/trf/crash-records/",
  "public-extract-file-specification.xlsx"
)
spec_path <- file.path(raw_dir, "public-extract-file-specification.xlsx")

cris_download_url <- Sys.getenv("TXDOT_CRIS_PUBLIC_EXTRACT_URL", unset = "")
overwrite_download <- FALSE

# ---- Helpers -----------------------------------------------------------------

clean_names <- function(x) {
  x %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "") %>%
    str_to_lower()
}

first_existing <- function(data, candidates, required = TRUE, label = "column") {
  found <- intersect(candidates, names(data))
  if (length(found) == 0) {
    if (required) {
      stop("Could not find required ", label, ". Tried: ", str_c(candidates, collapse = ", "))
    }
    return(NA_character_)
  }
  found[[1]]
}

read_header_names <- function(path) {
  readr::read_csv(
    path,
    n_max = 0,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    progress = FALSE
  ) %>%
    names() %>%
    clean_names()
}

score_crash_file <- function(path) {
  header <- tryCatch(read_header_names(path), error = function(e) character())
  required <- c("crash_id", "crash_date")
  location_candidates <- c("latitude", "longitude", "rpt_latitude", "rpt_longitude")
  severity_candidates <- c("crash_sev_id", "death_cnt", "sus_serious_injry_cnt")

  sum(required %in% header) * 10 +
    sum(location_candidates %in% header) +
    sum(severity_candidates %in% header)
}

copy_or_download_if_url <- function(url, dest) {
  if (!nzchar(url)) {
    return(invisible(FALSE))
  }

  if (file.exists(dest) && !overwrite_download) {
    cat("Using existing CRIS extract download: ", dest, "\n", sep = "")
    return(invisible(TRUE))
  }

  cat("Downloading CRIS public extract from TXDOT_CRIS_PUBLIC_EXTRACT_URL...\n")
  utils::download.file(url, destfile = dest, mode = "wb", quiet = FALSE)
  invisible(TRUE)
}

safe_number <- function(x) {
  suppressWarnings(as.numeric(x))
}

# ---- Pull official specification --------------------------------------------

if (!file.exists(spec_path) || overwrite_download) {
  cat("Downloading TxDOT public extract specification workbook...\n")
  utils::download.file(spec_url, destfile = spec_path, mode = "wb", quiet = FALSE)
} else {
  cat("Using existing TxDOT public extract specification: ", spec_path, "\n", sep = "")
}

county_lookup <- readxl::read_excel(spec_path, sheet = "CNTY_LKP") %>%
  rename_with(clean_names) %>%
  mutate(cris_cnty_desc = str_to_upper(cris_cnty_desc)) %>%
  filter(cris_cnty_desc %in% target_county_names) %>%
  transmute(
    county_id = as.character(cris_cnty_id),
    county_name = cris_cnty_desc
  )

city_lookup <- readxl::read_excel(spec_path, sheet = "CITY_LKP") %>%
  rename_with(clean_names) %>%
  mutate(city_desc = str_to_upper(city_desc)) %>%
  filter(city_desc == target_city_name) %>%
  transmute(
    city_id = as.character(city_id),
    city_name = city_desc
  )

crash_severity_lookup <- readxl::read_excel(spec_path, sheet = "CRASH_SEV_LKP") %>%
  rename_with(clean_names) %>%
  transmute(
    crash_sev_id = as.character(crash_sev_id),
    crash_sev_desc = crash_sev_desc
  ) %>%
  distinct()

if (nrow(county_lookup) != length(target_county_names)) {
  warning("Did not find all target counties in TxDOT CNTY_LKP.")
}

if (nrow(city_lookup) == 0) {
  warning("Did not find Austin in TxDOT CITY_LKP; spatial filtering will still be applied.")
}

# ---- Locate or download CRIS public extract ---------------------------------

if (nzchar(cris_download_url)) {
  dest_name <- basename(strsplit(cris_download_url, "\\?")[[1]][[1]])
  if (!nzchar(dest_name) || dest_name == "/") {
    dest_name <- paste0("txdot_cris_public_extract_", Sys.Date(), ".zip")
  }
  copy_or_download_if_url(cris_download_url, file.path(raw_dir, dest_name))
}

candidate_archives <- list.files(
  raw_dir,
  pattern = "\\.(zip|csv)$",
  full.names = TRUE,
  ignore.case = TRUE
) %>%
  setdiff(spec_path)

if (length(candidate_archives) == 0) {
  stop(
    "No CRIS public extract found in ", raw_dir, ".\n",
    "Place the TxDOT public extract zip/CSV there, or set ",
    "TXDOT_CRIS_PUBLIC_EXTRACT_URL to a direct TxDOT-provided download URL.\n",
    "Official source: https://www.txdot.gov/data-maps/crash-reports-records/",
    "crash-data-analysis-statistics.html"
  )
}

extract_dir <- file.path(raw_dir, "extract")
dir.create(extract_dir, showWarnings = FALSE, recursive = TRUE)

csv_files <- character()

for (archive in candidate_archives) {
  if (str_detect(str_to_lower(archive), "\\.zip$")) {
    cat("Extracting CRIS archive: ", archive, "\n", sep = "")
    utils::unzip(archive, exdir = extract_dir, overwrite = TRUE)
  } else {
    csv_files <- c(csv_files, archive)
  }
}

csv_files <- c(
  csv_files,
  list.files(extract_dir, pattern = "\\.csv$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
) %>%
  unique()

if (length(csv_files) == 0) {
  stop("Found CRIS archives but no CSV files after extraction.")
}

file_scores <- tibble(
  path = csv_files,
  crash_file_score = map_dbl(csv_files, score_crash_file)
) %>%
  arrange(desc(crash_file_score), path)

crash_file <- file_scores %>%
  filter(crash_file_score == max(crash_file_score)) %>%
  slice(1) %>%
  pull(path)

if (length(crash_file) != 1 || max(file_scores$crash_file_score) < 20) {
  stop(
    "Could not confidently identify the CRIS crash CSV. Candidate file scores written to QA/QC."
  )
}

readr::write_csv(file_scores, file.path(qaqc_dir, "txdot_cris_candidate_file_scores.csv"))

cat("Reading CRIS crash file: ", crash_file, "\n", sep = "")

crashes_raw <- readr::read_csv(
  crash_file,
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
) %>%
  rename_with(clean_names)

# Optional unit file: useful for pedestrian/pedalcyclist flags when present.
unit_file <- csv_files[
  map_lgl(csv_files, function(path) {
    header <- tryCatch(read_header_names(path), error = function(e) character())
    all(c("crash_id", "unit_nbr") %in% header) &&
      any(c("pbcat_pedestrian_id", "pbcat_pedalcyclist_id", "pedestrian_action_id", "pedalcyclist_action_id") %in% header)
  })
] %>%
  setdiff(crash_file) %>%
  first()

units_raw <- NULL

if (!is.na(unit_file) && length(unit_file) == 1) {
  cat("Reading optional CRIS unit file for pedestrian/pedalcyclist flags: ", unit_file, "\n", sep = "")
  units_raw <- readr::read_csv(
    unit_file,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  ) %>%
    rename_with(clean_names)
}

# ---- Standardize columns and derive flags -----------------------------------

id_col <- first_existing(crashes_raw, c("crash_id"), label = "crash ID column")
date_col <- first_existing(crashes_raw, c("crash_date"), label = "crash date column")
lat_col <- first_existing(crashes_raw, c("latitude", "rpt_latitude"), label = "latitude column")
lon_col <- first_existing(crashes_raw, c("longitude", "rpt_longitude"), label = "longitude column")
county_col <- first_existing(crashes_raw, c("cnty_id", "rpt_cris_cnty_id"), required = FALSE)
city_col <- first_existing(crashes_raw, c("city_id", "rpt_city_id"), required = FALSE)
severity_col <- first_existing(crashes_raw, c("crash_sev_id"), required = FALSE)
death_col <- first_existing(crashes_raw, c("death_cnt"), required = FALSE)
serious_col <- first_existing(crashes_raw, c("sus_serious_injry_cnt"), required = FALSE)
total_injury_col <- first_existing(crashes_raw, c("tot_injry_cnt"), required = FALSE)
fatal_flag_col <- first_existing(crashes_raw, c("crash_fatal_fl"), required = FALSE)
harm_event_col <- first_existing(crashes_raw, c("harm_evnt_id"), required = FALSE)

crashes <- crashes_raw %>%
  transmute(
    crash_id = .data[[id_col]],
    crash_date = as.Date(.data[[date_col]], tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y")),
    crash_year = as.integer(format(crash_date, "%Y")),
    latitude = safe_number(.data[[lat_col]]),
    longitude = safe_number(.data[[lon_col]]),
    county_id = if (!is.na(county_col)) as.character(.data[[county_col]]) else NA_character_,
    city_id = if (!is.na(city_col)) as.character(.data[[city_col]]) else NA_character_,
    crash_sev_id = if (!is.na(severity_col)) as.character(.data[[severity_col]]) else NA_character_,
    death_count = if (!is.na(death_col)) safe_number(.data[[death_col]]) else NA_real_,
    suspected_serious_injury_count = if (!is.na(serious_col)) safe_number(.data[[serious_col]]) else NA_real_,
    total_injury_count = if (!is.na(total_injury_col)) safe_number(.data[[total_injury_col]]) else NA_real_,
    crash_fatal_flag = if (!is.na(fatal_flag_col)) str_to_upper(.data[[fatal_flag_col]]) else NA_character_,
    harm_event_id = if (!is.na(harm_event_col)) as.character(.data[[harm_event_col]]) else NA_character_
  ) %>%
  left_join(county_lookup, by = "county_id") %>%
  left_join(city_lookup, by = "city_id") %>%
  left_join(crash_severity_lookup, by = "crash_sev_id") %>%
  mutate(
    coordinate_status = case_when(
      is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
      longitude < -107 | longitude > -93 | latitude < 25 | latitude > 37 ~
        "outside_texas_bbox",
      TRUE ~ "valid_coordinate"
    ),
    fatal_crash = coalesce(death_count, 0) > 0 |
      crash_sev_id == "4" |
      crash_fatal_flag %in% c("Y", "YES", "1", "TRUE"),
    suspected_serious_injury_crash = coalesce(suspected_serious_injury_count, 0) > 0 |
      crash_sev_id == "1",
    ksi_crash = fatal_crash | suspected_serious_injury_crash,
    pedestrian_or_bike_harm_event = harm_event_id %in% c("1", "5")
  )

if (!is.null(units_raw)) {
  unit_vru <- units_raw %>%
    transmute(
      crash_id = .data[["crash_id"]],
      pedestrian_unit = if ("pbcat_pedestrian_id" %in% names(units_raw)) {
        !is.na(pbcat_pedestrian_id) & !pbcat_pedestrian_id %in% c("-2", "-1", "0", "97", "98", "99")
      } else if ("pedestrian_action_id" %in% names(units_raw)) {
        !is.na(pedestrian_action_id) & !pedestrian_action_id %in% c("-2", "-1", "0", "97", "98", "99")
      } else {
        FALSE
      },
      pedalcyclist_unit = if ("pbcat_pedalcyclist_id" %in% names(units_raw)) {
        !is.na(pbcat_pedalcyclist_id) & !pbcat_pedalcyclist_id %in% c("-2", "-1", "0", "97", "98", "99")
      } else if ("pedalcyclist_action_id" %in% names(units_raw)) {
        !is.na(pedalcyclist_action_id) & !pedalcyclist_action_id %in% c("-2", "-1", "0", "97", "98", "99")
      } else {
        FALSE
      }
    ) %>%
    group_by(crash_id) %>%
    summarise(
      pedestrian_involved_unit = any(pedestrian_unit, na.rm = TRUE),
      pedalcyclist_involved_unit = any(pedalcyclist_unit, na.rm = TRUE),
      .groups = "drop"
    )

  crashes <- crashes %>%
    left_join(unit_vru, by = "crash_id") %>%
    mutate(
      pedestrian_involved_unit = coalesce(pedestrian_involved_unit, FALSE),
      pedalcyclist_involved_unit = coalesce(pedalcyclist_involved_unit, FALSE),
      pedestrian_or_bike_involved = pedestrian_or_bike_harm_event |
        pedestrian_involved_unit |
        pedalcyclist_involved_unit
    )
} else {
  crashes <- crashes %>%
    mutate(
      pedestrian_involved_unit = NA,
      pedalcyclist_involved_unit = NA,
      pedestrian_or_bike_involved = pedestrian_or_bike_harm_event
    )
}

crashes_window <- crashes %>%
  filter(crash_year %in% analysis_years)

# ---- Spatial filter to Austin ------------------------------------------------

cat("Pulling City of Austin boundary...\n")

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

valid_points <- crashes_window %>%
  filter(coordinate_status == "valid_coordinate") %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  st_make_valid()

crashes_austin <- valid_points %>%
  st_filter(austin_boundary, .predicate = st_intersects)

ksi_austin <- crashes_austin %>%
  filter(ksi_crash)

# ---- Write processed outputs -------------------------------------------------

cat("Writing processed CRIS outputs...\n")

readr::write_csv(
  crashes_austin %>% st_drop_geometry(),
  file.path(processed_dir, "txdot_cris_austin_crashes.csv")
)

readr::write_csv(
  ksi_austin %>% st_drop_geometry(),
  file.path(processed_dir, "txdot_cris_austin_ksi_crashes.csv")
)

if (nrow(crashes_austin) > 0) {
  st_write(
    crashes_austin,
    file.path(processed_dir, "txdot_cris_austin_crashes.gpkg"),
    layer = "txdot_cris_austin_crashes",
    delete_dsn = TRUE,
    quiet = TRUE
  )
}

if (nrow(ksi_austin) > 0) {
  st_write(
    ksi_austin,
    file.path(processed_dir, "txdot_cris_austin_ksi_crashes.gpkg"),
    layer = "txdot_cris_austin_ksi_crashes",
    delete_dsn = TRUE,
    quiet = TRUE
  )
}

# ---- QA/QC summaries ---------------------------------------------------------

cat("Writing CRIS QA/QC summaries...\n")

qaqc_summary <- tibble(
  metric = c(
    "source_spec_url",
    "spec_path",
    "crash_file_used",
    "unit_file_used",
    "analysis_years",
    "raw_crash_records",
    "records_in_analysis_window",
    "valid_coordinate_records_in_window",
    "missing_coordinate_records_in_window",
    "outside_texas_bbox_records_in_window",
    "austin_crash_records",
    "austin_ksi_crash_records",
    "austin_fatal_crash_records",
    "austin_suspected_serious_injury_crash_records",
    "austin_pedestrian_or_bike_ksi_records",
    "duplicate_crash_ids_raw"
  ),
  value = c(
    spec_url,
    spec_path,
    crash_file,
    ifelse(is.na(unit_file), NA_character_, unit_file),
    str_c(range(analysis_years), collapse = "-"),
    as.character(nrow(crashes_raw)),
    as.character(nrow(crashes_window)),
    as.character(sum(crashes_window$coordinate_status == "valid_coordinate")),
    as.character(sum(crashes_window$coordinate_status == "missing_coordinate")),
    as.character(sum(crashes_window$coordinate_status == "outside_texas_bbox")),
    as.character(nrow(crashes_austin)),
    as.character(nrow(ksi_austin)),
    as.character(sum(crashes_austin$fatal_crash, na.rm = TRUE)),
    as.character(sum(crashes_austin$suspected_serious_injury_crash, na.rm = TRUE)),
    as.character(sum(ksi_austin$pedestrian_or_bike_involved, na.rm = TRUE)),
    as.character(sum(duplicated(crashes_raw[[id_col]])))
  )
)

readr::write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "txdot_cris_qaqc_summary.csv")
)

annual_counts <- crashes_austin %>%
  st_drop_geometry() %>%
  count(
    crash_year,
    ksi_crash,
    fatal_crash,
    suspected_serious_injury_crash,
    pedestrian_or_bike_involved,
    name = "crashes"
  ) %>%
  arrange(crash_year, desc(ksi_crash), desc(fatal_crash))

readr::write_csv(
  annual_counts,
  file.path(qaqc_dir, "txdot_cris_austin_annual_counts.csv")
)

coordinate_qaqc <- crashes_window %>%
  count(county_name, city_name, coordinate_status, sort = TRUE, name = "records")

readr::write_csv(
  coordinate_qaqc,
  file.path(qaqc_dir, "txdot_cris_coordinate_qaqc.csv")
)

cat("\nTxDOT CRIS ingest complete.\n")
cat("Austin KSI crashes in analysis window: ", nrow(ksi_austin), "\n", sep = "")
cat("Processed files written to: ", processed_dir, "\n", sep = "")
cat("QA/QC files written to: ", qaqc_dir, "\n", sep = "")
