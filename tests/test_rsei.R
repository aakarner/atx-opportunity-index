# Spatial alignment, coverage, source missingness, and weighting contracts.
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
suppressPackageStartupMessages(library(sf))
for (p in list.files("R", pattern="\\.R$", full.names=TRUE)) source(p)
spec <- yaml::read_yaml("config/pipeline.yml")$rsei
rect <- function(x0,x1,y0,y1) st_polygon(list(matrix(c(x0,y0,x1,y0,x1,y1,x0,y1,x0,y0),ncol=2,byrow=TRUE)))
expect_error <- function(expr) stopifnot(inherits(try(force(expr), silent=TRUE), "try-error"))
# Known EPA grid origin and half-cell edges. Also check realistic Austin index.
austin <- st_as_sf(data.frame(lon=-97.7431,lat=30.2672),coords=c("lon","lat"),crs=4326)
xy <- st_coordinates(st_transform(austin,5070))
stopifnot(xy[1,1] < 0, xy[1,2] > 0)
template <- make_rsei_template(st_buffer(st_transform(austin,5070),1000),spec)
stopifnot(all(abs(as.numeric(st_area(template))-810^2) < 1e-5))
centers <- st_coordinates(st_centroid(st_geometry(template)))
stopifnot(max(abs(centers[,1]-template$X*810))<1e-7,
          max(abs(centers[,2]-template$Y*810))<1e-7)
# EPA Methodology Exhibit 5.1 gives the CONUS lower-left corner in meters.
sw <- st_as_sf(data.frame(x=-2365200,y=251910),coords=c("x","y"),crs=5070)
sw_cell <- make_rsei_template(sw,spec)
stopifnot(nrow(sw_cell)==1,sw_cell$X==-2920,sw_cell$Y==311,
          unname(st_bbox(sw_cell)["xmin"])==-2365605,
          unname(st_bbox(sw_cell)["ymin"])==251505)
# Independently specified two grid cells with 1:3 overlap weights.
cells <- st_sf(rsei_cell_id=c("14:0:0","14:1:0"),ToxConc=c(10,30),CTConc=c(5,15),
 NCTConc=c(8,24),rsei_record_present=c(TRUE,FALSE),
 rsei_source_status=c("Modeled source record","Absent from complete national file: no modeled contribution"),
 geometry=st_sfc(rect(-405,405,-405,405),rect(405,1215,-405,405),crs=5070))
areas <- st_sf(id=c("weighted","incomplete","outside"),geometry=st_sfc(
 rect(135,1215,-405,405),rect(0,2000,-405,405),rect(3000,3100,0,100),crs=5070))
cross <- rsei_overlap(areas,cells,"id")
agg <- aggregate_rsei(areas,cross,"id",spec)
stopifnot(agg$rsei_tox_conc[1]==25,agg$rsei_cancer_tox_conc[1]==12.5,
 abs(agg$rsei_record_area_share[1]-.25)<1e-10,all(is.na(agg$rsei_tox_conc[2:3])),
 agg$rsei_coverage_share[3]==0)
none <- aggregate_rsei(areas[3,],rsei_overlap(areas[3,],cells,"id"),"id",spec)
stopifnot(is.na(none$rsei_tox_conc),none$rsei_coverage_share==0)
pts <- st_as_sf(data.frame(site_id=c("left","right","edge","outside"),x=c(0,810,405,2000),y=0),coords=c("x","y"),crs=5070)
vals <- rsei_at_sites(pts,cells,spec)
stopifnot(identical(vals$rsei_cell_id,c("14:0:0","14:1:0","14:1:0","14:2:0")),
 is.na(vals$rsei_tox_conc[4]))
# Full gzip fixture: absent records are model-zero, present NA/negative are errors.
work <- tempfile("rsei-tests-");dir.create(work)
fixture <- data.frame(GridCode=14,X=template$X[1],Y=template$Y[1],NumFacs=1,
 NumReleases=1,NumChems=1,ToxConc=10,Score=20,Pop=2,CTConc=3,NCTConc=7)
p <- file.path(work,"fixture.csv.gz")
readr::write_csv(fixture,p)
validate_rsei_archive(p)
result <- extract_rsei_cells(p,template,spec)
stopifnot(sum(result$rsei_record_present)==1,all(result$ToxConc[-1]==0),
 all(is.na(result$Pop[-1])))
readr::write_csv(rbind(fixture,fixture),p)
expect_error(extract_rsei_cells(p,template,spec))
fixture$ToxConc <- NA_real_;readr::write_csv(fixture,p)
expect_error(extract_rsei_cells(p,template,spec))
fixture$ToxConc <- -1;readr::write_csv(fixture,p)
expect_error(extract_rsei_cells(p,template,spec))
writeBin(as.raw(c(1,2,3)),p);expect_error(validate_rsei_archive(p))
unlink(work,recursive=TRUE)
cat("RSEI checks passed: grid alignment, weighted means, partial coverage, boundaries, absent records, invalid data and archives.\n")
