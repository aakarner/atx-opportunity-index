source("setup_packages.R")
setup_project_packages(c(
  "tidyverse", "httr", "jsonlite", "socratadata", "ggspatial",
  "osmdata", "sf", "tidycensus", "tigris", "rmapshaper"
))
#
# source some useful functions
#
source("./accessibility/02-data-processing/utilities.R")
# Optional Socrata credentials should be supplied through the
# soc_api_key_id and soc_api_key_secret environment variables. Public queries
# do not require credentials.
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
blkgrps<-cut_polygons_rmapshaper(blkgrps, water)
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

choropleth(water_points_in_blkgrps,water_points_in_blkgrps$n_points,"Number of 311 flood/water calls",
              "Number of 311 flood/water calls",
              "Number of calls per Census Block Group",
              c(1, 4, 8, 12, 20, 40, 100))
