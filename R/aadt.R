# Traffic proximity and buffer coverage on the shared H8 grid.
aadt_settings <- function() {
  list(
    service_url = paste0("https://services.arcgis.com/KTcxiTD9dsQw4r7Z/",
                         "arcgis/rest/services/TxDOT_AADT/FeatureServer/0"),
    threshold_aadt = 50000,
    buffer_m = 300,
    measurement_crs = 26914L,
    search_padding_m = 20000
  )
}

aadt_grid <- function(city) {
  ids <- municipal_h8_ids(city, res = 8L)
  sf::st_sf(h3_id = ids, geometry = h3jsr::cell_to_polygon(ids), crs = 4326)
}

aadt_query_extent <- function(hex, settings) {
  bounds <- sf::st_bbox(sf::st_transform(hex, settings$measurement_crs))
  bounds[] <- as.numeric(bounds) + c(-1, -1, 1, 1) * settings$search_padding_m
  bounds
}

aadt_request <- function(url, query) {
  request <- httr2::request(url)
  request <- do.call(httr2::req_url_query, c(list(request), query))
  response <- request |>
    httr2::req_user_agent("atx-opportunity-index traffic preparation") |>
    httr2::req_timeout(180) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform()
  body <- httr2::resp_body_json(response, simplifyVector = FALSE)
  if (!is.null(body$error)) stop("TxDOT query failed: ", body$error$message)
  if (isTRUE(body$exceededTransferLimit)) stop("TxDOT response was truncated.")
  list(body = body, raw = httr2::resp_body_raw(response))
}

acquire_aadt_roads <- function(directory, bounds, settings) {
  manifest_path <- file.path(directory, "manifest.json")
  if (file.exists(manifest_path)) {
    manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
    if (manifest$service_url != settings$service_url ||
        manifest$threshold_aadt != settings$threshold_aadt ||
        manifest$query_crs != settings$measurement_crs ||
        !isTRUE(all.equal(as.numeric(manifest$query_bounds), as.numeric(bounds)))) {
      stop("Cached traffic query differs from the current settings/grid. Use a new source directory.")
    }
    for (file in names(manifest$sha256)) {
      path <- file.path(directory, file)
      if (!file.exists(path) || digest::digest(path, algo = "sha256", file = TRUE) != manifest$sha256[[file]]) {
        stop("Missing or changed cached traffic source: ", path)
      }
    }
    pages <- file.path(directory, manifest$pages)
  } else {
    # Stage a complete snapshot so interrupted downloads cannot become a valid cache.
    dir.create(dirname(directory), recursive = TRUE, showWarnings = FALSE)
    staging <- tempfile("aadt-source-", tmpdir = dirname(directory))
    dir.create(staging)
    on.exit(unlink(staging, recursive = TRUE), add = TRUE)
    metadata <- aadt_request(settings$service_url, list(f = "json"))
    ids_response <- aadt_request(paste0(settings$service_url, "/query"), list(
      f = "json", where = paste("AADT_CUR >", settings$threshold_aadt),
      returnIdsOnly = "true", geometryType = "esriGeometryEnvelope",
      geometry = paste(as.numeric(bounds), collapse = ","),
      inSR = settings$measurement_crs, spatialRel = "esriSpatialRelIntersects"
    ))
    ids <- sort(as.integer(unlist(ids_response$body$objectIds)))
    if (!length(ids) || anyDuplicated(ids)) stop("Invalid TxDOT object-ID inventory.")
    writeBin(metadata$raw, file.path(staging, "metadata.json"))
    writeBin(ids_response$raw, file.path(staging, "object_ids.json"))
    # Small batches keep GET URLs below the service gateway's length limit.
    batches <- split(ids, ceiling(seq_along(ids) / 100L))
    pages <- sprintf("roads_%03d.geojson", seq_along(batches))
    for (i in seq_along(batches)) {
      message("Downloading TxDOT road page ", i, " of ", length(batches))
      # No clipping geometry in this query: retrieve each entire source feature.
      page <- aadt_request(paste0(settings$service_url, "/query"), list(
        f = "geojson", objectIds = paste(batches[[i]], collapse = ","),
        outFields = "*", outSR = 4326, returnGeometry = "true"
      ))
      actual <- sort(vapply(page$body$features, function(feature) {
        as.integer(feature$properties$OBJECTID)
      }, integer(1)))
      if (!identical(actual, batches[[i]])) stop("Incomplete TxDOT road page.")
      writeBin(page$raw, file.path(staging, pages[i]))
    }
    after <- aadt_request(settings$service_url, list(f = "json"))
    if (!identical(metadata$body$editingInfo$lastEditDate, after$body$editingInfo$lastEditDate)) {
      stop("TxDOT source changed during download. Retry acquisition.")
    }
    files <- c("metadata.json", "object_ids.json", pages)
    hashes <- vapply(file.path(staging, files), digest::digest,
                     character(1), algo = "sha256", file = TRUE)
    manifest <- list(
      service_url = settings$service_url,
      retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      source_edit_time_ms = metadata$body$editingInfo$lastEditDate,
      threshold_aadt = settings$threshold_aadt, query_crs = settings$measurement_crs,
      query_bounds = as.numeric(bounds), feature_count = length(ids),
      pages = pages, sha256 = as.list(stats::setNames(hashes, files))
    )
    jsonlite::write_json(manifest, file.path(staging, "manifest.json"),
                         auto_unbox = TRUE, pretty = TRUE, digits = NA)
    if (dir.exists(directory) || !file.rename(staging, directory)) {
      stop("Cannot finalize traffic source directory: ", directory)
    }
    pages <- file.path(directory, pages)
  }
  roads <- do.call(rbind, lapply(pages, sf::st_read, quiet = TRUE))
  expected <- jsonlite::read_json(file.path(directory, "object_ids.json"), simplifyVector = TRUE)$objectIds
  if (!setequal(roads$OBJECTID, expected) || anyDuplicated(roads$OBJECTID) ||
      nrow(roads) != manifest$feature_count || anyNA(roads$AADT_CUR) ||
      any(roads$AADT_CUR <= settings$threshold_aadt) ||
      any(sf::st_is_empty(roads)) || any(!sf::st_is_valid(roads))) {
    stop("Invalid or incomplete cached high-volume roads.")
  }
  roads
}

calculate_aadt_metrics <- function(hex, roads, settings = aadt_settings()) {
  if (!nrow(hex) || anyNA(hex$h3_id) || anyDuplicated(hex$h3_id) ||
      any(h3jsr::get_res(hex$h3_id) != 8L)) stop("Expected unique H3 resolution 8 cells.")
  roads <- roads[!is.na(roads$AADT_CUR) & roads$AADT_CUR > settings$threshold_aadt, ]
  if (!nrow(roads)) stop("No qualifying traffic roads.")
  hex <- sf::st_transform(hex, settings$measurement_crs)
  road_lines <- sf::st_union(sf::st_geometry(sf::st_transform(roads, settings$measurement_crs)))
  centers <- sf::st_transform(h3jsr::cell_to_point(hex$h3_id), settings$measurement_crs)
  distances <- units::set_units(sf::st_distance(centers, road_lines), "ft")
  # A round-ended buffer is the set of points within buffer_m of the road lines.
  corridor <- sf::st_buffer(road_lines, settings$buffer_m, endCapStyle = "ROUND", nQuadSegs = 30)
  overlap <- suppressWarnings(sf::st_intersection(hex["h3_id"], corridor))
  areas <- tapply(as.numeric(sf::st_area(overlap)), overlap$h3_id, sum)
  fractions <- as.numeric(areas[hex$h3_id]) / as.numeric(sf::st_area(hex))
  fractions[is.na(fractions)] <- 0
  if (any(fractions < -1e-8 | fractions > 1 + 1e-8)) stop("Invalid buffer overlap fraction.")
  hex$distance_to_high_vol_ft <- as.numeric(distances)
  hex$fraction_overlap <- pmin(1, pmax(0, fractions))
  hex
}

validate_aadt_extent <- function(metrics, bounds, settings = aadt_settings()) {
  envelope <- sf::st_as_sfc(bounds)
  projected <- sf::st_transform(metrics, settings$measurement_crs)
  centers <- sf::st_transform(h3jsr::cell_to_point(metrics$h3_id), settings$measurement_crs)
  clearance <- as.numeric(sf::st_distance(centers, sf::st_boundary(envelope)))
  distance_m <- metrics$distance_to_high_vol_ft * 0.3048
  # A road wholly outside the queried envelope cannot be nearer than its boundary.
  if (any(lengths(sf::st_within(centers, envelope)) != 1L) || any(distance_m >= clearance) ||
      any(lengths(sf::st_covered_by(sf::st_buffer(projected, settings$buffer_m), envelope)) != 1L)) {
    stop("Road search extent is insufficient. Increase padding and acquire a new snapshot.")
  }
  invisible(TRUE)
}
