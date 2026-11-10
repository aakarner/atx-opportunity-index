.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/pedestrian_gaps.R');source('R/street_safety.R')
# Standalone route reuses the validated inventory analysis; targets can rebuild from source.
pedestrian<-readRDS('output/components/pedestrian-gaps/analysis.rds')
policy<-yaml::read_yaml('config/burdens.yml')$domain_components$street_safety_pedestrian_environment
result<-build_street_safety(pedestrian,targets::tar_read(pedestrian_inventory),
  targets::tar_read(crash_points),targets::tar_read(dam_inputs)$population,policy)
print(write_street_safety(result))
