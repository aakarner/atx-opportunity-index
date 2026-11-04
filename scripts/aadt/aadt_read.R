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
#
# map Austin with the high volume streets
#
bbox <- getbb("Austin, Texas")
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geom, color = "orange", fill='yellow',alpha=0.5) + # Austin City Limits ;-)
  geom_sf(data =hex$geom, color = "blue", fill=NA) + # hex
  geom_sf(data =high_vol$geom, color = "red", fill=NA) + # hex
  theme_minimal()
#
# allocate the sum of the AADT to the hexagons from the high volume buffers 
#
interpolated_result <- st_interpolate_aw(
  x = high_vol_buffer['AADT_CUR'], 
  to = hex, 
  extensive = TRUE
)
plot(interpolated_result)
hist(interpolated_result$AADT_CUR)
min(interpolated_result$AADT_CUR)
max(interpolated_result$AADT_CUR)
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geom, color = "orange", fill='yellow',alpha=0.5) + # Austin City Limits ;-)
  geom_sf(data =hex$geom, color = "black", fill=NA) + # hex
  geom_sf(data =interpolated_result$geom, color =NA, fill='red') + # hex
  theme_minimal()
#
# create a choropleth map
#
ggplot() +
  geom_sf(data = interpolated_result, aes(fill = AADT_CUR), color = "white", size = 0.2) +
  scale_fill_viridis_c(option = "plasma", name = "Sum AADT") +
  theme_minimal() +
  labs(
    title = "Area Weighted Wum of AADT ",
    subtitle = "Sum of AADT from Hight Volume Streets",
    caption = "Source: TXDOT"
  ) +
  theme(
    legend.position = "bottom",
    panel.grid = element_blank()
  )



