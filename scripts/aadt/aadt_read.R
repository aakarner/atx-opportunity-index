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
#
#
aadt_geo<-st_read("./TxDOT_AADT.shp")
atx<-st_read("../austin_city_limits.gpkg")
atx<-st_transform(atx,st_crs(aadt_geo))


# Clip 'target_layer' using 'clip_polygon'
clipped_object <- st_intersection(aadt_geo, atx)

ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geometry, color = "orange", fill='yellow',alpha=0.5) + # Austin City Limits ;-)
  geom_sf(data =hex_list$geometry, color = "blue", fill=NA) + # hexes
  theme_minimal()

head(clipped_object)

plot(clipped_object$geometry)

hist(clipped_object$AADT_CUR)

hex<-st_read("../surface_temp/hex_8.gpkg")
hex<-st_transform(hex,st_crs(aadt_geo))
plot(hex$geom,add=TRUE)
high_vol<-subset(clipped_object,clipped_object$AADT_CUR>50000)
plot(high_vol$geometry)
high_vol_buffer<-st_buffer(high_vol,300, 
                           endCapStyle = "FLAT")
plot(high_vol_buffer$geom,add=TRUE,col='blue')

plot(high_vol_buffer$geom[1:3])
plot(high_vol$geometry[1:3],add=TRUE,col='blue')
plot(atx$geom, add=TRUE)
plot(hex$geom,add=TRUE)
length(high_vol$OBJECTID)
