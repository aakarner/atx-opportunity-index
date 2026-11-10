.libPaths(c('.R-library',.libPaths()));library(sf)
r<-readRDS('output/components/pedestrian-gaps/analysis.rds')
ids<-targets::tar_read(h8_geometry)$h3_id
for(k in c('hex','neighborhood')) {
 exported<-st_read('output/components/pedestrian-gaps/pedestrian_gaps.gpkg',layer=k,quiet=TRUE)
 stopifnot(st_crs(exported)$epsg==26914,nrow(exported)==1029)
 d<-r[[k]];stopifnot(nrow(d)==1029,!anyDuplicated(d$h3_id),setequal(d$h3_id,ids),all(d$denominator_m>=0),all(d$observed_area_share>0 & d$observed_area_share<=1+1e-7))
 ok<-is.finite(d$gap_score)
 stopifnot(all(d$gap_score[ok]>=0 & d$gap_score[ok]<=100),all(abs(d$gap_score[ok]+d$completeness_score[ok]-100)<1e-9),all(d$potential_included_score[ok]>=d$gap_score[ok]-1e-9),all(d$dated_as_completed_score[ok]<=d$gap_score[ok]+1e-9),all(is.na(d$gap_score[d$denominator_m==0])))
 stopifnot(all(abs(d$gap_score[ok]-100*d$planned_m[ok]/d$denominator_m[ok])<1e-9))
}
# Independent exact overlays for three origin windows (zero, median, maximum known scores).
w<-r$neighborhood;ok<-which(is.finite(w$gap_score));pick<-unique(c(ok[which.min(w$gap_score[ok])],ok[order(w$gap_score[ok])][ceiling(length(ok)/2)],ok[which.max(w$gap_score[ok])]))
for(i in pick) {
 win<-r$windows[r$windows$h3_id==w$h3_id[i],]
 for(cl in c('completed','planned','potential','unknown')) {
   x<-r$network$lines[r$network$lines$classification==cl,]
   p<-suppressWarnings(st_intersection(x,st_geometry(win)))
   actual<-sum(as.numeric(st_length(p)));expected<-w[[paste0(cl,'_m')]][i]
   stopifnot(abs(actual-expected)<1e-5)
 }
}
cat('Snapshot passed: all 1,029 IDs, scores, missingness, sensitivity direction, boundary shares and independent overlays.\n')
