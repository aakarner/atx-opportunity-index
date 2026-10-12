# Census source snapshots are explicit file targets. Geometry and ACS attributes
# are prepared separately so updated estimates do not rebuild spatial overlays.
census_context_variables <- function() {
  c(poverty_total = "B17001_001", poverty_below = "B17001_002",
    race_ethnicity_total = "B03002_001", nh_white_alone = "B03002_003",
    households_total = "B11005_001", no_vehicle_households = "B08201_002",
    median_rent = "B25064_001")
}

census_download <- function(request, path, validate = NULL) {
  temporary <- paste0(path, ".partial")
  on.exit(unlink(temporary), add = TRUE)
  # Errors are deliberately replaced: authenticated request URLs may contain a
  # Census key, which must never appear in logs or source manifests.
  response <- tryCatch(httr2::req_perform(httr2::req_timeout(request, 120)),
    error = function(e) stop("Census download failed; check connectivity and API access.", call. = FALSE))
  writeBin(httr2::resp_body_raw(response), temporary)
  if (!is.null(validate)) validate(temporary)
  if (!file.rename(temporary, path)) stop("Cannot finalize Census source: ", path)
  invisible(path)
}

census_manifest <- function(paths, urls, acquisition, path) {
  readr::write_csv(data.frame(file = basename(paths), source_url = urls,
    acquisition = acquisition, recorded_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    sha256 = vapply(paths, digest::digest, character(1), algo = "sha256", file = TRUE),
    bytes = unname(file.info(paths)$size)), path)
  path
}

acquire_acs_sources <- function(spec) {
  directory <- file.path(spec$raw_dir, paste0("acs", spec$acs_year, "_5year"))
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  fields <- as.vector(rbind(paste0(census_context_variables(), "E"),
                           paste0(census_context_variables(), "M")))
  paths <- file.path(directory, paste0("acs", spec$acs_year, "_", spec$state_fips,
                                     spec$county_fips, "_tract_context.json"))
  urls <- character(length(paths))
  refreshed <- logical(length(paths))
  for (i in seq_along(paths)) {
    request <- httr2::request(paste0("https://api.census.gov/data/", spec$acs_year, "/acs/acs5")) |>
      httr2::req_url_query(get = paste(c("NAME", fields), collapse = ","),
        "for" = "tract:*", "in" = paste0("state:", spec$state_fips, " county:", spec$county_fips[i]))
    urls[i] <- request$url # Save only the public, key-free query.
    if (!file.exists(paths[i]) || isTRUE(spec$refresh)) {
      key <- Sys.getenv("CENSUS_API_KEY", unset = "")
      if (!nzchar(key)) stop("Set CENSUS_API_KEY to download ACS sources; existing cached sources do not require it.", call. = FALSE)
      request <- httr2::req_url_query(request, key = key)
      census_download(request, paths[i], function(path) read_acs_county(path, spec, spec$county_fips[i]))
      refreshed[i] <- TRUE
    }
    read_acs_county(paths[i], spec, spec$county_fips[i])
  }
  manifest <- file.path(directory, "source_manifest.csv")
  if (!file.exists(manifest) || any(refreshed)) {
    census_manifest(paths, urls, ifelse(refreshed, "Census API download", "Existing raw API snapshot"), manifest)
  }
  c(paths, manifest)
}

acquire_census_boundary <- function(kind, spec) {
  kind <- match.arg(kind, c("tracts", "city"))
  stem <- if (kind == "tracts") paste0("cb_", spec$boundary_year, "_", spec$state_fips, "_tract_500k") else
    paste0("tl_", spec$boundary_year, "_", spec$state_fips, "_place")
  url <- if (kind == "tracts") paste0("https://www2.census.gov/geo/tiger/GENZ", spec$boundary_year, "/shp/", stem, ".zip") else
    paste0("https://www2.census.gov/geo/tiger/TIGER", spec$boundary_year, "/PLACE/", stem, ".zip")
  directory <- file.path(spec$raw_dir, paste0("boundaries", spec$boundary_year), stem)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  extensions <- c(".shp", ".shx", ".dbf", ".prj", ".cpg")
  required <- file.path(directory, paste0(stem, extensions))
  manifest <- file.path(directory, "source_manifest.csv")
  if (!all(file.exists(required)) || isTRUE(spec$refresh)) {
    cache <- Sys.getenv("TIGRIS_CACHE_DIR", unset = "")
    if (!nzchar(cache)) cache <- rappdirs::user_cache_dir("tigris")
    cached <- file.path(path.expand(cache), paste0(stem, extensions))
    if (!isTRUE(spec$refresh) && all(file.exists(cached))) {
      if (!all(file.copy(cached, required, overwrite = TRUE))) stop("Cannot copy cached Census boundary files.")
      acquisition <- "Copied original Census shapefile components from Tigris cache; original retrieval date unknown"
    } else {
      archive <- file.path(directory, paste0(stem, ".zip"))
      census_download(httr2::request(url), archive, function(path) {
        members <- tryCatch(utils::unzip(path, list = TRUE)$Name,
                            error = function(e) stop("Invalid Census boundary archive: ", stem))
        if (!all(basename(required) %in% members)) stop("Incomplete Census boundary archive: ", stem)
      })
      utils::unzip(archive, files = basename(required), exdir = directory, overwrite = TRUE)
      acquisition <- "Census boundary archive download"
    }
    census_manifest(required, url, acquisition, manifest)
  }
  if (!file.exists(manifest)) census_manifest(required, url, "Existing raw shapefile components; original retrieval date unknown", manifest)
  c(required, if (file.exists(file.path(directory, paste0(stem, ".zip")))) file.path(directory, paste0(stem, ".zip")), manifest)
}

read_acs_county <- function(path, spec, county) {
  rows <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
                   error = function(e) stop("Invalid Census API JSON: ", basename(path), call. = FALSE))
  if (length(rows) < 2L || !is.list(rows)) stop("Empty or invalid Census API response: ", basename(path))
  header <- unlist(rows[[1]], use.names = FALSE)
  if (anyDuplicated(header) || any(!nzchar(header)) || any(lengths(rows[-1]) != length(header))) {
    stop("Invalid Census API response schema: ", basename(path))
  }
  x <- as.data.frame(do.call(rbind, lapply(rows[-1], function(row) {
    vapply(row, function(value) if (is.null(value)) NA_character_ else as.character(value), character(1))
  })), stringsAsFactors = FALSE)
  names(x) <- header
  codes <- census_context_variables()
  fields <- as.vector(rbind(paste0(codes, "E"), paste0(codes, "M")))
  require_columns(x, c("NAME", "state", "county", "tract", fields), "ACS response")
  if (anyNA(x[c("NAME", "state", "county", "tract")]) || any(x$state != spec$state_fips) ||
      any(x$county != county) || any(!grepl("^[0-9]{6}$", x$tract))) stop("ACS geography mismatch.")
  result <- data.frame(GEOID = paste0(x$state, x$county, x$tract), NAME = x$NAME)
  for (i in seq_along(codes)) for (suffix in c("E", "M")) {
    token <- x[[paste0(codes[i], suffix)]]
    value <- suppressWarnings(as.numeric(token))
    if (any(!is.na(token) & is.na(value))) stop("Nonnumeric ACS value: ", codes[i], suffix)
    # Match tidycensus treatment of published special-value codes; retain the
    # unchanged tokens in the raw JSON rather than converting them to zero.
    value[value %in% -(1:9 * 111111111)] <- NA_real_
    if (any(!is.na(value) & (!is.finite(value) | value < 0))) stop("Invalid ACS count/MOE: ", codes[i], suffix)
    field <- paste0(names(codes)[i], if (suffix == "M") "_moe" else "")
    result[[field]] <- value
  }
  require_unique_id(result, "GEOID", "ACS county")
  result
}

acs_proportion_moe <- function(numerator, denominator, numerator_moe, denominator_moe) {
  # ACS subset-proportion MOE, with the ratio fallback used by tidycensus::moe_prop.
  p <- numerator / denominator
  difference <- numerator_moe^2 - p^2 * denominator_moe^2
  result <- sqrt(numerator_moe^2 + p^2 * denominator_moe^2) / denominator
  positive <- !is.na(difference) & difference > 0
  result[positive] <- sqrt(difference[positive]) / denominator[positive]
  result[is.na(denominator) | denominator <= 0] <- NA_real_
  result
}

read_acs_sources <- function(paths, spec) {
  data_paths <- paths[grepl("_tract_context\\.json$", paths)]
  expected <- paste0("acs", spec$acs_year, "_", spec$state_fips, spec$county_fips, "_tract_context.json")
  if (!setequal(basename(data_paths), expected)) stop("ACS source files do not match configured counties/year.")
  x <- dplyr::bind_rows(lapply(seq_along(expected), function(i) {
    read_acs_county(data_paths[match(expected[i], basename(data_paths))], spec, spec$county_fips[i])
  }))
  require_unique_id(x, "GEOID", "ACS context")
  proportion <- function(n, d) ifelse(!is.na(d) & d > 0, n / d, NA_real_)
  x$poverty_rate <- proportion(x$poverty_below, x$poverty_total)
  x$people_of_color_share <- 1 - proportion(x$nh_white_alone, x$race_ethnicity_total)
  x$no_vehicle_share <- proportion(x$no_vehicle_households, x$households_total)
  x$poverty_rate_moe <- acs_proportion_moe(x$poverty_below, x$poverty_total, x$poverty_below_moe, x$poverty_total_moe)
  x$people_of_color_share_moe <- acs_proportion_moe(x$nh_white_alone, x$race_ethnicity_total, x$nh_white_alone_moe, x$race_ethnicity_total_moe)
  x$no_vehicle_share_moe <- acs_proportion_moe(x$no_vehicle_households, x$households_total, x$no_vehicle_households_moe, x$households_total_moe)
  for (field in c("poverty_rate", "people_of_color_share", "no_vehicle_share", "median_rent")) {
    x[[paste0(field, "_status")]] <- ifelse(is.na(x[[field]]), "Unavailable estimate or denominator", "Available")
  }
  x$acs_year <- spec$acs_year
  x$acs_survey <- "acs5"
  x
}

read_census_tracts <- function(paths, spec) {
  path <- paths[grepl("\\.shp$", paths)]
  if (length(path) != 1L) stop("Expected one raw tract shapefile.")
  x <- sf::st_read(path, quiet = TRUE)
  require_columns(x, c("GEOID", "STATEFP", "COUNTYFP", "NAME"), "Census tract boundaries")
  # Match the prior county sequence and each original shapefile's row order.
  counties <- lapply(spec$county_fips, function(county) x[x$STATEFP == spec$state_fips & x$COUNTYFP == county, ])
  if (any(vapply(counties, nrow, integer(1)) == 0L)) stop("Missing configured county in Census tract boundaries.")
  x <- dplyr::bind_rows(counties)
  require_unique_id(x, "GEOID", "Census tract boundaries")
  if (any(!grepl("^[0-9]{11}$", x$GEOID))) stop("Invalid Census tract GEOID.")
  sf::st_transform(dplyr::select(x, GEOID, NAME), 4326)
}

read_census_city <- function(paths, spec) {
  path <- paths[grepl("\\.shp$", paths)]
  if (length(path) != 1L) stop("Expected one raw place shapefile.")
  x <- sf::st_read(path, quiet = TRUE)
  require_columns(x, c("GEOID", "NAME"), "Census place boundaries")
  x <- x[x$GEOID == spec$place_geoid, ]
  if (nrow(x) != 1L) stop("Configured city GEOID is absent or duplicated.")
  x <- sf::st_make_valid(sf::st_transform(dplyr::select(x, GEOID, NAME), 4326))
  require_spatial(x, "Census city boundary")
  x
}

build_reporting_tracts <- function(tracts, city, crs = 5070) {
  x <- suppressWarnings(sf::st_intersection(sf::st_filter(tracts, city, .predicate = sf::st_intersects),
                                            sf::st_geometry(city)))
  x <- sf::st_make_valid(x)
  keep <- !sf::st_is_empty(x) & as.numeric(sf::st_area(sf::st_transform(x, crs))) > 0
  x <- x[keep, ]
  require_spatial(x, "City-clipped reporting tracts")
  require_unique_id(x, "GEOID", "City-clipped reporting tracts")
  x
}

join_tract_acs <- function(geometry, acs) {
  require_unique_id(acs, "GEOID", "ACS context")
  x <- dplyr::left_join(dplyr::rename(geometry, boundary_name = NAME), acs, by = "GEOID", relationship = "one-to-one")
  x$acs_record_status <- ifelse(is.na(x$NAME), "No ACS record for reporting tract", "Matched ACS record")
  x$NAME <- dplyr::coalesce(x$NAME, x$boundary_name)
  x
}
