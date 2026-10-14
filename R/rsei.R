# EPA RSEI v2.3.12 air geographic microdata. Measurement only: no policy cutoffs.
# Methodology Exhibit 5.1: CONUS grid 14 uses NAD83 / Conus Albers (EPSG:5070).
# X,Y are signed cell-center indices, not offsets from the lower-left corner.
validate_rsei_spec <- function(spec) {
  required <- c("version", "reporting_year", "grid_code", "cell_size_m", "url", "path", "refresh")
  if (!all(required %in% names(spec)) || spec$version != "2.3.12" ||
      spec$reporting_year != 2022 || spec$grid_code != 14 || spec$cell_size_m != 810) {
    stop("RSEI source contract requires v2.3.12, reporting year 2022, CONUS grid 14, 810 m.")
  }
  invisible(spec)
}

rsei_fields <- function() c("GridCode", "X", "Y", "NumFacs", "NumReleases", "NumChems",
                            "ToxConc", "Score", "Pop", "CTConc", "NCTConc")

acquire_rsei_source <- function(spec) {
  validate_rsei_spec(spec)
  path <- spec$path
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(path) || isTRUE(spec$refresh)) {
    tmp <- paste0(path, ".download")
    on.exit(unlink(tmp), add = TRUE)
    request <- httr2::request(spec$url) |> httr2::req_timeout(1800) |> httr2::req_retry(max_tries = 3)
    httr2::req_perform(request, path = tmp)
    validate_rsei_archive(tmp)
    if (!file.rename(tmp, path)) stop("Cannot finalize RSEI download.")
  }
  validate_rsei_archive(path)
  hash <- digest::digest(path, algo = "sha256", file = TRUE)
  metadata_path <- paste0(path, ".json")
  if (file.exists(metadata_path) && !isTRUE(spec$refresh)) {
    metadata <- jsonlite::read_json(metadata_path, simplifyVector = TRUE)
    if (!identical(metadata$sha256, hash) || !identical(metadata$url, spec$url) ||
        !identical(metadata$version, spec$version) || metadata$reporting_year != spec$reporting_year) {
      stop("RSEI cache differs from its provenance; inspect it or explicitly refresh the source.")
    }
  } else {
    jsonlite::write_json(list(url = spec$url, version = spec$version,
      reporting_year = spec$reporting_year, retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      sha256 = hash, bytes = unname(file.info(path)$size),
      documentation = "https://www.epa.gov/rsei/documentation-risk-screening-environmental-indicators-rsei-geographic-microdata-rsei-gm"),
      metadata_path, auto_unbox = TRUE, pretty = TRUE)
  }
  c(path, metadata_path)
}

validate_rsei_archive <- function(path) {
  # gzip checks the complete stream and CRC, not only the CSV header.
  gzip <- Sys.which("gzip")
  if (!nzchar(gzip)) stop("RSEI acquisition requires gzip for archive integrity validation.")
  status <- system2(gzip, c("-t", shQuote(path)), stdout = FALSE, stderr = FALSE)
  if (status != 0) stop("Invalid/truncated RSEI gzip archive: ", path)
  con <- gzfile(path, "rt"); on.exit(close(con))
  header <- strsplit(gsub('"', '', readLines(con, n = 1)), ",", fixed = TRUE)[[1]]
  if (!identical(header, rsei_fields())) stop("Unexpected RSEI source schema: ", paste(header, collapse = ", "))
  invisible(path)
}

make_rsei_template <- function(footprint, spec) {
  validate_rsei_spec(spec)
  footprint <- sf::st_transform(footprint, 5070)
  bb <- sf::st_bbox(footprint); size <- spec$cell_size_m
  xy <- expand.grid(X = seq(floor(bb["xmin"] / size - .5), ceiling(bb["xmax"] / size + .5)),
                    Y = seq(floor(bb["ymin"] / size - .5), ceiling(bb["ymax"] / size + .5)))
  geometry <- lapply(seq_len(nrow(xy)), function(i) {
    x <- xy$X[i] * size; y <- xy$Y[i] * size; h <- size / 2
    sf::st_polygon(list(matrix(c(x-h,y-h,x+h,y-h,x+h,y+h,x-h,y+h,x-h,y-h), ncol=2, byrow=TRUE)))
  })
  cells <- sf::st_sf(GridCode = spec$grid_code, xy, geometry = sf::st_sfc(geometry, crs=5070))
  cells <- cells[lengths(sf::st_intersects(cells, footprint)) > 0, ]
  cells$rsei_cell_id <- paste(cells$GridCode, cells$X, cells$Y, sep = ":")
  require_unique_id(cells, "rsei_cell_id", "RSEI template")
  cells
}

extract_rsei_cells <- function(source_files, template, spec) {
  path <- source_files[endsWith(source_files, ".gz")]
  if (length(path) != 1) stop("Expected one RSEI compressed source file.")
  wanted <- template$rsei_cell_id
  found <- list(); total_rows <- 0L
  xr <- range(template$X); yr <- range(template$Y)
  callback <- readr::SideEffectChunkCallback$new(function(x, pos) {
    if (nrow(readr::problems(x))) stop("RSEI CSV parse failure at source position ", pos)
    if (anyNA(x[c("GridCode", "X", "Y")]) || any(x$X != trunc(x$X) | x$Y != trunc(x$Y))) {
      stop("Invalid RSEI grid indices.")
    }
    nearby <- x$GridCode == spec$grid_code & x$X >= xr[1] & x$X <= xr[2] & x$Y >= yr[1] & x$Y <= yr[2]
    local <- x[nearby, ]
    ids <- paste(local$GridCode, local$X, local$Y, sep = ":")
    keep <- ids %in% wanted
    if (any(keep)) found[[length(found) + 1L]] <<- as.data.frame(local[keep, ])
    total_rows <<- total_rows + nrow(x)
  })
  readr::read_csv_chunked(path, callback, chunk_size = 250000,
    col_types = readr::cols(.default = readr::col_double()), progress = FALSE)
  values <- dplyr::bind_rows(found)
  if (!nrow(values)) stop("No modeled RSEI cells found in Austin; inspect grid alignment/source.")
  values$rsei_cell_id <- paste(values$GridCode, values$X, values$Y, sep = ":")
  require_unique_id(values, "rsei_cell_id", "RSEI source subset")
  measures <- setdiff(rsei_fields(), c("GridCode", "X", "Y"))
  if (any(!is.finite(as.matrix(values[measures]))) || any(as.matrix(values[measures]) < 0)) {
    stop("Invalid RSEI source measurements; missing measurements cannot become zero.")
  }
  result <- dplyr::left_join(template, values[c("rsei_cell_id", measures)],
                            by = "rsei_cell_id", relationship = "one-to-one")
  result$rsei_record_present <- result$rsei_cell_id %in% values$rsei_cell_id
  # EPA GM documentation p.12: national files omit cells unaffected by modeled
  # releases. Only an ABSENT record in a fully validated source becomes model zero.
  # This is not zero actual pollution, and Pop is not inferred from absence.
  for (field in setdiff(measures, "Pop")) result[[field]][!result$rsei_record_present] <- 0
  result$rsei_source_status <- ifelse(result$rsei_record_present, "Modeled source record",
                                     "Absent from complete national file: no modeled contribution")
  result$rsei_version <- spec$version
  result$rsei_year <- spec$reporting_year
  attr(result, "national_rows_scanned") <- total_rows
  result
}

rsei_overlap <- function(areas, cells, id) {
  require_unique_id(areas, id, "RSEI reporting areas")
  areas <- sf::st_transform(areas, 5070)
  overlaps <- suppressWarnings(sf::st_intersection(areas[, id],
    cells[, c("rsei_cell_id", "ToxConc", "CTConc", "NCTConc", "rsei_record_present")]))
  overlaps$overlap_area_m2 <- as.numeric(sf::st_area(overlaps))
  overlaps <- overlaps[overlaps$overlap_area_m2 > 0, ]
  result <- sf::st_drop_geometry(overlaps)
  result$reporting_area_m2 <- as.numeric(sf::st_area(areas))[match(result[[id]], areas[[id]])]
  result
}

aggregate_rsei <- function(areas, crosswalk, id, spec) {
  rows <- lapply(split(crosswalk, crosswalk[[id]]), function(x) {
    coverage <- sum(x$overlap_area_m2) / x$reporting_area_m2[1]
    if (coverage > 1 + 1e-6) stop("RSEI cells overlap or exceed reporting area.")
    complete <- abs(coverage - 1) < 1e-6
    out <- data.frame(key = x[[id]][1], rsei_coverage_share = coverage,
      rsei_record_area_share = sum(x$overlap_area_m2[x$rsei_record_present]) / x$reporting_area_m2[1],
      rsei_tox_conc = if (complete) weighted.mean(x$ToxConc, x$overlap_area_m2) else NA_real_,
      rsei_cancer_tox_conc = if (complete) weighted.mean(x$CTConc, x$overlap_area_m2) else NA_real_,
      rsei_noncancer_tox_conc = if (complete) weighted.mean(x$NCTConc, x$overlap_area_m2) else NA_real_)
    names(out)[1] <- id; out
  })
  values <- if (length(rows)) dplyr::bind_rows(rows) else {
    z <- data.frame(key=character(), rsei_coverage_share=numeric(), rsei_record_area_share=numeric(),
      rsei_tox_conc=numeric(), rsei_cancer_tox_conc=numeric(), rsei_noncancer_tox_conc=numeric())
    names(z)[1] <- id; z
  }
  out <- dplyr::left_join(sf::st_drop_geometry(areas)[id], values, by = id,
                          relationship = "one-to-one")
  out$rsei_coverage_share[is.na(out$rsei_coverage_share)] <- 0
  out$rsei_status <- ifelse(is.na(out$rsei_tox_conc), "Incomplete grid coverage", "Area-weighted modeled air concentration")
  out$rsei_version <- spec$version; out$rsei_year <- spec$reporting_year
  out
}

rsei_at_sites <- function(sites, cells, spec) {
  p <- sf::st_coordinates(sf::st_transform(sites, 5070))
  # Deterministic half-open cells at boundaries, matching the 810 m template.
  ids <- paste(spec$grid_code, floor(p[,1] / spec$cell_size_m + .5),
               floor(p[,2] / spec$cell_size_m + .5), sep = ":")
  idx <- match(ids, cells$rsei_cell_id)
  data.frame(site_id = sites$site_id, rsei_cell_id = ids, rsei_tox_conc = cells$ToxConc[idx],
    rsei_status = ifelse(is.na(idx), "Outside extracted grid", cells$rsei_source_status[idx]),
    rsei_year = spec$reporting_year, rsei_version = spec$version)
}

write_rsei_outputs <- function(cells, h8, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(output_dir, "rsei_and_h8.gpkg")
  sf::st_write(cells, path, layer = "rsei_native_grid", delete_dsn = TRUE, quiet = TRUE)
  sf::st_write(h8, path, layer = "h8_components", quiet = TRUE)
  c(path, write_pipeline_csv(sf::st_drop_geometry(cells), output_dir, "rsei_native_grid.csv"),
    write_pipeline_csv(sf::st_drop_geometry(h8), output_dir, "h8_components.csv"))
}

rsei_registry <- function(registry, spec) {
  i <- match("Industrial air-toxic burden", registry$indicator)
  registry$status[i] <- "tract_H8_and_native_grid_site_query"
  registry$units[i] <- "Air toxicity-weighted concentration (RSEI ToxConc)"
  registry$vintage[i] <- paste("EPA RSEI", spec$version, "reporting year", spec$reporting_year)
  registry$limitation[i] <- paste("810 m modeled TRI-related air contributions; no population multiplier;",
    "area averages for tracts/H8, containing EPA cell for sites; not total pollution or a health standard.")
  registry
}

rsei_qa <- function(cells, h8, tracts) {
  data.frame(check = c("RSEI national records scanned", "RSEI extracted grid cells",
    "RSEI cells absent from source (documented no modeled contribution)",
    "H8 cells with incomplete RSEI coverage", "Tracts with incomplete RSEI coverage"),
    value = c(attr(cells, "national_rows_scanned"), nrow(cells), sum(!cells$rsei_record_present),
              sum(is.na(h8$rsei_tox_conc)), sum(is.na(tracts$rsei_tox_conc))),
    status = c("info", "info", "info", ifelse(anyNA(h8$rsei_tox_conc), "review", "pass"),
               ifelse(anyNA(tracts$rsei_tox_conc), "review", "pass")))
}
