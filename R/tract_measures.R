# Tract burdens and contextual attributes rebuilt from their source snapshots.
# Representative points are selected after projection, matching the original
# tract method; choosing points before projection changes the sampled windows.
prepare_tract_crash_windows <- function(tract_geometry, city_boundary, crash_spec, spatial_crs) {
  require_spatial(tract_geometry, "Tract geometry")
  require_unique_id(tract_geometry, "GEOID", "Tract geometry")
  require_spatial(city_boundary, "City boundary")
  if (length(crash_spec$buffer_meters) != 1L ||
      !is.finite(crash_spec$buffer_meters) || crash_spec$buffer_meters <= 0) {
    stop("Crash buffer must be a positive distance in meters.")
  }
  projected <- sf::st_transform(dplyr::select(tract_geometry, GEOID), spatial_crs)
  if (sf::st_is_longlat(projected) || !sf::st_crs(projected)$units_gdal %in% c("metre", "meter")) {
    stop("Crash windows require a projected CRS in meters.")
  }
  points <- suppressWarnings(sf::st_point_on_surface(projected))
  buffers <- sf::st_buffer(points, dist = crash_spec$buffer_meters)
  city <- sf::st_geometry(sf::st_transform(city_boundary, spatial_crs))
  # A multi-feature boundary still represents one observation footprint.
  if (length(city) > 1L) city <- sf::st_union(city)
  windows <- suppressWarnings(sf::st_intersection(buffers, city))
  require_unique_id(windows, "GEOID", "City-clipped crash windows")
  if (!setequal(windows$GEOID, tract_geometry$GEOID)) {
    stop("A tract crash window has no overlap with the City observation footprint.")
  }
  windows <- windows[match(tract_geometry$GEOID, windows$GEOID), ]
  windows$crash_observation_area_sqmi <- as.numeric(sf::st_area(windows)) / 2589988.110336
  if (any(!is.finite(windows$crash_observation_area_sqmi) | windows$crash_observation_area_sqmi <= 0)) {
    stop("Crash-exposure aggregation requires a positive observed area for every tract.")
  }
  full_area <- as.numeric(sf::st_area(buffers)) / 2589988.110336
  windows$crash_observed_window_share <- windows$crash_observation_area_sqmi / full_area
  windows$crash_buffer_meters <- crash_spec$buffer_meters
  windows
}

summarize_tract_crashes <- function(windows, crash_points, crash_spec) {
  require_spatial(windows, "Tract crash windows")
  require_unique_id(windows, "GEOID", "Tract crash windows")
  require_columns(windows, c("crash_observation_area_sqmi", "crash_observed_window_share",
                             "crash_buffer_meters"), "Tract crash windows")
  require_spatial(crash_points, "KSI crashes")
  require_columns(crash_points, c("crash_id", "crash_year", "ksi_crash", "fatal_crash",
                                  "vulnerable_road_user_ksi_crash"), "KSI crashes")
  years <- c(crash_spec$first_year, crash_spec$last_year)
  if (length(years) != 2L || any(!is.finite(years)) || any(years != as.integer(years)) ||
      years[1] > years[2]) stop("Invalid crash observation years.")
  flags <- sf::st_drop_geometry(crash_points)[c("ksi_crash", "fatal_crash", "vulnerable_road_user_ksi_crash")]
  if (anyNA(crash_points$crash_id) || anyNA(crash_points$crash_year) || anyNA(flags) ||
      any(!crash_points$ksi_crash) || any(crash_points$crash_year < years[1] | crash_points$crash_year > years[2])) {
    stop("Crash records must have IDs and known KSI flags within the configured observation period.")
  }
  hits <- sf::st_intersects(windows, sf::st_transform(crash_points, sf::st_crs(windows)))
  count_ids <- function(indices, flag = rep(TRUE, nrow(crash_points))) {
    length(unique(crash_points$crash_id[indices[flag[indices]]]))
  }
  result <- sf::st_drop_geometry(windows)
  result$ksi_crashes_in_window <- vapply(hits, count_ids, integer(1))
  result$fatal_crashes_in_window <- vapply(hits, count_ids, integer(1), flag = crash_points$fatal_crash)
  result$vulnerable_road_user_ksi_crashes_in_window <- vapply(hits, count_ids, integer(1),
    flag = crash_points$vulnerable_road_user_ksi_crash)
  # The configured observation period includes years with zero recorded crashes.
  result$crash_observation_years <- years[2] - years[1] + 1L
  denominator <- result$crash_observation_years * result$crash_observation_area_sqmi
  result$annual_ksi_crash_density <- result$ksi_crashes_in_window / denominator
  result$annual_vru_ksi_crash_density <- result$vulnerable_road_user_ksi_crashes_in_window / denominator
  result
}

read_displacement_source <- function(path) {
  source <- sf::st_drop_geometry(sf::st_read(path, quiet = TRUE, stringsAsFactors = FALSE))
  require_columns(source, c("geoid22", "displaceme"), "City 2022 displacement source")
  if (!nrow(source)) stop("The City displacement source contains no tract records.")
  # Socrata's source serializes these integer identifiers as strings ending in
  # .0. Remove that suffix without rounding or performing a spatial crosswalk.
  ids <- sub("\\.0+$", "", trimws(as.character(source$geoid22)))
  if (anyNA(ids) || any(!grepl("^[0-9]{11}$", ids))) stop("Invalid displacement-source tract GEOIDs.")
  category_source <- gsub("[[:space:]]+", " ", trimws(as.character(source$displaceme)))
  known <- c("No published displacement-risk designation", "Vulnerable",
             "Active Displacement Risk", "Chronic Displacement Risk")
  category <- category_source
  category[category_source %in% "N/A"] <- known[1]
  category[!category %in% known] <- NA_character_
  missing <- is.na(category_source) | !nzchar(category_source)
  result <- data.frame(GEOID = ids, displacement_risk_source = category_source,
    displacement_risk_category_published = category,
    displacement_coverage_status = ifelse(missing, "Missing source category",
      ifelse(is.na(category), "Unrecognized source category", "Matched published category")))
  require_unique_id(result, "GEOID", "City 2022 displacement source")
  result
}

join_tract_displacement <- function(tracts, displacement) {
  require_unique_id(tracts, "GEOID", "Reporting tracts")
  require_unique_id(displacement, "GEOID", "City 2022 displacement source")
  require_columns(displacement, c("displacement_risk_source", "displacement_risk_category_published",
                                   "displacement_coverage_status"), "City 2022 displacement source")
  result <- dplyr::left_join(tracts, displacement, by = "GEOID", relationship = "one-to-one")
  outside <- is.na(result$displacement_coverage_status)
  result$displacement_coverage_status[outside] <- "Outside published coverage"
  result$displacement_risk_category_display <- result$displacement_risk_category_published
  result$displacement_risk_category_display[outside] <- "Unknown / outside published coverage"
  result$displacement_risk_category_display[result$displacement_coverage_status == "Missing source category"] <-
    "Unknown / missing source category"
  result$displacement_risk_category_display[result$displacement_coverage_status == "Unrecognized source category"] <-
    "Unknown / unrecognized source category"
  result
}
