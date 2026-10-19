if(dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"),.libPaths()))
for(p in list.files("R",pattern="\\.R$",full.names=TRUE))source(p)
spec <- read_classification_spec("config/classification-review.yml")
h8 <- targets::tar_read(h8_components)
tracts <- targets::tar_read(tract_components)
city <- targets::tar_read(city_boundary)
d <- tempfile("web-export-");dir.create(d)
files <- write_web_mockup_data(h8,tracts,city,spec,d)
stopifnot(length(files)==4,all(file.exists(files)))
x <- jsonlite::read_json(file.path(d,"hexagons.json"),simplifyVector=TRUE)
stopifnot(identical(x$id,h8$h3_id),max(abs(x$rsei-h8$rsei_tox_conc))<1e-9,
 all(x$jobs_total==h8$access_total_jobs),all(x$strong_access==(h8$access_total_jobs>50000)),all(x$elevated_burden==(h8$rsei_tox_conc>=100)))
t <- sf::st_read(file.path(d,"tracts.geojson"),quiet=TRUE)
stopifnot(nrow(t)==nrow(tracts),sf::st_crs(t)$epsg==4326,identical(t$id,tracts$GEOID),
 max(abs(t$jobs_total-tracts$transit_jobs_45min))<1e-8)
# Missing input must serialize as null / unknown, not zero or false.
h8$access_total_jobs[1]<-NA_real_;h8$rsei_tox_conc[1]<-NA_real_
invisible(write_web_mockup_data(h8,tracts,city,spec,d))
x<-jsonlite::read_json(file.path(d,"hexagons.json"))
stopifnot(is.null(x[[1]]$jobs_total),is.null(x[[1]]$rsei),is.null(x[[1]]$strong_access),is.null(x[[1]]$elevated_burden))
unlink(d,recursive=TRUE)
cat("Web export checks passed: source values, geography, counts, missingness.\n")
