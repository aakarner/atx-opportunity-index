# Run after fetching the inventory; consume the existing validated H8/city targets.
.libPaths(c('.R-library',.libPaths()))
source('R/pedestrian_gaps.R')
spec<-yaml::read_yaml('config/burdens.yml')$pedestrian
files<-pedestrian_inventory_files(spec)
cat('Reading and verifying pedestrian inventory\n')
source<-read_pedestrian_inventory(files,spec)
cat('Building pedestrian measure\n')
result<-build_pedestrian_measure(source,targets::tar_read(h8_geometry),targets::tar_read(city_boundary),spec)
print(write_pedestrian_measure(result))
