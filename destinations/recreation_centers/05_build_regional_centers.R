# Build documented regional candidates; source JSON and geocoder replies stay cached.
library(sf)
library(dplyr)
library(jsonlite)
source('destinations/R/destination_paths.R')
b <- 'data/destinations/recreation_centers/interim/regional'
x <- fromJSON(file.path(b,'facility_inventory.json'))
g <- lapply(x$facility_id,function(id){
 a <- fromJSON(file.path(b,'geocoder',paste0(id,'.json')))$candidates
 stopifnot(nrow(a)>0)
 a <- a[1,]
 data.frame(facility_id=id,geocoder_longitude=a$location$x,geocoder_latitude=a$location$y,geocoder_score=a$score,geocoder_type=a$attributes$Addr_type,matched_address=a$address)
}) |> bind_rows()
x <- left_join(x,g,by='facility_id')
stopifnot(all(x$geocoder_score>=98),all(x$geocoder_type %in% c('PointAddress','Subaddress')))
x <- x |> mutate(
 longitude=coalesce(source_longitude,geocoder_longitude),latitude=coalesce(source_latitude,geocoder_latitude),
 coordinate_source=if_else(!is.na(source_latitude),'City of Austin source point','ArcGIS World Geocoder address point'),
 coordinate_note='Address/site location; entrance not verified',
 source_geocoder_distance_m=if_else(!is.na(source_latitude),111000*sqrt((source_latitude-geocoder_latitude)^2+(.86*(source_longitude-geocoder_longitude))^2),NA_real_),
 wheelchair_access='Not verified',fee_amount='See source; not systematically collected',
 coverage_note='Initial regional search; not a complete census of all facilities')
p <- st_as_sf(x,coords=c('longitude','latitude'),crs=4326,remove=FALSE)
counties <- st_read('data/destinations/healthcare/interim/cms_nppes/austin_metro_counties_2024.gpkg',quiet=TRUE) |> st_transform(4326) |> select(county=NAME)
p <- st_join(p,counties,join=st_within)
stopifnot(nrow(p)==43,!anyDuplicated(p$facility_id),all(!is.na(p$county)),all(st_is_valid(p)))
p <- add_h3_cells(p)
out <- 'data/destinations/recreation_centers/processed/regional_public_centers.gpkg'
# Only the requested combined output is replaced on rerun.
st_write(p,out,layer='regional_centers',delete_layer=TRUE,quiet=TRUE)
# Store methodology inside the GeoPackage, avoiding another review file.
con <- DBI::dbConnect(RSQLite::SQLite(),out)
DBI::dbWriteTable(con,'inventory_notes',data.frame(topic=c('Scope','Status','Coordinates','Austin correction','Coverage'),note=c('43 researched locations. One point per named facility; services in a shared center combined.','candidate is provisional. Review social services, partnerships, nonprofit and unconfirmed operation separately. Luling is excluded rental-only.','Austin source points retained. Other facilities geocoded from documented address; cached ArcGIS replies. Scores >=98; point/subaddress matches; county polygon check. Not entrance verified.','Senior source points are distinct and independently agree with address matches within 11m. Earlier duplicate-longitude concern was incorrect.','20 existing Austin recreation/community centers + 3 senior centers + 20 regional locations. Not an exhaustive five-county inventory; absent municipalities do not imply no facilities.')),overwrite=TRUE)
DBI::dbDisconnect(con)
print(st_drop_geometry(p) |> count(county,review_status))
cat('Saved',nrow(p),'points with',ncol(p)-1,'attributes to',out,'\n')
