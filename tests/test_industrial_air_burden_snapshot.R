.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/industrial_air_burden.R')
r<-readRDS('output/components/industrial-air-burden/analysis.rds');x<-r$scores
old<-read.csv('output/components/industrial-air-review/origin_comparison.csv');i<-match(x$h3_id,old$h3_id)
stopifnot(nrow(x)==1029,!anyDuplicated(x$h3_id),!anyNA(i),all(is.finite(x$industrial_air_score)),
  isTRUE(all.equal(x$industrial_air_score,old$candidate_industrial_score[i],tolerance=1e-10)),
  sum(x$industrial_air_high)==103,sum(x$industrial_air_review_band)==231,
  !any(x$industrial_air_high & x$industrial_air_review_band),
  all(x$industrial_air_review_or_high==(x$industrial_air_high | x$industrial_air_review_band)),
  all(x$industrial_air_review_or_high==old$flag_mockup_100[i]))
e<-read.csv('output/components/industrial-air-burden/scores.csv')
stopifnot(isTRUE(all.equal(e$industrial_air_score,x$industrial_air_score,tolerance=1e-10)))
g<-st_read('output/components/industrial-air-burden/industrial_air_burden.gpkg',quiet=TRUE)
stopifnot(nrow(g)==1029,setequal(g$h3_id,x$h3_id),st_crs(g)==st_crs(r$geometry))
cat('Industrial-air snapshot checks passed: all origins, unchanged candidate scores, exact and exclusive flags, CSV/GIS exports.\n')
