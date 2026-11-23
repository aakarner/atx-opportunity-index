if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
source("R/municipal_boundary.R")
source("R/aadt.R")

settings <- aadt_settings()
id <- "88489e30bbfffff"
hex <- sf::st_sf(h3_id = id, geometry = h3jsr::cell_to_polygon(id), crs = 4326)
center <- sf::st_coordinates(sf::st_transform(h3jsr::cell_to_point(id), 26914))[1, ]
line <- function(start, end) {
  sf::st_linestring(rbind(center + start, center + end))
}
roads <- sf::st_sf(
  AADT_CUR = c(60000, 50000),
  geometry = sf::st_sfc(line(c(100, 0), c(150, 0)), line(c(-10, 0), c(10, 0)), crs = 26914)
)
settings$buffer_m <- 100
result <- calculate_aadt_metrics(hex, sf::st_transform(roads, 3857), settings)
# A nearby nonqualifying road must not affect the known 100 m distance.
stopifnot(abs(result$distance_to_high_vol_ft * 0.3048 - 100) < 0.001,
          sf::st_crs(result)$epsg == 26914)
# This short segment and its entire capsule fit inside the cell. The analytic
# area includes two semicircular end caps and catches the old FLAT buffer bug.
expected_area <- 2 * 100 * 50 + pi * 100^2
observed_area <- result$fraction_overlap * as.numeric(sf::st_area(result))
stopifnot(abs(observed_area / expected_area - 1) < 0.001)
duplicated_roads <- rbind(roads, roads)
duplicates <- calculate_aadt_metrics(hex, duplicated_roads, settings)
stopifnot(isTRUE(all.equal(result$fraction_overlap, duplicates$fraction_overlap, tolerance = 1e-8)))
far_road <- sf::st_sf(AADT_CUR = 60000,
  geometry = sf::st_sfc(line(c(3000, 0), c(3500, 0)), crs = 26914))
far <- calculate_aadt_metrics(hex, far_road, settings)
stopifnot(far$fraction_overlap == 0, abs(far$distance_to_high_vol_ft * 0.3048 - 3000) < 0.001)
bounds <- aadt_query_extent(hex, settings)
stopifnot(validate_aadt_extent(far, bounds, settings))
small_bounds <- sf::st_bbox(sf::st_transform(hex, 26914))
failed <- tryCatch(validate_aadt_extent(far, small_bounds, settings), error = identity)
stopifnot(inherits(failed, "error"))

# Inspect the actual regenerated deliverables and source provenance offline.
directory <- "scripts/aadt"
city <- load_municipal_boundary()
grid <- aadt_grid(city)
csv <- read.csv(file.path(directory, "aadt_metrics.csv"), stringsAsFactors = FALSE)
gpkg <- sf::st_read(file.path(directory, "aadt_metrics_hex8.gpkg"), quiet = TRUE)
metadata <- jsonlite::read_json(file.path(directory, "aadt_metrics.metadata.json"), simplifyVector = TRUE)
map <- jsonlite::read_json("site/assets/hexagons.json", simplifyVector = TRUE)
stopifnot(setequal(csv$h3_id, grid$h3_id), setequal(csv$h3_id, map$id),
          all(h3jsr::get_res(csv$h3_id) == 8L), !anyDuplicated(csv$h3_id),
          !anyNA(csv), all(csv$name == csv$h3_id), id %in% csv$h3_id,
          all(csv$fraction_overlap >= 0 & csv$fraction_overlap <= 1),
          all(csv$distance_to_high_vol_ft >= 0),
          isTRUE(all.equal(csv, sf::st_drop_geometry(gpkg))),
          identical(metadata$boundary_sha256, city$boundary_sha256))
for (file in names(metadata$output_sha256)) {
  stopifnot(digest::digest(file.path(directory, file), algo = "sha256", file = TRUE) == metadata$output_sha256[[file]])
}
settings <- aadt_settings()
bounds <- aadt_query_extent(grid, settings)
source_roads <- acquire_aadt_roads(file.path(directory, "source"), bounds, settings)
stopifnot(validate_aadt_extent(gpkg, bounds, settings))
road_outside <- sf::st_difference(sf::st_union(sf::st_transform(source_roads, 26914)),
                                sf::st_union(sf::st_transform(city, 26914)))
stopifnot(as.numeric(sf::st_length(road_outside)) > 0)
cat("AADT checks passed: ground distances, round ends, duplicate overlap, zero coverage,\n",
    "search completeness, map H8 IDs, Dog's Head, CSV/GPKG parity, and snapshot checksums.\n")
