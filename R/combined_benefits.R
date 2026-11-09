# One row per routing origin. Score complete origins first, then aggregate;
# never apply minimums to averaged tract components.
combined_origin_assessment <- function(origins, profile, scenario, spec, baskets, weights=NULL) {
  if(is.null(weights)) weights<-unlist(spec$presets[[profile]])
  required<-c('destinations','jobs',if(profile=='families')'education')
  stopifnot(all(required %in% names(weights)),all(is.finite(weights)),all(weights>=0),sum(weights[required])>0)
  weights<-weights[required]/sum(weights[required])
  mode<-if(scenario=='transit')'transit' else 'drive'
  target<-switch(scenario,transit=spec$transit$full_credit_jobs,drive=spec$driving$default$full_credit_jobs,
    drive30=spec$driving$sensitivity$full_credit_jobs)
  count<-origins[[paste(mode,profile,sep='_')]];grocery<-origins[[paste0(mode,'_grocery')]]
  jobs<-origins[[paste0('jobs_',scenario)]]
  domain<-data.frame(destinations=100*count/length(baskets$profiles[[profile]]),jobs=100*pmin(jobs/target,1))
  missing<-is.na(count)|is.na(grocery)|is.na(jobs)
  failed<-(!is.na(count)&count<spec$destination_minimums[[profile]]) |
    (!is.na(grocery)&grocery==0) | (!is.na(jobs)&jobs<target*spec$jobs$minimum_fraction)
  if(profile=='families') {
    domain$education<-100*pmin(origins$education_growth/spec$education$full_credit_growth,1)
    missing<-missing|is.na(origins$education_growth)
    failed<-failed|(!is.na(origins$education_growth)&origins$education_growth<spec$education$minimum_growth)
  }
  score<-as.vector(as.matrix(domain[required]) %*% weights)
  score[missing]<-NA_real_
  data.frame(id=origins$id,profile,scenario,score,
    status=ifelse(missing,'incomplete',ifelse(failed,'below','meets')))
}

write_combined_benefits <- function(benefits,population,schools,h8,crosswalk,tracts,spec,baskets,directory='site/assets') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  ids<-benefits$scores$id;ix<-match(ids,schools$origins$site_id);pi<-match(ids,population$h3_id)
  hi<-match(ids,h8$h3_id);ri<-match(ids,benefits$raw$id)
  stopifnot(!anyNA(c(ix,pi,hi,ri)),!anyDuplicated(ids))
  origins<-data.frame(id=ids,population=population$total_population[pi],
    education_growth=schools$origins$subgroup[ix],education_sample=schools$origins$minimum_growth_tests[ix],
    education_status=schools$origins$status[ix],jobs_transit=h8$access_total_jobs[hi],
    jobs_drive=benefits$raw$drive__jobs_cumulative__total_jobs__15[ri],
    jobs_drive30=benefits$raw$drive__jobs_cumulative__total_jobs__30[ri])
  for(mode in c('drive','transit')) {
    source_mode<-if(mode=='transit')'walk_transit' else 'drive'
    prefix<-paste(source_mode,baskets$defaults[[source_mode]],sep='_')
    for(profile in c(names(spec$presets),'grocery')) origins[[paste(mode,profile,sep='_')]]<-benefits$scores[[paste(prefix,profile,sep='_')]]
  }
  index<-match(crosswalk$h3_id,ids)
  weights<-data.frame(tract_id=crosswalk$GEOID,id=crosswalk$h3_id,
    residents=crosswalk$h8_area_share*origins$population[index],area=crosswalk$overlap_area_m2)
  stopifnot(!anyNA(index),all(is.na(weights$residents)|weights$residents>=0))
  reference<-dplyr::bind_rows(lapply(names(spec$presets),function(profile)
    dplyr::bind_rows(lapply(c('drive','transit','drive30'),function(scenario)
      combined_origin_assessment(origins,profile,scenario,spec,baskets)))))
  path<-file.path(directory,'combined-benefits.json')
  jsonlite::write_json(list(schema_version=1,spec=spec,origins=origins,tract_weights=weights,
    tracts=tracts[c('id','area_coverage','resident_weight_area_share')],reference=reference),path,
    dataframe='columns',digits=NA,auto_unbox=TRUE,na='null',null='null')
  path
}
