# US Census Bureau batch geocoder helpers
#
# Sourced by destination 03_geocode_* scripts. Not run directly.
#
# The geocoder is free, needs no key, and accepts up to 10,000 addresses per
# request. It interpolates along TIGER address ranges, so matched points sit on
# the street segment rather than the parcel.

census_geocoder_endpoint <-
  "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"

census_response_columns <- c(
  "unique_id", "input_address", "match_status", "match_type",
  "matched_address", "coordinates", "tiger_line_id", "street_side"
)

# Submit a headerless id,street,city,state,zip file and save the raw response.
census_submit_batch <- function(input_path, response_path,
                                benchmark = "Public_AR_Current") {
  response_text <- httr2::request(census_geocoder_endpoint) |>
    httr2::req_body_multipart(
      addressFile = curl::form_file(input_path),
      benchmark   = benchmark
    ) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_timeout(seconds = 600) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  writeLines(response_text, response_path, sep = "", useBytes = TRUE)
  invisible(response_path)
}

# Read a saved raw response. No-match rows have only three fields; the
# remaining columns are returned as NA.
census_read_response <- function(response_path) {
  lines <- readLines(response_path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  fields <- lapply(lines, function(line) {
    parsed <- utils::read.csv(text = line, header = FALSE, colClasses = "character",
                              na.strings = character())
    values <- unlist(parsed, use.names = FALSE)
    length(values) <- length(census_response_columns)
    values
  })
  out <- as.data.frame(do.call(rbind, fields), stringsAsFactors = FALSE)
  names(out) <- census_response_columns
  tibble::as_tibble(out)
}

# Split "lon,lat" into numeric columns.
census_split_coordinates <- function(x) {
  parts <- strsplit(ifelse(is.na(x$coordinates), "", x$coordinates), ",", fixed = TRUE)
  x$longitude <- suppressWarnings(as.numeric(vapply(parts, `[`, character(1), 1)))
  x$latitude  <- suppressWarnings(as.numeric(vapply(parts, `[`, character(1), 2)))
  x
}

# Remove trailing suite/building/unit designators, which commonly prevent a
# TIGER match. Leading designators (an address that is only "SUITE 301") are
# left unchanged.
strip_secondary_unit <- function(street) {
  sub("\\s+(STE|SUITE|BLDG|BUILDING|UNIT|APT|#)\\b.*$", "", street, perl = TRUE)
}
