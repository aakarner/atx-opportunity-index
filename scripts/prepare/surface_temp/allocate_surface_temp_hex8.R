library(rsi)
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
date<-{}
i<-1
for(f in file_names){
  st_raster <- rast(paste0('./raw_data/',f))
  if(global(st_raster, fun="notNA")[,1] > 0){
    #
    # convert from Kelvin (which is what you get with the rse package) to Celcius and then to Fahrenheit
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
    plot(projected_aoi$geometry,col=rgb(1, 1, 1, 0.25),add=TRUE)
    #
    # get the average temp and number of pixels in block groups
    #
    aggregated_polygons <- exact_extract(fahrenheit_temp[[1]], projected_aoi,append_cols='id',c('mean','count'))
    names(aggregated_polygons)<-c('id',paste('mean_',dt,sep=''),paste('pixels_',dt,sep=''))
  #  
    austin_hex_8<-merge(austin_hex_8,aggregated_polygons,all=TRUE)
    i<-i+1
  }
}
#
# now rank them
#
austin_hex_8$pctil_tot<-0
austin_hex_8$pctil_cnt<-0
austin_hex_8$pctil_avg<-0
austin_hex_8$avg_temp<-0
austin_hex_8$tot_pix<-0
for(dt in date){
  mn<-paste('mean_',dt,sep='')
  px<-paste('pixels_',dt,sep='')
  pctle<-paste('pctile_',dt,sep='')
  good_ones<-st_drop_geometry(subset(austin_hex_8,austin_hex_8[[px]] > 1,select=c('id',mn)))
  if(sum(good_ones[[mn]]) > 0){
    good_ones[[pctle]]<- ecdf(good_ones[[mn]])(good_ones[[mn]]) * 100
    austin_hex_8<-merge(austin_hex_8,subset(good_ones,select=c('id',pctle)),all=TRUE)
    i<-1
    for(i in 1:length(austin_hex_8$id)){
      if(!is.na(austin_hex_8[[pctle]][i])){
        austin_hex_8$pctil_tot[i] <- austin_hex_8$pctil_tot[i]+austin_hex_8[[pctle]][i]
        austin_hex_8$pctil_cnt[i] <- austin_hex_8$pctil_cnt[i]+1
        austin_hex_8$avg_temp[i] <- austin_hex_8$avg_temp[i]+austin_hex_8[[mn]][i]*austin_hex_8[[px]][i]
        austin_hex_8$tot_pix[i] <- austin_hex_8$tot_pix[i]+austin_hex_8[[px]][i]
      }
    }
  }
}
austin_hex_8$pctil_avg<-austin_hex_8$pctil_tot/austin_hex_8$pctil_cnt
austin_hex_8$tot_pctile<- ecdf(austin_hex_8$pctil_avg)(austin_hex_8$pctil_avg) * 100
austin_hex_8$avg_temp<-austin_hex_8$avg_temp/austin_hex_8$tot_pix
#
# save the geo package
#
st_write(austin_hex_8,dsn='./hex_8_temps.gpkg',delete_dsn=TRUE)

