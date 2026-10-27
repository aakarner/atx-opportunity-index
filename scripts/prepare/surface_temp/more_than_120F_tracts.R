library(sf)
library(tigris)
library(units)
library(terra)
library(exactextractr)
#
# clear all memory before starting
#
rm(list=ls())
#
# load some utilities
#
source("./overlaps_and_splits.R")
#
# get tiger shape file for Austin block groups
#
tracts<-tracts(state='48',county = c(209,491,453),year=2024)
names(tracts)
austin<-st_read(dsn='../austin_city_limits.gpkg')

# Ensure both layers share the exact same Coordinate Reference System (CRS)
austin <- st_transform(austin, st_crs(tracts))

# Subset tracts to keep only polygons that overlap austin
austin_tracts <- tracts[st_intersects(tracts, austin, sparse = FALSE), ]
#
# get water area 
#
water<-st_read(dsn='../water.gpkg')
#
# now cut out the water from the block groups
#
austin_tracts<-cut_polygons_rmapshaper(austin_tracts, water)
projected_aoi <- st_transform(austin_tracts, 32614) 
#
# now get the temps
#
file_names<-list.files(path = "./raw_data")
f<-file_names[10]
date<-{}
i<-1
for(f in file_names){
  st_raster <- rast(paste0('./raw_data/',f))
  if(global(st_raster, fun="notNA")[,1] > 0){
    #
    # convert from Kelvin (which is what you get with the rsi package) to Celsius and then to Fahrenheit
    #
    fahrenheit_temp <- ((st_raster) - 273.15)*9/5 + 32
    #
    # read in the date from the file name.
    #
    yr<-substring(f,9,12)
    mnth<-substring(f,14,15)
    dy<-substring(f,17,18)
    date[i]<-paste(mnth,"_",dy,"_",yr,sep='')
    dt<-date[i]
    #
    # plot the temp for each date 
    #
    plot(fahrenheit_temp, main = paste("Landsat Surface Temperature (°F)",dt))
    hot_grid <- (fahrenheit_temp >= 120)
    hot_pixels<-mask(fahrenheit_temp, hot_grid, maskvalues = FALSE)
    
    plot(hot_pixels, main = paste("Landsat Surface Temperature >= 120°F",dt))
    plot(hot_grid, main = paste("Landsat Surface Temperature >= 120°F",dt))
    
    plot(austin_tracts$geometry,col=rgb(1, 1, 1, 0.25),add=TRUE )
    #
    # get the average temp and number of pixels in block groups
    #
    aggregated_polygons <- exact_extract(hot_pixels, projected_aoi,append_cols='GEOID',c('count'))
    names(aggregated_polygons)<-c('GEOID',paste('hot_pixels_',dt,sep=''))
    total_polygons<-exact_extract(st_raster, projected_aoi,append_cols='GEOID',c('count'))
    names(total_polygons)<-c('GEOID',paste('tot_pixels_',dt,sep=''))
    #  
    austin_tracts<-merge(austin_tracts,aggregated_polygons,all=TRUE)
    austin_tracts<-merge(austin_tracts,total_polygons,all=TRUE)
    names(austin_tracts)
    i<-i+1
  }
}
names(austin_tracts)
dt<-date[10]
austin_tracts$hot_pixel_count<-0
austin_tracts$tot_pixel_count<-0
for(dt in date){
  this<-paste('hot_pixels_',dt,sep='')
  that<-paste('tot_pixels_',dt,sep='')
  austin_tracts$hot_pixel_count<-austin_tracts$hot_pixel_count+austin_tracts[[this]]
  austin_tracts$tot_pixel_count<-austin_tracts$tot_pixel_count+austin_tracts[[that]]
}
austin_tracts$pct_hot<-100*(austin_tracts$hot_pixel_count/austin_tracts$tot_pixel_count)                    
hist(austin_tracts$hot_pixel_count)
hist(austin_tracts$pct_hot)
#
# save the geo package
#
st_write(austin_tracts,dsn='./tract_hot_pixels.gpkg',delete_dsn=TRUE)
