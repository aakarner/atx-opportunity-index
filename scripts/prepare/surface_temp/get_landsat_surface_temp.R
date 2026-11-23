library(rsi)
library(sf)
library(tigris)
#library(terra)
library(exactextractr)
#
# clear all memory before starting
#
rm(list=ls())
#
# get tiger shape file for Austin tracts
#
tracts<-tracts(state='48',county = c(209,491,453),year=2024)
names(tracts)
austin<-st_read(dsn='../austin_city_limits.gpkg')
#
# Ensure both layers share the exact same Coordinate Reference System (CRS)
#
austin <- st_transform(austin, st_crs(tracts))
#
# Subset tracts to keep only tracts that overlap Austin
#
austin_tracts <- tracts[st_intersects(tracts, austin, sparse = FALSE), ]
#
# Project tracts to UTM for central Texas
#
projected_aoi <- st_transform(austin_tracts, 32614) 
#
# now get the temps
#
# Download and automatically get Landsat imagery for the area of interest that is the 
#  census tracts that intersect Austin, for May through September 2026. This will create a raster
#  for each date that the Landsat flys over Austin.
#
landsat_data <- get_landsat_imagery(
  aoi = projected_aoi,
  start_date = "2026-05-01",
  end_date = "2026-09-30",
  asset_names = landsat_band_mapping$planetary_computer_v1['lwir11'],
  mask_band = "qa_pixel", mask_function = landsat_mask_function, # mask off clouds
  output_filename = paste0('./raw_data/landsat',".tif"),
  composite_function = NULL        # CRITICAL: stops rsi from collapsing days together
)
