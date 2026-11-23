# Rebuild the combined export from the existing prepared component analyses.
# Run the component pipeline first if source inputs or component policies change.
.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/combined_burdens.R')
spec<-yaml::read_yaml('config/burdens.yml')
read_component<-function(name)readRDS(file.path('output/components',name,'analysis.rds'))
heat<-read_component('heat-burden')
street<-read_component('street-safety')
industrial<-read_component('industrial-air-burden')
traffic<-read_component('near-road-traffic')
stopifnot(identical(heat$spec,spec$heat),identical(street$policy,spec$domain_components$street_safety_pedestrian_environment),
  identical(industrial$spec,spec$industrial_air),identical(traffic$spec,spec$traffic_exposure))
result<-build_combined_burdens(heat,street,industrial,traffic,spec)
benefits <- jsonlite::fromJSON('site/assets/combined-benefits.json')
tracts <- burden_tract_estimates(result, as.data.frame(benefits$tract_weights), as.data.frame(benefits$tracts))
print(write_combined_burdens(result, tracts))
