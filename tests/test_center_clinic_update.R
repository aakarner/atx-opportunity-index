library(jsonlite);library(readr);library(dplyr);library(yaml);library(digest)
source('R/benefits.R')
spec<-read_yaml('config/benefits.yml');ids<-read_json('site/assets/benefits.json',simplifyVector=TRUE)$hex$id
x<-read_benefit_inputs(dam_files(Sys.getenv('DAM_DATA_DIR')),spec,ids)
b<-benefit_scores(x,spec)
stopifnot(nrow(b$scores)==length(ids),length(spec$profiles$older)==6,length(spec$profiles$single)==4)
for(mode in c('drive','walk_transit')){
 for(dest in names(spec$scenario_map)){
  a<-x$results[x$results$mode==mode & x$results$scenario==spec$scenario_map[[dest]],];a<-a[match(ids,a$h3_id),]
  expected<-ifelse(a$result_status=='not_reached_within_model',0,as.numeric(a$value<=spec$defaults[[mode]]))
  stopifnot(identical(as.numeric(b$scores[[paste(mode,spec$defaults[[mode]],dest,sep='_')]]),as.numeric(expected)))
 }
}
dir.create('output/components/center-clinic-update',recursive=TRUE,showWarnings=FALSE)
write_csv(b$scores,'output/components/center-clinic-update/profile_counts_h8.csv')
write_csv(b$raw,'output/components/center-clinic-update/raw_access_h8.csv')
write_csv(b$sensitivity,'output/components/center-clinic-update/sensitivity.csv')
cat('PASS: release hashes/schema,',length(ids),'Austin origins, all new series, explicit basket mappings and thresholds\n')
