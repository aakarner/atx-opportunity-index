# Pull and QA/QC EPA FRS environmental hazard candidate facilities for Austin
#
# This standalone script pulls the EPA Facility Registry Service (FRS) Texas
# single-file CSV, filters it to facilities/sites near the City of Austin, tags
# several environmental program families, and writes both processed data and
# QA/QC summaries under data/.
#
# Why FRS? The submitted step-22 proof of concept uses physical environmental
# context rather than an EJ index that already blends hazard and demographic
# information. FRS provides facility/site records with program affiliations
# such as Brownfields/ACRES, TRI, RCRA, RMP, SEMS/Superfund, and NPDES.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris"))

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

city_name <- "Austin"
state_abbr <- "TX"
city_boundary_year <- 2024
analysis_equal_area_crs <- 5070
analysis_county_names <- c("HAYS", "TRAVIS", "WILLIAMSON")
analysis_county_fips <- c("48209", "48453", "48491")

# Include facilities within the city plus a small buffer. The buffer is useful
# for exposure screening because facilities just outside the municipal boundary
# can still matter for nearby residents.
austin_buffer_miles <- 1

frs_zip_url <- "https://ordsext.epa.gov/FLA/www3/state_files/state_single_tx.zip"
overwrite_download <- FALSE

raw_dir <- "data/raw/epa_frs"
processed_dir <- "data/processed/environmental_hazards"
qaqc_dir <- "data/qaqc/environmental_hazards"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

frs_zip_path <- file.path(raw_dir, "state_single_tx.zip")
frs_extract_dir <- file.path(raw_dir, "state_single_tx")

# ---- Helpers -----------------------------------------------------------------

clean_names <- function(x) {
  x %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "") %>%
    str_to_lower()
}

collapse_flags <- function(...) {
  flag_values <- c(...)
  names(flag_values)[flag_values] %>%
    str_remove("^has_") %>%
    str_c(collapse = ";")
}

write_empty_if_needed <- function(data, path) {
  if (nrow(data) == 0) {
    readr::write_csv(tibble(note = "No records matched this filter."), path)
  } else {
    readr::write_csv(data, path)
  }
}

# ---- Download and read FRS ---------------------------------------------------

if (!file.exists(frs_zip_path) || overwrite_download) {
  cat("Downloading EPA FRS Texas single-file CSV...\n")
  utils::download.file(
    url = frs_zip_url,
    destfile = frs_zip_path,
    mode = "wb",
    quiet = FALSE
  )
} else {
  cat("Using existing EPA FRS download: ", frs_zip_path, "\n", sep = "")
}

dir.create(frs_extract_dir, showWarnings = FALSE, recursive = TRUE)

zip_listing <- utils::unzip(frs_zip_path, list = TRUE)
frs_csv_name <- zip_listing %>%
  as_tibble() %>%
  filter(str_detect(str_to_lower(Name), "\\.csv$")) %>%
  arrange(desc(Length)) %>%
  slice(1) %>%
  pull(Name)

if (length(frs_csv_name) != 1 || is.na(frs_csv_name)) {
  stop("Could not identify the FRS CSV inside ", frs_zip_path, ".")
}

utils::unzip(
  frs_zip_path,
  files = frs_csv_name,
  exdir = frs_extract_dir,
  overwrite = TRUE
)

frs_csv_path <- file.path(frs_extract_dir, frs_csv_name)

cat("Reading EPA FRS records...\n")

frs_raw <- readr::read_csv(
  frs_csv_path,
  col_types = readr::cols(.default = readr::col_character()),
  locale = readr::locale(encoding = "Latin1"),
  show_col_types = FALSE
) %>%
  rename_with(clean_names)

required_frs_cols <- c(
  "registry_id", "primary_name", "county_name", "fips_code",
  "state_code", "pgm_sys_acrnms", "interest_types",
  "latitude83", "longitude83"
)
missing_frs_cols <- setdiff(required_frs_cols, names(frs_raw))

if (length(missing_frs_cols) > 0) {
  stop(
    "The EPA FRS file is missing expected columns: ",
    str_c(missing_frs_cols, collapse = ", ")
  )
}

frs_clean <- frs_raw %>%
  mutate(
    latitude = readr::parse_number(latitude83),
    longitude = readr::parse_number(longitude83),
    county_name = str_to_upper(county_name),
    state_code = str_to_upper(state_code),
    fips_code = str_pad(fips_code, width = 5, side = "left", pad = "0"),
    interest_text = str_squish(str_to_upper(coalesce(interest_types, ""))),
    program_acronym_text = str_squish(str_to_upper(coalesce(pgm_sys_acrnms, ""))),
    program_text = str_squish(str_c(
      interest_text,
      program_acronym_text,
      sep = " | "
    )),
    coordinate_status = case_when(
      is.na(latitude) | is.na(longitude) ~ "missing_coordinate",
      longitude < -107 | longitude > -93 | latitude < 25 | latitude > 37 ~
        "outside_texas_bbox",
      TRUE ~ "valid_coordinate"
    )
  )

frs_three_county <- frs_clean %>%
  filter(
    state_code == state_abbr,
    county_name %in% analysis_county_names |
      fips_code %in% analysis_county_fips
  )

# ---- Tag program families ----------------------------------------------------

frs_three_county <- frs_three_county %>%
  mutate(
    has_brownfields = str_detect(interest_text, "BROWNFIELDS?") |
      str_detect(program_acronym_text, "\\bACRES\\b|ACRES:"),
    has_tri = str_detect(interest_text, "\\bTRI\\b|TRI REPORTER|TOXICS RELEASE") |
      str_detect(program_acronym_text, "\\bTRI\\b|TRI:"),
    has_rcra_lqg_tsd = str_detect(
      interest_text,
      "\\bLQG\\b|LARGE QUANTITY|\\bTSD\\b|\\bTSDF\\b|TREATMENT STORAGE"
    ),
    has_rcra_other = str_detect(
      interest_text,
      "\\bSQG\\b|\\bVSQG\\b|TRANSPORTER|HAZARDOUS WASTE|BIENNIAL REPORTER"
    ),
    has_rmp = str_detect(interest_text, "\\bRMP\\b|RISK MANAGEMENT PLAN") |
      str_detect(program_acronym_text, "\\bRMP\\b|RMP:"),
    has_superfund_sems = str_detect(
      interest_text,
      "\\bSEMS\\b|SUPERFUND|\\bNPL\\b|NATIONAL PRIORITIES"
    ),
    has_npdes_major = str_detect(interest_text, "ICIS-NPDES MAJOR|NPDES MAJOR"),
    has_air_major = str_detect(interest_text, "AIR MAJOR|AFS MAJOR"),
    hazard_candidate = has_brownfields | has_tri | has_rcra_lqg_tsd |
      has_rmp | has_superfund_sems | has_npdes_major | has_air_major,
    broader_environmental_record = hazard_candidate | has_rcra_other,
    hazard_program_flags = pmap_chr(
      list(
        has_brownfields = has_brownfields,
        has_tri = has_tri,
        has_rcra_lqg_tsd = has_rcra_lqg_tsd,
        has_rcra_other = has_rcra_other,
        has_rmp = has_rmp,
        has_superfund_sems = has_superfund_sems,
        has_npdes_major = has_npdes_major,
        has_air_major = has_air_major
      ),
      collapse_flags
    ),
    hazard_program_flags = na_if(hazard_program_flags, "")
  )

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

valid_points <- frs_three_county %>%
  filter(coordinate_status == "valid_coordinate") %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  st_make_valid() %>%
  st_transform(analysis_equal_area_crs)

austin_boundary_ea <- austin_boundary %>%
  st_transform(analysis_equal_area_crs)

austin_buffer_ea <- austin_boundary_ea %>%
  st_buffer(austin_buffer_miles * 1609.344)

inside_city <- lengths(st_intersects(valid_points, austin_boundary_ea)) > 0
inside_buffer <- lengths(st_intersects(valid_points, austin_buffer_ea)) > 0
distance_to_city_m <- as.numeric(st_distance(valid_points, st_union(austin_boundary_ea)))

frs_austin_area <- valid_points %>%
  mutate(
    in_city_of_austin = inside_city,
    in_city_or_buffer = inside_buffer,
    distance_to_city_m = if_else(inside_city, 0, distance_to_city_m),
    distance_to_city_miles = distance_to_city_m / 1609.344
  ) %>%
  filter(in_city_or_buffer) %>%
  st_transform(4326)

frs_austin_hazards <- frs_austin_area %>%
  filter(hazard_candidate)

frs_austin_broader <- frs_austin_area %>%
  filter(broader_environmental_record)

# ---- Write processed data ----------------------------------------------------

cat("Writing processed EPA FRS outputs...\n")

selected_output_cols <- c(
  "registry_id", "primary_name", "location_address", "city_name",
  "county_name", "fips_code", "state_code", "postal_code",
  "site_type_name", "pgm_sys_acrnms", "interest_types",
  "hazard_program_flags", "hazard_candidate",
  "broader_environmental_record", "has_brownfields", "has_tri",
  "has_rcra_lqg_tsd", "has_rcra_other", "has_rmp",
  "has_superfund_sems", "has_npdes_major", "has_air_major",
  "latitude", "longitude", "in_city_of_austin",
  "distance_to_city_miles", "frs_facility_detail_report_url"
)

frs_austin_hazards_out <- frs_austin_hazards %>%
  select(any_of(selected_output_cols), geometry)

frs_austin_broader_out <- frs_austin_broader %>%
  select(any_of(selected_output_cols), geometry)

readr::write_csv(
  frs_austin_hazards_out %>% st_drop_geometry(),
  file.path(processed_dir, "epa_frs_austin_hazard_candidate_facilities.csv")
)

readr::write_csv(
  frs_austin_broader_out %>% st_drop_geometry(),
  file.path(processed_dir, "epa_frs_austin_broader_environmental_records.csv")
)

if (nrow(frs_austin_hazards_out) > 0) {
  st_write(
    frs_austin_hazards_out,
    file.path(processed_dir, "epa_frs_austin_hazard_candidate_facilities.gpkg"),
    layer = "epa_frs_hazard_candidates",
    delete_dsn = TRUE,
    quiet = TRUE
  )
}

if (nrow(frs_austin_broader_out) > 0) {
  st_write(
    frs_austin_broader_out,
    file.path(processed_dir, "epa_frs_austin_broader_environmental_records.gpkg"),
    layer = "epa_frs_broader_environmental_records",
    delete_dsn = TRUE,
    quiet = TRUE
  )
}

# ---- QA/QC summaries ---------------------------------------------------------

cat("Writing EPA FRS QA/QC summaries...\n")

qaqc_summary <- tibble(
  metric = c(
    "source_url",
    "download_path",
    "download_date",
    "raw_texas_records",
    "three_county_records",
    "three_county_valid_coordinates",
    "three_county_missing_coordinates",
    "three_county_outside_texas_bbox",
    "austin_city_or_1mi_buffer_records",
    "austin_city_records",
    "austin_hazard_candidate_records",
    "austin_broader_environmental_records",
    "duplicate_registry_ids_three_county"
  ),
  value = c(
    frs_zip_url,
    frs_zip_path,
    as.character(Sys.Date()),
    as.character(nrow(frs_clean)),
    as.character(nrow(frs_three_county)),
    as.character(sum(frs_three_county$coordinate_status == "valid_coordinate")),
    as.character(sum(frs_three_county$coordinate_status == "missing_coordinate")),
    as.character(sum(frs_three_county$coordinate_status == "outside_texas_bbox")),
    as.character(nrow(frs_austin_area)),
    as.character(sum(frs_austin_area$in_city_of_austin)),
    as.character(nrow(frs_austin_hazards)),
    as.character(nrow(frs_austin_broader)),
    as.character(sum(duplicated(frs_three_county$registry_id)))
  )
)

readr::write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "epa_frs_qaqc_summary.csv")
)

program_counts <- frs_austin_area %>%
  st_drop_geometry() %>%
  summarise(
    brownfields = sum(has_brownfields, na.rm = TRUE),
    tri = sum(has_tri, na.rm = TRUE),
    rcra_lqg_tsd = sum(has_rcra_lqg_tsd, na.rm = TRUE),
    rcra_other = sum(has_rcra_other, na.rm = TRUE),
    rmp = sum(has_rmp, na.rm = TRUE),
    superfund_sems = sum(has_superfund_sems, na.rm = TRUE),
    npdes_major = sum(has_npdes_major, na.rm = TRUE),
    air_major = sum(has_air_major, na.rm = TRUE)
  ) %>%
  pivot_longer(everything(), names_to = "program_family", values_to = "records")

readr::write_csv(
  program_counts,
  file.path(qaqc_dir, "epa_frs_program_family_counts.csv")
)

county_program_counts <- frs_austin_area %>%
  st_drop_geometry() %>%
  filter(!is.na(hazard_program_flags)) %>%
  count(county_name, hazard_program_flags, sort = TRUE, name = "records")

write_empty_if_needed(
  county_program_counts,
  file.path(qaqc_dir, "epa_frs_county_program_counts.csv")
)

coordinate_qaqc <- frs_three_county %>%
  count(county_name, coordinate_status, sort = TRUE, name = "records")

readr::write_csv(
  coordinate_qaqc,
  file.path(qaqc_dir, "epa_frs_coordinate_qaqc.csv")
)

cat("\nEPA FRS pull complete.\n")
cat("Hazard candidates in Austin/city buffer: ", nrow(frs_austin_hazards), "\n", sep = "")
cat("Processed files written to: ", processed_dir, "\n", sep = "")
cat("QA/QC files written to: ", qaqc_dir, "\n", sep = "")
