.libPaths(c('.R-library',.libPaths()))
source('R/traffic_burden.R')
s<-yaml::read_yaml('config/burdens.yml')$traffic_exposure
x<-score_traffic_burden(c(0,.249999,.25,.499999,.5,1,NA),s)
stopifnot(isTRUE(all.equal(x$traffic_score,c(0,24.9999,25,49.9999,50,100,NA))),
  identical(x$traffic_high,c(FALSE,FALSE,FALSE,FALSE,TRUE,TRUE,NA)),
  identical(x$traffic_sensitivity_high,c(FALSE,FALSE,TRUE,TRUE,TRUE,TRUE,NA)),
  x$traffic_flag_comparison[3]=='Sensitivity flag only',x$traffic_status[7]=='Unavailable')
stopifnot(inherits(try(score_traffic_burden(-.1,s),silent=TRUE),'try-error'),
  inherits(try(score_traffic_burden(1.1,s),silent=TRUE),'try-error'))
cat('Traffic policy tests passed: direct percentages, inclusive flag boundaries, sensitivity separation, zeros, missingness and invalid shares.\n')
