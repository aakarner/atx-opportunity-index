# Georeference the extracted LTISD map classes using all four embedded controls.
source("scripts/prepare/packages.R")
setup_project_packages(c("sf", "terra", "jsonlite", "readr"))
raw <- "data/raw/elementary_boundaries/2026_27"
meta <- fromJSON(file.path(raw,"lake_travis_pdf_georeferencing.json"))
controls <- matrix(meta$gpts,ncol=2,byrow=TRUE)
world <- st_coordinates(st_transform(st_as_sf(data.frame(lon=controls[,2],lat=controls[,1]),
  coords=c("lon","lat"),crs=4269),meta$crs_wkt))
local <- matrix(meta$lpts,ncol=2,byrow=TRUE)
b <- meta$pdf_bbox
page <- cbind(1,b[1]+local[,1]*(b[3]-b[1]),b[2]+local[,2]*(b[4]-b[2]))
fit <- qr.solve(page,world)
error_m <- sqrt(rowSums((page %*% fit-world)^2))*1200/3937
stopifnot(max(error_m)<1, fit[2,1]>0,fit[3,2]>0)
pixel_m <- meta$pixel_points*sqrt(sum(fit[2,]^2))*1200/3937
stopifnot(pixel_m<3)
r <- rast(file.path(raw,"lake_travis_classes.tif"))
stopifnot(max(abs(as.vector(ext(r))-meta$raster_extent))<1e-6)
crs(r) <- "EPSG:2277" # Temporary PDF page coordinates; transformed below.
NAflag(r) <- 0
zones <- st_as_sf(as.polygons(r,aggregate=TRUE,values=TRUE,na.rm=TRUE))
names(zones)[1] <- "map_class"
stopifnot(setequal(zones$map_class,1:7))
st_geometry(zones) <- st_geometry(zones) * fit[2:3,] + as.numeric(fit[1,])
st_crs(zones) <- st_crs(meta$crs_wkt)
zones$name <- meta$names[zones$map_class]
zones <- st_make_valid(zones)
stopifnot(all(st_is_valid(zones)),!any(st_is_empty(zones)))
zones$boundary_method <- "Approximate polygons extracted from official georeferenced PDF"
zones$source_effective_year <- "2023-24"
zones$map_pixel_m <- pixel_m
zones$control_residual_m <- max(error_m)
# Independently located public campus points catch reversed axes/strips and
# incorrect legend mappings that small control residuals alone cannot detect.
campuses <- fromJSON(file.path(raw,"lake_travis_client.json"))$schools
campuses <- campuses[campuses$schoolId %in% 3:9,]
points <- st_as_sf(campuses,coords=c("lng","lat"),crs=4326)
hits <- st_intersects(st_transform(points,st_crs(zones)),zones)
expected <- sub(" ELEMENTARY$","",toupper(campuses$schoolName))
actual <- vapply(hits,function(i)paste(toupper(zones$name[i]),collapse="; "),character(1))
distances <- as.numeric(st_distance(st_transform(points,5070),
  st_transform(zones[match(expected,toupper(zones$name)),],5070),by_element=TRUE))
# Serene Hills' large black campus symbol crosses colors in the PDF. Its
# unclassifiable footprint is deliberately a hole, not an invented boundary.
symbol_hole <- expected=="SERENE HILLS" & lengths(hits)==0 & distances<100
stopifnot(nrow(campuses)==7,all(lengths(hits)<=1),sum(actual==expected)==6,
  all(actual==expected | symbol_hole))
st_write(st_transform(zones,4326),file.path(raw,"lake_travis_elementary.geojson"),
  delete_dsn=TRUE,quiet=TRUE)
dir.create("data/qaqc/elementary_access",recursive=TRUE,showWarnings=FALSE)
write_csv(data.frame(control=1:4,residual_m=error_m,pixel_m=pixel_m),
  "data/qaqc/elementary_access/lake_travis_georeferencing.csv")
write_csv(data.frame(school=campuses$schoolName,expected=expected,actual=actual,
  distance_to_expected_zone_m=distances,unassigned_cartographic_symbol=symbol_hole),
  "data/qaqc/elementary_access/lake_travis_campus_validation.csv")
print(st_drop_geometry(zones))
