.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/combined_burdens.R')
r<-readRDS('output/components/combined-burdens/analysis.rds');x<-r$results$primary
stopifnot(nrow(x)==1029,!anyDuplicated(x$id),sum(is.finite(x$combined_burden_score))==880,
  sum(x$any_high,na.rm=TRUE)==518,sum(x$overall_high,na.rm=TRUE)==156,
  sum(x$burden_status=='high')==154,sum(x$burden_status=='high_incomplete')==2,
  sum(x$burden_status=='not_flagged')==726,sum(x$burden_status=='incomplete')==147,
  sum(is.finite(r$results$sensitivity$combined_burden_score))==800,
  sum(x$heat_thin_coverage)==257,sum(x$industrial_air_review_band)==231)
expected<-x$heat_score/3+(x$crash_score+x$pedestrian_gap_score)/6+x$industrial_air_score/6+x$traffic_score/6
stopifnot(isTRUE(all.equal(expected,x$combined_burden_score,tolerance=1e-10)))
# Exhaust all five-component combinations, including unavailable components.
fields<-c('heat_high','crash_high','pedestrian_high','industrial_air_high','traffic_high')
combinations<-expand.grid(rep(list(c(FALSE,TRUE,NA)),5));names(combinations)<-fields
z<-x[rep(1,nrow(combinations)),,drop=FALSE];z[fields]<-combinations
z$traffic_sensitivity_high<-z$traffic_high
for(sensitivity in c(FALSE,TRUE)){
  a<-combined_burden_assessment(z,r$spec$combined,sensitivity)
  for(i in seq_len(nrow(z))){
    flags<-unlist(combinations[i,]);n<-sum(flags,na.rm=TRUE);unknown<-anyNA(flags)
    expected_status<-if(n>=2){if(unknown)'high_incomplete' else 'high'}else{if(unknown)'incomplete' else 'not_flagged'}
    stopifnot(a$burden_status[i]==expected_status,a$high_component_count[i]==n,
      identical(a$overall_high[i],if(n>=2)TRUE else if(unknown)NA else FALSE),
      identical(a$any_high[i],if(n>0)TRUE else if(unknown)NA else FALSE))
  }
}
# Crashes and gaps count separately, despite sharing a domain.
z<-x[1,,drop=FALSE];z[fields]<-FALSE;z$crash_high<-TRUE;z$pedestrian_high<-TRUE
stopifnot(combined_burden_assessment(z,r$spec$combined)$overall_high)
# One known component warning survives missing data without becoming overall high.
z$pedestrian_high<-NA;z$pedestrian_gap_score<-NA_real_
a<-combined_burden_assessment(z,r$spec$combined)
stopifnot(is.na(a$combined_burden_score),a$burden_status=='incomplete',is.na(a$overall_high),a$any_high)
z$heat_high<-TRUE
a<-combined_burden_assessment(z,r$spec$combined)
stopifnot(is.na(a$combined_burden_score),a$burden_status=='high_incomplete',a$overall_high)
stopifnot(abs(sum(x$population[x$overall_high %in% TRUE],na.rm=TRUE)-143916.016099)<0.01)
stopifnot(identical(r$spec$combined,yaml::read_yaml('config/burdens.yml')$combined))
# Join correctness: compare to each independently prepared source by origin ID.
for(pair in list(c('heat-burden','heat_score'),c('industrial-air-burden','industrial_air_score'),c('near-road-traffic','traffic_score'))){
 s<-readRDS(file.path('output/components',pair[1],'analysis.rds'))$scores
 stopifnot(isTRUE(all.equal(x[[pair[2]]],s[[pair[2]]][match(x$id,s$h3_id)],tolerance=1e-10)))
}
street<-readRDS('output/components/street-safety/analysis.rds')
for(k in names(r$results)){
 z<-r$results[[k]];s<-street$results[[k]]
 for(field in c('crash_score','pedestrian_gap_score'))
   stopifnot(isTRUE(all.equal(z[[field]],s[[field]][match(z$id,s$h3_id)],tolerance=1e-10)))
}
cat('Combined burden policy and snapshot checks passed: fixed thirds, missingness, retained warnings and all source joins.\n')
