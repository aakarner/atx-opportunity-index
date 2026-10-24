# Geocode TSBP pharmacy addresses with the Census batch geocoder
#
# Runs after destinations/pharmacies/02_clean_tsbp_pharmacies.R.
#
# Pass 1 submits every metro license (ADDRESS1, CITY, TX, 5-digit ZIP). Pass 2
# resubmits unmatched and tied addresses with trailing suite/building/unit text
# removed. A pass-2 result replaces pass 1 only when it matches.
#
# Saved Census responses are reused unless REFRESH_TSBP_GEOCODE=true, so the
# combined file can be rebuilt offline. Refresh after pulling a new roster.
#
# Writes data/destinations/pharmacies/interim/tsbp/geocoding/:
#   census_input.csv, census_response.csv          pass 1
#   census_retry_input.csv, census_retry_response.csv  pass 2
#   census_combined.csv                            one row per license
#   manifest.json
#
# Run from the repository root:
#   Rscript destinations/pharmacies/03_geocode_tsbp_pharmacies.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "httr2", "curl", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")
source("destinations/R/census_batch_geocoder.R")

benchmark <- "Public_AR_Current"
clean_path <- file.path(destination_dir("pharmacies", "interim", "tsbp", create = FALSE),
                        "tsbp_pharmacies_austin_metro.csv")
geo_dir <- file.path(destination_dir("pharmacies", "interim", "tsbp"), "geocoding")
dir.create(geo_dir, showWarnings = FALSE, recursive = TRUE)
refresh <- tolower(Sys.getenv("REFRESH_TSBP_GEOCODE", "false")) == "true"
if (!file.exists(clean_path)) stop("Missing ", clean_path, ". Run 02_clean_tsbp_pharmacies.R first.")

paths <- list(
  input = file.path(geo_dir, "census_input.csv"),
  response = file.path(geo_dir, "census_response.csv"),
  retry_input = file.path(geo_dir, "census_retry_input.csv"),
  retry_response = file.path(geo_dir, "census_retry_response.csv"),
  combined = file.path(geo_dir, "census_combined.csv")
)

x <- read_csv(clean_path, col_types = cols(.default = col_character()), na = character(),
              show_col_types = FALSE)
geocode_input <- tibble(
  unique_id = x$LIC_NBR, street = trimws(x$ADDRESS1), city = trimws(x$CITY),
  state = "TX", zip = substr(trimws(x$ZIP), 1, 5)
)

# Reuse a saved response only when its saved input matches the current input.
submitted <- FALSE
run_pass <- function(input, input_path, response_path) {
  saved_input <- if (file.exists(input_path)) {
    read_csv(input_path, col_names = names(input), col_types = cols(.default = col_character()),
             na = character(), show_col_types = FALSE)
  } else NULL
  reuse <- !refresh && file.exists(response_path) && !is.null(saved_input) &&
    isTRUE(all.equal(as.data.frame(saved_input), as.data.frame(input), check.attributes = FALSE))
  if (reuse) {
    message("Reusing saved response: ", response_path)
  } else {
    if (!refresh && file.exists(response_path)) {
      stop("Saved geocoder files do not match the current roster: ", input_path,
           ". Rerun with REFRESH_TSBP_GEOCODE=true.")
    }
    write_csv(input, input_path, col_names = FALSE, na = "")
    message("Submitting ", nrow(input), " addresses to the Census geocoder...")
    census_submit_batch(input_path, response_path, benchmark)
    submitted <<- TRUE
  }
  response <- census_read_response(response_path)
  stopifnot(setequal(response$unique_id, input$unique_id))
  response
}

first <- run_pass(geocode_input, paths$input, paths$response)
failed_ids <- first$unique_id[first$match_status != "Match"]
retry_input <- geocode_input |>
  filter(unique_id %in% failed_ids) |>
  mutate(street = strip_secondary_unit(street))
retry <- if (nrow(retry_input)) run_pass(retry_input, paths$retry_input, paths$retry_response) else first[0, ]

recovered <- retry |> filter(match_status == "Match") |> mutate(geocode_pass = "suite_removed_retry")
combined <- first |>
  mutate(geocode_pass = "original") |>
  rows_update(recovered, by = "unique_id")
stopifnot(nrow(combined) == nrow(x), !anyDuplicated(combined$unique_id))
write_csv(combined, paths$combined, col_names = FALSE, na = "")

manifest_path <- file.path(geo_dir, "manifest.json")
if (submitted || !file.exists(manifest_path)) {
  manifest <- list(
    geocoded_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    benchmark = benchmark, endpoint = census_geocoder_endpoint,
    original_records = nrow(first), retry_records = nrow(retry_input),
    recovered = nrow(recovered), input_sha256 = unname(file_sha256(paths$input))
  )
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
}
print(count(combined, match_status, geocode_pass))
