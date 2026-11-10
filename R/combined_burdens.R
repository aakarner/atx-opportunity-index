combined_burden_assessment <- function(x,spec,traffic_sensitivity=FALSE) {
  w<-unlist(spec$relative_weights);w<-w/sum(w)
  m<-as.matrix(x[,names(w)]);valid<-apply(is.finite(m),1,all)
  score<-rep(NA_real_,nrow(x));score[valid]<-as.numeric(m[valid,,drop=FALSE]%*%w)
  f<-x[,c('heat_high','crash_high','pedestrian_high','industrial_air_high')]
  f$traffic_high<-if(traffic_sensitivity)x$traffic_sensitivity_high else x$traffic_high
  high<-rowSums(f==TRUE,na.rm=TRUE)>0;complete<-rowSums(is.na(f))==0
  data.frame(combined_burden_score=score,
    burden_status=ifelse(high,ifelse(complete,'high','high_incomplete'),ifelse(complete,'not_flagged','incomplete')),
    any_high=ifelse(high,TRUE,ifelse(complete,FALSE,NA)))
}
build_combined_burdens <- function(heat,street,industrial,traffic,spec) {
  h<-heat$scores;i<-industrial$scores;t<-traffic$scores
  columns<-list(heat=c('heat_score','heat_high','heat_thin_coverage','dates_half_land','quality_hot_pixel_share'),
    street=c('street_safety_score','crash_score','pedestrian_gap_score','crash_high','pedestrian_high','annual_ksi_density','ksi_count','observed_area_sqmi','observed_area_share','denominator_m','completion_date_review','status'),
    industrial=c('industrial_air_score','industrial_air_high','industrial_air_review_band','rsei_tox_conc'),
    traffic=c('traffic_score','traffic_high','traffic_sensitivity_high','traffic_buffer_share','traffic_distance_ft'))
  result<-list()
  for(k in c('primary','sensitivity')) {
    parts<-list(heat=h,street=street$results[[k]],industrial=i,traffic=t)
    x<-data.frame(id=h$h3_id,population=h$total_population,children=h$children_under_18)
    for(name in names(parts)){
      p<-parts[[name]];stopifnot(!anyDuplicated(p$h3_id),setequal(p$h3_id,x$id))
      for(col in columns[[name]])x[[col]]<-p[[col]][match(x$id,p$h3_id)]
    }
    x$street_radius_miles<-if(k=='primary')spec$domain_components$street_safety_pedestrian_environment$spatial_review$adopted_radius_miles else spec$domain_components$street_safety_pedestrian_environment$spatial_review$sensitivity_radius_miles
    x<-cbind(x,combined_burden_assessment(x,spec$combined))
    alt<-combined_burden_assessment(x,spec$combined,TRUE)
    x$traffic_sensitivity_status<-alt$burden_status
    result[[k]]<-x
  }
  list(results=result,spec=spec,geometry=heat$geometry,
    provenance=list(heat=heat$spec,industrial=industrial$spec,traffic=traffic$spec,street=street$policy))
}
write_combined_burdens <- function(result,directory='site/assets',output='output/components/combined-burdens') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE);dir.create(output,recursive=TRUE,showWarnings=FALSE)
  for(k in names(result$results))write.csv(result$results[[k]],file.path(output,paste0(k,'.csv')),row.names=FALSE,na='')
  x<-result$results$primary
  counts<-list(origins=nrow(x),scored=sum(is.finite(x$combined_burden_score)),high=sum(x$any_high,na.rm=TRUE),
    statuses=as.list(table(factor(x$burden_status,levels=c('high','high_incomplete','not_flagged','incomplete')))),
    heat_thin=sum(x$heat_thin_coverage,na.rm=TRUE),industrial_review=sum(x$industrial_air_review_band,na.rm=TRUE))
  public<-list(schema_version=1,policy=result$spec$combined,rules=result$provenance,
    primary=result$results$primary,quarter_mile=result$results$sensitivity,counts=counts,
    interpretation='Higher scores mean greater burden. Local screening, not health risk. Primary warnings are separate from scores; flood eligibility remains independent.')
  path<-file.path(directory,'combined-burdens.json')
  jsonlite::write_json(public,path,dataframe='columns',digits=NA,auto_unbox=TRUE,na='null',null='null')
  saveRDS(result,file.path(output,'analysis.rds'))
  c(path,file.path(output,c('primary.csv','sensitivity.csv','analysis.rds')))
}
