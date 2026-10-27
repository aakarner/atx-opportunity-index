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
# get tiger shape file for Austin tracts
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
water_area<-area_water(state='48',county = c(209,491,453),year=2024)
names(water_area)<-tolower(names(water_area))
#
# now cut out the water from the tracts
#
austin_tracts<-cut_polygons_rmapshaper(austin_tracts, water_area)
projected_aoi <- st_transform(austin_tracts, 32614) 
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
    aggregated_polygons <- exact_extract(fahrenheit_temp[[1]], projected_aoi,append_cols='GEOID',c('mean','count'))
    names(aggregated_polygons)<-c('GEOID',paste('mean_',dt,sep=''),paste('pixels_',dt,sep=''))
  #  
    austin_tracts<-merge(austin_tracts,aggregated_polygons,all=TRUE)
    i<-i+1
  }
}
#
# now rank them
#
austin_tracts$pctil_tot<-0
austin_tracts$pctil_cnt<-0
austin_tracts$pctil_avg<-0
austin_tracts$avg_temp<-0
austin_tracts$tot_pix<-0
for(dt in date){
  mn<-paste('mean_',dt,sep='')
  px<-paste('pixels_',dt,sep='')
  pctle<-paste('pctile_',dt,sep='')
  good_ones<-st_drop_geometry(subset(austin_tracts,austin_tracts[[px]] > 45,select=c('GEOID',mn)))
  good_ones[[pctle]]<- ecdf(good_ones[[mn]])(good_ones[[mn]]) * 100
  austin_tracts<-merge(austin_tracts,subset(good_ones,select=c('GEOID',pctle)),all=TRUE)
  i<-1
  for(i in 1:length(austin_tracts$GEOID)){
    if(!is.na(austin_tracts[[pctle]][i])){
      austin_tracts$pctil_tot[i] <- austin_tracts$pctil_tot[i]+austin_tracts[[pctle]][i]
      austin_tracts$pctil_cnt[i] <- austin_tracts$pctil_cnt[i]+1
      austin_tracts$avg_temp[i] <- austin_tracts$avg_temp[i]+austin_tracts[[mn]][i]*austin_tracts[[px]][i]
      austin_tracts$tot_pix[i] <- austin_tracts$tot_pix[i]+austin_tracts[[px]][i]
    }
  }
}
austin_tracts$pctil_avg<-austin_tracts$pctil_tot/austin_tracts$pctil_cnt
austin_tracts$tot_pctile<- ecdf(austin_tracts$pctil_avg)(austin_tracts$pctil_avg) * 100
austin_tracts$avg_temp<-austin_tracts$avg_temp/austin_tracts$tot_pix
#
# save the geo package
#
st_write(austin_tracts,dsn='./tract_temps.gpkg',delete_dsn=TRUE)

