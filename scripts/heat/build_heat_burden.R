.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/heat_burden.R')
spec<-yaml::read_yaml('config/burdens.yml')$heat
inputs<-read_heat_inputs(heat_input_files(spec),spec)
result<-build_heat_burden(inputs,targets::tar_read(h8_geometry),targets::tar_read(dam_inputs)$population,spec)
print(write_heat_burden(result))
