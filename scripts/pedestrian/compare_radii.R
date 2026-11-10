.libPaths(c('.R-library', .libPaths()))
suppressPackageStartupMessages({library(sf); library(ggplot2); library(patchwork)})
source('R/pedestrian_gaps.R')
root <- 'output/components/pedestrian-gaps'
out <- file.path(root, 'radius-comparison')
dir.create(out, recursive=TRUE, showWarnings=FALSE)
r <- readRDS(file.path(root, 'analysis.rds'))
pop <- as.data.frame(targets::tar_read(dam_inputs)$population)
crashes <- st_transform(targets::tar_read(crash_points), st_crs(r$hex_geometry))
stopifnot(all(crashes$ksi_crash), all(crashes$crash_year %in% 2020:2024),
          !anyDuplicated(crashes$crash_id), !anyNA(crashes$crash_id))
centers <- st_sf(h3_id=r$hex_geometry$h3_id,
  geometry=st_transform(h3jsr::cell_to_point(r$hex_geometry$h3_id), st_crs(r$hex_geometry)))
results <- list(); window_list <- list()
for (radius in c(.25, .5, 1)) {
  cat('Radius:', radius, 'miles\n')
  full <- st_buffer(centers, radius*1609.344, nQuadSegs=90)
  windows <- suppressWarnings(st_intersection(full, r$network$city))
  windows <- windows[!st_is_empty(windows) & as.numeric(st_area(windows))>0, ]
  stopifnot(!anyDuplicated(windows$h3_id))
  # Reuse the exact baseline overlay; measure smaller windows from the same network.
  gaps <- if(radius==1) r$neighborhood else measure_pedestrian_windows(windows, r$network)
  hits <- st_intersects(windows, crashes)
  count <- function(flag=rep(TRUE,nrow(crashes)))
    vapply(hits, function(i) sum(flag[i]), integer(1))
  area <- as.numeric(st_area(windows))/2589988.110336
  d <- data.frame(h3_id=windows$h3_id, radius_miles=radius,
    observed_area_sqmi=area,
    observed_area_share=area/(as.numeric(st_area(full))[match(windows$h3_id,full$h3_id)]/2589988.110336),
    ksi_count_2020_2024=count(), vru_ksi_count_2020_2024=count(crashes$vulnerable_road_user_ksi_crash),
    ksi_count_2020_2022=count(crashes$crash_year<=2022),
    ksi_count_2023_2024=count(crashes$crash_year>=2023))
  d$annual_ksi_density <- d$ksi_count_2020_2024/(5*area)
  d$annual_vru_ksi_density <- d$vru_ksi_count_2020_2024/(5*area)
  d <- merge(d, gaps[,c('h3_id','gap_score','denominator_m','status')],by='h3_id',all.x=TRUE,sort=FALSE)
  # Keep origins without any City observation area as unavailable, never zero crashes.
  d <- merge(data.frame(h3_id=centers$h3_id),d,by='h3_id',all.x=TRUE,sort=FALSE)
  d$radius_miles <- radius
  d$status[is.na(d$observed_area_sqmi)] <- 'no_city_observation_area'
  d <- merge(d,pop[,c('h3_id','total_population','children_under_18')],by='h3_id',all.x=TRUE,sort=FALSE)
  results[[as.character(radius)]] <- d
  windows$radius_miles <- radius
  window_list[[as.character(radius)]] <- windows
}
d <- do.call(rbind,results); rownames(d)<-NULL
write.csv(d,file.path(out,'origin_results.csv'),row.names=FALSE,na='')
summary <- do.call(rbind,lapply(results,function(x){
  ok <- is.finite(x$annual_ksi_density); populated <- ok & is.finite(x$total_population) & x$total_population>0
  goodgap <- is.finite(x$gap_score)
  data.frame(radius_miles=x$radius_miles[1], crash_available=sum(ok), gap_available=sum(goodgap),
    zero_crash_windows=sum(x$ksi_count_2020_2024[ok]==0),
    zero_crash_percent=100*mean(x$ksi_count_2020_2024[ok]==0),
    populated_origins=sum(populated), populated_zero_crash_percent=100*mean(x$ksi_count_2020_2024[populated]==0),
    residents_in_zero_crash_windows_percent=100*sum(x$total_population[populated & !is.na(x$ksi_count_2020_2024) & x$ksi_count_2020_2024==0])/sum(x$total_population[populated]),
    median_ksi_count=median(x$ksi_count_2020_2024[ok]),
    fewer_than_5_crashes_percent=100*mean(x$ksi_count_2020_2024[ok]<5),
    median_annual_ksi_density=median(x$annual_ksi_density[ok]),
    temporal_density_spearman=cor(x$ksi_count_2020_2022/x$observed_area_sqmi/3,x$ksi_count_2023_2024/x$observed_area_sqmi/2,method='spearman',use='complete.obs'),
    median_gap_score=median(x$gap_score[goodgap]),
    median_network_m=median(x$denominator_m[goodgap]),
    gap_known_residents_percent=100*sum(x$total_population[goodgap],na.rm=TRUE)/sum(x$total_population,na.rm=TRUE),
    observed_area_below_half=sum(x$observed_area_share<.5,na.rm=TRUE))
}))
write.csv(summary,file.path(out,'summary.csv'),row.names=FALSE)
comparisons <- do.call(rbind,lapply(list(c(.25,.5),c(.5,1),c(.25,1)),function(pair){
  a<-results[[as.character(pair[1])]];b<-results[[as.character(pair[2])]]
  m<-merge(a,b,by='h3_id',suffixes=c('_a','_b'))
  do.call(rbind,lapply(c('annual_ksi_density','gap_score'),function(v){
    x<-m[[paste0(v,'_a')]];y<-m[[paste0(v,'_b')]];ok<-is.finite(x)&is.finite(y);x<-x[ok];y<-y[ok]
    # Diagnostic within-pair percentile ranks; these are NOT adopted crash scores.
    px<-100*(rank(x,ties.method='average')-1)/(length(x)-1)
    py<-100*(rank(y,ties.method='average')-1)/(length(y)-1)
    tx<-x>=quantile(x,.9);ty<-y>=quantile(y,.9)
    data.frame(radius_a=pair[1],radius_b=pair[2],measure=v,paired_origins=length(x),
      spearman=cor(x,y,method='spearman'),median_absolute_percentile_change=median(abs(px-py)),
      median_absolute_raw_change=median(abs(x-y)),top_decile_shared=sum(tx&ty),
      top_decile_a=sum(tx),top_decile_b=sum(ty))
  }))
}))
write.csv(comparisons,file.path(out,'comparisons.csv'),row.names=FALSE)
saveRDS(list(results=results,windows=window_list,summary=summary,comparisons=comparisons),file.path(out,'analysis.rds'))
jsonlite::write_json(list(radii_miles=c(.25,.5,1),crs=st_crs(centers)$epsg,crash_years=2020:2024,
  crash_definition='Unique crashes with at least one fatality or suspected serious injury; all road users',
  observation='City full- and limited-purpose portion of circular H3-center buffer; not walking-network distance',
  gap_source=r$network$source_manifest,
  status='Radius sensitivity only; no final radius or crash-score transformation adopted',
  caveats=c('Crash density is per observed square mile, not per traveler or mile traveled',
    'Zero recorded crashes does not establish safety; fewer than five is a diagnostic, not a reliability cutoff',
    'Temporal comparison uses 2020-2022 versus 2023-2024, not equal periods or an independent validation',
    'Whole-hex population is assigned to origin windows; unknown population is excluded',
    'Overlapping windows are not independent; network inventory gaps do not assess crossings or ADA conditions')),
  file.path(out,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,na='null')
# Core invariants: same origins, nested observation area and crash counts, bounded gap measures.
stopifnot(nrow(d)==3*nrow(centers), !anyDuplicated(paste(d$h3_id,d$radius_miles)),
          all(d$gap_score[is.finite(d$gap_score)]>=0 & d$gap_score[is.finite(d$gap_score)]<=100))
for(pair in list(c(.25,.5),c(.5,1))){
  m<-merge(results[[as.character(pair[1])]],results[[as.character(pair[2])]],by='h3_id')
  stopifnot(all(m$ksi_count_2020_2024.x<=m$ksi_count_2020_2024.y,na.rm=TRUE),
            all(m$observed_area_sqmi.x<=m$observed_area_sqmi.y+1e-8,na.rm=TRUE))
}
# Independently verify counts using distances to centers and City membership.
inside<-lengths(st_intersects(crashes,r$network$city))>0
for(radius in c(.25,.5,1)){
  x<-results[[as.character(radius)]]
  for(i in c(100,500,900)){
    dist<-as.numeric(st_distance(centers[i,],crashes))
    expected<-sum(inside & dist<=radius*1609.344)
    actual<-x$ksi_count_2020_2024[match(centers$h3_id[i],x$h3_id)]
    stopifnot(is.na(actual) || actual==expected)
  }
}
labels<-c('0.25'='¼ mile','0.5'='½ mile','1'='1 mile')
d$radius_label<-factor(labels[as.character(d$radius_miles)],levels=unname(labels))
geo<-merge(r$hex_geometry,d,by='h3_id')
geo$crash_display<-log1p(geo$annual_ksi_density)
map_theme<-theme_void(base_size=11)+theme(strip.text=element_text(face='bold'),legend.position='bottom')
p1<-ggplot(geo)+geom_sf(aes(fill=gap_score),color=NA)+facet_wrap(~radius_label,nrow=1)+
  scale_fill_viridis_c(option='magma',direction=-1,limits=c(0,100),na.value='#b8bfc2',name='Gap score')+
  labs(title='Pedestrian gaps: missing share of the planned network')+map_theme
ticks<-c(0,1,5,10,25,50,100)
p2<-ggplot(geo)+geom_sf(aes(fill=crash_display),color=NA)+facet_wrap(~radius_label,nrow=1)+
  scale_fill_viridis_c(option='magma',direction=-1,breaks=log1p(ticks),labels=ticks,na.value='#b8bfc2',name='Annual KSI crashes / sq. mile')+
  labs(title='Fatal and serious-injury crash density, 2020–2024',subtitle='Logarithmic color spacing for display only; no scoring transformation adopted')+map_theme
ggsave(file.path(out,'radius_maps.png'),p1/p2+plot_annotation(title='Smaller windows show more local variation',
  caption='Same City-clipped circular windows for both measures. Colors are comparable across radii within each row.\nValues assigned to hex centers; gray = unavailable. Crash density is not adjusted for travel exposure.'),width=12,height=12,dpi=160)
esc<-function(x){x<-gsub('&','&amp;',as.character(x),fixed=TRUE);gsub('<','&lt;',x,fixed=TRUE)}
tab<-function(x){x[]<-lapply(x,function(v)if(is.numeric(v))round(v,2)else v);paste0('<table><tr>',paste0('<th>',esc(names(x)),'</th>',collapse=''),'</tr>',paste(apply(x,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table>')}
writeLines(paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Street safety radius comparison</title><style>body{font:17px/1.5 system-ui;max-width:1150px;margin:35px auto;padding:0 24px;color:#18343e}img{max-width:100%}table{display:block;overflow:auto;border-collapse:collapse;font-size:13px}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}a{color:#176484}</style><h1>Crash and pedestrian-gap radius comparison</h1><p>1,029 H3 origins · City-clipped ¼-, ½- and 1-mile circles · fatal and suspected serious-injury crashes, 2020–2024 · pedestrian inventory, November 9, 2026</p><p>Both measures use the same observation window at each radius. Crash density is annual crashes per observed square mile, not exposure-adjusted risk. Pedestrian gap score is 100 × planned / (completed + planned) length. Potential sidewalks remain a separate sensitivity in the original analysis.</p><img src="radius_maps.png" alt="Maps comparing pedestrian gaps and serious crash density at three radii"><h2>Distribution and sparse counts</h2>',tab(summary),'<p>Fewer than five crashes is a descriptive diagnostic, not an adopted reliability threshold. Zero recorded crashes does not establish safety. Population is the estimate for each origin’s whole hex; 71 origins lack population estimates. Tiny City-clipped windows can have volatile densities; observation areas and shares are exported.</p><h2>Ranking sensitivity</h2>',tab(comparisons),'<p>Percentile ranks are diagnostics, not adopted scores. The top-decile comparison uses paired available origins and includes ties. Temporal rank correlation compares annual densities in 2020–2022 with 2023–2024; different periods, pandemic conditions and overlapping windows limit interpretation. It does not constitute independent validation.</p><p>No final radius, crash transform, or combined street-safety score is adopted by this comparison. Existing 50/50 component weights remain the agreed approach.</p><p><a href="origin_results.csv">Origin results</a> · <a href="summary.csv">Summary</a> · <a href="comparisons.csv">Ranking comparison</a> · <a href="metadata.json">Methods</a> · <a href="../review.html">Original inventory review</a></p></html>'),file.path(out,'review.html'))
print(summary); print(comparisons)
cat('Radius comparison and validation complete.\n')
