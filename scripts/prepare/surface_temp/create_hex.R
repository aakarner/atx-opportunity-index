library(h3r)         # H3 spatial indexing
library(sf)         # Spatial data handling
library(leaflet)    # Interactive mapping
library(dplyr)      # Data manipulation
library(tidycensus)
library(ggplot2)
library(units)
library(tigris)
library(osmdata)
library(rosm)
library(ggspatial)
#
# now get Austin
#
tx_places<-places(state='48',year=2024)
atx<-subset(tx_places,tx_places$NAME=='Austin')
#
# map Austin with its water
#
bbox <- getbb("Austin, Texas")
#
# now make hexigons centered on Austin's center
#
# 2. Get the H3 index for the center point
center_cell <- latLngToCell(lat = (bbox[2,1]+bbox[2,2])/2, 
                            lng = (bbox[1,1]+bbox[1,2])/2, 
                            res = '8')

# 3. Generate a matrix/grid of hexagons around the center (k=2 means 2 rings out)
# gridDisk returns a list of H3 cell IDs
hex_ids <- gridDisk(cell = center_cell, k = 30)

# Unlist to get a clean character vector of hexagon IDs
hex_ids <- unlist(hex_ids)

# Convert the cell IDs into spatial polygon boundaries
hex_boundaries <- cellToBoundary(hex_ids)

i<-1
# Since cellToBoundary outputs a list of coordinates, we manually format it to sf objects
hex_list<-st_sf(id = integer(),
                name = character(),
                acres = numeric(),
                geometry=st_sfc(),
                crs = 4326)
for(i in seq_along(hex_ids)){
  coords <- as.data.frame((hex_boundaries[[i]]))
  # Close the loop by repeating the first vertex at the end
  coords <- rbind(coords,coords[1, ])
  coords<-as.data.frame(coords)
  polygon_sf <- coords %>%
    st_as_sf(coords = c("lng", "lat"), crs = 4326) %>% # WGS84 projection
    summarise(geometry = st_combine(geometry)) %>%
    st_cast("POLYGON")
  hex_new<-st_sf(id = i,
                 name = hex_ids[[i]],
                 acres=0,
                 geometry=st_as_sfc(polygon_sf),
                 crs = 4326)
  hex_list<-rbind(hex_list,hex_new)
}
water<-area_water(state='48',county=c('453','491','209'),year=2024)
hex_list<-st_transform(hex_list,st_crs(water))
hex_list<-cut_polygons_rmapshaper(hex_list, water)
hex_list<-hex_list[st_intersects(hex_list, atx, sparse = FALSE), ]
# 
# now plot map
#
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geometry, color = "orange", fill='yellow',alpha=0.5) + # Austin City Limits ;-)
  geom_sf(data =hex_list$geometry, color = "blue", fill=NA) + # hexes
  theme_minimal()
#
# save the geo package
#
st_write(hex_list,dsn='./hex_8.gpkg',delete_dsn=TRUE)
