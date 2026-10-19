if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
source('R/municipal_boundary.R')
spec <- yaml::read_yaml('config/pipeline.yml')$municipal_boundary
files <- acquire_municipal_boundary(spec)
city <- read_municipal_boundary(files,spec)
raw <- sf::st_read(files[1],quiet=TRUE)
stopifnot(setequal(unique(raw$JURISDICTION_TYPE),c('FULL','LTD')),
  all(raw$CITY_NAME=='CITY OF AUSTIN'),all(sf::st_is_valid(city)),nrow(city)==1)
# Independently published annexation polygons: all four Dog's Head pieces
# must be retained, not just a representative location.
dogs <- sf::st_read('tests/fixtures/dogs-head-annexation-2026.geojson',quiet=TRUE)
stopifnot(nrow(dogs)==4,all(dogs$JURISDICTION_CASE_NUMBER=='C7a-2026-0003'))
dog_union <- sf::st_union(sf::st_make_valid(sf::st_transform(dogs,5070)))
missing <- suppressWarnings(sf::st_difference(dog_union,sf::st_geometry(sf::st_transform(city,5070))))
# Projected/spherical validity repair creates tiny edge slivers. Check both
# relative area (<0.001%) and a strict 25 cm spatial tolerance.
stopifnot(sum(as.numeric(sf::st_area(missing)))/sum(as.numeric(sf::st_area(dog_union)))<1e-5)
city_tolerance <- sf::st_buffer(sf::st_geometry(sf::st_transform(city,5070)),0.25)
stopifnot(sum(as.numeric(sf::st_area(sf::st_difference(dog_union,city_tolerance))))<1)
point <- sf::st_sfc(sf::st_point(c(-97.66219,30.24908)),crs=4326)
stopifnot(lengths(sf::st_intersects(point,city))==1)
# Retained limited-purpose land must not be silently dropped by a FULL-only query.
ltd <- sf::st_union(sf::st_make_valid(sf::st_transform(raw[raw$JURISDICTION_TYPE=='LTD',],5070)))
ltd_missing <- suppressWarnings(sf::st_difference(ltd,sf::st_geometry(sf::st_transform(city,5070))))
stopifnot(sum(as.numeric(sf::st_area(ltd_missing)))/sum(as.numeric(sf::st_area(ltd)))<1e-5,
  sum(as.numeric(sf::st_area(sf::st_difference(ltd,city_tolerance))))<1)
jobs <- readr::read_csv('accessibility/output/h8_job_accessibility.csv',show_col_types=FALSE)
stopifnot(identical(validate_access_boundary(jobs,city),jobs))
fails <- function(expr)stopifnot(inherits(tryCatch(force(expr),error=identity),'error'))
fails(validate_access_boundary(jobs[-1,],city))
stale <- jobs;stale$city_boundary_sha256[1]<-'old';fails(validate_access_boundary(stale,city))
# The cache must reject unreviewed geometry rather than silently advancing a dated snapshot.
bad <- spec;bad$sha256<-paste(rep('0',64),collapse='');fails(acquire_municipal_boundary(bad))
p <- tempfile(fileext='.gpkg');file.create(p)
jsonlite::write_json(list(boundary_sha256=city$boundary_sha256,boundary_snapshot=city$boundary_snapshot),paste0(p,'.boundary.json'),auto_unbox=TRUE)
stopifnot(identical(validate_prepared_boundary(prepared_boundary_files(p),city),p))
changed <- city;changed$boundary_sha256<-'different';fails(validate_prepared_boundary(prepared_boundary_files(p),changed))
unlink(c(p,paste0(p,'.boundary.json')))
cat('Municipal boundary checks passed: Dog’s Head polygons, limited-purpose scope, exact origins, pinned checksum, and stale-source guards.\n')
