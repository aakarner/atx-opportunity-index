require_columns <- function(x, columns, label) {
  missing <- setdiff(columns, names(x))
  if (length(missing)) stop(label, " lacks columns: ", paste(missing, collapse = ", "))
  invisible(x)
}

require_unique_id <- function(x, column, label) {
  require_columns(x, column, label)
  if (anyNA(x[[column]]) || any(!nzchar(as.character(x[[column]]))) || anyDuplicated(x[[column]])) {
    stop(label, " requires unique nonmissing ", column, ".")
  }
  invisible(x)
}

require_spatial <- function(x, label) {
  if (!inherits(x, "sf") || !nrow(x) || is.na(sf::st_crs(x))) stop("Invalid spatial input: ", label)
  if (any(sf::st_is_empty(x)) || any(!sf::st_is_valid(x))) stop("Empty/invalid geometry: ", label)
  invisible(x)
}

read_pipeline_config <- function(path) {
  cfg <- yaml::read_yaml(path)
  required <- c("jobs", "schools", "flood", "crashes", "sites")
  if (!all(required %in% names(cfg$inputs))) stop("Incomplete pipeline input configuration.")
  if (!identical(cfg$geography$h3_resolution, 8L)) stop("This migration supports H8 origins only.")
  if (cfg$geography$equal_area_crs != 5070) stop("Area and distance calculations require EPSG:5070.")
  census <- cfg$census
  if (!all(c("acs_year", "boundary_year", "state_fips", "county_fips", "place_geoid", "raw_dir", "refresh") %in% names(census)) ||
      length(census$state_fips) != 1L || !grepl("^[0-9]{2}$", census$state_fips) ||
      !length(census$county_fips) || anyDuplicated(census$county_fips) || any(!grepl("^[0-9]{3}$", census$county_fips)) ||
      length(census$place_geoid) != 1L || !grepl("^[0-9]{7}$", census$place_geoid) ||
      substr(census$place_geoid, 1, 2) != census$state_fips) stop("Invalid Census source configuration.")
  if (census$state_fips != "48" || census$place_geoid != "4805000" ||
      !setequal(census$county_fips, c("453", "491", "209"))) {
    stop("Current routing and spatial inputs require Austin and the Travis, Williamson, and Hays county set.")
  }
  if (census$acs_year != 2024 || census$boundary_year != 2024) {
    stop("Current source contracts use 2024 ACS and boundaries; review geography and indicator definitions before changing vintages.")
  }
  if (!all(c("source_year", "path", "url", "refresh") %in% names(cfg$displacement)) ||
      cfg$displacement$source_year != 2022) stop("Expected the City 2022 displacement source configuration.")
  if (cfg$jobs$cutoff_minutes != 45) stop("This migration's job-access fields require a 45-minute cutoff.")
  if (cfg$crashes$first_year != 2020 || cfg$crashes$last_year != 2024) {
    stop("The current processed crash input contract covers 2020-2024; update the source contract before changing years.")
  }
  if (cfg$crashes$first_year > cfg$crashes$last_year || cfg$crashes$buffer_meters <= 0 ||
      cfg$sites$max_origin_distance_meters <= 0) stop("Invalid spatial/time parameters.")
  # Keep generated products separate from source inputs.
  if (!grepl("^output/[A-Za-z0-9_-]+$", cfg$output_dir)) {
    stop("Use a dedicated output subdirectory (default: output/components).")
  }
  cfg
}

input_path <- function(path, preparation) {
  if (!file.exists(path)) stop("Missing ", path, ". ", preparation)
  path
}

acquire_displacement_source <- function(spec) {
  path <- spec$path
  if (!file.exists(path) || isTRUE(spec$refresh)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    temporary <- paste0(path, ".partial.geojson")
    on.exit(unlink(temporary), add = TRUE)
    request <- httr2::request(spec$url) |>
      httr2::req_url_query(`$limit` = 50000L, `$order` = "geoid22") |>
      httr2::req_timeout(120) |>
      httr2::req_retry(max_tries = 3)
    httr2::req_perform(request, path = temporary)
    parsed <- read_displacement_source(temporary)
    if (nrow(parsed) >= 50000L) stop("Displacement source may be truncated; add pagination before proceeding.")
    if (!file.rename(temporary, path)) stop("Cannot finalize displacement source.")
  }
  read_displacement_source(path)
  path
}

read_job_access <- function(path, spec) {
  x <- readr::read_csv(path, col_types = readr::cols(h3_id = readr::col_character()), show_col_types = FALSE)
  require_unique_id(x, "h3_id", "H8 accessibility")
  metrics <- c("access_total_jobs", "access_low_wage_jobs", "access_middle_wage_jobs", "access_high_wage_jobs")
  require_columns(x, c(metrics, "lon", "lat", "workers_all", "cutoff", "percentile",
                       "jobs_year", "network_snapshot", "gtfs_snapshot", "departure_datetime"), "H8 accessibility")
  values <- as.matrix(x[c(metrics, "workers_all", "lon", "lat")])
  if (any(!is.finite(values)) || any(as.matrix(x[c(metrics, "workers_all")]) < 0)) {
    stop("Missing, nonfinite, or negative job/worker counts.")
  }
  if (any(abs(x$access_total_jobs - rowSums(x[metrics[-1]])) > 1e-6)) stop("Wage groups do not reconcile.")
  if (anyNA(x[c("cutoff", "percentile", "jobs_year", "network_snapshot", "gtfs_snapshot")]) ||
      any(x$cutoff != spec$cutoff_minutes) || any(x$percentile != spec$percentile) ||
      any(x$jobs_year != spec$employment_year) ||
      any(as.character(x$network_snapshot) != spec$network_snapshot) ||
      any(as.character(x$gtfs_snapshot) != spec$network_snapshot)) stop("Job-access vintage/settings mismatch.")
  # Legacy CSV serialized the local clock as UTC. Compare displayed clock time,
  # without pretending this repairs the upstream routing timestamp.
  clock <- format(x$departure_datetime, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  if (anyNA(clock) || any(clock != spec$departure_local)) stop("Job-access departure mismatch.")
  if (any(h3jsr::get_res(x$h3_id) != 8L)) stop("Unexpected H3 resolution.")
  centers <- sf::st_coordinates(h3jsr::cell_to_point(x$h3_id))
  if (max(abs(centers - as.matrix(x[c("lon", "lat")]))) > 1e-6) stop("H8 IDs and coordinates disagree.")
  x
}

read_school_zones <- function(path, spec) {
  levels <- c("elementary", "middle", "high")
  setNames(lapply(levels, function(level) {
    x <- sf::st_read(path, layer = level, quiet = TRUE)
    require_spatial(x, paste(level, "school zones"))
    require_unique_id(x, "source_object_id", level)
    require_columns(x, c("campus_id", "campus_name", "usable_growth", "score_status",
                         "school_level", "assignment_school_year", "growth_school_year", "accountability_year"), level)
    if (anyNA(x[c("campus_id", "campus_name", "score_status", "school_level", "assignment_school_year",
                   "growth_school_year", "accountability_year")]) ||
        any(x$school_level != level) || any(x$assignment_school_year != spec$assignment_year) ||
        any(x$growth_school_year != spec$growth_year) || any(x$accountability_year != spec$accountability_year)) {
      stop("School assignment/score vintage mismatch: ", level)
    }
    if (any(!is.na(x$usable_growth) & (!is.finite(x$usable_growth) | x$usable_growth < 0 | x$usable_growth > 100)) ||
        any(is.na(x$usable_growth) != (x$score_status != "Available"))) stop("Invalid school score/status.")
    x
  }), levels)
}

read_flood_layer <- function(path) {
  x <- sf::st_read(path, layer = "austin_fema_floodplain", quiet = TRUE)
  require_spatial(x, "FEMA floodplain")
  require_columns(x, "one_percent_annual_chance", "FEMA floodplain")
  if (anyNA(x$one_percent_annual_chance)) stop("Unknown flood category.")
  x[x$one_percent_annual_chance %in% TRUE, ]
}

read_crash_points <- function(path, spec) {
  x <- sf::st_read(path, layer = "austin_open_data_ksi_crashes", quiet = TRUE)
  require_spatial(x, "KSI crashes")
  require_unique_id(x, "austin_crash_id", "KSI crashes")
  require_columns(x, c("crash_id", "crash_year", "ksi_crash", "fatal_crash", "vulnerable_road_user_ksi_crash"), "KSI crashes")
  if (anyNA(x$crash_year) || anyNA(x$ksi_crash) || any(!x$ksi_crash) ||
      any(x$crash_year < spec$first_year | x$crash_year > spec$last_year)) stop("Crash window/selection mismatch.")
  x
}

read_sites <- function(path) {
  x <- readr::read_csv(path, show_col_types = FALSE)
  require_columns(x, c("site_id", "label", "longitude", "latitude", "selection_note"), "Sites")
  require_unique_id(x, "site_id", "Sites")
  if (!nrow(x) || any(!is.finite(as.matrix(x[c("longitude", "latitude")])))) stop("Invalid site coordinates.")
  if (any(abs(x$longitude) > 180 | abs(x$latitude) > 90)) stop("Site coordinates out of range.")
  sf::st_as_sf(x, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
}

source_manifest <- function(paths) {
  data.frame(source = names(paths), path = unname(paths),
    sha256 = vapply(paths, digest::digest, character(1), algo = "sha256", file = TRUE),
    bytes = unname(file.info(paths)$size), row.names = NULL)
}
