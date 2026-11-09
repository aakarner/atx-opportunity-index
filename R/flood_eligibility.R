# The City fully developed floodplain is a separate, noncompensatory constraint.
# It does not alter benefit values or enter a weighted environmental score.
flood_constraint_files <- function(spec) {
  manifest_path <- file.path(spec$snapshot_dir, "manifest.json")
  if (!file.exists(manifest_path)) stop("Run python3 scripts/prepare/pull_fully_developed_floodplain.py first.")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  c(manifest_path, file.path(spec$snapshot_dir, manifest$files$path))
}

read_flood_constraint <- function(files, spec) {
  manifest <- jsonlite::read_json(files[basename(files) == "manifest.json"], simplifyVector = TRUE)
  if (!identical(manifest$source_url, spec$url)) stop("Flood constraint source does not match policy.")
  for (i in seq_len(nrow(manifest$files))) {
    path <- files[basename(files) == manifest$files$path[i]]
    if (length(path) != 1L || digest::digest(file = path, algo = "sha256") != manifest$files$sha256[i])
      stop("Flood constraint checksum mismatch.")
  }
  polygons <- do.call(rbind, lapply(files[grepl("\\.geojson$", files)], sf::st_read, quiet = TRUE))
  if (anyDuplicated(polygons$OBJECTID) || !setequal(polygons$OBJECTID, manifest$source_ids))
    stop("Flood constraint source IDs are incomplete or duplicated.")
  known <- c("City of Austin Fully Developed 100-Year Floodplain", "City of Austin Fully Developed 25-Year Floodplain",
             "City of Austin Master Plan 25-Year Floodplain", "Shallow", "A", "AE",
             paste0("AH Depth ", 1:3, "ft"), paste0("AO Depth ", 1:3, "ft"))
  if (anyNA(polygons$FLOOD_ZONE) || !all(polygons$FLOOD_ZONE %in% known))
    stop("Unrecognized City regulatory flood category; review the layer before screening.")
  invalid <- sum(!sf::st_is_valid(polygons))
  polygons <- sf::st_make_valid(sf::st_transform(polygons, 5070))
  if (any(sf::st_is_empty(polygons)) || !all(sf::st_is_valid(polygons))) stop("Invalid flood geometry.")
  list(polygons = polygons, manifest = manifest, repaired_geometries = invalid)
}

flood_constraint_union <- function(source, hexes, city) {
  envelope <- as.numeric(strsplit(source$manifest$query_envelope, ",", fixed = TRUE)[[1]])
  current <- sf::st_bbox(c(sf::st_geometry(sf::st_transform(hexes, 4326)),
                         sf::st_geometry(sf::st_transform(city, 4326))))
  if (any(current[c(1,2)] < envelope[c(1,2)] - 1e-8) || any(current[c(3,4)] > envelope[c(3,4)] + 1e-8))
    stop("Flood source query does not cover the current study envelope.")
  footprint <- sf::st_union(c(sf::st_geometry(sf::st_transform(hexes,5070)),
                              sf::st_geometry(sf::st_transform(city,5070))))
  relevant <- source$polygons[lengths(sf::st_intersects(source$polygons, footprint)) > 0,]
  if (!nrow(relevant)) stop("No City floodplain polygons intersect the study footprint; review source.")
  sf::st_union(sf::st_geometry(relevant))
}

flood_area_screen <- function(areas, flood, id) {
  if (anyDuplicated(areas[[id]]) || anyNA(areas[[id]])) stop("Flood screen requires unique IDs.")
  areas <- sf::st_transform(areas[, id, drop = FALSE], sf::st_crs(flood))
  area <- as.numeric(sf::st_area(areas))
  if (any(!is.finite(area) | area <= 0)) stop("Flood screen requires nonempty area geometries.")
  # Index individual dissolved components so each cell only overlays nearby
  # polygons, rather than repeating a citywide overlay for every cell.
  pieces <- suppressWarnings(sf::st_intersection(areas, sf::st_sf(geometry = sf::st_cast(flood, "POLYGON"))))
  amounts <- tapply(as.numeric(sf::st_area(pieces)), pieces[[id]], sum)
  overlap <- as.numeric(amounts[match(areas[[id]], names(amounts))]); overlap[is.na(overlap)] <- 0
  if (any(overlap > area * (1 + 1e-8))) stop("Flood overlap exceeds full geometry area.")
  # Strict geometric coverage, never a rounded percentage or centroid test.
  entire <- seq_len(nrow(areas)) %in% unique(unlist(sf::st_covers(flood, areas, prepared = TRUE)))
  result <- data.frame(id = as.character(areas[[id]]), overlap_share = pmin(1, overlap / area),
                       excluded = entire,
                       status = ifelse(entire, "ineligible", ifelse(overlap > 0, "address_check_required", "not_excluded")))
  list(rows = result, pieces = pieces)
}

flood_address_screen <- function(points, flood, study = NULL, id = "site_id") {
  if (anyDuplicated(points[[id]]) || anyNA(points[[id]]) || any(sf::st_is_empty(points)))
    stop("Flood addresses require unique IDs and known coordinates.")
  points <- sf::st_transform(points, sf::st_crs(flood))
  covered <- if (is.null(study)) rep(TRUE, nrow(points)) else
    lengths(sf::st_intersects(points, sf::st_transform(study, sf::st_crs(flood)))) > 0
  hit <- lengths(sf::st_intersects(points, flood)) > 0
  hit[!covered] <- NA
  data.frame(site_id = as.character(points[[id]]), flood_ineligible = hit,
             flood_eligibility_status = ifelse(is.na(hit), "unknown", ifelse(hit, "ineligible", "not_excluded")))
}

attach_flood_constraint <- function(profiles, constraint) {
  if (!setequal(profiles$site_id, constraint$site_id)) stop("Site flood constraint IDs differ.")
  result <- dplyr::left_join(profiles, constraint, by = "site_id", relationship = "one-to-one")
  result$overall_screen[result$flood_ineligible %in% TRUE] <-
    "Ineligible for development: City fully developed floodplain"
  result
}

flood_constraint_registry <- function(registry, source) {
  registry$role[registry$indicator == "Mapped FEMA floodplain"] <- "legacy_context"
  rbind(registry, data.frame(indicator = "City fully developed floodplain", role = "eligibility_constraint",
    status = "hex_and_address_screen", units = "Entire-hex coverage / actual-point intersection",
    vintage = source$manifest$retrieved_at_utc,
    limitation = "Project eligibility rule, not a permit determination; partial hexes require address checks; no score weight"))
}

write_flood_constraint <- function(source, flood, hexes, tracts, sites, city, spec,
                                   directory = "site/assets", output = "output/components/flood-eligibility") {
  h <- flood_area_screen(hexes, flood, "h3_id")
  t <- flood_area_screen(tracts, flood, "GEOID")
  s <- flood_address_screen(sites, flood, city)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  # Per-hex exact intersections support fast, actual-point checks in the browser.
  parts <- h$pieces[as.numeric(sf::st_area(h$pieces)) > 0, "h3_id", drop = FALSE]
  parts <- suppressWarnings(sf::st_collection_extract(parts, "POLYGON"))
  path <- file.path(directory, "flood-geometry.geojson")
  sf::st_write(sf::st_transform(parts, 4326), path, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE,
               layer_options = "COORDINATE_PRECISION=10")
  data <- list(schema_version = 1L,
    metadata = list(source = spec$source, source_url = spec$url, retrieved_at_utc = source$manifest$retrieved_at_utc,
      source_manifest_sha256 = digest::digest(file = file.path(spec$snapshot_dir,"manifest.json"), algo = "sha256"),
      repaired_source_geometries = source$repaired_geometries,
      hex_rule = spec$hex_rule, address_rule = spec$address_rule,
      role = "eligibility_constraint", contributes_to_burden_score = FALSE,
      qualification = "Prototype development eligibility rule; not a permit determination.",
      counts = as.list(table(factor(h$rows$status, levels = c("ineligible", "address_check_required", "not_excluded"))))),
    hex = h$rows, tract = t$rows[,c("id","overlap_share")],
    geometry_file = basename(path), geometry_sha256 = digest::digest(file = path, algo = "sha256"))
  asset <- file.path(directory, "flood-eligibility.json")
  jsonlite::write_json(data, asset, auto_unbox = TRUE, na = "null", null = "null", digits = 15)
  files <- c(asset, file.path(output,c("hexagons.csv", "tracts.csv", "sites.csv")))
  write.csv(h$rows,files[2],row.names=FALSE,na="")
  write.csv(t$rows[,c("id","overlap_share")],files[3],row.names=FALSE,na="")
  write.csv(s,files[4],row.names=FALSE,na="")
  # Independent browser acceptance fixtures: true H3 centers plus a wet point
  # inside every affected cell, classified using projected sf geometry.
  centers <- sf::st_sf(h3_id=hexes$h3_id,geometry=h3jsr::cell_to_point(hexes$h3_id))
  wet <- suppressWarnings(sf::st_point_on_surface(parts))
  wet <- sf::st_transform(wet,4326)
  checks <- rbind(centers,wet[,"h3_id",drop=FALSE])
  coords <- sf::st_coordinates(checks)
  expected <- lengths(sf::st_intersects(sf::st_transform(checks,sf::st_crs(flood)),flood))>0
  fixtures <- data.frame(id=checks$h3_id,longitude=coords[,1],latitude=coords[,2],ineligible=expected)
  fixture_path <- file.path(output,"point_checks.json")
  jsonlite::write_json(fixtures,fixture_path,auto_unbox=TRUE,digits=15)
  dir.create('tests/fixtures',recursive=TRUE,showWarnings=FALSE)
  committed_fixture <- 'tests/fixtures/flood-point-checks.json'
  file.copy(fixture_path,committed_fixture,overwrite=TRUE)
  files <- c(files,path,fixture_path,committed_fixture)
  print(table(h$rows$status))
  files
}
