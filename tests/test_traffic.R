if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)
fails <- function(expr) stopifnot(inherits(tryCatch(force(expr), error = identity), "error"))

# A tract with half its area covered averages only that covered half. A tract
# with no H8 overlap must remain unavailable instead of inheriting a neighbor.
square <- function(offset) sf::st_polygon(list(matrix(
  c(offset,0, offset+10,0, offset+10,10, offset,10, offset,0), ncol=2, byrow=TRUE)))
tracts <- sf::st_sf(GEOID=c("partial","uncovered"),
  geometry=sf::st_sfc(square(0),square(20),crs=5070))
traffic <- data.frame(h3_id=c("a","b"), traffic_distance_ft=c(100,300), traffic_buffer_share=c(0,1))
crosswalk <- data.frame(GEOID="partial",h3_id=c("a","b"),overlap_area_m2=c(25,25))
result <- aggregate_traffic_tracts(tracts,traffic,crosswalk)
stopifnot(result$traffic_distance_ft[1]==200,result$traffic_buffer_share[1]==.5,
          result$traffic_coverage_share[1]==.5,result$traffic_coverage_share[2]==0,
          is.na(result$traffic_distance_ft[2]),is.na(result$traffic_buffer_share[2]))
# Equal-area coverage must also be correct when reporting geometry is geographic.
geographic <- aggregate_traffic_tracts(sf::st_transform(tracts,4326),traffic,crosswalk)
stopifnot(abs(geographic$traffic_coverage_share[1]-.5)<1e-7)
traffic$traffic_distance_ft[2] <- NA_real_
missing <- aggregate_traffic_tracts(tracts,traffic,crosswalk)
stopifnot(missing$traffic_distance_ft[1]==100,missing$traffic_buffer_share[1]==0,
          missing$traffic_coverage_share[1]==.25)

config <- read_pipeline_config("config/pipeline.yml")
city <- load_municipal_boundary()
files <- traffic_input_files(config$inputs$traffic)
metadata <- read_traffic_metadata(files,city)
ids <- municipal_h8_ids(city)
actual <- read_traffic_h8(files,metadata,ids)
fails(read_traffic_h8(files,metadata,ids[-1]))
stale <- city;stale$boundary_sha256 <- "old"
fails(read_traffic_metadata(files,stale))
work <- tempfile("traffic-input-test-");dir.create(work)
copies <- file.path(work,basename(files));stopifnot(all(file.copy(files,copies)))
cat("\n",file=copies[1],append=TRUE)
fails(read_traffic_metadata(copies,city))
unlink(work,recursive=TRUE)

# Pipeline and browser exports must retain the original measurements exactly.
h8 <- targets::tar_read(h8_components)
tract <- targets::tar_read(tract_components)
profile <- targets::tar_read(site_profiles)
index <- match(h8$h3_id,actual$h3_id)
stopifnot(identical(h8$traffic_distance_ft,actual$traffic_distance_ft[index]),
          identical(h8$traffic_buffer_share,actual$traffic_buffer_share[index]),
          all(tract$traffic_coverage_share>=0 & tract$traffic_coverage_share<=1),
          all(is.na(tract$traffic_distance_ft[tract$traffic_coverage_share==0])))
site_index <- match(profile$traffic_h3_id,actual$h3_id)
stopifnot(identical(profile$traffic_distance_ft,actual$traffic_distance_ft[site_index]),
          identical(profile$traffic_buffer_share,actual$traffic_buffer_share[site_index]))
web <- jsonlite::read_json("site/assets/hexagons.json",simplifyVector=TRUE)
index <- match(web$id,actual$h3_id)
stopifnot(max(abs(web$traffic_distance_ft-actual$traffic_distance_ft[index]))<1e-8,
          max(abs(web$traffic_buffer_share-actual$traffic_buffer_share[index]))<1e-12)
web_tract <- sf::st_read("site/assets/tracts.geojson",quiet=TRUE)
index <- match(web_tract$id,tract$GEOID)
stopifnot(isTRUE(all.equal(web_tract$traffic_distance_ft,tract$traffic_distance_ft[index],tolerance=1e-12)),
          isTRUE(all.equal(web_tract$traffic_buffer_share,tract$traffic_buffer_share[index],tolerance=1e-12)))
unknown <- sf::st_as_sf(data.frame(site_id="outside",lon=-96.8,lat=32.8),coords=c("lon","lat"),crs=4326)
stopifnot(is.na(traffic_at_sites(unknown,actual)$traffic_distance_ft))
cat("Traffic integration passed: area weights, partial/missing coverage, stale-input rejection, H8/site/tract exports.\n")
