.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/combined_burdens.R')
r<-readRDS('output/components/combined-burdens/analysis.rds');x<-r$results$primary
stopifnot(nrow(x)==1029,!anyDuplicated(x$id),sum(is.finite(x$combined_burden_score))==874,
  sum(x$any_high,na.rm=TRUE)==551,sum(x$overall_high,na.rm=TRUE)==185,
  sum(x$burden_status=='high')==184,sum(x$burden_status=='high_incomplete')==1,
  sum(x$burden_status=='not_flagged')==690,sum(x$burden_status=='incomplete')==154,
  sum(is.finite(r$results$sensitivity$combined_burden_score))==731,
  sum(x$heat_thin_coverage)==257,sum(x$industrial_air_review_band)==231)
expected<-x$heat_score/3+(x$crash_score+x$major_frontage_score)/6+x$industrial_air_score/6+x$traffic_score/6
stopifnot(isTRUE(all.equal(expected,x$combined_burden_score,tolerance=1e-10)))
# Exhaust all five-component combinations, including unavailable components.
fields<-c('heat_high','crash_high','major_frontage_high','industrial_air_high','traffic_high')
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
# Crashes and unserved frontage count separately, despite sharing a domain.
z<-x[1,,drop=FALSE];z[fields]<-FALSE;z$crash_high<-TRUE;z$major_frontage_high<-TRUE
stopifnot(combined_burden_assessment(z,r$spec$combined)$overall_high)
# One known component warning survives missing data without becoming overall high.
z$major_frontage_high<-NA;z$major_frontage_score<-NA_real_
a<-combined_burden_assessment(z,r$spec$combined)
stopifnot(is.na(a$combined_burden_score),a$burden_status=='incomplete',is.na(a$overall_high),a$any_high)
z$heat_high<-TRUE
a<-combined_burden_assessment(z,r$spec$combined)
stopifnot(is.na(a$combined_burden_score),a$burden_status=='high_incomplete',a$overall_high)
stopifnot(abs(sum(x$population[x$overall_high %in% TRUE],na.rm=TRUE)-167711.548493)<0.01)
stopifnot(identical(r$spec$combined,yaml::read_yaml('config/burdens.yml')$combined))
# Include a high/incomplete hexagon in the confirmed-high share but omit it
# from the combined score mean. Population outside an overlap supplies no weight.
cells <- x[rep(1, 5), ]
cells$id <- letters[1:5]
cells$combined_burden_score <- c(20, NA, NA, 100, 100)
cells$heat_score <- c(10, 50, NA, 100, 100)
cells$overall_high <- c(FALSE, TRUE, NA, TRUE, TRUE)
cells$traffic_sensitivity_status <- c("high", "high_incomplete", "incomplete", "high", "high")
weights <- data.frame(tract_id=c("mixed","mixed","mixed","mixed","zero"), id=cells$id,
  residents=c(20, 30, 50, NA, 0))
coverage <- data.frame(id=c("empty","mixed","zero"), area_coverage=c(0,.8,1),
  resident_weight_area_share=c(0,.6,1))
fixture <- list(results=list(primary=cells), spec=r$spec)
tracts <- burden_tract_estimates(fixture, weights, coverage)$primary
mixed <- tracts[tracts$id == "mixed", ]
stopifnot(identical(tracts$id,coverage$id), mixed$resident_weight==100,
  mixed$combined_burden_score==20, mixed$combined_burden_score_coverage_pct==20,
  mixed$heat_score==34, mixed$heat_score_coverage_pct==50, mixed$overall_high_pct==30,
  mixed$overall_unknown_pct==50, mixed$traffic_sensitivity_overall_high_pct==50,
  all(is.na(tracts$combined_burden_score[tracts$resident_weight==0])),
  all(is.na(tracts$overall_high_pct[tracts$resident_weight==0])))
# Join correctness: compare to each independently prepared source by origin ID.
for(pair in list(c('heat-burden','heat_score'),c('industrial-air-burden','industrial_air_score'),c('near-road-traffic','traffic_score'))){
 s<-readRDS(file.path('output/components',pair[1],'analysis.rds'))$scores
 stopifnot(isTRUE(all.equal(x[[pair[2]]],s[[pair[2]]][match(x$id,s$h3_id)],tolerance=1e-10)))
}
street<-readRDS('output/components/street-safety/analysis.rds')
for(k in names(r$results)){
 z<-r$results[[k]];s<-street$results[[k]]
 for(field in c('crash_score','major_frontage_score'))
   stopifnot(isTRUE(all.equal(z[[field]],s[[field]][match(z$id,s$h3_id)],tolerance=1e-10)))
}
cat('Combined burden policy and snapshot checks passed: fixed thirds, missingness, retained warnings and all source joins.\n')
