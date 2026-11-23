# Run from the repository root: Rscript scripts/aadt/aadt_read.R
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
source("R/municipal_boundary.R")
source("R/aadt.R")

settings <- aadt_settings()
directory <- "scripts/aadt"
city <- load_municipal_boundary()
hex <- aadt_grid(city)
bounds <- aadt_query_extent(hex, settings)
roads <- acquire_aadt_roads(file.path(directory, "source"), bounds, settings)
metrics <- calculate_aadt_metrics(hex, roads, settings)
validate_aadt_extent(metrics, bounds, settings)

# Keep the original name/id fields for readers of Peter's CSV, with h3_id as the
# stable integration key. The sequential id is only a row identifier.
metrics$id <- seq_len(nrow(metrics))
metrics$name <- metrics$h3_id
metrics <- metrics[c("id", "name", "h3_id", "distance_to_high_vol_ft", "fraction_overlap")]
table <- sf::st_drop_geometry(metrics)
if (anyNA(table) || any(!is.finite(table$distance_to_high_vol_ft))) stop("Incomplete traffic metrics.")
jobs <- read.csv("accessibility/output/h8_job_accessibility.csv", stringsAsFactors = FALSE)
invisible(validate_access_boundary(jobs, city))
if (!setequal(table$h3_id, jobs$h3_id)) stop("Traffic and map source grids differ.")

# Build all deliverables before replacing outputs. CSV is written without row names.
staging <- tempfile("aadt-outputs-", tmpdir = directory)
dir.create(staging)
tryCatch({
  sf::st_write(metrics, file.path(staging, "aadt_metrics_hex8.gpkg"),
               layer = "aadt_metrics_hex8", quiet = TRUE)
  write.csv(table, file.path(staging, "aadt_metrics.csv"), row.names = FALSE)
  sf::st_write(hex, file.path(staging, "hex_8_full.gpkg"), layer = "hex_8_full", quiet = TRUE)
  sf::st_write(city, file.path(staging, "austin_city_limits.gpkg"), layer = "austin_city_limits", quiet = TRUE)
  source_manifest <- jsonlite::read_json(file.path(directory, "source", "manifest.json"))
  metadata <- list(
    h3_resolution = 8L, cell_count = nrow(table), cell_selection = "H3 centers within shared municipal boundary",
    measurement_crs = settings$measurement_crs, distance_origin = "Canonical H3 cell center",
    threshold = paste("AADT_CUR >", settings$threshold_aadt),
    buffer_m = settings$buffer_m, buffer_end_caps = "ROUND", overlap_scale = "fraction 0 to 1",
    overlap_denominator = "Full H3 cell area", road_geometry = "Full source features, including outside city",
    source_url = settings$service_url, source_retrieved_utc = source_manifest$retrieved_utc,
    source_extract_dates = sort(unique(roads$EXT_DATE)),
    traffic_observation_year = "Not supplied by AADT_CUR; EXT_DATE is the source extraction date",
    boundary_snapshot = city$boundary_snapshot, boundary_sha256 = city$boundary_sha256,
    road_search_padding_m = settings$search_padding_m, nearest_road_extent_check_passed = TRUE,
    high_volume_road_features = nrow(roads),
    distance_range_ft = range(table$distance_to_high_vol_ft), overlap_range = range(table$fraction_overlap),
    zero_overlap_cells = sum(table$fraction_overlap == 0),
    missing_data_note = "Coverage check verifies the query, not completeness of TxDOT traffic observations"
  )
  output_files <- list.files(staging)
  metadata$output_sha256 <- as.list(stats::setNames(
    vapply(file.path(staging, output_files), digest::digest, character(1), algo = "sha256", file = TRUE),
    output_files
  ))
  jsonlite::write_json(metadata, file.path(staging, "aadt_metrics.metadata.json"),
                       auto_unbox = TRUE, pretty = TRUE, digits = NA)
  # Publish metadata last. Its checksums identify any interrupted/mixed output set.
  for (file in c(output_files, "aadt_metrics.metadata.json")) {
    if (!file.rename(file.path(staging, file), file.path(directory, file))) stop("Cannot publish ", file)
  }
}, finally = unlink(staging, recursive = TRUE))
cat("Rebuilt traffic metrics for", nrow(table), "H3 resolution 8 cells.\n")
