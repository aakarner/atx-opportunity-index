# Review-only fields. No production burden rule is changed by these functions.
industrial_air_candidates <- function(value,spec) {
  full<-spec$candidate_full_burden_concentration
  high<-spec$candidate_high_concentration;old<-spec$existing_mockup_high_concentration
  stopifnot(is.finite(full),is.finite(high),is.finite(old),full>0,high>old,high<=full,old>=0)
  if(any(value<0,na.rm=TRUE))stop('Industrial concentration cannot be negative')
  value[!is.finite(value)]<-NA_real_
  score<-pmin(100,100*value/full)
  oldflag<-value>=old;newflag<-value>=high
  change<-ifelse(is.na(value),'Unavailable',ifelse(newflag,'Flagged under both',
    ifelse(oldflag,'Flag removed at higher cutoff','Below both cutoffs')))
  data.frame(candidate_industrial_score=score,flag_mockup_100=oldflag,
    flag_candidate_p90=newflag,flag_comparison=change,
    candidate_score_capped=ifelse(is.na(value),NA,value>=full))
}
