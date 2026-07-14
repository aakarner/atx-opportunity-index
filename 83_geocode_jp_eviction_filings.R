# Locally match and QA/QC de-identified JP eviction-filing address proxies
#
# Run 81_process_jp_eviction_filings.R and
# 82_pull_austin_open_data_address_points.R
# first. This script performs normalized exact matching entirely on the local
# machine. Locally supplied court addresses are never transmitted to an
# external service.
#
# Methodological caution:
# The court export labels this field "Correspondence Address." It may represent
# a mailing address rather than the property named in the eviction action.
# Results therefore remain an experimental housing-instability overlay, not a
# cluster input or definitive property-level eviction database.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "scales"))

options(tigris_use_cache = TRUE)

# ---- User-facing settings ----------------------------------------------------

analysis_years <- 2020:2024
city_boundary_year <- 2024

input_file <- paste0(
  "data/processed/evictions/",
  "jp_eviction_filings_for_geocoding.csv"
)
address_reference_file <- paste0(
  "data/processed/address_reference/",
  "austin_public_address_points.gpkg"
)
processed_dir <- "data/processed/evictions"
qaqc_dir <- "data/qaqc/evictions"

dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

required_files <- c(input_file, address_reference_file)
missing_files <- required_files[!file.exists(required_files)]

if (length(missing_files) > 0) {
  stop(
    "Missing local eviction-geocoding inputs: ",
    str_c(missing_files, collapse = ", "),
    ". Run the JP processing and Austin address-point pull scripts first."
  )
}

# ---- Helpers -----------------------------------------------------------------

normalize_address_key <- function(x) {
  x %>%
    str_to_upper() %>%
    str_replace_all("[.,]", " ") %>%
    str_replace_all("\\bINTERSTATE\\b", "IH") %>%
    str_replace_all("\\bSTATE HIGHWAY\\b", "SH") %>%
    str_replace_all("\\bUS HIGHWAY\\b", "US") %>%
    str_replace_all("\\bEAST\\b", "E") %>%
    str_replace_all("\\bWEST\\b", "W") %>%
    str_replace_all("\\bNORTH\\b", "N") %>%
    str_replace_all("\\bSOUTH\\b", "S") %>%
    str_replace_all("\\bSTREET\\b", "ST") %>%
    str_replace_all("\\bROAD\\b", "RD") %>%
    str_replace_all("\\bDRIVE\\b", "DR") %>%
    str_replace_all("\\bBOULEVARD\\b", "BLVD") %>%
    str_replace_all("\\bLANE\\b", "LN") %>%
    str_replace_all("\\bAVENUE\\b", "AVE") %>%
    str_replace_all("\\bCOURT\\b", "CT") %>%
    str_replace_all("\\bCIRCLE\\b", "CIR") %>%
    str_replace_all("\\bTRAIL\\b", "TRL") %>%
    str_replace_all("\\bPLACE\\b", "PL") %>%
    str_replace_all("\\bPARKWAY\\b", "PKWY") %>%
    str_replace_all("\\bTERRACE\\b", "TER") %>%
    str_replace_all("\\bBEND\\b", "BND") %>%
    str_replace_all("\\bHIGHWAY\\b", "HWY") %>%
    str_replace_all("\\s+", " ") %>%
    str_squish() %>%
    na_if("")
}

parse_address_proxy <- function(address) {
  segments <- str_split(
    str_replace_all(
      str_to_upper(coalesce(address, "")),
      regex("<BR\\s*/?>", ignore_case = TRUE),
      "|"
    ),
    fixed("|")
  )

  street <- map_chr(
    segments,
    function(parts) {
      parts <- str_squish(parts)
      candidates <- str_extract(
        parts,
        "[0-9]{2,6}[[:space:]]+[A-Z0-9].*$"
      )
      candidates <- candidates[!is.na(candidates)]

      if (length(candidates) == 0) {
        return(NA_character_)
      }

      first(candidates)
    }
  )

  final_segment <- map_chr(
    segments,
    ~str_squish(last(.x, default = ""))
  )
  location_match <- str_match(
    final_segment,
    "^(.+),[[:space:]]*([A-Z]{2})[[:space:]]+([0-9]{5})"
  )

  street <- street %>%
    str_remove(regex(
      paste0(
        "[,[:space:]]+(APT|APARTMENT|UNIT|BLDG|BUILDING|STE|SUITE|#|",
        "LOT|SITE)[[:space:]#.A-Z0-9-]*$"
      ),
      ignore_case = TRUE
    )) %>%
    str_squish() %>%
    na_if("")

  tibble(
    geocode_street = street,
    address_match_key = normalize_address_key(street),
    geocode_city = str_squish(location_match[, 2]) %>% na_if(""),
    geocode_state = location_match[, 3] %>% na_if(""),
    geocode_zip = location_match[, 4] %>% na_if("")
  )
}

# ---- Prepare the local public address index ---------------------------------

cat("Reading the local public Austin address-point reference...\n")

address_reference <- st_read(address_reference_file, quiet = TRUE) %>%
  st_transform(4326) %>%
  mutate(address_match_key = normalize_address_key(full_street_name))

required_reference_columns <- c(
  "address_reference_id", "full_street_name", "address_match_key"
)
missing_reference_columns <- setdiff(
  required_reference_columns,
  names(address_reference)
)

if (length(missing_reference_columns) > 0) {
  stop(
    "Local address reference is missing: ",
    str_c(missing_reference_columns, collapse = ", ")
  )
}

reference_coordinates <- st_coordinates(address_reference)

address_reference_index <- address_reference %>%
  st_drop_geometry() %>%
  mutate(
    longitude = reference_coordinates[, "X"],
    latitude = reference_coordinates[, "Y"]
  ) %>%
  filter(!is.na(address_match_key)) %>%
  group_by(address_match_key) %>%
  summarise(
    address_reference_id = first(address_reference_id),
    address_reference_candidates = n(),
    longitude = mean(longitude),
    latitude = mean(latitude),
    longitude_span = max(longitude) - min(longitude),
    latitude_span = max(latitude) - min(latitude),
    .groups = "drop"
  ) %>%
  mutate(
    spatially_ambiguous_reference = longitude_span > 0.002 |
      latitude_span > 0.002
  )

# ---- Parse and locally match address proxies --------------------------------

cat("Reading de-identified case-level eviction filings...\n")

eviction_cases <- read_csv(input_file, show_col_types = FALSE) %>%
  mutate(
    file_date = as.Date(file_date),
    filing_year = as.integer(filing_year)
  ) %>%
  filter(filing_year %in% analysis_years)

required_case_columns <- c(
  "eviction_case_id", "correspondence_address_clean", "court", "file_date",
  "filing_year", "case_status", "status_group"
)
missing_case_columns <- setdiff(required_case_columns, names(eviction_cases))

if (length(missing_case_columns) > 0) {
  stop(
    "Eviction geocoding input is missing: ",
    str_c(missing_case_columns, collapse = ", ")
  )
}

if (anyDuplicated(eviction_cases$eviction_case_id) > 0) {
  stop("Eviction case IDs are not unique.")
}

parsed_addresses <- parse_address_proxy(
  eviction_cases$correspondence_address_clean
)

eviction_cases_matched <- bind_cols(eviction_cases, parsed_addresses) %>%
  mutate(
    parseable_texas_address = !is.na(address_match_key) &
      !is.na(geocode_city) &
      geocode_state == "TX" &
      !is.na(geocode_zip) &
      geocode_zip != "00000"
  ) %>%
  left_join(address_reference_index, by = "address_match_key") %>%
  mutate(
    local_match_status = case_when(
      !parseable_texas_address ~ "not_parseable_texas_address",
      is.na(address_reference_id) ~ "no_exact_public_address_match",
      spatially_ambiguous_reference ~ "spatially_ambiguous_public_address",
      TRUE ~ "normalized_exact_public_address_match"
    ),
    valid_local_match = local_match_status ==
      "normalized_exact_public_address_match"
  )

# ---- Clip de-identified matched points to Austin -----------------------------

cat("Pulling City of Austin boundary...\n")

austin_boundary <- places(state = "TX", year = city_boundary_year) %>%
  filter(NAME == "Austin") %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(austin_boundary) != 1) {
  stop("Expected one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

valid_points <- eviction_cases_matched %>%
  filter(valid_local_match) %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

inside_city <- lengths(st_intersects(valid_points, austin_boundary)) > 0

eviction_points_austin <- valid_points %>%
  mutate(in_city_of_austin = inside_city) %>%
  filter(in_city_of_austin) %>%
  # Do not retain the correspondence address or public matched address.
  select(
    eviction_case_id, court, file_date, filing_year, case_status,
    status_group, defendant_records, case_has_multiple_addresses,
    address_reference_id, address_reference_candidates, local_match_status,
    in_city_of_austin
  )

if (nrow(eviction_points_austin) < 1) {
  stop("No locally matched eviction filing proxies fell inside Austin.")
}

# ---- Save de-identified outputs and QA/QC -----------------------------------

output_gpkg <- file.path(
  processed_dir,
  "jp_eviction_filings_geocoded_2020_2024.gpkg"
)
output_csv <- file.path(
  processed_dir,
  "jp_eviction_filings_geocoded_2020_2024.csv"
)

st_write(
  eviction_points_austin,
  output_gpkg,
  layer = "jp_eviction_filing_proxies",
  delete_dsn = TRUE,
  quiet = TRUE
)
write_csv(st_drop_geometry(eviction_points_austin), output_csv)

local_match_qaqc <- eviction_cases_matched %>%
  count(local_match_status, name = "case_filings") %>%
  mutate(share_of_analysis_window = case_filings / nrow(eviction_cases))

qaqc_summary <- tibble(
  metric = c(
    "analysis_years", "case_filings_in_analysis_window",
    "case_filings_with_parseable_texas_address_proxy",
    "case_filings_with_normalized_exact_local_match",
    "case_filings_inside_austin", "public_address_reference_records",
    "public_address_reference_ambiguous_keys", "retrieved_at_utc",
    "external_transmission_of_court_addresses",
    "personal_fields_in_spatial_output", "spatial_address_caveat",
    "recommended_analysis_role"
  ),
  value = c(
    paste0(min(analysis_years), "-", max(analysis_years)),
    as.character(nrow(eviction_cases)),
    as.character(sum(eviction_cases_matched$parseable_texas_address)),
    as.character(sum(eviction_cases_matched$valid_local_match)),
    as.character(nrow(eviction_points_austin)),
    as.character(nrow(address_reference)),
    as.character(sum(address_reference_index$spatially_ambiguous_reference)),
    format(Sys.time(), tz = "UTC", usetz = TRUE),
    "none; all matching performed locally",
    "none",
    paste0(
      "correspondence address is a proxy and may not always be the ",
      "eviction property address"
    ),
    "post-clustering housing-instability overlay/filter"
  )
)

court_year_qaqc <- eviction_points_austin %>%
  st_drop_geometry() %>%
  count(court, filing_year, name = "case_filings") %>%
  arrange(court, filing_year)

write_csv(
  local_match_qaqc,
  file.path(qaqc_dir, "jp_evictions_local_address_match_qaqc.csv")
)
write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "jp_evictions_geocoding_qaqc_summary.csv")
)
write_csv(
  court_year_qaqc,
  file.path(qaqc_dir, "jp_evictions_austin_court_year_counts.csv")
)

cat("\n=== Local Eviction Address Matching Complete ===\n")
cat("Analysis-window case filings: ", scales::comma(nrow(eviction_cases)), "\n", sep = "")
cat("Exact local address matches: ", scales::comma(sum(eviction_cases_matched$valid_local_match)), "\n", sep = "")
cat("Case filings inside Austin: ", scales::comma(nrow(eviction_points_austin)), "\n", sep = "")
cat("Processed spatial output: ", output_gpkg, "\n", sep = "")
