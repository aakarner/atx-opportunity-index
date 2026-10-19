# Small public snapshot for a static GitHub Pages client. No private site inputs.
web_component_rows <- function(x, geography, spec) {
  is_hex <- geography == "hex"
  x <- sf::st_drop_geometry(x)
  fields <- if (is_hex) c("access_total_jobs", "access_low_wage_jobs", "access_middle_wage_jobs", "access_high_wage_jobs") else
    c("transit_jobs_45min", "transit_low_wage_jobs_45min", "transit_middle_wage_jobs_45min", "transit_high_wage_jobs_45min")
  out <- data.frame(id=if(is_hex) x$h3_id else x$GEOID,
    jobs_total=x[[fields[1]]], jobs_low=x[[fields[2]]], jobs_middle=x[[fields[3]]], jobs_high=x[[fields[4]]],
    rsei=x$rsei_tox_conc, rsei_cancer=x$rsei_cancer_tox_conc, rsei_noncancer=x$rsei_noncancer_tox_conc,
    rsei_coverage=x$rsei_coverage_share,
    access_method=if(is_hex) "H8 origin estimate" else x$access_aggregation_method,
    stringsAsFactors=FALSE)
  flags <- classify_mockup(out$jobs_total, out$rsei, spec)
  out$strong_access <- flags$mockup_strong_access
  out$elevated_burden <- flags$mockup_elevated_burden
  stopifnot(!anyDuplicated(out$id))
  out
}

write_web_mockup_data <- function(h8, tracts, city, classification_spec, directory="site/assets") {
  dir.create(directory, recursive=TRUE, showWarnings=FALSE)
  spec <- classification_spec$mockup
  validate_mockup_spec(spec)
  hex <- web_component_rows(h8, "hex", spec)
  tract <- web_component_rows(tracts, "tract", spec)
  city_projected <- sf::st_geometry(sf::st_transform(city,5070))
  covered <- suppressWarnings(sf::st_intersection(sf::st_union(sf::st_geometry(sf::st_transform(h8,5070))),city_projected))
  metadata <- list(boundary=list(snapshot=city$boundary_snapshot,source=city$boundary_source,
    sha256=city$boundary_sha256,area_km2=as.numeric(sf::st_area(city_projected))/1e6,
    hex_coverage_share=sum(as.numeric(sf::st_area(covered)))/sum(as.numeric(sf::st_area(city_projected)))),
    schema_version=1L, thresholds=spec, h3_resolution=8L,
    jobs_year=unique(h8$jobs_year), network_snapshot=unique(h8$network_snapshot),
    gtfs_snapshot=unique(h8$gtfs_snapshot), departure_datetime=unique(as.character(h8$departure_datetime)),
    rsei_year=unique(h8$rsei_year), rsei_version=unique(h8$rsei_version),
    counts=list(hexagons=nrow(hex), tracts=nrow(tract),
      strong_hex=sum(hex$strong_access,na.rm=TRUE), elevated_hex=sum(hex$elevated_burden,na.rm=TRUE),
      both_hex=sum(hex$strong_access & hex$elevated_burden,na.rm=TRUE),
      both_tract=sum(tract$strong_access & tract$elevated_burden,na.rm=TRUE),
      strong_tract=sum(tract$strong_access,na.rm=TRUE), elevated_tract=sum(tract$elevated_burden,na.rm=TRUE)))
  json <- function(x, filename) {
    p <- file.path(directory,filename)
    jsonlite::write_json(x,p,auto_unbox=TRUE,na="null",null="null",digits=15,pretty=FALSE)
    p
  }
  geo <- function(x, filename) {
    p <- file.path(directory,filename)
    sf::st_write(sf::st_transform(x,4326),p,driver="GeoJSON",delete_dsn=TRUE,quiet=TRUE,
      layer_options="COORDINATE_PRECISION=7")
    p
  }
  tract_sf <- sf::st_sf(tract,geometry=sf::st_geometry(tracts),crs=sf::st_crs(tracts))
  c(json(metadata,"metadata.json"),json(hex,"hexagons.json"),geo(tract_sf,"tracts.geojson"),
    geo(city[,c("NAME","boundary_snapshot","boundary_source","boundary_sha256"),drop=FALSE],"city.geojson"))
}
