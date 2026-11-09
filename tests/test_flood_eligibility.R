if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
source('R/flood_eligibility.R')
suppressPackageStartupMessages(library(sf))
square<-function(x0,y0,x1,y1)st_polygon(list(rbind(c(x0,y0),c(x1,y0),c(x1,y1),c(x0,y1),c(x0,y0))))
areas<-st_sf(h3_id=c('full','partial','dry','tiny_dry_sliver'),geometry=st_sfc(
 square(0,0,1,1),square(.5,0,1.5,1),square(2,0,3,1),square(0,0,1.0000001,1),crs=5070))
flood<-st_sfc(square(0,0,1,1),crs=5070)
a<-flood_area_screen(areas,flood,'h3_id')$rows
stopifnot(identical(a$excluded,c(TRUE,FALSE,FALSE,FALSE)),
 identical(a$status,c('ineligible','address_check_required','not_excluded','address_check_required')),
 max(abs(a$overlap_share[1:3]-c(1,.5,0)))<1e-10,
 a$overlap_share[4]>.9999)
# Point status is independent of the containing cell's partial overlap.
pts<-st_as_sf(data.frame(site_id=c('inside','edge','outside','beyond_study'),x=c(.9,1,1.1,5),y=.5),coords=c('x','y'),crs=5070)
study<-st_sfc(square(-1,-1,4,4),crs=5070)
b<-flood_address_screen(pts,flood,study)
stopifnot(identical(b$flood_ineligible,c(TRUE,TRUE,FALSE,NA)))
# Holes remain dry; the hole boundary still intersects the flood polygon.
donut<-st_sfc(st_polygon(list(st_coordinates(square(0,0,4,4))[,1:2],
                            st_coordinates(square(1,1,2,2))[,1:2])),crs=5070)
hole_pts<-st_as_sf(data.frame(site_id=c('hole','hole_boundary','wet'),x=c(1.5,1,3),y=c(1.5,1.5,3)),coords=c('x','y'),crs=5070)
stopifnot(identical(flood_address_screen(hole_pts,donut)$flood_ineligible,c(FALSE,TRUE,TRUE)))
# Several adjoining polygons can jointly cover a full cell; dissolve before testing.
joined<-st_union(st_sfc(square(0,0,.5,1),square(.5,0,1,1),crs=5070))
stopifnot(flood_area_screen(areas[1,],joined,'h3_id')$rows$excluded)
profiles<-data.frame(site_id=c('wet','dry','missing'),benefit_score=c(100,0,100),overall_screen='Incomplete')
constraint<-data.frame(site_id=profiles$site_id,flood_ineligible=c(TRUE,FALSE,NA),
 flood_eligibility_status=c('ineligible','not_excluded','unknown'))
combined<-attach_flood_constraint(profiles,constraint)
stopifnot(grepl('Ineligible',combined$overall_screen[1]),
 combined$overall_screen[2]=='Incomplete',combined$overall_screen[3]=='Incomplete',
 identical(combined$benefit_score,profiles$benefit_score))
cat('Flood tests passed: full coverage, partial coverage, tiny dry slivers, actual points, boundaries, holes, unknown coverage, and dissolved polygons.\n')
