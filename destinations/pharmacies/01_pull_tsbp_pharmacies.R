# Download the Texas State Board of Pharmacy (TSBP) public pharmacy roster
#
# Source: TSBP licensing download tables
#         https://www.pharmacy.texas.gov/dbsearch/tables.asp
#         file: https://www.pharmacy.texas.gov/downloads/phydsk.csv
#
# Statewide list of licensed pharmacies, updated daily, with license class,
# status, ownership, and service flags. Addresses only; no coordinates.
#
# The saved snapshot is reused unless REFRESH_TSBP=true, because the source is
# overwritten daily and the downstream geocoding is tied to one snapshot.
#
# Writes: data/destinations/pharmacies/raw/tsbp/phydsk.csv + manifest.json
#
# Run from the repository root:
#   Rscript destinations/pharmacies/01_pull_tsbp_pharmacies.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")

source_url  <- "https://www.pharmacy.texas.gov/downloads/phydsk.csv"
source_page <- "https://www.pharmacy.texas.gov/dbsearch/tables.asp"

raw_dir  <- destination_dir("pharmacies", "raw", "tsbp")
raw_path <- file.path(raw_dir, "phydsk.csv")
refresh  <- tolower(Sys.getenv("REFRESH_TSBP", "false")) == "true"

if (file.exists(raw_path) && !refresh) {
  message("Reusing saved TSBP snapshot: ", raw_path,
          "\nSet REFRESH_TSBP=true to download a new one.")
} else {
  options(timeout = max(300, getOption("timeout")))
  temporary <- tempfile(fileext = ".csv")
  download.file(source_url, temporary, mode = "wb", quiet = TRUE)
  if (file.size(temporary) < 1e5) stop("Download looks truncated: ", file.size(temporary), " bytes.")
  file.copy(temporary, raw_path, overwrite = TRUE)
  manifest <- list(
    source_url = source_url, source_page = source_page,
    retrieved_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.size(raw_path), sha256 = unname(file_sha256(raw_path)),
    encoding = "cp1252",
    note = "Source is overwritten daily; the CSV carries no snapshot date."
  )
  jsonlite::write_json(manifest, file.path(raw_dir, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  message("Saved ", raw_path)
}
