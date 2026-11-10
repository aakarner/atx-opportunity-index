score_industrial_air <- function(value,spec,coverage=rep(1,length(value))) {
  full<-spec$full_burden_concentration;high<-spec$high_burden_concentration
  lower<-spec$review_band_lower_concentration
  stopifnot(length(coverage)==length(value),is.finite(full),is.finite(high),is.finite(lower),
    full>0,high>lower,high<=full,lower>=0)
  if(any(value<0,na.rm=TRUE))stop('Industrial concentration cannot be negative')
  valid<-is.finite(value)&is.finite(coverage)&abs(coverage-1)<=1e-6
  v<-ifelse(valid,value,NA_real_)
  is_high<-v>=high;review<-v>=lower & v<high
  data.frame(industrial_air_score=pmin(100,100*v/full),industrial_air_high=is_high,
    industrial_air_review_band=review,industrial_air_review_or_high=v>=lower,
    industrial_air_status=ifelse(!valid,'Unavailable',ifelse(is_high,'High burden',
      ifelse(review,'Secondary review','Below review band'))),
    industrial_air_score_capped=ifelse(valid,v>=full,NA),scoring_version=spec$version)
}
build_industrial_air_burden <- function(hexes,population,source_files,spec) {
  stopifnot(!anyDuplicated(hexes$h3_id),!anyDuplicated(population$h3_id),setequal(hexes$h3_id,population$h3_id),
    all(hexes$rsei_year==spec$reporting_year),all(hexes$rsei_version==spec$source_version))
  fields<-c('h3_id','rsei_tox_conc','rsei_coverage_share','rsei_record_area_share','rsei_status','rsei_year','rsei_version')
  x<-sf::st_drop_geometry(hexes)[,fields]
  for(n in c('total_population','children_under_18'))x[[n]]<-population[[n]][match(x$h3_id,population$h3_id)]
  x<-cbind(x,score_industrial_air(x$rsei_tox_conc,spec,x$rsei_coverage_share))
  list(scores=x,geometry=hexes[,c('h3_id','geometry')],spec=spec,
    source_manifest=jsonlite::read_json(source_files[grepl('json$',source_files)]),
    input_sha256=digest::digest(hexes[,fields],algo='sha256'))
}
write_industrial_air_burden <- function(result,directory='output/components/industrial-air-burden') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  write.csv(result$scores,file.path(directory,'scores.csv'),row.names=FALSE,na='')
  g<-merge(sf::st_as_sf(result$geometry),result$scores,by='h3_id',all.x=TRUE,sort=FALSE)
  sf::st_write(g,file.path(directory,'industrial_air_burden.gpkg'),layer='hex_scores',delete_layer=TRUE,quiet=TRUE)
  jsonlite::write_json(list(policy=result$spec,source_manifest=result$source_manifest,input_sha256=result$input_sha256,
    qualification='Local industrial-air screening measure, not health risk or total pollution. Secondary review is distinct from high burden.'),
    file.path(directory,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,na='null',digits=17)
  saveRDS(result,file.path(directory,'analysis.rds'))
  file.path(directory,c('scores.csv','industrial_air_burden.gpkg','metadata.json','analysis.rds'))
}
