# Prepared traffic measurements retain their H8 analytical support in summaries.
traffic_input_files <- function(csv) {
  paths <- c(csv, sub("\\.csv$", ".metadata.json", csv))
  if (length(unique(paths)) != 2L || !all(file.exists(paths))) {
    stop("Missing traffic CSV/metadata. Run Rscript scripts/aadt/aadt_read.R.")
  }
  paths
}

read_traffic_metadata <- function(files, city) {
  metadata <- jsonlite::read_json(files[2], simplifyVector = TRUE)
  hash <- metadata$output_sha256[[basename(files[1])]]
  if (is.null(hash) || hash != digest::digest(files[1], algo = "sha256", file = TRUE)) {
    stop("Traffic CSV does not match its metadata checksum. Rebuild traffic preparation.")
  }
  if (!identical(metadata$boundary_sha256, city$boundary_sha256) ||
      !identical(metadata$boundary_snapshot, city$boundary_snapshot) ||
      !identical(metadata$h3_resolution, 8L) || metadata$measurement_crs != 26914L ||
      metadata$threshold != "AADT_CUR > 50000" || metadata$buffer_m != 300 ||
      metadata$buffer_end_caps != "ROUND" || metadata$overlap_scale != "fraction 0 to 1" ||
      !isTRUE(metadata$nearest_road_extent_check_passed)) {
    stop("Traffic source geography or measurement method differs from the reviewed specification.")
  }
  metadata
}

read_traffic_h8 <- function(files, metadata, ids) {
  x <- readr::read_csv(files[1], col_types = readr::cols(h3_id = "c"), show_col_types = FALSE)
  require_columns(x, c("h3_id", "distance_to_high_vol_ft", "fraction_overlap"), "Traffic CSV")
  require_unique_id(x, "h3_id", "Traffic CSV")
  if (!setequal(x$h3_id, ids) || nrow(x) != metadata$cell_count || any(h3jsr::get_res(x$h3_id) != 8L)) {
    stop("Traffic cell IDs differ from the map/accessibility grid. Rebuild traffic preparation.")
  }
  if (any(!is.na(x$distance_to_high_vol_ft) & (!is.finite(x$distance_to_high_vol_ft) | x$distance_to_high_vol_ft < 0)) ||
      any(!is.na(x$fraction_overlap) & (!is.finite(x$fraction_overlap) | x$fraction_overlap < 0 | x$fraction_overlap > 1))) {
    stop("Traffic measurements outside their valid ranges.")
  }
  data.frame(h3_id = x$h3_id, traffic_distance_ft = x$distance_to_high_vol_ft,
             traffic_buffer_share = x$fraction_overlap)
}

aggregate_traffic_tracts <- function(tracts, traffic, crosswalk) {
  rows <- dplyr::left_join(crosswalk, traffic, by = "h3_id", relationship = "many-to-one")
  valid <- is.finite(rows$traffic_distance_ft) & is.finite(rows$traffic_buffer_share)
  groups <- split(rows[valid & rows$overlap_area_m2 > 0, ], rows$GEOID[valid & rows$overlap_area_m2 > 0])
  result <- data.frame(GEOID = tracts$GEOID, traffic_distance_ft = NA_real_,
    traffic_buffer_share = NA_real_, traffic_coverage_share = 0, traffic_h8_cells = 0L,
    traffic_aggregation_method = "Unavailable: no measured H8 overlap")
  # Crosswalk areas are measured in the pipeline's EPSG:5070 equal-area CRS.
  tract_area <- as.numeric(sf::st_area(sf::st_transform(tracts, 5070)))
  for (id in names(groups)) {
    x <- groups[[id]]
    i <- match(id, result$GEOID)
    result$traffic_distance_ft[i] <- stats::weighted.mean(x$traffic_distance_ft, x$overlap_area_m2)
    result$traffic_buffer_share[i] <- stats::weighted.mean(x$traffic_buffer_share, x$overlap_area_m2)
    result$traffic_coverage_share[i] <- sum(x$overlap_area_m2) / tract_area[i]
    result$traffic_h8_cells[i] <- nrow(x)
    result$traffic_aggregation_method[i] <- "Area-weighted H8 mean over covered tract area"
  }
  if (any(result$traffic_coverage_share > 1 + 1e-7)) stop("Traffic overlap exceeds tract area.")
  result$traffic_coverage_share <- pmin(1, result$traffic_coverage_share)
  result
}

traffic_at_sites <- function(sites, traffic) {
  ids <- h3jsr::point_to_cell(sf::st_transform(sites, 4326), res = 8L)
  index <- match(ids, traffic$h3_id)
  data.frame(site_id = sites$site_id, traffic_h3_id = ids,
    traffic_distance_ft = traffic$traffic_distance_ft[index],
    traffic_buffer_share = traffic$traffic_buffer_share[index],
    traffic_method = ifelse(is.na(index), "Unavailable: containing H8 has no traffic record",
                            "Containing H8 center distance and full-cell buffer coverage"))
}

traffic_registry <- function(registry, metadata) {
  i <- match("Near-road traffic pollution", registry$indicator)
  registry$indicator[i] <- "Near-road traffic exposure"
  registry$status[i] <- "H8_and_area_weighted_tract_summary"
  registry$units[i] <- "Feet to nearest >50,000-AADT road; H8 fraction within 300 m"
  registry$vintage[i] <- paste("TxDOT extraction", paste(metadata$source_extract_dates, collapse = ", "))
  registry$limitation[i] <- paste("Traffic proximity proxy; observation years unspecified.",
    "Tract means describe covered H8 area; full-cell overlap fractions are spatial approximations.")
  registry
}

traffic_qa <- function(h8, tracts) {
  data.frame(check = c("Traffic H8 records", "H8 cells with unavailable traffic measurements",
    "Tracts with no traffic H8 coverage", "Tracts with partial traffic H8 coverage"),
    value = c(nrow(h8), sum(!is.finite(h8$traffic_distance_ft) | !is.finite(h8$traffic_buffer_share)),
      sum(tracts$traffic_coverage_share == 0), sum(tracts$traffic_coverage_share > 0 & tracts$traffic_coverage_share < .999999)),
    status = c("pass", "info", "info", "info"))
}
