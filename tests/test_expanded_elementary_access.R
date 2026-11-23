# Integration checks for added districts, future assignments, and map extraction.
source("scripts/prepare/packages.R")
setup_project_packages(c("sf", "dplyr", "readr", "jsonlite"))
source("R/pipeline_sites.R")
raw <- "data/raw/elementary_boundaries/2026_27"
z <- st_read("data/processed/school_indicators/elementary_growth_assignments_2026_27.gpkg",quiet=TRUE)
expected <- c("Austin ISD","Round Rock ISD","Pflugerville ISD","Del Valle ISD","Manor ISD",
              "Eanes ISD","Leander ISD","Hays CISD","Lake Travis ISD")
stopifnot(setequal(z$district_name,expected),all(st_is_valid(z)),!any(st_is_empty(z)),
  all(z$assignment_school_year=="2026-27"),all(z$growth_school_year=="2025-26"),
  !anyDuplicated(z$source_object_id),all(is.na(z$usable_growth)==(z$score_status!="Available")))
stopifnot(nrow(z[z$district_name=="Eanes ISD",])==5,
  nrow(z[z$district_name=="Leander ISD",])==29,
  nrow(z[z$district_name=="Hays CISD",])==17,
  nrow(z[z$district_name=="Lake Travis ISD",])==7,
  !any(grepl("VALLEY VIEW",z$campus_name[z$district_name=="Eanes ISD"])),
  !any(grepl("FAUBION",z$campus_name[z$district_name=="Leander ISD"])))

# The January 2027 move-in zone is explicitly Sunfield at this snapshot date.
h <- st_read(file.path(raw,"hays_elementary.geojson"),quiet=TRUE)
future <- h[h$future_move_in_exception,]
stopifnot(nrow(future)==1,future$name=="Sunfield")
point <- suppressWarnings(st_point_on_surface(st_transform(future,5070)))
point$site_id <- "future-move-in-overlay"
assignment <- school_at_sites(point,z)
stopifnot(assignment$campus_name=="SUNFIELD EL",assignment$status=="Available")

# Validate geographic orientation against independent official campus locations.
lt <- z[z$district_name=="Lake Travis ISD",]
campuses <- fromJSON(file.path(raw,"lake_travis_client.json"))$schools
campuses <- campuses[campuses$schoolId %in% 3:9,]
points <- st_as_sf(campuses,coords=c("lng","lat"),crs=4326)
hits <- st_intersects(points,lt)
expected_names <- sub(" ELEMENTARY$","",toupper(campuses$schoolName))
actual <- sub(" EL$","",vapply(hits,function(i)paste(lt$campus_name[i],collapse="; "),character(1)))
symbol_hole <- expected_names=="SERENE HILLS" & lengths(hits)==0
distance <- as.numeric(st_distance(st_transform(points,5070),st_transform(
  lt[match(paste0(expected_names," EL"),lt$campus_name),],5070),by_element=TRUE))
stopifnot(nrow(campuses)==7,all(lengths(hits)<=1),sum(expected_names==actual)==6,
  all(expected_names==actual | (symbol_hole & distance<100)),
  all(grepl("approximate",lt$boundary_year_basis)))
controls <- read_csv("data/qaqc/elementary_access/lake_travis_georeferencing.csv",show_col_types=FALSE)
stopifnot(nrow(controls)==4,max(controls$residual_m)<1,max(controls$pixel_m)<3)

crosswalk <- read_csv("data/qaqc/elementary_access/campus_crosswalk.csv",
  col_types=cols(campus_id="c",district_id="c"),show_col_types=FALSE)
stopifnot(all(substr(na.omit(crosswalk$campus_id),1,6) %in% unique(crosswalk$district_id)),
  all(!is.na(crosswalk$campus_id[crosswalk$district_name %in% expected[6:9]])))
cat("Expanded elementary sources passed: nine districts, closure handling, current Hays assignment, and Lake Travis geography.\n")
