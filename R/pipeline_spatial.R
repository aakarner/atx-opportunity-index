# Pure spatial transformations. Each expensive crosswalk is cached separately.
make_job_geography <- function(jobs, crs) {
  sf::st_sf(jobs, geometry = h3jsr::cell_to_polygon(jobs$h3_id), crs = 4326) |>
    # Match the legacy normalization before projection: S2 can slightly move
    # vertices even for valid H8 polygons, changing boundary-tract weights.
    sf::st_make_valid() |>
    sf::st_transform(crs)
}

build_tract_h8_crosswalk <- function(tracts, h8) {
  tracts <- sf::st_transform(dplyr::select(tracts, GEOID), sf::st_crs(h8))
  cells <- dplyr::select(h8, h3_id)
  cells$h8_area_m2 <- as.numeric(sf::st_area(cells))
  overlaps <- suppressWarnings(sf::st_intersection(tracts, cells))
  overlaps$overlap_area_m2 <- as.numeric(sf::st_area(overlaps))
  overlaps$h8_area_share <- overlaps$overlap_area_m2 / overlaps$h8_area_m2
  sf::st_drop_geometry(overlaps)
}

aggregate_job_access <- function(tracts, h8, crosswalk) {
  metrics <- c("access_total_jobs", "access_low_wage_jobs", "access_middle_wage_jobs", "access_high_wage_jobs")
  jobs <- sf::st_drop_geometry(h8)
  rows <- dplyr::left_join(crosswalk, dplyr::select(jobs, h3_id, workers_all, dplyr::all_of(metrics)),
                           by = "h3_id", relationship = "many-to-one")
  groups <- split(rows, rows$GEOID)
  result <- lapply(groups, function(x) {
    weights <- x$workers_all * x$h8_area_share
    worker_weight <- sum(weights)
    method <- "area-apportioned resident-worker weighted H8 mean"
    if (worker_weight <= 0) {
      weights <- x$overlap_area_m2
      method <- "area-weighted H8 mean"
    }
    if (sum(weights) <= 0) stop("Zero-area H8 intersection for tract ", x$GEOID[1])
    values <- vapply(x[metrics], stats::weighted.mean, numeric(1), w = weights)
    data.frame(GEOID = x$GEOID[1], access_h8_cells = nrow(x), access_worker_weight = worker_weight,
               access_overlap_area_m2 = sum(x$overlap_area_m2), access_aggregation_method = method,
               as.list(values), check.names = FALSE)
  })
  result <- dplyr::bind_rows(result)
  missing <- tracts[!tracts$GEOID %in% result$GEOID, ]
  if (nrow(missing)) {
    nearest <- sf::st_nearest_feature(sf::st_transform(missing, sf::st_crs(h8)), h8)
    fallback <- data.frame(GEOID = missing$GEOID, access_h8_cells = 1L,
      access_worker_weight = jobs$workers_all[nearest], access_overlap_area_m2 = 0,
      access_aggregation_method = "nearest H8 origin fallback", jobs[nearest, metrics])
    result <- dplyr::bind_rows(result, fallback)
  }
  names(result)[match(metrics, names(result))] <- c("transit_jobs_45min", "transit_low_wage_jobs_45min",
                                                  "transit_middle_wage_jobs_45min", "transit_high_wage_jobs_45min")
  result[match(tracts$GEOID, result$GEOID), ]
}

make_flood_union <- function(flood, crs) {
  if (!nrow(flood)) stop("No 1%-annual-chance flood polygons in input.")
  sf::st_union(sf::st_geometry(sf::st_transform(flood, crs)))
}

summarize_flood_tracts <- function(tracts, flood_union) {
  tracts <- sf::st_transform(dplyr::select(tracts, GEOID), sf::st_crs(flood_union))
  total_area <- as.numeric(sf::st_area(tracts))
  if (any(total_area <= 0)) stop("Zero-area reporting tract.")
  overlap <- suppressWarnings(sf::st_intersection(tracts, flood_union))
  overlap$area <- as.numeric(sf::st_area(overlap))
  area_by_tract <- tapply(overlap$area, overlap$GEOID, sum)
  areas <- unname(area_by_tract[tracts$GEOID])
  areas[is.na(areas)] <- 0
  share <- areas / total_area
  if (any(share > 1 + 1e-7)) stop("Flood overlap exceeds reporting area.")
  data.frame(GEOID = tracts$GEOID, fema_one_percent_area_share = pmin(1, pmax(0, share)))
}

assemble_tract_components <- function(tracts, jobs, flood) {
  # Context retained for interpretation; no demographics enter benefit values.
  tracts |>
    dplyr::left_join(jobs, by = "GEOID", relationship = "one-to-one") |>
    dplyr::left_join(flood, by = "GEOID", relationship = "one-to-one")
}

pipeline_qa <- function(tracts, jobs, schools, sites) {
  require_unique_id(tracts, "GEOID", "Tract inputs")
  require_unique_id(jobs, "GEOID", "Tract job access")
  if (!setequal(tracts$GEOID, jobs$GEOID)) stop("Reporting and access tract IDs differ.")
  job_values <- as.matrix(jobs[c("transit_jobs_45min", "transit_low_wage_jobs_45min",
                                "transit_middle_wage_jobs_45min", "transit_high_wage_jobs_45min")])
  if (any(!is.finite(job_values)) || any(job_values < 0)) stop("Invalid tract access values.")
  difference <- max(abs(job_values[, 1] - rowSums(job_values[, -1, drop = FALSE])))
  if (difference > 1e-6) stop("Tract wage-group job access does not reconcile.")
  shares <- as.matrix(sf::st_drop_geometry(tracts)[c("poverty_rate", "people_of_color_share", "no_vehicle_share")])
  if (any(!is.na(shares) & (shares < 0 | shares > 1))) stop("ACS context share outside [0, 1].")
  if (any(!is.finite(tracts$annual_ksi_crash_density)) || any(tracts$annual_ksi_crash_density < 0) ||
      any(tracts$crash_observed_window_share <= 0 | tracts$crash_observed_window_share > 1 + 1e-7)) {
    stop("Invalid tract crash density or observation area.")
  }
  context_fields <- c("poverty_rate", "people_of_color_share", "no_vehicle_share", "median_rent")
  missing_context <- vapply(sf::st_drop_geometry(tracts)[context_fields], function(x) sum(is.na(x)), integer(1))
  school_counts <- vapply(schools, function(x) sum(!is.na(x$usable_growth)), integer(1))
  data.frame(check = c("Reporting tracts", "Max job-access wage-group reconciliation difference",
    "Tracts using nearest-H8 boundary fallback", "Tracts without an ACS source record",
    paste("Unavailable ACS context:", context_fields), "Tracts outside published displacement coverage",
    "Tracts with missing/unrecognized displacement categories", "Valid tract crash observations",
    paste("Usable growth zones:", names(school_counts)), "Example sites"),
    value = c(nrow(tracts), difference, sum(jobs$access_aggregation_method == "nearest H8 origin fallback"),
      sum(tracts$acs_record_status != "Matched ACS record"), missing_context,
      sum(tracts$displacement_coverage_status == "Outside published coverage"),
      sum(tracts$displacement_coverage_status %in% c("Missing source category", "Unrecognized source category")),
      nrow(tracts), school_counts, nrow(sites)),
    status = c("info", "pass", rep("info", 8), "pass", rep("info", 4)))
}

indicator_registry <- function(job_spec, school_spec, crash_spec, census_spec, displacement_spec) {
  data.frame(
    indicator = c("Transit job access by wage", "Assigned-school academic growth", "Mapped FEMA floodplain",
      "Severe-crash density", "Industrial air-toxic burden",
      "Heat exposure", "Tree canopy", "Near-road traffic pollution", "Pedestrian barriers",
      "Non-job destination access", "Driving access", "Demographic and market context"),
    role = c("benefit", "benefit", "burden", "burden", rep("burden", 2),
      "mitigation_context", rep("burden", 2), "benefit", "benefit", "overlay"),
    status = c("available", "AISD_only", "FEMA_snapshot_only", "tract_and_site_source_query",
      rep("not_integrated", 7), "source_derived_tract_context"),
    units = c("Jobs reachable in 45 minutes", "Raw academic growth score (0-100)",
      "Share of mapped reporting area / point intersection", "KSI crashes per year per square mile",
      "Toxicity-weighted concentration", "Source to be selected",
      "Canopy coverage", "Source to be selected", "Source to be selected", "Destinations reachable",
      "Destinations reachable", "Indicator-specific"),
    vintage = c(paste(job_spec$employment_year, "jobs; network", job_spec$network_snapshot),
      paste(school_spec$assignment_year, "assignments;", school_spec$growth_year, "growth; TEA",
            school_spec$accountability_year), "Cached FEMA layer; mixed study dates",
      paste(crash_spec$first_year, crash_spec$last_year, sep = "-"),
      rep("Not yet integrated", 7), paste(census_spec$acs_year, "ACS; City", displacement_spec$source_year, "displacement")),
    limitation = c("Pinned summer morning service; resident-worker tract weighting; not new site routing",
      "Campus-wide outcomes; AISD only; missing scores stay missing; no tract school composite",
      "Mapped overlap only; no coverage certification or City Atlas 14 replacement; no overlap does not imply no risk",
      "City-observed window around tract representative point or site; low counts do not establish pedestrian safety",
      "Missing data cannot count as a passed screen", "Physical heat measure still needed",
      "Protective feature; not an independent second heat burden", "Traffic activity proxy not yet built",
      "Route quality and crossings not yet assessed", "Awaiting screened destination layers and routing inputs",
      "Awaiting validated H8 travel-time matrix", "Whole-tract ACS attributes despite City-clipped geometry"),
    stringsAsFactors = FALSE)
}
