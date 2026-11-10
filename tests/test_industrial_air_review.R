.libPaths(c('.R-library',.libPaths()))
source('R/industrial_air_review.R')
s<-yaml::read_yaml('config/industrial-air-review.yml');a<-s$candidate_full_burden_concentration;h<-s$candidate_high_concentration
z<-industrial_air_candidates(c(0,99.999,100,h-1e-8,h,a,2*a,NA),s)
stopifnot(z$candidate_industrial_score[1]==0,all(z$candidate_industrial_score[6:7]==100),
  !z$flag_mockup_100[2],z$flag_mockup_100[3],!z$flag_candidate_p90[4],z$flag_candidate_p90[5],
  is.na(z$candidate_industrial_score[8]),is.na(z$flag_candidate_p90[8]),z$flag_comparison[8]=='Unavailable')
x<-read.csv('output/components/industrial-air-review/origin_comparison.csv')
stopifnot(nrow(x)==1029,!anyDuplicated(x$h3_id),sum(x$flag_mockup_100)==334,sum(x$flag_candidate_p90)==103,
  sum(x$flag_comparison=='Flag removed at higher cutoff')==231,
  all(!x$flag_candidate_p90 | x$flag_mockup_100),
  all(abs(x$candidate_industrial_score-pmin(100,100*x$rsei_tox_conc/a))<1e-10))
summary<-read.csv('output/components/industrial-air-review/flag_population_summary.csv')
for(k in c('existing_100','candidate_p90','removed_flag')){
  use<-switch(k,existing_100=x$flag_mockup_100,candidate_p90=x$flag_candidate_p90,removed_flag=x$flag_mockup_100 & !x$flag_candidate_p90)
  row<-summary[summary$rule==k,]
  stopifnot(abs(row$known_residents-sum(x$total_population[use],na.rm=TRUE))<1e-6,
    abs(row$known_children-sum(x$children_under_18[use],na.rm=TRUE))<1e-6)
}
cat('Industrial-air review checks passed: threshold inclusivity, zero/missing handling, capping, nested flags, all origin scores and population summaries.\n')
