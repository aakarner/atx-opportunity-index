major_frontage_files <- function(spec) {
  inventory <- file.path(spec$inventory_dir, 'manifest.json')
  transport <- file.path(spec$transport_dir, 'manifest.json')
  inv <- jsonlite::fromJSON(inventory)$files
  net <- unlist(jsonlite::fromJSON(transport)$files)
  inv <- inv[grepl('^page-.*\\.geojson$', inv$path), ]
  net <- net[grepl('^(roads|other_roads|trails)_[0-9]+\\.geojson$', names(net))]
  stopifnot(nrow(inv) > 0, all(vapply(c('roads_', 'other_roads_', 'trails_'),
    function(prefix) any(startsWith(names(net), prefix)), logical(1))))
  inventory_pages <- list.files(spec$inventory_dir, '^page-.*\\.geojson$')
  network_pages <- list.files(spec$transport_dir, '^(roads|other_roads|trails)_.*\\.geojson$')
  if (!setequal(inventory_pages, inv$path) || !setequal(network_pages, names(net)))
    stop('Major-street source pages differ from the acquisition manifest')
  c(inventory, transport, file.path(spec$inventory_dir, inv$path), file.path(spec$transport_dir, names(net)))
}

build_street_windows <- function(hexes, city, policy) {
  geometry <- sf::st_transform(hexes, 26914)
  city <- sf::st_union(sf::st_geometry(sf::st_transform(city, 26914)))
  centers <- sf::st_sf(h3_id = geometry$h3_id,
    geometry = sf::st_transform(h3jsr::cell_to_point(geometry$h3_id), 26914))
  radii <- c(primary = policy$adopted_radius_miles, sensitivity = policy$sensitivity_radius_miles)
  windows <- lapply(radii, function(radius) {
    circle <- sf::st_buffer(centers, radius * 1609.344, nQuadSegs = 90)
    clipped <- suppressWarnings(sf::st_intersection(circle, city))
    area <- as.numeric(sf::st_area(clipped))
    clipped$observed_area_share <- area / as.numeric(sf::st_area(circle))[match(clipped$h3_id, circle$h3_id)]
    clipped[area > 0, ]
  })
  list(windows = windows, geometry = geometry, city = city, radii = radii)
}

build_major_frontage <- function(study, files, script, spec) {
  inv <- jsonlite::fromJSON(files[1])
  net <- jsonlite::fromJSON(files[2])
  expected <- c(setNames(inv$files$sha256, inv$files$path), unlist(net$files))
  hashes <- vapply(files[-(1:2)], digest::digest, character(1), algo = 'sha256', file = TRUE)
  if (!all(hashes == expected[basename(names(hashes))])) stop('Major-street source checksum mismatch')
  scratch <- tempfile('major-frontage-')
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  windows <- file.path(scratch, 'windows.gpkg')
  output <- file.path(scratch, 'frontage.csv')
  sf::st_write(sf::st_sf(geometry = study$city), windows, layer = 'city', quiet = TRUE)
  for (scenario in names(study$windows))
    sf::st_write(study$windows[[scenario]], windows, layer = scenario, quiet = TRUE)
  python <- Sys.getenv('FRONTAGE_PYTHON', 'python3')
  args <- c(script, spec$inventory_dir, spec$transport_dir, windows, output)
  if (system2(python, shQuote(args)) != 0) stop('Error measuring major-street frontage with ', python)
  x <- read.csv(output, colClasses = c(inventory_observed = 'logical'))
  if (!setequal(x$scenario, names(study$windows))) stop('Missing frontage scenario')
  for (scenario in names(study$windows)) {
    ids <- x$h3_id[x$scenario == scenario]
    stopifnot(!anyDuplicated(ids), setequal(ids, study$windows[[scenario]]$h3_id))
  }
  list(data = x, sources = list(inventory = inv$source_url, inventory_retrieved = inv$retrieved_utc,
    transport = net$sources[c('roads', 'other_roads', 'trails')], transport_retrieved = net$retrieved,
    manifest_hashes = as.list(setNames(vapply(files[1:2], digest::digest, character(1),
      algo = 'sha256', file = TRUE), c('inventory', 'transport')))))
}
