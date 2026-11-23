# Validated extraction is a pinned prepared-data boundary, like the crash inputs.
heat_input_files <- function(spec) {
  paths<-vapply(spec$inputs,`[[`,character(1),'path')
  if(!all(file.exists(paths)))stop('Missing heat input. Run scripts/heat/validate_heat.R after acquiring the pinned snapshot.')
  unname(paths)
}
heat_percentile <- function(x) {
  out<-rep(NA_real_,length(x));ok<-is.finite(x)
  if(any(ok))out[ok]<-100*rank(x[ok],ties.method='max')/sum(ok)
  out
}
score_heat_burden <- function(x,spec) {
  stopifnot(spec$high_burden_percentile>=0,spec$high_burden_percentile<=100,
    spec$thin_coverage_below_dates>=1)
  if(any(!is.na(x$quality_relative_rank)&(!is.finite(x$quality_relative_rank)|x$quality_relative_rank<0|x$quality_relative_rank>100))||
     any(!is.na(x$dates_half_land)&(!is.finite(x$dates_half_land)|x$dates_half_land<0|x$dates_half_land!=floor(x$dates_half_land))))
    stop('Invalid heat rank or eligible-date count')
  ok<-is.finite(x$quality_relative_rank)&!is.na(x$dates_half_land)&x$dates_half_land>0
  x$heat_score<-ifelse(ok,x$quality_relative_rank,NA_real_)
  x$heat_high<-ifelse(ok,x$heat_score>=spec$high_burden_percentile,NA)
  x$heat_thin_coverage<-ifelse(ok,x$dates_half_land<spec$thin_coverage_below_dates,NA)
  x$heat_status<-ifelse(!ok,'Unavailable',ifelse(x$heat_thin_coverage,'Scored; limited observations','Scored'))
  x$heat_flag_status<-ifelse(!ok,'Unavailable',ifelse(x$heat_high,'High relative heat','Below high-heat flag'))
  x$heat_review_class<-ifelse(!ok,'Unavailable',ifelse(x$heat_high,
    ifelse(x$heat_thin_coverage,'High heat; limited observations','High heat'),
    ifelse(x$heat_thin_coverage,'Below flag; limited observations','Below flag')))
  x$scoring_version<-spec$version
  x
}
read_heat_inputs <- function(files,spec) {
  stopifnot(setequal(files,vapply(spec$inputs,`[[`,character(1),'path')))
  for(s in spec$inputs)if(!identical(digest::digest(file=s$path,algo='sha256'),s$sha256))
    stop('Heat input changed from adopted reference; review and explicitly version the new reference.')
  x<-read.csv(spec$inputs$indicators$path);d<-read.csv(spec$inputs$daily$path)
  stopifnot(!anyNA(x$h3_id),!anyDuplicated(x$h3_id),!anyDuplicated(paste(d$h3_id,d$date)),
    setequal(x$h3_id,d$h3_id),nrow(d)==nrow(x)*length(unique(d$date)),
    all(is.finite(d$land_coverage)),all(d$land_coverage>=0 & d$land_coverage<=1.00001),
    all(d$hot_pixel_equivalents>=0 & d$hot_pixel_equivalents<=d$valid_pixel_equivalents+1e-7))
  eligible<-d$land_coverage>=spec$minimum_daily_land_coverage
  stopifnot(all(is.finite(d$mean_F[eligible])),all(d$valid_pixel_equivalents[eligible]>0))
  d$eligible<-eligible;d$daily_percentile<-NA_real_
  for(date in unique(d$date)){
    i<-which(d$date==date & eligible);d$daily_percentile[i]<-heat_percentile(d$mean_F[i])
  }
  means<-vapply(x$h3_id,function(id){v<-d$daily_percentile[d$h3_id==id];if(any(is.finite(v)))mean(v,na.rm=TRUE)else NA_real_},numeric(1))
  counts<-vapply(x$h3_id,function(id)sum(eligible[d$h3_id==id]),integer(1))
  shares<-vapply(x$h3_id,function(id){z<-d[d$h3_id==id & eligible,];if(nrow(z))100*sum(z$hot_pixel_equivalents)/sum(z$valid_pixel_equivalents)else NA_real_},numeric(1))
  stopifnot(isTRUE(all.equal(unname(heat_percentile(means)),x$quality_relative_rank,tolerance=1e-8)),
    all(counts==x$dates_half_land),isTRUE(all.equal(unname(shares),x$quality_hot_pixel_share,tolerance=1e-8)))
  list(indicators=x,daily=d,source_manifest=jsonlite::read_json(spec$inputs$source_manifest$path),spec=spec)
}
build_heat_burden <- function(inputs,hexes,population,spec) {
  stopifnot(setequal(inputs$indicators$h3_id,hexes$h3_id),!anyDuplicated(hexes$h3_id),
    !anyDuplicated(population$h3_id),setequal(population$h3_id,hexes$h3_id))
  x<-inputs$indicators
  # Current population is contextual; it never changes the equal-hex ranking reference.
  for(n in c('total_population','children_under_18'))x[[n]]<-population[[n]][match(x$h3_id,population$h3_id)]
  x<-score_heat_burden(x,spec)
  list(scores=x,geometry=hexes,spec=spec,
    daily=inputs$daily,source_manifest=inputs$source_manifest,
    geometry_sha256=digest::digest(hexes,algo='sha256'))
}
write_heat_burden <- function(result,directory='output/components/heat-burden') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  write.csv(result$scores,file.path(directory,'scores.csv'),row.names=FALSE,na='')
  write.csv(result$daily,file.path(directory,'daily_reference.csv'),row.names=FALSE,na='')
  g<-merge(sf::st_as_sf(result$geometry),result$scores,by='h3_id',all.x=TRUE,sort=FALSE)
  sf::st_write(g,file.path(directory,'heat_burden.gpkg'),layer='hex_scores',delete_layer=TRUE,quiet=TRUE)
  jsonlite::write_json(list(policy=result$spec,source_manifest=result$source_manifest,
    geometry_sha256=result$geometry_sha256,
    qualification='Relative daytime land-surface heat in one 2026 season, not air temperature, health risk or a long-term normal. Thin observations flagged, not excluded. Hot-pixel share is context only.'),
    file.path(directory,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,na='null',digits=17)
  saveRDS(result,file.path(directory,'analysis.rds'))
  file.path(directory,c('scores.csv','daily_reference.csv','heat_burden.gpkg','metadata.json','analysis.rds'))
}
