.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/combined_burdens.R')
r<-readRDS('output/components/combined-burdens/analysis.rds');x<-r$results$primary
stopifnot(nrow(x)==1029,!anyDuplicated(x$id),sum(is.finite(x$combined_burden_score))==880,
  sum(x$any_high,na.rm=TRUE)==518,sum(x$burden_status=='high_incomplete')==38,
  sum(is.finite(r$results$sensitivity$combined_burden_score))==800,
  sum(x$heat_thin_coverage)==257,sum(x$industrial_air_review_band)==231)
expected<-x$heat_score/3+x$street_safety_score/3+x$industrial_air_score/6+x$traffic_score/6
stopifnot(isTRUE(all.equal(expected,x$combined_burden_score,tolerance=1e-10)))
# Hold a known warning through missing input, without redistributing its weight.
z<-x[1,,drop=FALSE];z$heat_score<-90;z$heat_high<-TRUE
z$street_safety_score<-NA_real_;z$pedestrian_high<-NA
a<-combined_burden_assessment(z,r$spec$combined)
stopifnot(is.na(a$combined_burden_score),a$burden_status=='high_incomplete',a$any_high)
z$heat_high<-FALSE;z$crash_high<-FALSE;z$industrial_air_high<-FALSE;z$traffic_high<-FALSE
a<-combined_burden_assessment(z,r$spec$combined)
stopifnot(a$burden_status=='incomplete',is.na(a$any_high))
# Join correctness: compare to each independently prepared source by origin ID.
for(pair in list(c('heat-burden','heat_score'),c('industrial-air-burden','industrial_air_score'),c('near-road-traffic','traffic_score'))){
 s<-readRDS(file.path('output/components',pair[1],'analysis.rds'))$scores
 stopifnot(isTRUE(all.equal(x[[pair[2]]],s[[pair[2]]][match(x$id,s$h3_id)],tolerance=1e-10)))
}
street<-readRDS('output/components/street-safety/analysis.rds')
for(k in names(r$results)){
 z<-r$results[[k]];s<-street$results[[k]]
 stopifnot(isTRUE(all.equal(z$street_safety_score,s$street_safety_score[match(z$id,s$h3_id)],tolerance=1e-10)))
}
cat('Combined burden policy and snapshot checks passed: fixed thirds, missingness, retained warnings and all source joins.\n')
