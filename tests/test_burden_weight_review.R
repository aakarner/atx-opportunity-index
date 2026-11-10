.libPaths(c('.R-library',.libPaths()))
source('R/burden_weight_review.R')
s<-yaml::read_yaml('config/burden-weight-review.yml')
fixture<-data.frame(heat_score=c(100,0,100),street_safety_score=c(0,0,NA),industrial_air_score=c(0,0,0),traffic_score=c(0,100,0))
a<-review_weighted_burden(fixture,s$presets$equal_themes$relative_weights)
b<-review_weighted_burden(fixture,s$presets$equal_domains$relative_weights)
stopifnot(isTRUE(all.equal(a,c(100/3,100/6,NA))),isTRUE(all.equal(b,c(25,25,NA))))
flags<-review_burden_warning(data.frame(a=c(TRUE,FALSE,FALSE),b=c(NA,NA,FALSE)))
stopifnot(identical(flags$any_high,c(TRUE,NA,FALSE)),!flags$assessment_complete[1])
x<-read.csv('output/components/burden-weight-review/origin_comparison.csv')
ok<-is.finite(x$score_equal_themes)&is.finite(x$score_equal_domains)
stopifnot(nrow(x)==1029,!anyDuplicated(x$h3_id),sum(ok)==880,
  identical(is.na(x$score_equal_themes),is.na(x$score_equal_domains)),
  all(abs(x$themes_minus_domains[ok]-(x$heat_score[ok]+x$street_safety_score[ok]-x$industrial_air_score[ok]-x$traffic_score[ok])/12)<1e-10))
for(k in names(s$presets))stopifnot(isTRUE(all.equal(x[[paste0('score_',k)]],review_weighted_burden(x,s$presets[[k]]$relative_weights),tolerance=1e-10)))
expected<-review_burden_warning(x[,c('heat_high','crash_high','pedestrian_high','industrial_air_high','traffic_high')])
stopifnot(identical(x$warning_status,expected$warning_status))
summary<-read.csv('output/components/burden-weight-review/summary.csv')
known<-ok & is.finite(x$total_population) & x$total_population>0
for(k in names(s$presets))stopifnot(abs(summary$resident_weighted_mean[summary$preset==k]-
  sum(x[[paste0('score_',k)]][known]*x$total_population[known])/sum(x$total_population[known]))<1e-10)
tails<-read.csv('output/components/burden-weight-review/tail_overlap.csv')
for(t in c(75,90)){
  a<-x[[paste0('top',t,'_equal_themes')]] %in% TRUE;b<-x[[paste0('top',t,'_equal_domains')]] %in% TRUE
  stopifnot(tails$shared[tails$percentile==t]==sum(a&b))
}
cat('Weight review tests passed: exact weights, no missing-data renormalization, algebraic difference, all origins and invariant warning semantics.\n')
