# Geocode childcare operations missing coordinates
#
# The HHSC licensing dataset populates location_address_geo for only a small
# and non-random share of records, so most operations arrive address-only.
# This script submits those addresses to the Census Bureau batch geocoder and
# writes a coordinate table that 04_build_texas_hhsc_childcare_gpkg.R can join.
#
# The Census geocoder is free, needs no key, and accepts up to 10,000 records
# per submission. It is address-range interpolation against TIGER, so matched
# points sit on the street segment rather than on the parcel. At H3 resolution
# 8 (roughly 460 m across) that error is almost always immaterial, but it is
# worth stating rather than implying parcel-level precision.
#
# Run after 01_pull_texas_hhsc_childcare.R has written the geocode input file:
#   Rscript destinations/childcare/03_geocode_texas_hhsc_childcare.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "httr2", "curl"))
source("destinations/R/destination_paths.R")

compact <- purrr::compact

# ---- Settings ----------------------------------------------------------------

interim_dir <- destination_dir("childcare", "interim", "texas_hhsc")
qaqc_dir    <- destination_dir("childcare", "qaqc", "texas_hhsc")

geocode_input_path  <- file.path(interim_dir, "childcare_geocode_input.csv")
geocode_output_path <- file.path(interim_dir, "childcare_geocoded.csv")

# Census caps submissions at 10,000 rows. Smaller chunks fail less often and
# make partial progress recoverable when one chunk times out.
chunk_size <- 1000L

# Public_AR_Current tracks the most recent TIGER vintage. Pin a dated benchmark
# instead if the run needs to be exactly reproducible later.
census_benchmark <- "Public_AR_Current"

geocoder_endpoint <-
  "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"

# ---- Load input --------------------------------------------------------------

if (!file.exists(geocode_input_path)) {
  stop(
    "No geocode input found at ", geocode_input_path,
    ". Run 01_pull_texas_hhsc_childcare.R first."
  )
}

# Written without a header, in the column order Census requires.
geocode_input <- read_csv(
  geocode_input_path,
  col_names = c("unique_id", "street", "city", "state", "zip"),
  col_types = cols(.default = col_character())
)

cat("Addresses to geocode: ", nrow(geocode_input), "\n", sep = "")

# Records without a street address cannot be matched. Separating them here
# keeps the reported match rate honest: they are a coverage gap in the source,
# not a geocoder failure.
unmatchable <- geocode_input %>%
  filter(is.na(street) | str_trim(street) == "")

submittable <- geocode_input %>%
  filter(!is.na(street), str_trim(street) != "")

if (nrow(unmatchable) > 0) {
  cat(
    "Records with no street address (cannot be geocoded): ",
    nrow(unmatchable), "\n", sep = ""
  )
  write_csv(
    unmatchable,
    file.path(qaqc_dir, "childcare_unmatchable_addresses.csv")
  )
}

if (nrow(submittable) == 0) {
  stop("No submittable addresses remain.")
}

# ---- Submit one chunk --------------------------------------------------------

geocode_chunk <- function(chunk_data, chunk_index) {
  temporary_input <- tempfile(
    pattern = paste0("census_geocode_", chunk_index, "_"),
    fileext = ".csv"
  )
  on.exit(unlink(temporary_input), add = TRUE)

  write_csv(chunk_data, temporary_input, col_names = FALSE, na = "")

  response_text <- request(geocoder_endpoint) %>%
    req_body_multipart(
      addressFile = curl::form_file(temporary_input),
      benchmark   = census_benchmark
    ) %>%
    req_retry(max_tries = 3) %>%
    req_timeout(seconds = 600) %>%
    req_perform() %>%
    resp_body_string()

  # The response is headerless CSV. Column order is fixed by the API:
  # id, input address, match status, match type, matched address,
  # "longitude,latitude", TIGER line id, street side.
  parsed <- read_csv(
    I(response_text),
    col_names = c(
      "unique_id", "input_address", "match_status", "match_type",
      "matched_address", "coordinates", "tiger_line_id", "street_side"
    ),
    col_types = cols(.default = col_character())
  )

  parsed %>%
    separate_wider_delim(
      coordinates,
      delim = ",",
      names = c("longitude", "latitude"),
      too_few  = "align_start",
      too_many = "drop"
    ) %>%
    mutate(
      longitude = suppressWarnings(as.numeric(longitude)),
      latitude  = suppressWarnings(as.numeric(latitude))
    )
}

# ---- Run all chunks ----------------------------------------------------------

chunked <- submittable %>%
  mutate(chunk_index = ceiling(row_number() / chunk_size)) %>%
  group_split(chunk_index)

cat("Submitting ", length(chunked), " chunk(s) of up to ",
    chunk_size, " addresses\n", sep = "")

geocoded_chunks <- imap(chunked, function(chunk_data, chunk_index) {
  cat("  chunk ", chunk_index, " (", nrow(chunk_data), " addresses)... ",
      sep = "")

  result <- tryCatch(
    geocode_chunk(select(chunk_data, -chunk_index), chunk_index),
    error = function(e) {
      cat("FAILED: ", conditionMessage(e), "\n", sep = "")
      NULL
    }
  )

  if (!is.null(result)) {
    matched <- sum(result$match_status == "Match", na.rm = TRUE)
    cat(matched, " matched\n", sep = "")
  }

  result
})

geocoded_chunks <- compact(geocoded_chunks)

if (length(geocoded_chunks) == 0) {
  stop("Every chunk failed. Check network access and the endpoint URL.")
}

if (length(geocoded_chunks) < length(chunked)) {
  warning(
    length(chunked) - length(geocoded_chunks),
    " chunk(s) failed. Results below are incomplete."
  )
}

geocoded <- bind_rows(geocoded_chunks)

# ---- Assess match quality ----------------------------------------------------
#
# Exact and Non_Exact are both usable at H8. Non_Exact means the geocoder
# matched a nearby address range rather than the exact number, which shifts the
# point along the same street segment. Ties are ambiguous and excluded.

match_summary <- geocoded %>%
  count(match_status, match_type, name = "records") %>%
  arrange(desc(records))

cat("\nMatch results:\n")
print(match_summary, n = Inf)

write_csv(
  match_summary,
  file.path(qaqc_dir, "childcare_geocode_match_summary.csv")
)

geocoded_usable <- geocoded %>%
  filter(
    match_status == "Match",
    !is.na(latitude),
    !is.na(longitude)
  ) %>%
  transmute(
    unique_id,
    latitude,
    longitude,
    geocode_match_type = match_type,
    geocode_source     = "census_batch",
    geocode_benchmark  = census_benchmark
  )

write_csv(geocoded_usable, geocode_output_path)

match_rate <- nrow(geocoded_usable) / nrow(submittable)

cat("\n=== Geocoding Complete ===\n")
cat("Submitted:  ", nrow(submittable), "\n", sep = "")
cat("Matched:    ", nrow(geocoded_usable), "\n", sep = "")
cat("Match rate: ", round(match_rate * 100, 1), "%\n", sep = "")
cat("Written to: ", geocode_output_path, "\n", sep = "")

# A match rate below roughly 90% usually means address formatting rather than
# genuinely unlocatable addresses. Inspect the failures before accepting it.
if (match_rate < 0.90) {
  failed <- geocoded %>%
    filter(match_status != "Match") %>%
    left_join(submittable, by = "unique_id")

  write_csv(
    failed,
    file.path(qaqc_dir, "childcare_geocode_failures.csv")
  )

  cat(
    "\nMatch rate is below 90%. Failures written to ",
    file.path(qaqc_dir, "childcare_geocode_failures.csv"),
    "\nCommon causes: suite or unit numbers in the street field, PO boxes,\n",
    "rural route addresses, and addresses in newly annexed areas that\n",
    "postdate the TIGER vintage.\n", sep = ""
  )
}

# ---- Non-response check ------------------------------------------------------
#
# Whether geocoding succeeded at different rates across operation types
# determines whether the resulting accessibility surface is biased. If home
# based operations match at a materially lower rate than centers, the childcare
# measure understates access in whatever neighborhoods rely on them.
#
# Join geocode_output_path back in 04_build_texas_hhsc_childcare_gpkg.R, then compare match
# rates by operation_type before treating the coordinates as complete.
