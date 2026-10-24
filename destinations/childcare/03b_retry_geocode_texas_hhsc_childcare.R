# Retry failed childcare geocodes with cleaned address strings
#
# The first pass matched 84.6% and returned Non_Exact for every match, which
# points to a systematic formatting difference between HHSC address strings and
# TIGER reference data rather than to unlocatable addresses. This script
# applies progressive cleaning and resubmits only the failures.
#
# Each cleaning pass is applied to whatever remains unmatched, so a record is
# only ever touched by the least aggressive rule that works for it. Recording
# which pass matched each record keeps the resulting coordinate quality
# auditable rather than uniform-by-assumption.
#
# Runs after 03_geocode_texas_hhsc_childcare.R:
#   Rscript destinations/childcare/03b_retry_geocode_texas_hhsc_childcare.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "httr2", "curl"))
source("destinations/R/destination_paths.R")

compact <- purrr::compact

# ---- Settings ----------------------------------------------------------------

interim_dir <- destination_dir("childcare", "interim", "texas_hhsc")
qaqc_dir    <- destination_dir("childcare", "qaqc", "texas_hhsc")

geocode_input_path   <- file.path(interim_dir, "childcare_geocode_input.csv")
geocode_output_path  <- file.path(interim_dir, "childcare_geocoded.csv")
retry_output_path    <- file.path(interim_dir, "childcare_geocoded_retry.csv")
combined_output_path <- file.path(interim_dir, "childcare_geocoded_combined.csv")

chunk_size       <- 500L
census_benchmark <- "Public_AR_Current"

geocoder_endpoint <-
  "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"

# ---- Load ---------------------------------------------------------------------

geocode_input <- read_csv(
  geocode_input_path,
  col_names = c("unique_id", "street", "city", "state", "zip"),
  col_types = cols(.default = col_character())
)

already_matched <- read_csv(
  geocode_output_path,
  col_types = cols(.default = col_character())
) %>%
  mutate(across(c(latitude, longitude), as.numeric))

unmatched <- geocode_input %>%
  filter(!unique_id %in% already_matched$unique_id)

cat("Previously matched: ", nrow(already_matched), "\n", sep = "")
cat("Remaining to retry: ", nrow(unmatched), "\n", sep = "")

if (nrow(unmatched) == 0) {
  cat("Nothing to retry.\n")
  quit(save = "no")
}

# ---- Address cleaning rules ---------------------------------------------------
#
# Ordered from least to most destructive. Secondary unit designators are the
# usual cause of Census batch failures: TIGER indexes the street segment, not
# the suite, so anything after the street name confuses the parser.

strip_secondary_units <- function(street) {
  street %>%
    str_replace_all(
      regex(
        "\\s+(ste|suite|unit|apt|apartment|bldg|building|fl|floor|rm|room|#)\\s*[a-z0-9\\-]*\\s*$",
        ignore_case = TRUE
      ),
      ""
    ) %>%
    str_trim()
}

strip_after_comma <- function(street) {
  street %>%
    str_replace("^([^,]+),.*$", "\\1") %>%
    str_trim()
}

normalize_whitespace <- function(street) {
  street %>%
    str_replace_all("\\s+", " ") %>%
    str_replace_all("\\.", "") %>%
    str_trim()
}

cleaning_passes <- list(
  pass_1_units = function(data) {
    mutate(data, street = strip_secondary_units(street))
  },
  pass_2_comma = function(data) {
    mutate(data, street = strip_after_comma(strip_secondary_units(street)))
  },
  pass_3_normalize = function(data) {
    mutate(
      data,
      street = normalize_whitespace(strip_after_comma(strip_secondary_units(street)))
    )
  },
  pass_4_drop_zip = function(data) {
    mutate(
      data,
      street = normalize_whitespace(strip_after_comma(strip_secondary_units(street))),
      zip    = NA_character_
    )
  }
)

# ---- Submission ---------------------------------------------------------------

# The Census batch geocoder returns a variable number of fields per row: eight
# for a match, but only three for No_Match and Tie (id, input address, status).
# When every row in a response is a non-match, readr infers three columns and
# any reference to the coordinate column fails. Padding to the full width first
# makes the parse independent of what the response happened to contain.
geocoder_response_columns <- c(
  "unique_id", "input_address", "match_status", "match_type",
  "matched_address", "coordinates", "tiger_line_id", "street_side"
)

parse_geocoder_response <- function(response_text) {
  parsed <- read_delim(
    I(response_text),
    delim         = ",",
    col_names     = FALSE,
    col_types     = cols(.default = col_character()),
    quote         = "\"",
    trim_ws       = TRUE,
    show_col_types = FALSE
  )

  if (nrow(parsed) == 0) {
    return(NULL)
  }

  # Pad to eight columns, then name them.
  while (ncol(parsed) < length(geocoder_response_columns)) {
    parsed[[paste0("X", ncol(parsed) + 1)]] <- NA_character_
  }
  parsed <- parsed[, seq_along(geocoder_response_columns)]
  names(parsed) <- geocoder_response_columns

  parsed %>%
    mutate(
      longitude = suppressWarnings(
        as.numeric(str_extract(coordinates, "^[^,]+"))
      ),
      latitude = suppressWarnings(
        as.numeric(str_extract(coordinates, "[^,]+$"))
      )
    )
}

geocode_chunk <- function(chunk_data, label) {
  temporary_input <- tempfile(pattern = paste0("retry_", label, "_"), fileext = ".csv")
  on.exit(unlink(temporary_input), add = TRUE)

  chunk_data %>%
    select(unique_id, street, city, state, zip) %>%
    write_csv(temporary_input, col_names = FALSE, na = "")

  response_text <- request(geocoder_endpoint) %>%
    req_body_multipart(
      addressFile = curl::form_file(temporary_input),
      benchmark   = census_benchmark
    ) %>%
    req_retry(max_tries = 3) %>%
    req_timeout(seconds = 600) %>%
    req_perform() %>%
    resp_body_string()

  parse_geocoder_response(response_text)
}

submit_all_chunks <- function(data, label) {
  chunked <- data %>%
    mutate(chunk_index = ceiling(row_number() / chunk_size)) %>%
    group_split(chunk_index)

  results <- imap(chunked, function(chunk_data, chunk_index) {
    tryCatch(
      geocode_chunk(chunk_data, paste0(label, "_", chunk_index)),
      error = function(e) {
        cat("    chunk ", chunk_index, " failed: ",
            conditionMessage(e), "\n", sep = "")
        NULL
      }
    )
  })

  results <- compact(results)

  if (length(results) == 0) {
    return(tibble())
  }

  bind_rows(results)
}

# ---- Run passes ---------------------------------------------------------------

remaining         <- unmatched
recovered_records <- list()

for (pass_name in names(cleaning_passes)) {
  if (nrow(remaining) == 0) break

  cat("\n", pass_name, ": submitting ", nrow(remaining), " addresses\n", sep = "")

  cleaned <- cleaning_passes[[pass_name]](remaining)
  results <- submit_all_chunks(cleaned, pass_name)

  if (nrow(results) == 0) {
    cat("  no response returned; skipping to next pass\n")
    next
  }

  # Distinguish "the request worked but nothing matched" from "the request
  # failed" -- these need different responses and look identical otherwise.
  cat("  response status counts: ")
  status_counts <- results %>% count(match_status, name = "records")
  cat(paste0(status_counts$match_status, "=", status_counts$records,
             collapse = ", "), "\n", sep = "")

  matched <- results %>%
    filter(match_status == "Match", !is.na(latitude), !is.na(longitude)) %>%
    transmute(
      unique_id,
      latitude,
      longitude,
      geocode_match_type = match_type,
      geocode_source     = "census_batch_retry",
      geocode_benchmark  = census_benchmark,
      geocode_pass       = pass_name
    )

  cat("  recovered ", nrow(matched), "\n", sep = "")

  recovered_records[[pass_name]] <- matched
  remaining <- remaining %>% filter(!unique_id %in% matched$unique_id)
}

recovered <- bind_rows(recovered_records)

# ---- Outputs ------------------------------------------------------------------

if (nrow(recovered) > 0) {
  write_csv(recovered, retry_output_path)
}

combined <- already_matched %>%
  mutate(geocode_pass = "pass_0_original") %>%
  bind_rows(recovered) %>%
  distinct(unique_id, .keep_all = TRUE)

write_csv(combined, combined_output_path)

if (nrow(remaining) > 0) {
  write_csv(
    remaining,
    file.path(qaqc_dir, "childcare_geocode_still_failed.csv")
  )
}

pass_summary <- combined %>%
  count(geocode_pass, name = "records") %>%
  arrange(geocode_pass)

cat("\n=== Retry Complete ===\n")
print(pass_summary, n = Inf)
cat("\nTotal matched: ", nrow(combined), " of ", nrow(geocode_input),
    " (", round(nrow(combined) / nrow(geocode_input) * 100, 1), "%)\n", sep = "")
cat("Still unmatched: ", nrow(remaining), "\n", sep = "")
cat("Combined file: ", combined_output_path, "\n", sep = "")

write_csv(
  pass_summary,
  file.path(qaqc_dir, "childcare_geocode_pass_summary.csv")
)

# Point script 04 at the combined file:
#   CHILDCARE_GEOCODE_PATH=data/destinations/childcare/interim/texas_hhsc/childcare_geocoded_combined.csv Rscript destinations/childcare/04_build_texas_hhsc_childcare_gpkg.R
