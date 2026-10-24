# Shared folder conventions and study-area settings for destination scripts
#
# Sourced by every script under destinations/. Not run directly.
#
# Folder convention (all under the git-ignored data/ folder):
#
#   data/destinations/<destination>/raw/<source>/      untouched downloads or exports
#   data/destinations/<destination>/interim/<source>/  cleaned tables, geocoder files
#   data/destinations/<destination>/qaqc/<source>/     checks and review queues
#   data/destinations/<destination>/processed/         final layers, one per source:
#       <destination>_<source>.gpkg / .csv
#   data/destinations/manual/                          human review inputs
#   data/destinations/comparisons/<name>/              cross-source comparisons
#
# Script convention (destinations/<destination>/):
#
#   01_pull_<source>_<destination>.R    download from the source
#   02_clean_<source>_<destination>.R   standardize, filter, screen
#   03_geocode_<source>_<destination>.R add coordinates when the source has none
#   04_build_<source>_<destination>_gpkg.R  write the final GeoPackage
#   05_map_<source>_<destination>.R     diagnostic maps
#
# Stage numbers keep the same meaning in every folder, so a source that skips
# a stage simply has no script with that number.

destination_data_root <- file.path("data", "destinations")

# Five-county Austin metro used for destination collection.
destination_metro_counties <- c("Travis", "Williamson", "Hays", "Bastrop", "Caldwell")

# Broad coordinate sanity screen (lon/lat). Not a study-area boundary.
destination_region_bbox <- c(xmin = -99, ymin = 29, xmax = -96, ymax = 32)

# City-catchment settings used by City of Austin layers and childcare.
destination_city_boundary_year <- 2024
destination_buffer_miles <- 5
destination_equal_area_crs <- 5070

destination_dir <- function(destination,
                            stage = c("raw", "interim", "qaqc", "processed"),
                            source = NULL,
                            create = TRUE) {
  stage <- match.arg(stage)
  if (stage != "processed" && is.null(source)) {
    stop("A source name is required for the ", stage, " stage.")
  }
  path <- if (stage == "processed") {
    file.path(destination_data_root, destination, stage)
  } else {
    file.path(destination_data_root, destination, stage, source)
  }
  if (create) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

# Final product path, e.g. data/destinations/pharmacies/processed/pharmacies_tsbp.gpkg
destination_output_path <- function(destination, source, extension, suffix = NULL) {
  file_name <- paste0(
    paste(c(destination, source, suffix), collapse = "_"), ".", extension
  )
  file.path(destination_dir(destination, "processed"), file_name)
}

destination_manual_dir <- function(create = TRUE) {
  path <- file.path(destination_data_root, "manual")
  if (create) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

destination_comparison_dir <- function(name, create = TRUE) {
  path <- file.path(destination_data_root, "comparisons", name)
  if (create) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

# Coordinate status against the regional bounding box.
destination_coordinate_status <- function(latitude, longitude,
                                          bbox = destination_region_bbox) {
  dplyr::case_when(
    !is.finite(latitude) | !is.finite(longitude) ~ "missing_or_invalid",
    longitude < bbox[["xmin"]] | longitude > bbox[["xmax"]] |
      latitude < bbox[["ymin"]] | latitude > bbox[["ymax"]] ~ "outside_region_bbox",
    TRUE ~ "plausible_unverified"
  )
}

# Add H3 resolution 7 and 8 cells for rows flagged in `keep`.
add_h3_cells <- function(x, keep = rep(TRUE, nrow(x)),
                         lon = "longitude", lat = "latitude") {
  x$h3_h7 <- NA_character_
  x$h3_h8 <- NA_character_
  if (any(keep)) {
    points <- sf::st_as_sf(x[keep, ], coords = c(lon, lat), crs = 4326, remove = FALSE)
    x$h3_h7[keep] <- h3jsr::point_to_cell(sf::st_geometry(points), res = 7)
    x$h3_h8[keep] <- h3jsr::point_to_cell(sf::st_geometry(points), res = 8)
  }
  x
}

# Write one point layer and read it back to confirm row count and CRS.
write_point_layer <- function(x, path, layer, id_column = NULL,
                              lon = "longitude", lat = "latitude") {
  points <- sf::st_as_sf(x, coords = c(lon, lat), crs = 4326, remove = FALSE)
  sf::st_write(points, path, layer = layer, delete_layer = TRUE, quiet = TRUE)
  check <- sf::st_read(path, layer = layer, quiet = TRUE)
  stopifnot(nrow(check) == nrow(points), sf::st_crs(check)$epsg == 4326)
  if (!is.null(id_column)) stopifnot(!anyDuplicated(check[[id_column]]))
  invisible(path)
}

# City of Austin boundary buffered for destination collection.
destination_city_catchment <- function(year = destination_city_boundary_year,
                                       buffer_miles = destination_buffer_miles) {
  boundary <- tigris::places(state = "TX", year = year) |>
    dplyr::filter(NAME == "Austin") |>
    sf::st_transform(4326) |>
    sf::st_make_valid()
  if (nrow(boundary) != 1) {
    stop("Expected one City of Austin boundary; found ", nrow(boundary), ".")
  }
  boundary |>
    sf::st_transform(destination_equal_area_crs) |>
    sf::st_buffer(buffer_miles * 1609.344) |>
    sf::st_transform(4326)
}

file_sha256 <- function(paths) {
  vapply(paths, function(p) digest::digest(file = p, algo = "sha256"), character(1))
}
