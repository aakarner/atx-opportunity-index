# Validate Peter's pinned artifacts and reconstruct heat indicators on current H8s.
if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
suppressPackageStartupMessages({library(sf);library(terra);library(Matrix);library(dplyr);library(ggplot2);library(patchwork)})
root<-'data/raw/peter_heat/d90d74f38a';out<-'output/components/heat-validation';dir.create(out,recursive=TRUE,showWarnings=FALSE)
manifest<-jsonlite::read_json(file.path(root,'manifest.json'),simplifyVector=TRUE)
stopifnot(all(vapply(seq_len(nrow(manifest$files)),function(i)digest::digest(file=file.path(root,manifest$files$path[i]),algo='sha256')==manifest$files$sha256[i],logical(1))))
water_root<-'data/raw/heat_validation_water_2024'
wm<-jsonlite::read_json(file.path(water_root,'manifest.json'),simplifyVector=TRUE)
stopifnot(all(vapply(seq_len(nrow(wm)),function(i)digest::digest(file=file.path(water_root,wm$file[i]),algo='sha256')==wm$sha256[i],logical(1))))
base<-st_read(file.path(root,'hex_8.gpkg'),quiet=TRUE)
saved<-st_read(file.path(root,'hex_8_temps.gpkg'),quiet=TRUE)
hot<-st_read(file.path(root,'hex_8_hot_pixels.gpkg'),quiet=TRUE)
clean<-saved[!is.na(saved$name)&!st_is_empty(saved),]
stopifnot(!anyDuplicated(clean$name),!anyDuplicated(hot$name),setequal(clean$name,hot$name),!anyDuplicated(base$name))
clean<-clean[match(hot$name,clean$name),]
current<-targets::tar_read(h8_geometry);pop<-targets::tar_read(dam_inputs)$population
stopifnot(!anyDuplicated(current$h3_id),setequal(current$h3_id,pop$h3_id))
current<-current[match(pop$h3_id,current$h3_id),];current<-st_transform(current,32614)
old<-st_transform(hot,32614)
matched<-match(current$h3_id,base$name)
geometry_check<-data.frame(h3_id=current$h3_id,peter_match=!is.na(matched),
 total_population=pop$total_population,children_under_18=pop$children_under_18)
common<-which(!is.na(matched))
bp<-st_transform(base,32614)
geometry_check$full_geometry_difference_m2<-NA_real_
geometry_check$full_geometry_difference_m2[common]<-vapply(common,function(i)as.numeric(st_area(st_sym_difference(st_geometry(current)[i],st_geometry(bp)[matched[i]]))),numeric(1))
water<-bind_rows(lapply(wm$file,function(f){x<-st_read(paste0('/vsizip/',normalizePath(file.path(water_root,f))),quiet=TRUE);st_sf(geometry=st_geometry(st_transform(x,32614)))}))
water<-st_make_valid(water[lengths(st_intersects(water,current))>0,])
mask<-st_union(water)
land<-st_sf(h3_id=current$h3_id,geometry=st_difference(st_geometry(current),mask))
stopifnot(all(st_is_valid(land)),all(!st_is_empty(land)))
geometry_check$land_share<-as.numeric(st_area(land)/st_area(current))
geometry_check$land_geometry_difference_m2<-NA_real_
k<-match(current$h3_id,hot$name);both<-which(!is.na(k))
geometry_check$land_geometry_difference_m2[both]<-vapply(both,function(i)as.numeric(st_area(st_sym_difference(st_geometry(land)[i],st_geometry(old)[k[i]]))),numeric(1))
write.csv(geometry_check,file.path(out,'geometry_audit.csv'),row.names=FALSE,na='')
write.csv(geometry_check[!geometry_check$peter_match,],file.path(out,'missing_from_peter_grid.csv'),row.names=FALSE,na='')
cat('Geometry checked:',nrow(current),'current cells;',sum(!geometry_check$peter_match),'absent from Peter grid.\n')
rasters<-list.files(file.path(root,'raw_data'),pattern='tif$',full.names=TRUE)
dates<-as.Date(substr(basename(rasters),9,18));stopifnot(!anyDuplicated(dates))
template<-rast(rasters[1]);stopifnot(all(vapply(rasters,function(f)compareGeom(rast(f),template,stopOnError=FALSE),logical(1))))
# One sparse exact-area crosswalk, reused for all dates and both geographies.
geom<-st_sf(key=c(paste0('peter:',hot$name),paste0('current:',current$h3_id)),
 geometry=c(st_geometry(old),st_geometry(land)))
cache<-file.path(out,'extraction_cache.rds')
signature<-digest::digest(list(geometry=st_as_binary(st_geometry(geom)),files=manifest$files$sha256,water=wm$sha256))
if(file.exists(cache)&&identical(readRDS(cache)$signature,signature)) {
 extract<-readRDS(cache);counts<-extract$counts;means<-extract$means;hot_counts<-extract$hot_counts;area_pixels<-extract$area_pixels;scene_stats<-extract$scene_stats
} else {
 e<-terra::extract(template,vect(geom),cells=TRUE,exact=TRUE)
 e<-e[!is.na(e$cell)&e$fraction>0,];cells<-sort(unique(e$cell))
 W<-sparseMatrix(i=e$ID,j=match(e$cell,cells),x=e$fraction,dims=c(nrow(geom),length(cells)))
 area_pixels<-as.numeric(rowSums(W));rm(e);gc()
 counts<-means<-hot_counts<-matrix(NA_real_,nrow(geom),length(rasters));scene_stats<-list()
 for(j in seq_along(rasters)) {
  r<-rast(rasters[j]);v<-values(r,mat=FALSE);all_valid<-is.finite(v)
  scene_stats[[j]]<-data.frame(date=dates[j],file=basename(rasters[j]),valid_raster_pixels=sum(all_valid),
   minimum_kelvin=if(any(all_valid))min(v[all_valid])else NA_real_,maximum_kelvin=if(any(all_valid))max(v[all_valid])else NA_real_)
  v<-v[cells];valid<-is.finite(v);fahrenheit<-(v-273.15)*9/5+32;fahrenheit[!valid]<-0
  counts[,j]<-as.numeric(W%*%as.numeric(valid));hot_counts[,j]<-as.numeric(W%*%as.numeric(valid & fahrenheit>=120))
  means[,j]<-as.numeric(W%*%fahrenheit)/counts[,j];means[counts[,j]==0,j]<-NA_real_
  cat('Extracted',as.character(dates[j]),'\n')
 }
 scene_stats<-bind_rows(scene_stats)
 saveRDS(list(signature=signature,counts=counts,means=means,hot_counts=hot_counts,area_pixels=area_pixels,scene_stats=scene_stats),cache)
}
colnames(counts)<-colnames(means)<-colnames(hot_counts)<-as.character(dates)
stopifnot(all(hot_counts>=0),all(hot_counts<=counts+1e-7),all(counts>=0))
# Reproduce the hot-pixel product on exactly Peter's saved land geometry.
np<-nrow(hot);pm<-means[seq_len(np),];pc<-counts[seq_len(np),];ph<-hot_counts[seq_len(np),]
max_finite<-function(v)if(any(is.finite(v)))max(v[is.finite(v)])else NA_real_
compare<-list()
for(j in seq_along(dates)) {
 suffix<-format(dates[j],'%m_%d_%Y');f<-paste0('tot_pixels_',suffix)
 if(!f%in%names(hot))next
 valid<-pc[,j]>1e-9
 compare[[length(compare)+1]]<-data.frame(date=dates[j],
  max_count_difference=max(abs(pc[,j]-hot[[f]]),na.rm=TRUE),
  max_hot_count_difference=max(abs(ph[,j]-hot[[paste0('hot_pixels_',suffix)]]),na.rm=TRUE),
  max_mean_difference_F=max_finite(abs(pm[valid,j]-clean[[paste0('mean_',suffix)]][valid])))
}
reconciliation<-bind_rows(compare)
# Equal-cell empirical CDF, keeping ties together, and equal weighting across valid dates.
percentile<-function(x) {r<-rep(NA_real_,length(x));ok<-is.finite(x);if(any(ok))r[ok]<-100*rank(x[ok],ties.method='max')/sum(ok);r}
relative<-function(m,c,eligible) {
 rank_days<-vapply(seq_len(ncol(m)),function(j)percentile(ifelse(eligible[,j],m[,j],NA_real_)),numeric(nrow(m)))
 nd<-rowSums(is.finite(rank_days));av<-rowMeans(rank_days,na.rm=TRUE);av[nd==0]<-NA_real_
 list(date_ranks=rank_days,n_dates=nd,mean_percentile=av,percentile=percentile(av))
}
pr<-relative(pm,pc,pc>1)
# Saved ranks retain >45 pixels through August, but >1 in September.
# Verify that inferred historical rule instead of silently treating it as consistent.
historical_mask<-sweep(pc,2,ifelse(dates<as.Date('2026-09-01'),45,1),'>')
historical<-relative(pm,pc,historical_mask)
source_check<-data.frame(h3_id=hot$name,saved_rank=clean$tot_pctile,reconstructed_rank=pr$percentile,
 historical_rank=historical$percentile,historical_date_count=historical$n_dates,
 saved_rank_mean=clean$pctil_avg,reconstructed_rank_mean=pr$mean_percentile,
 saved_hot_share=hot$pct_hot,reconstructed_hot_share=100*rowSums(ph)/rowSums(pc),
 saved_date_count=clean$pctil_cnt,reconstructed_date_count=pr$n_dates)
stopifnot(max(abs(source_check$saved_rank-source_check$historical_rank),na.rm=TRUE)<1e-8,
 all(source_check$saved_date_count==source_check$historical_date_count),
 max(abs(source_check$saved_hot_share-source_check$reconstructed_hot_share),na.rm=TRUE)<1e-4,
 max(reconciliation$max_mean_difference_F,na.rm=TRUE)<1e-3)
write.csv(source_check,file.path(out,'peter_reconciliation.csv'),row.names=FALSE,na='')
write.csv(data.frame(saved_rows=nrow(saved),named_rows=nrow(clean),extra_rows=nrow(saved)-nrow(clean)),file.path(out,'source_row_audit.csv'),row.names=FALSE)
write.csv(reconciliation,file.path(out,'daily_reconciliation.csv'),row.names=FALSE,na='')
cat('Peter reconstruction max hot-share difference:',max(abs(source_check$saved_hot_share-source_check$reconstructed_hot_share),na.rm=T),'\n')
ix<-np+seq_len(nrow(current));cm<-means[ix,];cc<-counts[ix,];ch<-hot_counts[ix,]
land_pixels<-as.numeric(st_area(land))/prod(res(template))
coverage<-cc/land_pixels
stopifnot(all(coverage<=1.00001))
current_rank<-relative(cm,cc,cc>1)
all_hot<-100*rowSums(ch)/rowSums(cc)
# Quality comparator: at least half the land area observed on an eligible date.
quality_dates<-coverage>=.5
quality_rank<-relative(cm,cc,quality_dates)
quality_hot<-100*rowSums(ifelse(quality_dates,ch,0))/rowSums(ifelse(quality_dates,cc,0))
centers<-st_coordinates(h3jsr::cell_to_point(current$h3_id))
origins<-data.frame(h3_id=current$h3_id,longitude=centers[,1],latitude=centers[,2],
 total_population=pop$total_population,children_under_18=pop$children_under_18,
 peter_grid_match=!is.na(k),land_share=geometry_check$land_share,
 raster_extent_land_coverage=area_pixels[ix]/land_pixels,
 dates_any=rowSums(cc>0),dates_over_one_pixel=rowSums(cc>1),dates_half_land=rowSums(quality_dates),
 pixel_observation_coverage=rowSums(cc)/(land_pixels*length(rasters)),
 mean_temperature_F=rowSums(ifelse(is.finite(cm),cm*cc,0))/rowSums(cc),
 mean_daily_percentile=current_rank$mean_percentile,relative_rank=current_rank$percentile,hot_pixel_share=all_hot,
 quality_mean_daily_percentile=quality_rank$mean_percentile,quality_relative_rank=quality_rank$percentile,quality_hot_pixel_share=quality_hot)
# Hold the quality-rank reference fixed; show coverage separately for minimum date counts.
for(j in seq_along(dates)) {
 scene_stats$current_hexes_any[j]<-sum(cc[,j]>0);scene_stats$current_hexes_half_land[j]<-sum(quality_dates[,j]);
 scene_stats$current_land_coverage[j]<-sum(cc[,j])/sum(land_pixels)
}
write.csv(scene_stats,file.path(out,'scene_coverage.csv'),row.names=FALSE,na='')
long<-bind_rows(lapply(seq_along(dates),function(j)data.frame(h3_id=current$h3_id,date=dates[j],
 mean_F=cm[,j],valid_pixel_equivalents=cc[,j],hot_pixel_equivalents=ch[,j],land_coverage=coverage[,j])))
write.csv(long,file.path(out,'current_daily_values.csv'),row.names=FALSE,na='')
write.csv(origins,file.path(out,'current_heat_indicators.csv'),row.names=FALSE,na='')
print(reconciliation)
print(summary(origins[c('dates_any','dates_half_land','pixel_observation_coverage','relative_rank','hot_pixel_share','quality_hot_pixel_share')]))
cat('Current indicator reconstruction saved in',out,'\n')
