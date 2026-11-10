.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/street_safety.R')
r<-readRDS('output/components/street-safety/analysis.rds')
prior<-read.csv('output/components/pedestrian-gaps/radius-comparison/origin_results.csv')
p<-r$policy;s<-p$scoring
for(k in names(r$results)) {
  x<-r$results[[k]];stopifnot(nrow(x)==1029,!anyDuplicated(x$h3_id))
  ok<-is.finite(x$street_safety_score)
  stopifnot(all(x$street_safety_score[ok]>=0 & x$street_safety_score[ok]<=100),
    all(is.na(x$street_safety_score)==(is.na(x$crash_score)|is.na(x$pedestrian_gap_score))),
    all(abs(x$street_safety_score[ok]-(x$crash_score[ok]+x$pedestrian_gap_score[ok])/2)<1e-10),
    all(x$crash_high== (x$annual_ksi_density>=s$crash_high_burden_density),na.rm=TRUE),
    all(x$pedestrian_high==(x$gap_score>=50),na.rm=TRUE))
  old<-prior[prior$radius_miles==unique(x$radius_miles),]
  m<-match(x$h3_id,old$h3_id)
  stopifnot(isTRUE(all.equal(x$gap_score,old$gap_score[m],tolerance=1e-10)),
    isTRUE(all.equal(x$annual_ksi_density,old$annual_ksi_density[m],tolerance=1e-10)),
    all(x$ksi_count==old$ksi_count_2020_2024[m]),
    all(x$dated_as_completed_score<=x$gap_score+1e-10,na.rm=TRUE))
  exported<-read.csv(file.path('output/components/street-safety',paste0(k,'.csv')))
  stopifnot(nrow(exported)==1029,
    isTRUE(all.equal(exported$street_safety_score,x$street_safety_score,tolerance=1e-12)))
  g<-st_read('output/components/street-safety/street_safety.gpkg',layer=paste0(k,'_hex'),quiet=TRUE)
  stopifnot(nrow(g)==1029,st_crs(g)$epsg==26914)
}
primary<-r$results$primary
stopifnot(abs(quantile(primary$annual_ksi_density,.95)-s$crash_full_burden_density)<1e-10,
  abs(quantile(primary$annual_ksi_density,.9)-s$crash_high_burden_density)<1e-10)
cat('Street-safety snapshot checks passed: all origins, raw spatial results, frozen anchors, missingness, scores, flags, date review and GIS/CSV exports.\n')
