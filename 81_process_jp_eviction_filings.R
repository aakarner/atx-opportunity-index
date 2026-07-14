# Process and QA/QC local Justice of the Peace eviction filing data
#
# This standalone script ingests locally supplied JP eviction-defendant reports,
# converts them to a case-level eviction-filing file, and writes QA/QC summaries.
#
# Methodological note:
# Eviction filings are treated as a housing instability / displacement-pressure
# overlay, not as a clustering input. The raw reports are defendant-level and
# include personal contact fields, so the processed outputs deliberately exclude
# defendant names, phone numbers, and email addresses. The address field in these
# exports is labeled "Correspondence Address"; it is retained only as a spatial
# proxy for later geocoding/aggregation and should be validated before being
# interpreted as the eviction property address.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "readxl", "lubridate", "digest"))

# ---- User-facing settings ----------------------------------------------------

raw_dir <- "data/raw/JP_evictions"
processed_dir <- "data/processed/evictions"
qaqc_dir <- "data/qaqc/evictions"
geocoded_addresses_path <- file.path(raw_dir, "eviction_addresses_geocoded.csv")

analysis_start_date <- as.Date("2020-01-01")

dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Helpers -----------------------------------------------------------------

clean_names <- function(x) {
  x %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "") %>%
    str_to_lower()
}

normalize_text <- function(x) {
  x %>%
    as.character() %>%
    str_replace_all("\\s+", " ") %>%
    str_squish() %>%
    na_if("")
}

normalize_address <- function(x) {
  x %>%
    normalize_text() %>%
    str_to_upper() %>%
    str_replace_all("\\bTEXAS\\b", "TX") %>%
    str_replace_all("\\s+", " ") %>%
    str_squish() %>%
    na_if("")
}

parse_file_date <- function(x) {
  if (inherits(x, "Date")) {
    return(as.Date(x))
  }

  if (inherits(x, "POSIXt")) {
    return(as.Date(x))
  }

  if (is.numeric(x)) {
    # Excel serial dates use 1899-12-30 as the standard R origin. This fixes
    # the Odyssey export that otherwise reads as years 2090-2096 if as.Date()
    # is applied directly to the serial values.
    return(as.Date(x, origin = "1899-12-30"))
  }

  x_chr <- str_squish(as.character(x))
  numeric_like <- str_detect(x_chr, "^\\d+(\\.\\d+)?$")
  out <- rep(as.Date(NA), length(x_chr))

  out[numeric_like] <- as.Date(
    suppressWarnings(as.numeric(x_chr[numeric_like])),
    origin = "1899-12-30"
  )

  parsed <- suppressWarnings(lubridate::parse_date_time(
    x_chr[!numeric_like],
    orders = c("ymd", "mdy", "m/d/Y", "m/d/y", "Y-m-d")
  ))

  out[!numeric_like] <- as.Date(parsed)
  out
}

find_header_row <- function(path, sheet = 1, max_rows = 100, max_cols = 52) {
  preview <- readxl::read_excel(
    path,
    sheet = sheet,
    range = readxl::cell_limits(c(1, 1), c(max_rows, max_cols)),
    col_names = FALSE,
    .name_repair = "minimal"
  )

  header_terms <- regex(
    "court|case|cause|file|date|status|defendant|address",
    ignore_case = TRUE
  )

  row_scores <- map_int(seq_len(nrow(preview)), function(i) {
    vals <- as.character(unlist(preview[i, ], use.names = FALSE))
    vals <- vals[!is.na(vals) & str_squish(vals) != ""]
    sum(str_detect(vals, header_terms))
  })

  header_row <- which(row_scores >= 4)

  if (length(header_row) == 0) {
    stop("Could not identify a header row in ", path, ".")
  }

  header_row[[1]]
}

read_eviction_workbook <- function(path) {
  sheet <- readxl::excel_sheets(path)[[1]]
  header_row <- find_header_row(path, sheet)

  readxl::read_excel(
    path,
    sheet = sheet,
    skip = header_row - 1,
    .name_repair = "unique_quiet"
  ) %>%
    rename_with(clean_names) %>%
    # Drop unnamed/blank columns created by the export layout.
    select(!matches("^x\\d+$|^\\d+$|^\\.\\.\\.")) %>%
    mutate(across(everything(), as.character)) %>%
    mutate(
      source_file = basename(path),
      source_sheet = sheet,
      source_header_row = header_row
    )
}

make_case_id <- function(case_key) {
  # Prefer a stable hash if the digest package is installed. Fall back to a
  # deterministic sequential ID otherwise.
  if (requireNamespace("digest", quietly = TRUE)) {
    paste0(
      "evict_",
      map_chr(case_key, digest::digest, algo = "xxhash64", serialize = FALSE)
    )
  } else {
    paste0("evict_", str_pad(seq_along(case_key), 6, pad = "0"))
  }
}

first_non_missing <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    return(NA)
  }
  x[[1]]
}

# ---- Read source files -------------------------------------------------------

eviction_files <- list.files(
  raw_dir,
  pattern = "\\.xlsx$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(eviction_files) == 0) {
  stop("No .xlsx files found in ", raw_dir, ".")
}

cat("Reading JP eviction workbooks...\n")

raw_eviction_rows <- map_dfr(eviction_files, read_eviction_workbook)

required_cols <- c(
  "court", "case_type", "case_number", "file_date",
  "case_status", "correspondence_address"
)
missing_cols <- setdiff(required_cols, names(raw_eviction_rows))

if (length(missing_cols) > 0) {
  stop(
    "The eviction report is missing expected columns: ",
    str_c(missing_cols, collapse = ", ")
  )
}

# ---- Clean and de-identify ---------------------------------------------------

cat("Cleaning eviction records...\n")

eviction_rows_clean <- raw_eviction_rows %>%
  mutate(
    court = normalize_text(court),
    case_type = normalize_text(case_type),
    case_number = normalize_text(case_number),
    file_date = parse_file_date(file_date),
    filing_year = year(file_date),
    case_status = normalize_text(case_status),
    correspondence_address_clean = normalize_address(correspondence_address),
    has_correspondence_address = !is.na(correspondence_address_clean),
    case_key = str_c(court, case_number, sep = "|"),
    source_date_out_of_range = is.na(file_date) | file_date < analysis_start_date |
      file_date > Sys.Date()
  ) %>%
  filter(!is.na(court), !is.na(case_number))

eviction_case_level <- eviction_rows_clean %>%
  group_by(case_key) %>%
  summarise(
    court = first_non_missing(court),
    case_type = first_non_missing(case_type),
    file_date = suppressWarnings(min(file_date, na.rm = TRUE)),
    filing_year = year(file_date),
    case_status = first_non_missing(case_status),
    defendant_records = n(),
    source_files = str_c(sort(unique(source_file)), collapse = "; "),
    n_source_files = n_distinct(source_file),
    n_distinct_statuses = n_distinct(case_status, na.rm = TRUE),
    n_distinct_addresses = n_distinct(correspondence_address_clean, na.rm = TRUE),
    has_correspondence_address = any(has_correspondence_address, na.rm = TRUE),
    case_has_multiple_addresses = n_distinct(
      correspondence_address_clean,
      na.rm = TRUE
    ) > 1,
    correspondence_address_clean = first_non_missing(correspondence_address_clean),
    source_date_out_of_range = any(source_date_out_of_range, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    file_date = if_else(is.infinite(file_date), as.Date(NA), file_date),
    filing_year = year(file_date),
    status_group = case_when(
      str_detect(str_to_lower(case_status), "dismiss") ~ "Dismissed",
      str_detect(str_to_lower(case_status), "appeal") ~ "Appealed",
      str_detect(str_to_lower(case_status), "final|judgment|writ|satisfied") ~
        "Final/judgment-related",
      str_detect(str_to_lower(case_status), "active|pending|hearing|trial|set") ~
        "Active/pending/hearing",
      TRUE ~ "Other/unknown"
    )
  ) %>%
  filter(is.na(file_date) | file_date >= analysis_start_date) %>%
  arrange(file_date, court, case_key) %>%
  mutate(eviction_case_id = make_case_id(case_key), .before = case_key)

eviction_case_level_public <- eviction_case_level %>%
  select(
    eviction_case_id, court, case_type, file_date, filing_year,
    case_status, status_group, defendant_records, has_correspondence_address,
    case_has_multiple_addresses, correspondence_address_clean, source_files,
    n_source_files, n_distinct_statuses, n_distinct_addresses
  )

eviction_geocoding_file <- eviction_case_level_public %>%
  filter(has_correspondence_address) %>%
  select(
    eviction_case_id, correspondence_address_clean, court, file_date,
    filing_year, case_status, status_group, defendant_records,
    case_has_multiple_addresses
  )

# ---- Read supplied geocoded-address file, when available ---------------------

geocoded_addresses_clean <- NULL
case_geocode_join_summary <- tibble(
  metric = c(
    "geocoded_address_file_present",
    "case_join_method",
    "case_filings",
    "case_filings_with_address",
    "case_filings_matched_to_geocoded_address",
    "case_filings_with_valid_latlon"
  ),
  value = c(
    as.character(file.exists(geocoded_addresses_path)),
    "not_attempted",
    as.character(nrow(eviction_case_level_public)),
    as.character(sum(eviction_case_level_public$has_correspondence_address)),
    NA_character_,
    NA_character_
  )
)

if (file.exists(geocoded_addresses_path)) {
  cat("Reading supplied geocoded eviction-address file...\n")

  geocoded_addresses_raw <- readr::read_csv(
    geocoded_addresses_path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  ) %>%
    rename_with(clean_names)

  required_geocode_cols <- c(
    "address_id", "address_for_geocoding", "status",
    "score", "longitude", "latitude"
  )
  missing_geocode_cols <- setdiff(required_geocode_cols, names(geocoded_addresses_raw))

  if (length(missing_geocode_cols) > 0) {
    warning(
      "The supplied geocoded-address file is missing expected columns: ",
      str_c(missing_geocode_cols, collapse = ", ")
    )
  } else {
    geocoded_addresses_clean <- geocoded_addresses_raw %>%
      transmute(
        address_id = normalize_text(address_id),
        address_for_geocoding = normalize_address(address_for_geocoding),
        geocode_status = normalize_text(status),
        geocode_score = readr::parse_number(score),
        geocode_match_address = normalize_address(match_addr),
        geocode_address_type = normalize_text(addr_type),
        geocode_city = normalize_text(city),
        geocode_region = normalize_text(region_abbr),
        geocode_postal = normalize_text(postal),
        geocode_distance = if ("distance" %in% names(geocoded_addresses_raw)) {
          readr::parse_number(distance)
        } else {
          NA_real_
        },
        longitude = readr::parse_number(longitude),
        latitude = readr::parse_number(latitude),
        geocode_coordinate_status = case_when(
          is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
          longitude < -107 | longitude > -93 | latitude < 25 | latitude > 37 ~
            "outside_texas_bbox",
          TRUE ~ "valid_coordinate"
        )
      )

    case_geocode_exact_join <- eviction_case_level_public %>%
      mutate(join_address = normalize_address(correspondence_address_clean)) %>%
      left_join(
        geocoded_addresses_clean %>%
          mutate(join_address = normalize_address(address_for_geocoding)) %>%
          select(
            join_address, address_id, geocode_status, geocode_score,
            geocode_address_type, longitude, latitude,
            geocode_coordinate_status
          ),
        by = "join_address"
      )

    case_geocode_join_summary <- tibble(
      metric = c(
        "geocoded_address_file_present",
        "case_join_method",
        "case_filings",
        "case_filings_with_address",
        "case_filings_matched_to_geocoded_address",
        "case_filings_with_valid_latlon"
      ),
      value = c(
        "TRUE",
        paste0(
          "exact normalized correspondence_address_clean to ",
          "address_for_geocoding"
        ),
        as.character(nrow(case_geocode_exact_join)),
        as.character(sum(!is.na(case_geocode_exact_join$join_address))),
        as.character(sum(!is.na(case_geocode_exact_join$address_id))),
        as.character(sum(
          case_geocode_exact_join$geocode_coordinate_status == "valid_coordinate",
          na.rm = TRUE
        ))
      )
    )

    if (sum(!is.na(case_geocode_exact_join$address_id)) > 0) {
      readr::write_csv(
        case_geocode_exact_join %>%
          select(-join_address),
        file.path(
          processed_dir,
          "jp_eviction_filings_case_level_geocoded_exact_address_join.csv"
        )
      )
    }
  }
}

# ---- Write processed outputs -------------------------------------------------

cat("Writing processed eviction outputs...\n")

readr::write_csv(
  eviction_case_level_public,
  file.path(processed_dir, "jp_eviction_filings_case_level.csv")
)

readr::write_csv(
  eviction_geocoding_file,
  file.path(processed_dir, "jp_eviction_filings_for_geocoding.csv")
)

if (!is.null(geocoded_addresses_clean)) {
  readr::write_csv(
    geocoded_addresses_clean,
    file.path(processed_dir, "jp_eviction_geocoded_addresses.csv")
  )
}

# ---- QA/QC summaries ---------------------------------------------------------

cat("Writing eviction QA/QC summaries...\n")

date_min <- suppressWarnings(min(eviction_case_level$file_date, na.rm = TRUE))
date_max <- suppressWarnings(max(eviction_case_level$file_date, na.rm = TRUE))

qaqc_summary <- tibble(
  metric = c(
    "raw_directory",
    "source_workbooks",
    "raw_defendant_rows_read",
    "clean_defendant_rows_with_court_case",
    "case_level_filings_since_start_date",
    "analysis_start_date",
    "min_case_file_date",
    "max_case_file_date",
    "case_filings_with_missing_date",
    "case_filings_with_address",
    "case_filings_without_address",
    "case_filings_with_multiple_addresses",
    "case_filings_from_multiple_source_files",
    "source_rows_with_date_out_of_range",
    "personal_contact_fields_dropped",
    "spatial_address_caveat"
  ),
  value = c(
    raw_dir,
    as.character(length(eviction_files)),
    as.character(nrow(raw_eviction_rows)),
    as.character(nrow(eviction_rows_clean)),
    as.character(nrow(eviction_case_level)),
    as.character(analysis_start_date),
    as.character(date_min),
    as.character(date_max),
    as.character(sum(is.na(eviction_case_level$file_date))),
    as.character(sum(eviction_case_level$has_correspondence_address)),
    as.character(sum(!eviction_case_level$has_correspondence_address)),
    as.character(sum(eviction_case_level$case_has_multiple_addresses)),
    as.character(sum(eviction_case_level$n_source_files > 1)),
    as.character(sum(eviction_rows_clean$source_date_out_of_range, na.rm = TRUE)),
    "defendant_name; home_phone; cell_phone; email_address",
    "correspondence_address is a spatial proxy and may not always be the eviction property address"
  )
)

readr::write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "jp_evictions_qaqc_summary.csv")
)

annual_counts <- eviction_case_level %>%
  count(filing_year, status_group, name = "case_filings") %>%
  arrange(filing_year, status_group)

readr::write_csv(
  annual_counts,
  file.path(qaqc_dir, "jp_evictions_annual_counts.csv")
)

court_counts <- eviction_case_level %>%
  count(court, filing_year, status_group, name = "case_filings") %>%
  arrange(court, filing_year, status_group)

readr::write_csv(
  court_counts,
  file.path(qaqc_dir, "jp_evictions_court_year_status_counts.csv")
)

address_qaqc <- eviction_case_level %>%
  summarise(
    case_filings = n(),
    with_address = sum(has_correspondence_address),
    without_address = sum(!has_correspondence_address),
    multiple_addresses = sum(case_has_multiple_addresses),
    unique_addresses = n_distinct(correspondence_address_clean, na.rm = TRUE),
    repeat_address_case_filings = sum(duplicated(correspondence_address_clean) &
      !is.na(correspondence_address_clean))
  )

readr::write_csv(
  address_qaqc,
  file.path(qaqc_dir, "jp_evictions_address_qaqc.csv")
)

source_file_summary <- eviction_rows_clean %>%
  count(source_file, court, name = "defendant_rows") %>%
  arrange(source_file, court)

readr::write_csv(
  source_file_summary,
  file.path(qaqc_dir, "jp_evictions_source_file_summary.csv")
)

readr::write_csv(
  case_geocode_join_summary,
  file.path(qaqc_dir, "jp_evictions_geocode_case_join_qaqc.csv")
)

if (!is.null(geocoded_addresses_clean)) {
  geocode_qaqc_summary <- tibble(
    metric = c(
      "geocoded_address_rows",
      "unique_address_ids",
      "unique_address_inputs",
      "matched_status_m",
      "tied_status_t",
      "unmatched_status_u",
      "missing_latlon",
      "outside_texas_bbox",
      "valid_latlon",
      "min_score",
      "median_score",
      "mean_score"
    ),
    value = c(
      as.character(nrow(geocoded_addresses_clean)),
      as.character(n_distinct(geocoded_addresses_clean$address_id)),
      as.character(n_distinct(geocoded_addresses_clean$address_for_geocoding)),
      as.character(sum(geocoded_addresses_clean$geocode_status == "M", na.rm = TRUE)),
      as.character(sum(geocoded_addresses_clean$geocode_status == "T", na.rm = TRUE)),
      as.character(sum(geocoded_addresses_clean$geocode_status == "U", na.rm = TRUE)),
      as.character(sum(geocoded_addresses_clean$geocode_coordinate_status == "missing_coordinate")),
      as.character(sum(geocoded_addresses_clean$geocode_coordinate_status == "outside_texas_bbox")),
      as.character(sum(geocoded_addresses_clean$geocode_coordinate_status == "valid_coordinate")),
      as.character(min(geocoded_addresses_clean$geocode_score, na.rm = TRUE)),
      as.character(median(geocoded_addresses_clean$geocode_score, na.rm = TRUE)),
      as.character(mean(geocoded_addresses_clean$geocode_score, na.rm = TRUE))
    )
  )

  geocode_address_type_counts <- geocoded_addresses_clean %>%
    count(geocode_address_type, sort = TRUE, name = "addresses")

  readr::write_csv(
    geocode_qaqc_summary,
    file.path(qaqc_dir, "jp_evictions_geocoded_addresses_qaqc.csv")
  )

  readr::write_csv(
    geocode_address_type_counts,
    file.path(qaqc_dir, "jp_evictions_geocoded_address_type_counts.csv")
  )
}

cat("\nJP eviction processing complete.\n")
cat("Case-level filings: ", nrow(eviction_case_level), "\n", sep = "")
cat("Processed files written to: ", processed_dir, "\n", sep = "")
cat("QA/QC files written to: ", qaqc_dir, "\n", sep = "")
