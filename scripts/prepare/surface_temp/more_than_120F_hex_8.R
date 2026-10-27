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
# get tiger shape file for Austin hex_8
#
hex_8<-st_read(dsn='hex_8.gpkg')
names(hex_8)
austin<-st_read(dsn='../austin_city_limits.gpkg')

# Ensure both layers share the exact same Coordinate Reference System (CRS)
austin <- st_transform(austin, st_crs(hex_8))

# Subset hex_8 to keep only polygons that overlap austin
austin_hex_8 <- hex_8[st_intersects(hex_8, austin, sparse = FALSE), ]
#
# get water area 
#
water_area<-area_water(state='48',county = c(209,491,453),year=2024)
names(water_area)<-tolower(names(water_area))
#
# now cut out the water from the hex_8
#
austin_hex_8<-cut_polygons_rmapshaper(austin_hex_8, water_area)
projected_aoi <- st_transform(austin_hex_8, 32614) 
plot(projected_aoi$geometry)
#
# read each file that you downloaded in get_landsat_surface_temp.r for each date
#
file_names<-list.files(path = "./raw_data")
#
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
    
    plot(austin_hex_8$geometry,col=rgb(1, 1, 1, 0.25),add=TRUE )
    #
    # get the average temp and number of pixels in block groups
    #
    aggregated_polygons <- exact_extract(hot_pixels, projected_aoi,append_cols='id',c('count'))
    names(aggregated_polygons)<-c('id',paste('hot_pixels_',dt,sep=''))
    total_polygons<-exact_extract(st_raster, projected_aoi,append_cols='id',c('count'))
    names(total_polygons)<-c('id',paste('tot_pixels_',dt,sep=''))
    #  
    austin_hex_8<-merge(austin_hex_8,aggregated_polygons,all=TRUE)
    austin_hex_8<-merge(austin_hex_8,total_polygons,all=TRUE)
    names(austin_hex_8)
    i<-i+1
  }


}
names(austin_hex_8)
dt<-date[1]
austin_hex_8$hot_pixel_count<-0
austin_hex_8$tot_pixel_count<-0
for(dt in date){
  this<-paste('hot_pixels_',dt,sep='')
  that<-paste('tot_pixels_',dt,sep='')
  austin_hex_8$hot_pixel_count<-austin_hex_8$hot_pixel_count+austin_hex_8[[this]]
  austin_hex_8$tot_pixel_count<-austin_hex_8$tot_pixel_count+austin_hex_8[[that]]
}
austin_hex_8$pct_hot<-100*(austin_hex_8$hot_pixel_count/austin_hex_8$tot_pixel_count)                    
hist(austin_hex_8$hot_pixel_count)
hist(austin_hex_8$pct_hot)
#
# save the geo package
#
st_write(austin_hex_8,dsn='./hex_8_hot_pixels.gpkg',delete_dsn=TRUE)
