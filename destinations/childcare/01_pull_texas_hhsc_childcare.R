# Childcare destinations from Texas HHSC Child Care Regulation licensing data
#
# Source: Texas Open Data Portal, dataset bc5r-88dy
#         "HHSC CCL Daycare and Residential Operations Data"
#
# Chosen over Data Axle for this category because it carries licensed capacity
# per operation. Childcare access is capacity-dependent in a way grocery access
# is not: a 3-slot registered home and a 190-slot licensed center are not
# interchangeable destinations, and an unweighted count treats them as if they
# were. The dataset also flags subsidy acceptance, which supports a second
# affordability-conditioned measure from the same pull.
#
# Field names below were verified against a live pull. The five metro counties
# return roughly 1,400 records.
#
# Run from repository root:
#   Rscript destinations/childcare/01_pull_texas_hhsc_childcare.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "tigris", "httr2", "jsonlite", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/parse_addresses.R")

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# h3jsr masks purrr::compact. Namespace-qualify rather than reordering library
# calls, which would silently break again if setup_project_packages changes.
compact <- purrr::compact

# ---- Settings ----------------------------------------------------------------

texas_domain         <- "data.texas.gov"
childcare_dataset_id <- "bc5r-88dy"

city_boundary_year       <- 2024
analysis_equal_area_crs  <- 5070
h3_resolution            <- 8
destination_buffer_miles <- 5

# Counties pulled server-side to keep the request small. Spatial filtering to
# the buffered catchment happens later; this is only a coarse prefilter.
target_counties <- c("TRAVIS", "WILLIAMSON", "HAYS", "BASTROP", "CALDWELL")

# Listed Family Homes are registered with the state but not licensed or
# routinely inspected, are capped at very few children, and frequently serve
# relatives rather than operating as open-enrollment care. They are retained
# by default and flagged, so the sensitivity measure below can exclude them
# without a second pull.
exclude_listed_family_homes <- FALSE

raw_dir     <- destination_dir("childcare", "raw", "texas_hhsc")
interim_dir <- destination_dir("childcare", "interim", "texas_hhsc")
qaqc_dir    <- destination_dir("childcare", "qaqc", "texas_hhsc")

retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

# ---- Field map ---------------------------------------------------------------
#
# Verified against the live dataset. operation_id rather than operation_number:
# HHSC documents Operation ID as the key joining to their other Child Care
# Regulation datasets, so it is the identifier to preserve if inspection or
# deficiency history is joined later.

field_map <- list(
  operation_id       = "operation_id",
  operation_name     = "operation_name",
  operation_type     = "operation_type",
  operation_status   = "operation_status",
  temporarily_closed = "temporarily_closed",
  county             = "county",
  address            = "location_address",
  city               = "city",
  zip                = "zipcode",
  capacity           = "total_capacity",
  subsidies          = "accepts_child_care_subsidies",
  hours              = "hours_of_operation",
  days               = "days_of_operation",
  ages_served        = "licensed_to_serve_ages"
)

candidate_latitude_fields <- c(
  "geo_latitude", "latitude", "location_latitude", "lat"
)
candidate_longitude_fields <- c(
  "geo_longitude", "longitude", "location_longitude", "lon", "lng"
)

# ---- Socrata pull with pagination -------------------------------------------

socrata_pull <- function(domain,
                         dataset_id,
                         where_clause = NULL,
                         page_size    = 5000L) {

  endpoint <- paste0("https://", domain, "/resource/", dataset_id, ".json")

  accumulated <- list()
  offset      <- 0L

  repeat {
    query_parameters <- list(
      `$limit`  = as.integer(page_size),
      `$offset` = as.integer(offset)
    )
    if (!is.null(where_clause)) {
      query_parameters[["$where"]] <- where_clause
    }

    page <- request(endpoint) %>%
      req_url_query(!!!query_parameters) %>%
      req_retry(max_tries = 4) %>%
      req_timeout(seconds = 180) %>%
      req_perform() %>%
      resp_body_json(simplifyVector = FALSE)

    if (length(page) == 0) break

    accumulated <- c(accumulated, page)
    offset      <- offset + page_size

    cat("  retrieved ", length(accumulated), " records\n", sep = "")

    if (length(page) < page_size) break
  }

  accumulated
}

# ---- Record flattening -------------------------------------------------------
#
# location_address_geo is a nested list column. Coercing every list column to
# NA discards the coordinates, so the geo field is extracted explicitly before
# the scalar fields are flattened.

extract_geo_coordinates <- function(record) {
  geo_field <- pluck(record, "location_address_geo", .default = NULL)

  if (is.null(geo_field)) {
    return(list(geo_longitude = NA_real_, geo_latitude = NA_real_))
  }

  coordinates <- pluck(geo_field, "coordinates", .default = NULL)
  if (!is.null(coordinates) && length(coordinates) >= 2) {
    return(list(
      geo_longitude = suppressWarnings(as.numeric(coordinates[[1]])),
      geo_latitude  = suppressWarnings(as.numeric(coordinates[[2]]))
    ))
  }

  if (!is.null(pluck(geo_field, "latitude"))) {
    return(list(
      geo_longitude = suppressWarnings(as.numeric(pluck(geo_field, "longitude"))),
      geo_latitude  = suppressWarnings(as.numeric(pluck(geo_field, "latitude")))
    ))
  }

  list(geo_longitude = NA_real_, geo_latitude = NA_real_)
}

flatten_socrata_record <- function(record) {
  extracted     <- extract_geo_coordinates(record)
  scalar_fields <- record[!map_lgl(record, is.list)]

  as_tibble(map(scalar_fields, as.character)) %>%
    mutate(!!!extracted)
}

# ---- Pull --------------------------------------------------------------------

cat("Pulling Texas HHSC child care licensing data...\n")

county_list  <- paste0("'", target_counties, "'", collapse = ", ")
where_clause <- paste0("upper(", field_map$county, ") in (", county_list, ")")

childcare_records <- tryCatch(
  socrata_pull(texas_domain, childcare_dataset_id, where_clause),
  error = function(e) {
    cat("Server-side county filter failed. Falling back to full pull.\n")
    cat("Error was: ", conditionMessage(e), "\n", sep = "")
    socrata_pull(texas_domain, childcare_dataset_id, where_clause = NULL)
  }
)

if (length(childcare_records) == 0) {
  stop(
    "No records returned. Check the county field name in field_map ",
    "against the dataset's actual API fields."
  )
}

write_json(
  childcare_records,
  file.path(raw_dir, "childcare_texas_hhsc.json"),
  auto_unbox = TRUE
)

childcare_raw <- map_dfr(childcare_records, flatten_socrata_record)

cat("Raw records retrieved: ", nrow(childcare_raw), "\n", sep = "")
cat(
  "Records with coordinates: ",
  sum(!is.na(childcare_raw$geo_latitude)), " of ", nrow(childcare_raw), "\n",
  sep = ""
)

# ---- Validate field map ------------------------------------------------------

available_fields <- names(childcare_raw)
missing_fields   <- setdiff(unlist(field_map), available_fields)

if (length(missing_fields) > 0) {
  cat("\nAvailable fields in this dataset:\n")
  walk(sort(available_fields), ~ cat("  ", .x, "\n", sep = ""))
  stop(
    "field_map references fields not present: ",
    paste(missing_fields, collapse = ", "),
    ". Update field_map to match the list above."
  )
}

# ---- Operating status filter -------------------------------------------------
#
# The dataset includes closed and temporarily closed operations, and
# total_capacity remains populated for them. Counting those as reachable
# destinations inflates slot totals with no visible error.
#
# The accepted status values below are a guess until the printed breakdown
# confirms them. The script stops rather than proceeding with zero records if
# they do not match.

cat("\nOperating status breakdown:\n")
status_counts <- childcare_raw %>%
  count(
    .data[[field_map$operation_status]],
    .data[[field_map$temporarily_closed]],
    sort = TRUE,
    name = "records"
  )
print(status_counts, n = Inf)

write_csv(
  status_counts,
  file.path(qaqc_dir, "childcare_status_observed.csv")
)

active_status_values <- c("Y", "YES", "ACTIVE", "OPEN", "TRUE")
closed_flag_values   <- c("Y", "YES", "TRUE")

childcare_active <- childcare_raw %>%
  filter(
    str_to_upper(str_trim(.data[[field_map$operation_status]])) %in%
      active_status_values,
    !str_to_upper(str_trim(.data[[field_map$temporarily_closed]])) %in%
      closed_flag_values
  )

if (nrow(childcare_active) == 0) {
  stop(
    "Status filter removed every record. Inspect the breakdown printed above ",
    "and adjust active_status_values / closed_flag_values to match."
  )
}

cat(
  "After status filter: ", nrow(childcare_active), " of ",
  nrow(childcare_raw), " records\n", sep = ""
)

# ---- Operation type filter ---------------------------------------------------
#
# Observed types in the five-county pull: Licensed Center, Licensed Child-Care
# Home, Listed Family Home, Registered Child-Care Home, Child Placing Agency,
# General Residential Operation. The last two serve children in out-of-home
# placement rather than families seeking day care, so they are not destinations
# for this analysis.

cat("\nOperation types present:\n")
operation_type_counts <- childcare_active %>%
  count(.data[[field_map$operation_type]], sort = TRUE, name = "records")
print(operation_type_counts, n = Inf)

write_csv(
  operation_type_counts,
  file.path(qaqc_dir, "childcare_operation_types_observed.csv")
)

residential_patterns <- c(
  "child placing", "child-placing", "general residential",
  "foster", "residential treatment", "cottage home", "emergency care"
)

childcare_operations <- childcare_active %>%
  filter(
    !str_detect(
      str_to_lower(.data[[field_map$operation_type]]),
      paste(residential_patterns, collapse = "|")
    )
  )

cat(
  "After removing residential operations: ",
  nrow(childcare_operations), " records\n", sep = ""
)

# Home-based operations sit at residential addresses. Retained as genuine
# capacity, but flagged so published outputs can carry H8 aggregates only.
childcare_operations <- childcare_operations %>%
  mutate(
    operation_type_clean = str_trim(.data[[field_map$operation_type]]),
    is_home_based = str_detect(str_to_lower(operation_type_clean), "home"),
    is_listed_family_home = str_detect(
      str_to_lower(operation_type_clean), "listed family"
    )
  )

if (exclude_listed_family_homes) {
  childcare_operations <- childcare_operations %>%
    filter(!is_listed_family_home)
  cat(
    "Listed Family Homes excluded: ", nrow(childcare_operations),
    " records remain\n", sep = ""
  )
}

# ---- Normalize ---------------------------------------------------------------

latitude_field  <- intersect(candidate_latitude_fields, available_fields)[1]
longitude_field <- intersect(candidate_longitude_fields, available_fields)[1]

if (is.na(latitude_field) || is.na(longitude_field)) {
  stop("No coordinate fields detected. Check extract_geo_coordinates().")
}

childcare_normalized <- childcare_operations %>%
  transmute(
    destination_id   = .data[[field_map$operation_id]],
    destination_name = .data[[field_map$operation_name]],
    category         = "childcare",
    operation_type   = operation_type_clean,
    is_home_based,
    is_listed_family_home,
    capacity = suppressWarnings(as.numeric(.data[[field_map$capacity]])),
    accepts_subsidies = str_to_upper(
      str_trim(.data[[field_map$subsidies]])
    ) %in% c("Y", "YES", "TRUE"),
    ages_served        = .data[[field_map$ages_served]],
    hours_of_operation = .data[[field_map$hours]],
    days_of_operation  = .data[[field_map$days]],
    street_address     = .data[[field_map$address]],
    city               = .data[[field_map$city]],
    zip                = .data[[field_map$zip]],
    county             = .data[[field_map$county]],
    latitude  = suppressWarnings(as.numeric(.data[[latitude_field]])),
    longitude = suppressWarnings(as.numeric(.data[[longitude_field]])),
    source_type      = "socrata_json_texas",
    source_reference = childcare_dataset_id,
    retrieved_at_utc = retrieved_at_utc
  )

# ---- Write geocode input -----------------------------------------------------
#
# All records go to the geocoder, not only those missing coordinates. The 73
# records carrying location_address_geo skew heavily toward Listed Family
# Homes for no documented reason, so uniform Census-derived coordinates are
# easier to defend than a mixture. The HHSC values are retained as
# hhsc_latitude / hhsc_longitude for validation in script 04.

childcare_normalized <- childcare_normalized %>%
  rename(hhsc_latitude = latitude, hhsc_longitude = longitude)

geocode_input_path <- file.path(interim_dir, "childcare_geocode_input.csv")

# location_address holds a full formatted address, not a street line. Parse the
# street out and normalize the ZIP before submitting.
childcare_geocode_input <- childcare_normalized %>%
  transmute(
    unique_id = destination_id,
    street    = clean_street_line(street_address, city),
    city      = str_squish(city),
    state     = "TX",
    zip       = normalize_zip(zip)
  )

write_csv(childcare_geocode_input, geocode_input_path,
          col_names = FALSE, na = "")

# Persist for script 04, which cannot rebuild this without a second API pull.
write_rds(
  childcare_normalized,
  file.path(interim_dir, "childcare_normalized.rds")
)

cat("\n=== Childcare Pull Complete ===\n")
cat("Records normalized: ", nrow(childcare_normalized), "\n", sep = "")
cat("Written for geocoding: ", geocode_input_path, "\n", sep = "")
cat("Next: Rscript destinations/childcare/03_geocode_texas_hhsc_childcare.R\n")

preview_address_cleaning(childcare_normalized) %>% print(n = 20)
