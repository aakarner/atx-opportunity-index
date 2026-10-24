#!/usr/bin/env Rscript
# =============================================================================
# destinations/healthcare/01_pull_cms_nppes_healthcare.R
# =============================================================================
#
# PURPOSE
#   Build a healthcare-provider destination file for the Austin-Round Rock-
#   Georgetown five-county metro area (Travis, Williamson, Hays, Bastrop,
#   Caldwell) from the CMS NPPES ("NPI Registry") monthly bulk file, filtered
#   to four selected NUCC taxonomy codes: community/retail pharmacy, general
#   acute-care hospital, urgent-care clinic/center, and general clinic/center.
#
# WHY NPPES INSTEAD OF A COMMERCIAL DIRECTORY (E.G. DATA AXLE)
#   NPPES is the federal regulatory registry every billing healthcare
#   provider/organization must enumerate in. It is free, uses standardized
#   NUCC taxonomy codes (finer-grained than NAICS for healthcare), and is the
#   source used in the peer-reviewed spatial-healthcare-access literature.
#   This mirrors how the existing repo prefers authoritative government
#   sources (ACS, LODES, EPA FRS, TxDOT CRIS) over commercial directories.
#
# DISK-SPACE STRATEGY
#   The national NPPES file unzips to tens of GB. This script NEVER writes
#   the full unzipped file to disk. It opens a streaming connection directly
#   into the ZIP archive (unz()), reads it in chunks, and writes ONLY the
#   rows that pass the state/county/taxonomy/active-status filters. Only the
#   original ZIP (~1-1.5 GB) and the small filtered output ever touch disk.
#
# REPRODUCIBILITY NOTE
#   Unlike ACS/LODES, NPPES has no versioned vintage beyond "the file CMS
#   published this month." This script logs the exact source URL and
#   download timestamp into the QA/QC output so the extract is auditable,
#   consistent with the project's existing QA/QC conventions
#   (analysis_qaqc_summary.csv, cluster_input_missingness.csv, etc.).
#
# OUTPUTS
#   data/destinations/healthcare/raw/cms_nppes/      cached NPPES ZIP
#   data/destinations/healthcare/interim/cms_nppes/  filtered extract + crosswalks
#   data/destinations/healthcare/qaqc/cms_nppes/     QA/QC summaries
#   - nppes_austin_metro_healthcare_providers.csv / .rds
#       One row per NPI record passing all filters, with an added
#       `destination_domain` column mapping each record to a population-
#       basket amenity category.
#   - nppes_taxonomy_domain_crosswalk.csv
#       The taxonomy-code -> domain mapping actually applied, for
#       transparency/reproducibility.
#   - nppes_extract_qaqc_summary.csv
#       Row counts by county, domain, entity type, and active status, plus
#       the source file URL and download timestamp.
#
# WHAT THIS SCRIPT DOES NOT DO
#   - Does not geocode addresses to lat/long. NPPES practice-location
#     addresses are text only; geocoding (e.g., via the Census Geocoder) is
#     left as a follow-on step so this script's job stays limited to
#     acquisition and filtering, matching the single-purpose style of the
#     project's other 1X_pull_*.R scripts.
#   - Does not deduplicate multiple individual providers (NPI-1) sharing one
#     physical address into a single "facility" point. Left as an explicit
#     analytic decision for the next script, since collapsing to facilities
#     changes what a destination "count" means for accessibility purposes.
#
# =============================================================================

# Run from the repository root:
#   Rscript destinations/healthcare/01_pull_cms_nppes_healthcare.R
#
source("00_setup_packages.R")
setup_project_packages(c("dplyr", "readr", "lubridate", "sf", "tigris", "tibble"))
source("destinations/R/destination_paths.R")

# -----------------------------------------------------------------------------
# 0. Configuration
# -----------------------------------------------------------------------------

TARGET_STATE     <- "TX"
TARGET_COUNTIES  <- destination_metro_counties

# The NPPES monthly file name changes every month (e.g. "September_2026"). Update
# this to match the file currently listed at:
#   https://download.cms.gov/nppes/NPI_Files.html
# under "Monthly NPPES Downloadable File Version 2 (V.2)".
NPPES_ZIP_URL <- "https://download.cms.gov/nppes/NPPES_Data_Dissemination_September_2026_V2.zip"

RAW_DIR    <- destination_dir("healthcare", "raw", "cms_nppes")
OUTPUT_DIR <- destination_dir("healthcare", "interim", "cms_nppes")
QAQC_DIR   <- destination_dir("healthcare", "qaqc", "cms_nppes")
ZIP_PATH   <- file.path(RAW_DIR, basename(NPPES_ZIP_URL))

# Set FALSE to delete the raw ZIP after a successful extract (saves ~1-1.5 GB).
# Default keeps it, consistent with the repo's .gitignore-based approach of
# caching downloaded source data locally rather than re-pulling every run.
KEEP_RAW_ZIP <- TRUE

CHUNK_SIZE <- 100000L  # rows per streamed chunk; tune down if memory-limited


# -----------------------------------------------------------------------------
# 1. Selected NUCC taxonomy codes -> destination domains
# -----------------------------------------------------------------------------
# The general Clinic/Center code is deliberately separated as a review group:
# it does not by itself establish that a location provides urgent care.

taxonomy_domain_map <- tibble::tribble(
  ~taxonomy_code, ~taxonomy_label,                                  ~destination_domain,
  "3336C0003X",   "Pharmacy, Community/Retail Pharmacy",            "pharmacy",
  "282N00000X",   "General Acute Care Hospital",                    "hospital",
  "261QU0200X",   "Clinic/Center, Urgent Care",                     "urgent_care",
  "261Q00000X",   "Clinic/Center",                                  "general_clinic_review"
)

readr::write_csv(taxonomy_domain_map, file.path(OUTPUT_DIR, "nppes_taxonomy_domain_crosswalk.csv"))

target_taxonomy_codes <- taxonomy_domain_map$taxonomy_code
taxonomy_col_names  <- paste0("Healthcare Provider Taxonomy Code_", 1:15)

# -----------------------------------------------------------------------------
# 2. Build the target ZIP (ZCTA) list for the five-county metro
# -----------------------------------------------------------------------------
# Uses a spatial join (ZCTA boundaries intersecting the five target county
# boundaries) rather than guessing ZIP-code number ranges, consistent with
# the project's existing tigris/sf-based geographic workflow (step 20 clips
# tracts to the Austin boundary the same way).

zip_crosswalk_path <- file.path(OUTPUT_DIR, "nppes_zip_county_crosswalk.csv")

if (!file.exists(zip_crosswalk_path)) {

  message("Building ZIP-to-county crosswalk for the five-county metro...")

  counties_sf <- tigris::counties(state = TARGET_STATE, cb = TRUE, year = 2024) |>
    dplyr::filter(NAME %in% TARGET_COUNTIES) |>
    sf::st_transform(4326)

  zctas_sf <- tigris::zctas(cb = TRUE, year = 2020) |>
    sf::st_transform(4326) |>
    sf::st_filter(counties_sf, .predicate = sf::st_intersects)

  zip_county_xwalk <- sf::st_join(
    zctas_sf,
    counties_sf |> dplyr::select(county_name = NAME),
    join = sf::st_intersects,
    left = FALSE
  ) |>
    sf::st_drop_geometry() |>
    dplyr::select(zip_code = ZCTA5CE20, county_name) |>
    dplyr::distinct()

  readr::write_csv(zip_county_xwalk, zip_crosswalk_path)

} else {
  message("Reusing cached ZIP-to-county crosswalk: ", zip_crosswalk_path)
  zip_county_xwalk <- readr::read_csv(zip_crosswalk_path, col_types = "cc")
}

target_zips <- unique(zip_county_xwalk$zip_code)
message("Target ZIP codes identified: ", length(target_zips))

# -----------------------------------------------------------------------------
# 3. Download the NPPES bulk file if not already cached
# -----------------------------------------------------------------------------

download_timestamp <- NA_character_

if (!file.exists(ZIP_PATH)) {
  message("Downloading NPPES bulk file (~1-1.5 GB, one-time)...")
  message("Source: ", NPPES_ZIP_URL)
  download.file(NPPES_ZIP_URL, destfile = ZIP_PATH, mode = "wb")
  download_timestamp <- as.character(lubridate::now(tzone = "UTC"))
} else {
  message("Reusing cached NPPES ZIP: ", ZIP_PATH)
  download_timestamp <- as.character(file.info(ZIP_PATH)$mtime)
}

# -----------------------------------------------------------------------------
# 4. Identify the main provider data file inside the ZIP (never extracted)
# -----------------------------------------------------------------------------

zip_contents <- utils::unzip(ZIP_PATH, list = TRUE)

main_csv_name <- zip_contents$Name[
  grepl("^npidata_pfile_.*\\.csv$", zip_contents$Name, ignore.case = TRUE) &
    !grepl("fileheader", zip_contents$Name, ignore.case = TRUE)
]

if (length(main_csv_name) != 1) {
  stop(
    "Could not uniquely identify the main NPPES data file inside the ZIP.\n",
    "Files found:\n", paste(zip_contents$Name, collapse = "\n"),
    "\nUpdate the matching pattern above to match the current file layout."
  )
}

message("Streaming main data file from ZIP (never extracted to disk): ", main_csv_name)

# -----------------------------------------------------------------------------
# 5. Stream-filter: state -> target ZIP -> target taxonomy -> active status
# -----------------------------------------------------------------------------

output_csv_path <- file.path(OUTPUT_DIR, "nppes_austin_metro_healthcare_providers.csv")
if (file.exists(output_csv_path)) file.remove(output_csv_path)

n_written <- 0L
first_chunk <- TRUE

filter_and_write_chunk <- function(chunk, pos) {

  # Restrict to the practice-location state first (cheapest filter, applied
  # before the more expensive taxonomy-column scan below).
  chunk <- chunk |>
    dplyr::filter(`Provider Business Practice Location Address State Name` == TARGET_STATE)

  if (nrow(chunk) == 0) return(invisible(NULL))

  chunk <- chunk |>
    dplyr::mutate(
      postal_code_5 = substr(
        `Provider Business Practice Location Address Postal Code`, 1, 5
      )
    ) |>
    dplyr::filter(postal_code_5 %in% target_zips)

  if (nrow(chunk) == 0) return(invisible(NULL))

  # A provider can carry the same taxonomy across any of 15 columns; keep a
  # record if ANY of its 15 taxonomy slots match the target code list, and
  # record which domain(s) matched.
  taxonomy_cols_present <- intersect(taxonomy_col_names, names(chunk))

  matches_any_taxonomy <- Reduce(
    `|`,
    lapply(taxonomy_cols_present, function(col) chunk[[col]] %in% target_taxonomy_codes)
  )

  chunk <- chunk[matches_any_taxonomy & !is.na(matches_any_taxonomy), ]
  if (nrow(chunk) == 0) return(invisible(NULL))

  # These four codes describe facilities/suppliers rather than individual
  # practitioners. Restrict the destination inventory to organization NPIs.
  chunk <- chunk |>
    dplyr::filter(`Entity Type Code` == "2")

  if (nrow(chunk) == 0) return(invisible(NULL))

  # Keep only currently active NPIs (blank deactivation date). Deactivated
  # records remain in NPPES indefinitely and would overstate current access.
  chunk <- chunk |>
    dplyr::filter(is.na(`NPI Deactivation Date`) | `NPI Deactivation Date` == "")

  if (nrow(chunk) == 0) return(invisible(NULL))

  # Determine the first matching domain per row for a simple summary label;
  # a provider matching multiple domains keeps all raw taxonomy columns for
  # downstream re-classification if needed.
  first_match_taxonomy <- apply(chunk[taxonomy_cols_present], 1, function(row) {
    hit <- row[row %in% target_taxonomy_codes]
    if (length(hit) == 0) NA_character_ else hit[[1]]
  })

  chunk <- chunk |>
    dplyr::mutate(
      matched_taxonomy_code = first_match_taxonomy,
      postal_code_5 = postal_code_5
    ) |>
    dplyr::left_join(taxonomy_domain_map, by = c("matched_taxonomy_code" = "taxonomy_code")) |>
    dplyr::left_join(zip_county_xwalk, by = c("postal_code_5" = "zip_code")) |>
    # A ZCTA can intersect more than one metro county. The join is used only
    # for preliminary county labeling and must not duplicate an NPI record.
    dplyr::distinct(NPI, .keep_all = TRUE)

  readr::write_csv(chunk, output_csv_path, append = !first_chunk)
  first_chunk <<- FALSE
  n_written <<- n_written + nrow(chunk)

  message("  ...chunk at row ", pos, ": ", nrow(chunk), " matches written (running total: ", n_written, ")")
  invisible(NULL)
}

# readr requires a binary connection; it handles the CSV text decoding after
# reading bytes from the compressed member.
zip_connection <- unz(ZIP_PATH, main_csv_name, open = "rb")

readr::read_csv_chunked(
  file        = zip_connection,
  callback    = filter_and_write_chunk,
  chunk_size  = CHUNK_SIZE,
  col_types   = readr::cols(.default = readr::col_character()),
  progress    = FALSE
)

close(zip_connection)

message("Streaming complete. Total matching provider records: ", n_written)

if (!KEEP_RAW_ZIP) {
  message("Deleting raw ZIP to free disk space (KEEP_RAW_ZIP = FALSE): ", ZIP_PATH)
  file.remove(ZIP_PATH)
}

# -----------------------------------------------------------------------------
# 6. Save .rds copy and QA/QC summary
# -----------------------------------------------------------------------------

providers <- readr::read_csv(output_csv_path, col_types = readr::cols(.default = readr::col_character()))
saveRDS(providers, file.path(OUTPUT_DIR, "nppes_austin_metro_healthcare_providers.rds"))

qaqc_summary <- providers |>
  dplyr::count(county_name, destination_domain, name = "n_providers") |>
  dplyr::arrange(county_name, destination_domain)

qaqc_meta <- tibble::tibble(
  source_url         = NPPES_ZIP_URL,
  download_timestamp = download_timestamp,
  extract_timestamp  = as.character(lubridate::now(tzone = "UTC")),
  total_records      = n_written,
  target_state       = TARGET_STATE,
  target_counties     = paste(TARGET_COUNTIES, collapse = "; "),
  n_taxonomy_codes    = length(target_taxonomy_codes)
)

readr::write_csv(qaqc_summary, file.path(QAQC_DIR, "nppes_extract_qaqc_summary.csv"))
readr::write_csv(qaqc_meta, file.path(QAQC_DIR, "nppes_extract_qaqc_metadata.csv"))

message("Done. Extract written to: ", normalizePath(OUTPUT_DIR))
message("Review nppes_extract_qaqc_summary.csv for counts by county x domain before use.")
