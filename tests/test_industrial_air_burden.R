.libPaths(c('.R-library',.libPaths()))
source('R/industrial_air_burden.R')
s<-yaml::read_yaml('config/burdens.yml')$industrial_air
a<-s$full_burden_concentration;h<-s$high_burden_concentration
x<-score_industrial_air(c(0,99.999,100,h-1e-8,h,a,a*2,NA,200),s,c(rep(1,8),.9))
stopifnot(x$industrial_air_score[1]==0,all(x$industrial_air_score[6:7]==100),
  identical(x$industrial_air_review_band,c(FALSE,FALSE,TRUE,TRUE,FALSE,FALSE,FALSE,NA,NA)),
  !x$industrial_air_high[4],x$industrial_air_high[5],all(is.na(x$industrial_air_score[8:9])))
# Frozen anchors do not change when a batch is filtered or new values are supplied.
stopifnot(score_industrial_air(100,s)$industrial_air_score==x$industrial_air_score[3])
cat('Industrial-air policy tests passed: exact boundaries, exclusive review band, capping, frozen anchors and unavailable incomplete data.\n')
