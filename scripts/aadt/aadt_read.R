library(sf)         # Spatial data handling
library(dplyr)      # Data manipulation
library(ggplot2)
library(ggspatial)
library(osmdata)
#
#
#
aadt_geo<-st_read("./scripts/aadt/aadt_austin_only.gpkg")
atx<-st_read("./scripts/aadt/austin_city_limits.gpkg")
atx<-st_transform(atx,st_crs(aadt_geo))
hex<-st_read("./scripts/aadt/hex_8.gpkg")
hex<-st_transform(hex,st_crs(aadt_geo))


#
# histogram aadt for these streets
#
hist(aadt_geo$AADT_CUR)
high_vol<-subset(clipped_object,clipped_object$AADT_CUR>50000)

high_vol_buffer<-st_buffer(high_vol,300, 
                           endCapStyle = "FLAT")
plot(high_vol_buffer$geom,add=TRUE,col='blue')

plot(high_vol_buffer$geom[1:3])
plot(high_vol$geometry[1:3],add=TRUE,col='blue')
plot(atx$geom, add=TRUE)
plot(hex$geom,add=TRUE)
length(high_vol$OBJECTID)
#
# map Austin with its water
#
bbox <- getbb("Austin, Texas")
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geom, color = "orange", fill='yellow',alpha=0.5) + # Austin City Limits ;-)
  geom_sf(data =hex$geom, color = "blue", fill=NA) + # hex
  geom_sf(data =high_vol$geom, color = "red", fill=NA) + # hex
  theme_minimal()

