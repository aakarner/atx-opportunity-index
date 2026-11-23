score_traffic_burden <- function(share,spec) {
  stopifnot(is.finite(spec$high_burden_share),is.finite(spec$sensitivity_high_burden_share),
    spec$high_burden_share<=1,spec$sensitivity_high_burden_share>=0,
    spec$sensitivity_high_burden_share<spec$high_burden_share)
  if(any(!is.na(share)&(!is.finite(share)|share<0|share>1)))stop('Traffic overlap share outside [0,1]')
  high<-share>=spec$high_burden_share;sensitivity<-share>=spec$sensitivity_high_burden_share
  data.frame(traffic_score=100*share,traffic_high=high,traffic_sensitivity_high=sensitivity,
    traffic_status=ifelse(is.na(share),'Unavailable',ifelse(high,'High burden','Below high-burden flag')),
    traffic_flag_comparison=ifelse(is.na(share),'Unavailable',ifelse(high,'Primary high-burden flag',
      ifelse(sensitivity,'Sensitivity flag only','Below both flags'))),scoring_version=spec$version)
}
build_traffic_burden <- function(traffic,hexes,population,metadata,spec) {
  stopifnot(!anyDuplicated(traffic$h3_id),!anyDuplicated(hexes$h3_id),!anyDuplicated(population$h3_id),
    setequal(traffic$h3_id,hexes$h3_id),setequal(traffic$h3_id,population$h3_id),
    metadata$buffer_m==spec$buffer_m,
    metadata$threshold==paste('AADT_CUR >',spec$road_aadt_greater_than),
    metadata$overlap_denominator=='Full H3 cell area',metadata$nearest_road_extent_check_passed)
  x<-as.data.frame(traffic)
  x$traffic_center_distance_m<-x$traffic_distance_ft*.3048
  for(n in c('total_population','children_under_18'))x[[n]]<-population[[n]][match(x$h3_id,population$h3_id)]
  x<-cbind(x,score_traffic_burden(x$traffic_buffer_share,spec))
  list(scores=x,geometry=hexes,spec=spec,source_metadata=metadata,
    input_sha256=digest::digest(traffic,algo='sha256'),geometry_sha256=digest::digest(hexes,algo='sha256'))
}
write_traffic_burden <- function(result,directory='output/components/near-road-traffic') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  write.csv(result$scores,file.path(directory,'scores.csv'),row.names=FALSE,na='')
  g<-merge(sf::st_as_sf(result$geometry),result$scores,by='h3_id',all.x=TRUE,sort=FALSE)
  sf::st_write(g,file.path(directory,'traffic_burden.gpkg'),layer='hex_scores',delete_layer=TRUE,quiet=TRUE)
  jsonlite::write_json(list(policy=result$spec,source_metadata=result$source_metadata,
    input_sha256=result$input_sha256,geometry_sha256=result$geometry_sha256,
    qualification='Traffic proximity proxy, not pollutant concentration or personal exposure. Distance is from the hex center, not a development address. Zero overlap is not clean air.'),
    file.path(directory,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,na='null',digits=17)
  saveRDS(result,file.path(directory,'analysis.rds'))
  file.path(directory,c('scores.csv','traffic_burden.gpkg','metadata.json','analysis.rds'))
}
