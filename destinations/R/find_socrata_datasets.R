# Resolve City of Austin Socrata dataset identifiers by keyword
#
# Utility, not a pipeline step. Run interactively to find the four-character
# dataset ID for a destination layer, then record it (with the date you
# resolved it) in destinations/<destination>/01_pull_austin_open_data_*.R.
#
# Dataset IDs are stable once assigned, but datasets are retired and replaced.
# Resolving them from the catalog rather than hardcoding a remembered ID avoids
# silently pulling a deprecated layer.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "httr2"))

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")

search_austin_catalog <- function(search_terms, limit = 20L) {
  request_object <- request("https://api.us.socrata.com/api/catalog/v1") %>%
    req_url_query(
      domains = "data.austintexas.gov",
      q       = search_terms,
      limit   = as.integer(limit)
    ) %>%
    req_retry(max_tries = 3) %>%
    req_timeout(seconds = 60)

  if (nzchar(app_token)) {
    request_object <- request_object %>%
      req_headers(`X-App-Token` = app_token)
  }

  response_body <- request_object %>%
    req_perform() %>%
    resp_body_json(simplifyVector = FALSE)

  results <- pluck(response_body, "results", .default = list())

  if (length(results) == 0) {
    return(tibble(
      dataset_id  = character(),
      name        = character(),
      type        = character(),
      updated_at  = character(),
      description = character()
    ))
  }

  map_dfr(results, function(result) {
    resource <- pluck(result, "resource", .default = list())
    tibble(
      dataset_id  = as.character(pluck(resource, "id", .default = NA_character_)),
      name        = as.character(pluck(resource, "name", .default = NA_character_)),
      type        = as.character(pluck(resource, "type", .default = NA_character_)),
      updated_at  = as.character(pluck(resource, "updatedAt", .default = NA_character_)),
      description = str_trunc(
        as.character(pluck(resource, "description", .default = "")),
        160
      )
    )
  })
}

# Inspect the field names of a candidate dataset before wiring it into the
# registry. Socrata column names rarely match what the web UI displays, and
# location fields are sometimes nested objects rather than flat lat/lon columns.
inspect_dataset_fields <- function(dataset_id, sample_rows = 3L) {
  endpoint <- paste0(
    "https://data.austintexas.gov/resource/", dataset_id, ".json"
  )

  request_object <- request(endpoint) %>%
    req_url_query(`$limit` = as.integer(sample_rows)) %>%
    req_retry(max_tries = 3) %>%
    req_timeout(seconds = 60)

  if (nzchar(app_token)) {
    request_object <- request_object %>%
      req_headers(`X-App-Token` = app_token)
  }

  sample_records <- request_object %>%
    req_perform() %>%
    resp_body_json(simplifyVector = FALSE)

  if (length(sample_records) == 0) {
    cat("Dataset", dataset_id, "returned no records.\n")
    return(invisible(NULL))
  }

  field_names <- unique(unlist(map(sample_records, names)))

  cat("Fields in", dataset_id, ":\n")
  walk(sort(field_names), ~ cat("  ", .x, "\n", sep = ""))

  cat("\nFirst record:\n")
  str(sample_records[[1]], max.level = 2)

  invisible(field_names)
}

# ---- Example usage -----------------------------------------------------------
#
# search_austin_catalog("senior center")
# search_austin_catalog("health clinic")
# search_austin_catalog("food pantry")
# inspect_dataset_fields("8dff-2vkt")
