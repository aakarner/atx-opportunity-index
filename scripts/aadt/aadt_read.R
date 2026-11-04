library(sf)         # Spatial data handling
library(dplyr)      # Data manipulation
library(ggplot2)
library(ggspatial)
library(osmdata)
library(units)
#
#
#
aadt_geo<-st_read("./scripts/aadt/aadt_austin_only.gpkg")
atx<-st_read("./scripts/aadt/austin_city_limits.gpkg")
atx<-st_transform(atx,st_crs(aadt_geo))
hex<-st_read("./scripts/aadt/hex_8_full.gpkg")
hex<-st_transform(hex,st_crs(aadt_geo))
hex$acres<-NULL
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
names(high_vol_buffer)
interpolated_result <- st_interpolate_aw(
  x = high_vol_buffer['AADT_CUR'], 
  to = hex, 
  extensive = TRUE
)
plot(interpolated_result)
hist(interpolated_result$AADT_CUR)
min(interpolated_result$AADT_CUR)
max(interpolated_result$AADT_CUR)
#
# create a choropleth map
#
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geom, color = "orange", fill='yellow',alpha=0.5) +
  geom_sf(data = interpolated_result, aes(fill = AADT_CUR), color = NA, size = 0.2) +
  scale_fill_viridis_c(option = "plasma", name = "Sum AADT") +
  theme_minimal() +
  labs(
    title = "Area Weighted Sum of AADT ",
    subtitle = "Sum of AADT from Hight Volume Streets",
    caption = "Source: TXDOT"
  ) +
  theme(
    legend.position = "bottom",
    panel.grid = element_blank()
  )
st_write(interpolated_result,'./scripts/aadt/aadt_sum_hex8.gpkg',delete_dsn=TRUE)
all_high_vol<-st_union(high_vol)

hex$distance_to_high_vol_ft <- as.numeric(st_distance(st_centroid(hex), all_high_vol))*3.28084

ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm",alpha=0.5) + # OSM background
  geom_sf(data =atx$geom, color = "orange", fill='yellow',alpha=0.5) +
  geom_sf(data = hex, aes(fill = distance_to_high_vol_ft), color = NA, size = 0.2) +
  scale_fill_viridis_c(option = "plasma", name = "Sum AADT") +
  theme_minimal() +
  labs(
    title = "Area Weighted Sum of AADT ",
    subtitle = "Sum of AADT from Hight Volume Streets",
    caption = "Source: TXDOT"
  ) +
  theme(
    legend.position = "bottom",
    panel.grid = element_blank()
  )
#
# now get the fraction covered by the buffer
#  first merge them into one polygon
#
all_high_vol_buff<-st_as_sf(st_union(high_vol_buffer))

# 1. Calculate the initial area of the target polygons (Layer A)
hex <- hex %>%
  mutate(total_area = st_area(.))

# 2. Intersect the two layers to find overlapping geometries
intersections <- st_intersection(hex, all_high_vol_buff) %>%
  mutate(intersect_area = st_area(.)) %>%
  st_drop_geometry() # Drop geometry to speed up the tabular join

# 3. Aggregate intersection areas (in case Layer B has multiple overlapping polygons)
overlap_summary <- intersections %>%
  group_by(id) %>% # Replace id with your unique identifier for Layer A
  summarize(overlap_area = sum(intersect_area), .groups = "drop")

# 4. Join back to the original Layer A and calculate fractions
hex <- hex %>%
  left_join(overlap_summary, by = "id") %>%
  mutate(
    # Replace NA values (no overlap) with 0
    overlap_area = ifelse(is.na(overlap_area), 0, overlap_area),
    # Calculate the fraction (units will cancel out automatically)
    fraction_overlap = as.numeric(overlap_area / total_area)
  )
hex$total_area<-hex$overlap_area<-NULL
st_write(hex,'./scripts/aadt/aadt_metrics_hex8.gpkg',delete_dsn=TRUE)
