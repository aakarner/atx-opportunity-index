.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
r<-readRDS('output/components/near-road-traffic/analysis.rds');x<-r$scores
raw<-read.csv('scripts/aadt/aadt_metrics.csv');i<-match(x$h3_id,raw$h3_id)
stopifnot(nrow(x)==1029,!anyDuplicated(x$h3_id),!anyNA(i),
  isTRUE(all.equal(x$traffic_score,100*raw$fraction_overlap[i],tolerance=1e-10)),
  isTRUE(all.equal(x$traffic_distance_ft,raw$distance_to_high_vol_ft[i],tolerance=1e-10)),
  isTRUE(all.equal(x$traffic_center_distance_m,raw$distance_to_high_vol_ft[i]*.3048,tolerance=1e-10)),
  sum(x$traffic_high)==123,sum(x$traffic_sensitivity_high)==201,sum(x$traffic_score==0)==717,
  all(!x$traffic_high | x$traffic_sensitivity_high),all(is.finite(x$traffic_score)))
e<-read.csv('output/components/near-road-traffic/scores.csv')
stopifnot(isTRUE(all.equal(e$traffic_score,x$traffic_score,tolerance=1e-10)))
g<-st_read('output/components/near-road-traffic/traffic_burden.gpkg',quiet=TRUE)
stopifnot(nrow(g)==1029,setequal(g$h3_id,x$h3_id),st_crs(g)==st_crs(r$geometry))
summary<-read.csv('output/components/near-road-traffic/flag_population_summary.csv')
for(k in c('primary_50_percent','sensitivity_25_percent')){
  use<-if(k=='primary_50_percent')x$traffic_high else x$traffic_sensitivity_high
  stopifnot(abs(summary$known_residents[summary$rule==k]-sum(x$total_population[use],na.rm=TRUE))<1e-6)
}
cat('Traffic snapshot checks passed: raw data agreement, all origins, scores, nested flags, zero preservation, distance units, exports and population summaries.\n')
