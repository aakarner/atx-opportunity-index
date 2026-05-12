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
#
# api codes 
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
  geom_sf(data = raw_data$sr_location_lat_long, color = "red", size = 3) + # Point layer
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
  geom_sf(data = water_data$sr_location_lat_long, color = "blue", size = 3) + # Point layer
  theme_minimal()
