combined_burden_assessment <- function(x,spec,traffic_sensitivity=FALSE) {
  stopifnot(identical(spec$classification_rule,'at_least_two_primary_components_high_independent_of_score'),
    isTRUE(spec$high_component_minimum==2))
  w<-unlist(spec$relative_weights);w<-w/sum(w)
  m<-as.matrix(x[,names(w)]);valid<-apply(is.finite(m),1,all)
  score<-rep(NA_real_,nrow(x));score[valid]<-as.numeric(m[valid,,drop=FALSE]%*%w)
  f<-x[,c('heat_high','crash_high','major_frontage_high','industrial_air_high')]
  f$traffic_high<-if(traffic_sensitivity)x$traffic_sensitivity_high else x$traffic_high
  count<-rowSums(f==TRUE,na.rm=TRUE)
  high<-count>=spec$high_component_minimum;complete<-rowSums(is.na(f))==0
  data.frame(combined_burden_score=score,
    burden_status=ifelse(high,ifelse(complete,'high','high_incomplete'),ifelse(complete,'not_flagged','incomplete')),
    high_component_count=count,
    overall_high=ifelse(high,TRUE,ifelse(complete,FALSE,NA)),
    any_high=ifelse(count>0,TRUE,ifelse(complete,FALSE,NA)))
}
build_combined_burdens <- function(heat,street,industrial,traffic,spec) {
  h<-heat$scores;i<-industrial$scores;t<-traffic$scores
  columns<-list(heat=c('heat_score','heat_high','heat_thin_coverage','dates_half_land','quality_hot_pixel_share'),
    street=c('crash_score','major_frontage_score','crash_high','major_frontage_high','annual_ksi_density','ksi_count','observed_area_sqmi','observed_area_share','major_frontage_m','major_served_m','major_coverage_pct','frontage_status','inventory_observed'),
    industrial=c('industrial_air_score','industrial_air_high','industrial_air_review_band','rsei_tox_conc'),
    traffic=c('traffic_score','traffic_high','traffic_sensitivity_high','traffic_buffer_share','traffic_distance_ft'))
  result<-list()
  for(k in c('primary','sensitivity')) {
    parts<-list(heat=h,street=street$results[[k]],industrial=i,traffic=t)
    x<-data.frame(id=h$h3_id,population=h$total_population,children=h$children_under_18)
    for(name in names(parts)){
      p<-parts[[name]];stopifnot(all(columns[[name]] %in% names(p)), !anyDuplicated(p$h3_id),setequal(p$h3_id,x$id))
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
burden_tract_estimates <- function(result, weights, coverage) {
  coverage <- coverage[c("id", "area_coverage", "resident_weight_area_share")]
  stopifnot(!anyDuplicated(coverage$id), !anyDuplicated(weights[c("tract_id", "id")]),
    all(weights$tract_id %in% coverage$id))
  # A hexagon with no known residents contributes no weight to any tract estimate.
  weights <- weights[which(weights$residents > 0), ]
  groups <- split(seq_len(nrow(weights)), factor(weights$tract_id, levels = coverage$id))
  score_fields <- c("combined_burden_score", names(result$spec$combined$relative_weights))
  flag_fields <- c("overall_high", "heat_high", "crash_high", "major_frontage_high",
    "industrial_air_high", "traffic_high", "traffic_sensitivity_high", "traffic_sensitivity_overall_high",
    "heat_thin_coverage", "industrial_air_review_band")
  lapply(result$results, function(rows) {
    index <- match(weights$id, rows$id)
    stopifnot(!anyNA(index), !anyDuplicated(rows$id))
    status <- rows$traffic_sensitivity_status
    rows$traffic_sensitivity_overall_high <- ifelse(status == "incomplete", NA, status %in% c("high", "high_incomplete"))
    estimates <- lapply(groups, function(k) {
      x <- rows[index[k], , drop = FALSE]
      w <- weights$residents[k]
      total <- sum(w)
      percent <- function(mask) if (total > 0) 100 * sum(w[mask]) / total else NA_real_
      values <- list(resident_weight = total)
      for (field in score_fields) {
        valid <- is.finite(x[[field]])
        values[[field]] <- if (any(valid)) weighted.mean(x[[field]][valid], w[valid]) else NA_real_
        values[[paste0(field, "_coverage_pct")]] <- percent(valid)
      }
      for (field in flag_fields) {
        flag <- x[[field]]
        values[[paste0(field, "_pct")]] <- if (any(!is.na(flag))) percent(flag %in% TRUE) else NA_real_
      }
      values$overall_unknown_pct <- percent(is.na(x$overall_high))
      values$traffic_sensitivity_overall_unknown_pct <- percent(is.na(x$traffic_sensitivity_overall_high))
      as.data.frame(values)
    })
    cbind(coverage, dplyr::bind_rows(estimates))
  })
}

write_combined_burdens <- function(result,tracts,directory='site/assets',output='output/components/combined-burdens') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE);dir.create(output,recursive=TRUE,showWarnings=FALSE)
  for(k in names(result$results))write.csv(result$results[[k]],file.path(output,paste0(k,'.csv')),row.names=FALSE,na='')
  x<-result$results$primary
  counts<-list(origins=nrow(x),scored=sum(is.finite(x$combined_burden_score)),high=sum(x$overall_high,na.rm=TRUE),
    any_component_high=sum(x$any_high,na.rm=TRUE),
    statuses=as.list(table(factor(x$burden_status,levels=c('high','high_incomplete','not_flagged','incomplete')))),
    heat_thin=sum(x$heat_thin_coverage,na.rm=TRUE),industrial_review=sum(x$industrial_air_review_band,na.rm=TRUE))
  tract_files <- file.path(output, paste0("tract_", names(tracts), ".csv"))
  for (k in seq_along(tracts)) write.csv(tracts[[k]], tract_files[k], row.names=FALSE, na='')
  public<-list(schema_version=5,policy=result$spec$combined,rules=result$provenance,
    primary=result$results$primary,quarter_mile=result$results$sensitivity,counts=counts,
    tracts=list(primary=tracts$primary,quarter_mile=tracts$sensitivity),
    interpretation='Overall high burden requires at least two high components, counting crashes and sidewalk gaps on major streets separately. Individual component warnings remain visible independently of classification and score. Higher scores mean greater burden. Local screening, not health risk; flood eligibility remains independent.')
  path<-file.path(directory,'combined-burdens.json')
  jsonlite::write_json(public,path,dataframe='columns',digits=NA,auto_unbox=TRUE,na='null',null='null')
  saveRDS(result,file.path(output,'analysis.rds'))
  c(path,file.path(output,c('primary.csv','sensitivity.csv','analysis.rds')),tract_files)
}
