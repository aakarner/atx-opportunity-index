#
# SOP libraries
#
library(readr)
library(dplyr)
library(httr)
library(jsonlite)
#
#install soda library
#
library(socratadata)
#
# spatial stuff to make some maps
#
library(ggspatial)
library(osmdata)
library(sf)
library(ggplot2)
library(tidycensus)
library(tigris)
#
# add this function to cut out water from geos
#

cut_polygons_rmapshaper <- function(polygons, cutters) {
  require("rmapshaper")
  
  # 1. Align Coordinate Reference Systems (CRS)
  if (st_crs(polygons) != st_crs(cutters)) {
    cutters <- st_transform(cutters, st_crs(polygons))
  }
  
  # 2. Fix invalid geometries 
  polygons <- st_make_valid(polygons)
  cutters <- st_make_valid(cutters)
  
  # 3. Combine the water polygons into a single mask [st_union is a big bottleneck!]
  cutters_combined <- ms_dissolve(cutters)
  
  # 4. Use ms_erase to punch out the water
  result <- ms_erase(target = polygons, erase = cutters_combined)
  
  # 5. Fix invalid geometries that result from the cutting
  result <- st_make_valid(result)
  
  return(result)
}

#
# api codes don't really need unless we want some of the synthesized data.
#
api_secret='4gsr7tsc10qttzlduvoetlfhjofyetmev44w76rij1yhdp1wbn'
app_token='dy6ckwt4mxigot5hii89m60s4'
#
# base url for Austin's 311 data
#
base_url <- "https://data.austintexas.gov/api/v3/views/xwdj-i9he"
#
# build the query for get one year (2025)
#
query <- soc_query(
  select = "sr_number,sr_type_desc,sr_created_date,sr_location_lat_long,sr_location_lat,sr_location_long",
  where ='sr_created_date >= "2025-01-01T00:00:00.000" and sr_created_date < "2026-01-01T00:00:00.000"'
)
#
# get all the data
#
raw_data<-soc_read(
  base_url,
  query = query,
)
#
# some of these have really bad lat/long
#
raw_data<-subset(raw_data,raw_data$sr_location_long> -100)
#
# map all the locations
#
bbox <- getbb("Austin, Texas")
# 
# now plot map
#
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm") + # OSM background
  geom_sf(data = raw_data$sr_location_lat_long, color = "red", size = 1) + # Point layer
  theme_minimal()
#
# get the unique descriptions, filter on ones that have water or flood in the description
#
desc<-unique(raw_data$sr_type_desc)
desc<-subset(desc,grepl('flood',desc,ignore.case = TRUE) | grepl('water',desc,ignore.case = TRUE))
water_data<-subset(raw_data,raw_data$sr_type_desc %in% desc)
# 
# now plot map
#
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  annotation_map_tile(type = "osm") + # OSM background
  geom_sf(data = water_data$sr_location_lat_long, color = "blue", size = 1) + # Point layer
  theme_minimal()
#
# now get block groups
#
# The city of Austin, Texas (48), is primarily located in 
#   Travis County (453), while extending into 
#   Williamson County (491) to the north and 
#   Hays County (209) to the south.
#
blkgrps<-block_groups(state='48',county=c('453','491','209'),year=2024)
water<-area_water(state='48',county=c('453','491','209'),year=2024)
blkgrps<-cut_polygons_rmapshaper(atx_blkgrps, atx_water)
tx_places<-places(state='48',year=2024)
atx<-subset(tx_places,tx_places$NAME=='Austin')
atx_blkgrps<-blkgrps[st_intersects(blkgrps, atx, sparse = FALSE), ]
#
# map this just to make sure
#
ggplot() +
  coord_sf(crs = 2847,xlim = bbox[1,], ylim = bbox[2,]) +
  geom_sf(data = atx_blkgrps$geometry, color ="grey",alpha=0.5) + 
  geom_sf(data = atx$geometry, color ="lightblue",fill='lightyellow',alpha=0.5) + 
  geom_sf(data = water_data$sr_location_lat_long, color = "blue", size = 1) +
  theme_minimal()
#
# now count the "water" 311 calls in each block group
#
water_data <- st_transform(water_data, crs = st_crs(atx_blkgrps))
water_points_in_blkgrps <- atx_blkgrps %>%
  st_join(water_data) %>%
  group_by(GEOID) %>% 
  summarise(n_points = n())

hist(water_points_in_blkgrps$n_points)

p <- ggplot(water_points_in_blkgrps) +
  geom_sf(aes(fill = n_points), linewidth = 0, alpha = 0.9) +
  theme_void() +
  scale_fill_viridis_c(
    trans = "log", breaks = c(1, 4, 8, 12, 20, 40),
    name = "Number of 311 flood/water calls",
    guide = guide_legend(
      keyheight = unit(3, units = "mm"),
      keywidth = unit(12, units = "mm"),
      label.position = "bottom",
      title.position = "top",
      nrow = 1
    )
  ) +
  labs(
    title = "Number of 311 flood/water calls",
    subtitle = "Number of calls per Census Block Group",
    caption = ""
  ) +
  theme(
    text = element_text(color = "#22211d"),
    plot.background = element_rect(fill = "#f5f5f2", color = NA),
    panel.background = element_rect(fill = "#f5f5f2", color = NA),
    legend.background = element_rect(fill = "#f5f5f2", color = NA),
    plot.title = element_text(
      size = 20, hjust = 0.01, color = "#4e4d47",
      margin = margin(
        b = -0.1, t = 0.4, l = 2,
        unit = "cm"
      )
    ),
    plot.subtitle = element_text(
      size = 15, hjust = 0.01,
      color = "#4e4d47",
      margin = margin(
        b = -0.1, t = 0.43, l = 2,
        unit = "cm"
      )
    ),
    plot.caption = element_text(
      size = 10,
      color = "#4e4d47",
      margin = margin(
        b = 0.3, r = -99, t = 0.3,
        unit = "cm"
      )
    ),
    legend.position = c(0.7, 0.09)
  )

p



