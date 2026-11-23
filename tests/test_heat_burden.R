.libPaths(c('.R-library',.libPaths()))
source('R/heat_burden.R')
s<-yaml::read_yaml('config/burdens.yml')$heat
x<-score_heat_burden(data.frame(quality_relative_rank=c(89.99,90,100,20,NA,50),dates_half_land=c(8,7,8,1,0,0)),s)
stopifnot(identical(x$heat_high,c(FALSE,TRUE,TRUE,FALSE,NA,NA)),
  identical(x$heat_thin_coverage,c(FALSE,TRUE,FALSE,TRUE,NA,NA)),
  x$heat_score[2]==90,x$heat_score[4]==20,all(is.na(x$heat_score[5:6])),
  isTRUE(all.equal(heat_percentile(c(1,2,2,NA)),c(100/3,100,100,NA))))
# Subsetting for display must not recompute the original percentile score.
y<-score_heat_burden(data.frame(quality_relative_rank=90,dates_half_land=7),s)
stopifnot(y$heat_score==x$heat_score[2])
cat('Heat policy tests passed: inclusive high flag, thin observations retained, zero-date/missing unavailable, ties, fixed display reference.\n')
