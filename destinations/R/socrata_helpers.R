# City of Austin Open Data (Socrata) helpers for destination layers
#
# Sourced by destinations/<destination>/01_pull_austin_open_data_*.R and
# 04_build_austin_open_data_*_gpkg.R. Not run directly.
#
# Authentication is optional for public Socrata queries. If available, set
# AUSTIN_OPEN_DATA_APP_TOKEN in the process environment. Never commit a token.
# Use destinations/R/find_socrata_datasets.R to look up dataset IDs.

austin_open_data_domain <- "data.austintexas.gov"

socrata_request <- function(dataset_id, format = c("json", "geojson"), limit = 5000L,
                            domain = austin_open_data_domain) {
  format <- match.arg(format)
  token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")
  request_object <- httr2::request(paste0("https://", domain, "/resource/", dataset_id, ".", format)) |>
    httr2::req_url_query(`$limit` = as.integer(limit)) |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_timeout(seconds = 180)
  if (nzchar(token)) request_object <- httr2::req_headers(request_object, `X-App-Token` = token)
  httr2::req_perform(request_object)
}

# Download one dataset to raw/austin_open_data/ and record a manifest entry.
pull_austin_open_data <- function(destination, layer_name, dataset_id,
                                  format = c("json", "geojson"), limit = 5000L) {
  format <- match.arg(format)
  raw_dir <- destination_dir(destination, "raw", "austin_open_data")
  raw_path <- file.path(raw_dir, paste0(layer_name, ".", format))
  response <- socrata_request(dataset_id, format, limit)
  writeBin(httr2::resp_body_raw(response), raw_path)
  records <- if (format == "json") {
    length(jsonlite::fromJSON(raw_path, simplifyVector = FALSE))
  } else {
    nrow(sf::st_read(raw_path, quiet = TRUE))
  }
  if (records >= limit) warning("Record count reached the request limit (", limit, "); raise `limit`.")
  manifest <- list(
    dataset_id = dataset_id, domain = austin_open_data_domain, format = format,
    retrieved_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    records = records, sha256 = unname(file_sha256(raw_path)),
    app_token_used = nzchar(Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = ""))
  )
  jsonlite::write_json(manifest, file.path(raw_dir, paste0(layer_name, "_manifest.json")),
                       auto_unbox = TRUE, pretty = TRUE)
  message("Saved ", records, " records to ", raw_path)
  invisible(raw_path)
}

# Socrata serves location either as a nested object with latitude/longitude
# strings or as a GeoJSON-style point with coordinates in lon/lat order.
extract_socrata_coordinates <- function(record, location_field) {
  location <- purrr::pluck(record, location_field, .default = list())
  if (!is.null(purrr::pluck(location, "latitude"))) {
    return(list(
      latitude  = suppressWarnings(as.numeric(purrr::pluck(location, "latitude"))),
      longitude = suppressWarnings(as.numeric(purrr::pluck(location, "longitude")))
    ))
  }
  coordinates <- purrr::pluck(location, "coordinates", .default = NULL)
  if (!is.null(coordinates) && length(coordinates) >= 2) {
    return(list(
      latitude  = suppressWarnings(as.numeric(coordinates[[2]])),
      longitude = suppressWarnings(as.numeric(coordinates[[1]]))
    ))
  }
  list(latitude = NA_real_, longitude = NA_real_)
}

# Point records from a saved .json download.
normalize_socrata_points <- function(raw_path, layer_name, category, dataset_id,
                                     location_field, name_field = "name") {
  records <- jsonlite::fromJSON(raw_path, simplifyVector = FALSE)
  purrr::imap_dfr(records, function(record, record_index) {
    coordinates <- extract_socrata_coordinates(record, location_field)
    tibble::tibble(
      destination_id   = paste0(layer_name, "_", record_index),
      destination_name = as.character(purrr::pluck(record, name_field, .default = NA_character_)),
      category         = category,
      latitude         = coordinates$latitude,
      longitude        = coordinates$longitude,
      source_type      = "socrata_json",
      source_reference = dataset_id
    )
  })
}

# Polygon records reduce to a representative point. st_point_on_surface rather
# than st_centroid, because a centroid can fall outside a concave park
# boundary and land in the wrong H3 cell.
normalize_socrata_polygons <- function(polygons, layer_name, category, dataset_id,
                                       name_field = "location_name") {
  points <- polygons |>
    sf::st_make_valid() |>
    sf::st_point_on_surface() |>
    sf::st_transform(4326)
  xy <- sf::st_coordinates(points)
  names_out <- if (name_field %in% names(points)) as.character(points[[name_field]]) else NA_character_
  tibble::tibble(
    destination_id   = paste0(layer_name, "_", seq_len(nrow(points))),
    destination_name = names_out,
    category         = category,
    latitude         = xy[, "Y"],
    longitude        = xy[, "X"],
    source_type      = "socrata_geojson",
    source_reference = dataset_id
  )
}

# Screen coordinates, keep destinations inside the buffered City catchment,
# add H3 cells, and write the processed GeoPackage + CSV + QA summary.
build_austin_open_data_layer <- function(destinations, destination, layer_name,
                                         polygons = NULL) {
  qa_dir <- destination_dir(destination, "qaqc", "austin_open_data")
  destinations$coordinate_status <- destination_coordinate_status(
    destinations$latitude, destinations$longitude)
  valid <- destinations[destinations$coordinate_status == "plausible_unverified", ]
  valid_sf <- sf::st_as_sf(valid, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  catchment <- destination_city_catchment()
  valid$in_catchment <- lengths(sf::st_intersects(valid_sf, catchment)) > 0
  kept <- valid[valid$in_catchment, ]
  if (!nrow(kept)) stop("No ", layer_name, " destinations remained inside the buffered catchment.")
  kept <- add_h3_cells(kept)

  target <- destination_output_path(destination, "austin_open_data", "gpkg")
  if (file.exists(target)) unlink(target)
  write_point_layer(kept, target, layer_name, "destination_id")
  if (!is.null(polygons)) {
    sf::st_write(sf::st_transform(sf::st_make_valid(polygons), 4326), target,
                 layer = paste0(layer_name, "_polygons"), quiet = TRUE)
  }
  readr::write_csv(kept, destination_output_path(destination, "austin_open_data", "csv"))

  summary <- tibble::tibble(
    metric = c("raw_records", "plausible_coordinates", "in_city_catchment",
               "destination_buffer_miles", "distinct_h8_cells"),
    value = c(nrow(destinations), nrow(valid), nrow(kept), destination_buffer_miles,
              dplyr::n_distinct(kept$h3_h8))
  )
  readr::write_csv(summary, file.path(qa_dir, paste0(layer_name, "_summary.csv")))
  readr::write_csv(destinations[destinations$coordinate_status != "plausible_unverified", ],
                   file.path(qa_dir, paste0(layer_name, "_invalid_coordinates.csv")))
  print(summary)
  message("Saved ", target)
  invisible(kept)
}
