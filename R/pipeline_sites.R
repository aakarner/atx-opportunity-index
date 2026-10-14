school_at_sites <- function(sites, zones) {
  hits <- sf::st_intersects(sf::st_transform(sites, sf::st_crs(zones)), zones)
  dplyr::bind_rows(lapply(seq_along(hits), function(i) {
    x <- sf::st_drop_geometry(zones[hits[[i]], ])
    ids <- unique(x$campus_id)
    status <- if (!length(ids)) "Outside available assignment coverage" else if (length(ids) > 1) {
      "Ambiguous assignment overlap"
    } else if (length(unique(x$usable_growth)) > 1 || length(unique(x$score_status)) > 1) {
      "Conflicting records for assigned campus"
    } else x$score_status[1]
    data.frame(site_id = sites$site_id[i], campus_id = if(length(ids) == 1) ids else NA_character_,
      campus_name = if(length(ids) == 1) x$campus_name[1] else NA_character_,
      growth = if(status == "Available") x$usable_growth[1] else NA_real_, status = status)
  }))
}

site_job_access <- function(sites, h8, max_distance) {
  pts <- sf::st_transform(sites, sf::st_crs(h8))
  centers <- sf::st_transform(h3jsr::cell_to_point(h8$h3_id), sf::st_crs(h8))
  hits <- sf::st_intersects(pts, h8)
  nearest <- sf::st_nearest_feature(pts, centers)
  # Ambiguous boundary points use nearest center, with H3 ID as the stable tie
  # order inherited from the source file; report the approximation explicitly.
  chosen <- vapply(seq_along(hits), function(i) if(length(hits[[i]]) == 1) hits[[i]] else nearest[i], integer(1))
  distance <- as.numeric(sf::st_distance(pts, centers[chosen], by_element = TRUE))
  available <- distance <= max_distance
  data.frame(site_id = sites$site_id, access_origin_h3 = h8$h3_id[chosen], access_origin_distance_m = distance,
    access_status = ifelse(!available, "No origin within configured distance", ifelse(lengths(hits) == 1,
      "Containing H8 origin approximation", "Nearest H8 origin approximation")),
    transit_jobs_45min = ifelse(available, h8$access_total_jobs[chosen], NA_real_),
    transit_low_wage_jobs_45min = ifelse(available, h8$access_low_wage_jobs[chosen], NA_real_))
}

site_crash_burden <- function(sites, crashes, city_footprint, spec) {
  require_columns(crashes, "crash_id", "KSI crashes")
  if (anyNA(crashes$crash_id)) stop("KSI crashes need nonmissing event IDs.")
  pts <- sf::st_transform(sites, sf::st_crs(city_footprint))
  buffers <- sf::st_buffer(pts, dist = spec$buffer_meters)
  observed <- suppressWarnings(sf::st_intersection(dplyr::select(buffers, site_id), city_footprint))
  area <- as.numeric(sf::st_area(observed)) / 2589988.110336
  hits <- sf::st_intersects(observed, sf::st_transform(crashes, sf::st_crs(observed)))
  counts <- vapply(hits, function(i) length(unique(crashes$crash_id[i])), integer(1))
  years <- spec$last_year - spec$first_year + 1
  result <- data.frame(site_id = observed$site_id, ksi_crashes_in_window = counts,
    crash_observed_area_sqmi = area, annual_ksi_crash_density = ifelse(area > 0, counts / years / area, NA_real_))
  full_area <- as.numeric(sf::st_area(buffers)) / 2589988.110336
  result$crash_observed_window_share <- area / full_area[match(result$site_id, sites$site_id)]
  result$crash_buffer_meters <- spec$buffer_meters
  result$crash_observation_years <- years
  dplyr::left_join(data.frame(site_id = sites$site_id), result, by = "site_id", relationship = "one-to-one")
}

build_site_profiles <- function(sites, tracts, access, school_zones, flood_union, crashes, crash_spec, city_boundary) {
  hits <- sf::st_intersects(sf::st_transform(sites, sf::st_crs(tracts)), tracts)
  # Inputs outside the City reporting footprint are a scope error, not zero access.
  if (any(lengths(hits) == 0)) stop("Sites outside the reporting footprint: ", paste(sites$site_id[lengths(hits) == 0], collapse = ", "))
  result <- sf::st_drop_geometry(sites)
  result$tract_GEOID <- vapply(hits, function(x) if(length(x) == 1) tracts$GEOID[x] else NA_character_, character(1))
  result$tract_assignment_status <- ifelse(lengths(hits) == 1, "Single tract", "On tract boundary")
  result <- dplyr::left_join(result, access, by = "site_id", relationship = "one-to-one")
  for (level in names(school_zones)) {
    x <- school_at_sites(sites, school_zones[[level]])
    names(x)[-1] <- paste0("school_", level, "_", names(x)[-1])
    result <- dplyr::left_join(result, x, by = "site_id", relationship = "one-to-one")
  }
  flood_hits <- lengths(sf::st_intersects(sf::st_transform(sites, sf::st_crs(flood_union)), flood_union)) > 0
  result$fema_point_intersects <- flood_hits
  result$flood_screen <- ifelse(flood_hits, "Mapped overlap: site review needed",
                               "No mapped point overlap; flood risk not ruled out")
  footprint <- sf::st_geometry(sf::st_transform(city_boundary, sf::st_crs(flood_union)))
  if (length(footprint) > 1L) footprint <- sf::st_union(footprint)
  result <- dplyr::left_join(result, site_crash_burden(sites, crashes, footprint, crash_spec),
                            by = "site_id", relationship = "one-to-one")
  result$overall_screen <- "Incomplete: heat, traffic pollution and pedestrian barriers not integrated; no adopted screening thresholds"
  result
}
