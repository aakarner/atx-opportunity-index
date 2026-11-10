.libPaths(c('.R-library',.libPaths()))
source('R/street_safety.R')
p<-yaml::read_yaml('config/burdens.yml')$domain_components$street_safety_pedestrian_environment
a<-p$scoring$crash_full_burden_density;h<-p$scoring$crash_high_burden_density
x<-score_street_safety(data.frame(annual_ksi_density=c(0,a/2,a,a*2,h,h-1e-8,NA,h,0),
  gap_score=c(0,40,100,0,50,50,75,NA,NA)),p)
stopifnot(isTRUE(all.equal(x$crash_score[1:4],c(0,50,100,100))),
  isTRUE(all.equal(x$street_safety_score[1:4],c(0,45,100,50))),
  x$crash_high[5],!x$crash_high[6],x$pedestrian_high[5],
  all(is.na(x$street_safety_score[7:9])),x$any_high[7],x$any_high[8],is.na(x$any_high[9]),
  x$flag_detail[8]=='High; other component unavailable')
# Radius and the other rows in a batch cannot change frozen scoring anchors.
y<-score_street_safety(data.frame(annual_ksi_density=a/2,gap_score=40,radius_miles=.25),p)
stopifnot(y$street_safety_score==x$street_safety_score[2])
cat('Street-safety policy tests passed: anchors, capping, inclusive flags, missingness, retained warnings, fixed sensitivity anchors.\n')
