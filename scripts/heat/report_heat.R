# Compare validated heat measures, keeping unknown coverage explicit.
if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
suppressPackageStartupMessages({library(dplyr);library(tidyr);library(ggplot2);library(patchwork);library(sf)})
root<-'output/components/heat-validation'
x<-read.csv(file.path(root,'current_heat_indicators.csv'));daily<-read.csv(file.path(root,'current_daily_values.csv'))
scene<-read.csv(file.path(root,'scene_coverage.csv'));audit<-read.csv(file.path(root,'geometry_audit.csv'))
old<-read.csv(file.path(root,'peter_reconciliation.csv'));rec<-read.csv(file.path(root,'daily_reconciliation.csv'))
q<-function(v,w,p){ok<-is.finite(v)&is.finite(w)&w>0;o<-order(v[ok]);v<-v[ok][o];w<-w[ok][o];sapply(p,function(p)v[which(cumsum(w)/sum(w)>=p)[1]])}
percentile<-function(v){r<-rep(NA_real_,length(v));ok<-is.finite(v);r[ok]<-100*rank(v[ok],ties.method='max')/sum(ok);r}
coverage_rows<-list();k<-0
for(min_area in c(0,.25,.5,.75))for(min_days in c(1,5,8,10)){
 nd<-tapply(daily$land_coverage>=min_area & daily$valid_pixel_equivalents>1,daily$h3_id,sum)
 eligible<-nd[match(x$h3_id,names(nd))]>=min_days
 for(group in c('total_population','children_under_18')) {
  w<-x[[group]];known<-!is.na(w);k<-k+1
  coverage_rows[[k]]<-data.frame(minimum_land_fraction=min_area,minimum_dates=min_days,group,origins=sum(eligible),
    known_weight_total=sum(w[known]),covered_population=sum(w[known&eligible]),coverage_percent=100*sum(w[known&eligible])/sum(w[known]),
    missing_weight_origins=sum(!known))
 }
}
coverage<-bind_rows(coverage_rows);write.csv(coverage,file.path(root,'quality_coverage_sensitivity.csv'),row.names=FALSE)
# A transparent quality scenario for comparison, not an adopted exclusion rule.
use<-x$dates_half_land>=1 & is.finite(x$quality_relative_rank)&is.finite(x$quality_hot_pixel_share)
x$comparison_eligible<-use
x$thin_coverage_flag<-x$dates_half_land<8
x$comparison_relative_rank<-ifelse(use,x$quality_relative_rank,NA_real_)
x$comparison_hot_pixel_share<-ifelse(use,x$quality_hot_pixel_share,NA_real_)
# Fixed reference consists of all current origins with at least one half-land date.
# Minimum-date sensitivities subset this reference, never re-rank the survivors.
metrics<-c('relative_rank','hot_pixel_share','quality_relative_rank','quality_hot_pixel_share')
summary<-bind_rows(lapply(metrics,function(m) {
 keep<-if(startsWith(m,'quality'))use else is.finite(x[[m]])
 bind_rows(lapply(c('equal_hex','total_population','children_under_18'),function(g) {
  w<-if(g=='equal_hex')rep(1,nrow(x))else x[[g]];v<-ifelse(keep,x[[m]],NA_real_)
  z<-q(v,w,c(0,.1,.25,.5,.75,.9,1))
  data.frame(metric=m,weighting=g,min=z[1],p10=z[2],p25=z[3],median=z[4],p75=z[5],p90=z[6],max=z[7])
 }))
}))
correlations<-data.frame(comparison=c('All observations','Half-land dates; retain with coverage flags','Half-land dates; at least 8 dates'),
 n=c(sum(is.finite(x$relative_rank)&is.finite(x$hot_pixel_share)),sum(use),sum(x$dates_half_land>=8)),
 spearman=c(cor(x$relative_rank,x$hot_pixel_share,method='spearman',use='complete.obs'),cor(x$quality_relative_rank[use],x$quality_hot_pixel_share[use],method='spearman'),cor(x$quality_relative_rank[x$dates_half_land>=8],x$quality_hot_pixel_share[x$dates_half_land>=8],method='spearman')))
flags<-list('Relative rank >=75'=use & x$quality_relative_rank>=75,'Relative rank >=90'=use & x$quality_relative_rank>=90)
for(t in c(5,10,15,20))flags[[paste0('Hot-pixel share >=',t,'%')]]<-use & x$quality_hot_pixel_share>=t
thresholds<-bind_rows(lapply(names(flags),function(n)bind_rows(lapply(c('equal_hex','total_population','children_under_18'),function(g){
 w<-if(g=='equal_hex')rep(1,nrow(x))else x[[g]];known<-!is.na(w)
 data.frame(rule=n,weighting=g,flagged_origins=sum(flags[[n]],na.rm=TRUE),
 flagged_weight=sum(w[known&flags[[n]]],na.rm=TRUE),scored_weight=sum(w[known&use]),all_known_weight=sum(w[known]),
 percent_of_scored=100*sum(w[known&flags[[n]]],na.rm=TRUE)/sum(w[known&use]),percent_of_all_known=100*sum(w[known&flags[[n]]],na.rm=TRUE)/sum(w[known]))
}))))
# Compare matched-tail definitions to separate differences in ordering from cutoff strictness.
overlap<-list()
for(p in c(.75,.9)){
 t<-min(x$quality_hot_pixel_share[percentile(x$quality_hot_pixel_share)>=100*p])
 a<-use & x$quality_relative_rank>=100*p;b<-use & x$quality_hot_pixel_share>=t
 cls<-ifelse(!use,'Unavailable',ifelse(a&b,'Both',ifelse(a,'Relative rank only',ifelse(b,'Hot-pixel share only','Neither'))))
 x[[paste0('comparison_',100*p)]]<-cls
 for(g in c('equal_hex','total_population','children_under_18')){
  w<-if(g=='equal_hex')rep(1,nrow(x))else x[[g]];known<-!is.na(w)
  for(label in unique(cls))overlap[[length(overlap)+1]]<-data.frame(percentile=100*p,hot_share_cutoff=t,weighting=g,classification=label,
    origins=sum(cls==label),weight=sum(w[known & cls==label]),percent_all_known=100*sum(w[known&cls==label])/sum(w[known]),
    percent_scored=if(label=='Unavailable')NA_real_ else 100*sum(w[known&cls==label])/sum(w[known&use]))
 }
}
overlap<-bind_rows(overlap)
x$hot_share_percentile<-ifelse(use,percentile(ifelse(use,x$quality_hot_pixel_share,NA_real_)),NA_real_)
x$rank_difference<-x$comparison_relative_rank-x$hot_share_percentile
outliers<-x[order(abs(x$rank_difference),decreasing=TRUE),c('h3_id','longitude','latitude','total_population','dates_half_land','comparison_relative_rank','comparison_hot_pixel_share','hot_share_percentile','rank_difference')]
outliers<-head(outliers,20)
quality_change<-data.frame(metric=c('Relative rank','Hot-pixel share'),
 spearman=c(cor(x$relative_rank[use],x$quality_relative_rank[use],method='spearman'),cor(x$hot_pixel_share[use],x$quality_hot_pixel_share[use],method='spearman')),
 median_absolute_change=c(median(abs(x$relative_rank[use]-x$quality_relative_rank[use])),median(abs(x$hot_pixel_share[use]-x$quality_hot_pixel_share[use]))))
# Same broad-coverage date subset reduces differences in which days were observed.
broad_dates<-scene$date[scene$current_land_coverage>=.8]
broad<-daily %>% filter(date %in% broad_dates,land_coverage>=.5) %>%
 group_by(date) %>% mutate(daily_rank=percentile(mean_F)) %>% group_by(h3_id) %>%
 summarise(n_dates=n(),mean_rank=mean(daily_rank),hot_share=100*sum(hot_pixel_equivalents)/sum(valid_pixel_equivalents),.groups='drop') %>%
 mutate(relative_rank=percentile(mean_rank))
broad<-broad[match(x$h3_id,broad$h3_id),]
scene_sensitivity<-data.frame(metric=c('Relative rank','Hot-pixel share'),dates=paste(broad_dates,collapse='; '),
 spearman=c(cor(broad$relative_rank,x$quality_relative_rank,method='spearman'),cor(broad$hot_share,x$quality_hot_pixel_share,method='spearman')),
 median_absolute_change=c(median(abs(broad$relative_rank-x$quality_relative_rank)),median(abs(broad$hot_share-x$quality_hot_pixel_share))))
tables<-list(metric_distributions=summary,metric_correlations=correlations,threshold_comparison=thresholds,
 matched_tail_overlap=overlap,largest_rank_differences=outliers,quality_filter_effect=quality_change,comparison_origins=x,
 broad_date_sensitivity=scene_sensitivity,broad_date_origins=broad)
for(n in names(tables))write.csv(tables[[n]],file.path(root,paste0(n,'.csv')),row.names=FALSE,na='')
# Scientific figures: scatter, cumulative observation coverage, and spatial comparison.
p1<-ggplot(x[use,],aes(quality_relative_rank,quality_hot_pixel_share,color=dates_half_land))+
 geom_point(alpha=.65,size=1.6)+scale_color_viridis_c(option='C')+
 geom_vline(xintercept=c(75,90),linetype='dashed',color='grey60')+
 labs(title='Relative heat ranking and hot-pixel share',subtitle=paste0(sum(use),' current hexagons; ',sum(x$thin_coverage_flag),' have fewer than 8 well-observed dates'),
 x='Relative heat percentile (higher = hotter)',y='Valid pixel observations at or above 120 F (%)',color='Eligible\ndates',
 caption='Comparison rule: at least 50% of land observed per date; fewer than 8 dates flagged. Not an adopted scoring rule.')+
 theme_minimal(base_size=12)+theme(plot.margin=margin(15,15,15,15))
p2<-ggplot(scene,aes(as.Date(date),100*current_land_coverage))+
 geom_col(fill='#27677c',width=5)+scale_x_date(date_breaks='1 month',date_labels='%b')+
 labs(title='Observation coverage varies substantially by date',x='Committed Landsat observation date, 2026',y='Current land area with valid pixels (%)',
 caption='Seventeen committed scenes. Valid-pixel coverage reflects the supplied raster masks, not all days in the season.')+
 theme_minimal(base_size=12)+theme(plot.margin=margin(15,15,15,15))
ggsave(file.path(root,'heat-scatter.png'),p1,width=9,height=6.3,dpi=160,bg='white')
fig<-p1/p2+plot_layout(heights=c(1.4,1))
ggsave(file.path(root,'heat-comparison.png'),fig,width=9,height=10,dpi=160,bg='white')
ggsave(file.path(root,'heat-comparison.pdf'),fig,width=9,height=10)
geog<-targets::tar_read(h8_geometry);geog<-geog[match(x$h3_id,geog$h3_id),];geog<-st_transform(geog,32614)
map_data<-st_sf(x,geometry=st_geometry(geog))
m1<-ggplot(map_data)+geom_sf(aes(fill=comparison_relative_rank),linewidth=0)+scale_fill_viridis_c(limits=c(0,100),na.value='grey85')+labs(title='Relative heat percentile',fill='Percentile')+theme_void()
m2<-ggplot(map_data)+geom_sf(aes(fill=comparison_hot_pixel_share),linewidth=0)+scale_fill_viridis_c(na.value='grey85')+labs(title='Hot-pixel share',fill='Percent')+theme_void()
m3<-ggplot(map_data)+geom_sf(aes(fill=comparison_75),linewidth=0)+scale_fill_manual(values=c('Both'='#7a4f8c','Relative rank only'='#27738b','Hot-pixel share only'='#d58d42','Neither'='#e2e9e6','Unavailable'='#a3adb2'))+labs(title='Upper-tail comparison',fill=NULL)+theme_void()
maps<-m1+m2+m3+plot_annotation(title='Heat on the current Austin prototype hexagons',subtitle='Full hexagons shown; indicators summarize land after removing Census water polygons',caption='Both upper tails contain 258 cells; 193 are shared. Coverage flags are retained in the accompanying origin table.')
ggsave(file.path(root,'heat-maps.png'),maps,width=15,height=7,dpi=160,bg='white')
ggsave(file.path(root,'heat-maps.pdf'),maps,width=15,height=7)
html_table<-function(d){d[]<-lapply(d,function(v)if(is.numeric(v))format(round(v,2),trim=TRUE,big.mark=',')else v)
 paste0('<div class="scroll"><table><thead><tr>',paste0('<th>',names(d),'</th>',collapse=''),'</tr></thead><tbody>',paste(apply(d,1,function(r)paste0('<tr>',paste0('<td>',r,'</td>',collapse=''),'</tr>')),collapse=''),'</tbody></table></div>')}
source_qa<-data.frame(check=c('Current origins','Matched Peter origins','Extra rows in saved ranking file','Maximum land-geometry difference, matched origins (m2)','Maximum reconstructed hot-share difference (percentage points)','Maximum reconstructed date-mean difference (F)'),
 value=c(nrow(x),sum(x$peter_grid_match),read.csv(file.path(root,'source_row_audit.csv'))$extra_rows,max(audit$land_geometry_difference_m2,na.rm=TRUE),max(abs(old$saved_hot_share-old$reconstructed_hot_share),na.rm=TRUE),max(rec$max_mean_difference_F,na.rm=TRUE)))
notes<-paste0('<p>Peter\'s acquisition script requests May 1 through September 30, 2026, scales Landsat values via rsi, and masks with QA_PIXEL. The committed rasters contain already-scaled Kelvin values; Fahrenheit is (K - 273.15) × 9/5 + 32. Applying the USGS digital-number scaling again would be incorrect. This audit reproduces the supplied rasters; original QA bands, STAC acquisition records and the original rsi package version are not committed, so source cloud masking and upstream scene completeness are not independently re-created.</p>',
 '<p>120 F is an exploratory land-surface-temperature threshold. It is not air temperature, heat index, an established safety limit, or a fixed conversion to 100 F air temperature. Hot share is a pooled share of valid pixel observations across satellite dates, not the share of days or residents experiencing extreme heat. Both indicators describe one season of daytime satellite snapshots; they do not measure nighttime heat or a long-term climate normal.</p>')
writeLines(paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Heat validation and indicator comparison</title><style>body{max-width:1100px;margin:40px auto;padding:0 20px;font:16px/1.55 system-ui;color:#243541}img{max-width:100%}table{border-collapse:collapse;font-size:13px}th,td{padding:8px;border-bottom:1px solid #ccd6dc;text-align:right}th{background:#edf3f4}.scroll{overflow:auto}.notice{background:#fff0db;padding:14px}</style><h1>Heat validation and indicator comparison</h1>',
 '<p>Source: Peter Haas\'s October 27 heat contribution, pinned to repository main commit d90d74f38a. All downloaded artifacts are checked against Git blob hashes and SHA-256. No source files are executed or overwritten.</p><h2>Validation</h2>',html_table(source_qa),
 '<p>The saved temperature-ranking layer has 12,890 records but only 1,372 named nonempty hexagon geometries. Filtered named rows have unique H3 IDs. Their saved final ranks reproduce exactly only when using more than 45 pixel-equivalents per date through August and more than one in September. The committed hex script uses more than one throughout. The comparison below reconstructs both indicators using a consistent half-land observation rule. Reconstructing from rasters avoids using sequential IDs or joining the extra empty rows. Peter\'s land geometries match current land geometries closely; the apparent full-hex differences are water removal. Seven current cells are absent from Peter\'s grid; their raster observations are extracted directly here.</p>',notes,
 '<h2>Coverage before scoring</h2>',html_table(coverage[coverage$minimum_land_fraction==.5,]),
 '<p>For the main comparison, each eligible date must observe at least half the cell\'s land area, and all cells with such observations are retained. Flag the 257 cells with fewer than eight dates; the eight-date exclusion appears as a sensitivity above. These are comparison scenarios, not adopted scoring rules. The relative-rank reference is fixed across current hexes with at least one eligible date; changing the minimum date count does not re-rank the survivors. Population weights are the same ACS-based whole-hex weights used in benefits. Unknown population is excluded from population denominators, not treated as zero.</p>',
 '<h2>Definitions and comparison</h2><p>Relative heat: rank each eligible date\'s mean land-surface temperature across current hexagons, average valid daily percentiles equally across dates, then rank those averages. Hot-pixel share: sum observed pixel-area fractions at or above 120 F and divide by all observed pixel-area fractions, using the same eligible dates. Thus hot share weights dates with more observed area more heavily. Both metrics use fractional pixel overlap, not nearest-pixel assignment.</p>',html_table(correlations),'<img src="heat-comparison.png" alt="Scatterplot comparing the heat measures and valid land coverage by satellite date">',
 '<img src="heat-maps.png" alt="Maps of relative heat, hot-pixel share, and their upper-tail agreement">',
 '<h2>Candidate flags</h2>',html_table(thresholds[thresholds$weighting%in%c('equal_hex','total_population'),]),
 '<h2>Matched upper-tail comparisons</h2>',html_table(overlap[overlap$weighting%in%c('equal_hex','total_population'),]),
 '<h2>Effect of filtering poorly observed dates</h2>',html_table(quality_change),
 '<h2>Sensitivity to observation dates</h2><p>Restricting to the four dates with at least 80% of current land observed (July 26, August 19, September 20, September 28) preserves the broad ranking, but individual locations can change. Cells have two to four eligible dates within this subset. Hot-share values are more sensitive to which dates are observed. This is a robustness check, not a substitute season or a complete common-date panel.</p>',html_table(scene_sensitivity),
 '<h2>Scoring options for discussion</h2><p>Recommended prototype: use the consistent relative percentile as a 0–100 heat-burden score (higher means more burden), retain hot-pixel share in the display, and flag fewer than eight well-observed dates. A 90th-percentile high-heat flag is a narrower candidate; 75th percentile is a broader sensitivity. These are local comparison thresholds, not health standards. If a combined index runs in the opposite direction, invert only at the combination step.</p><p>An absolute alternative is 100 × min(hot share / 20%, 1), with a candidate flag at 10% or 15%. Those choices are illustrative and require agreement about why 120 F and those shares should determine burden. Avoid counting both measures as independent heat components, which would increase heat’s weight. No scoring choice or public-map update is adopted by this report.</p>',
 '<h2>Distribution</h2>',html_table(summary),
 '<h2>References and reproduce</h2><p><a href="https://github.com/aakarner/atx-opportunity-index/tree/d90d74f38a70472418e59666ac86e9d5736efab5/scripts/prepare/surface_temp">Pinned Peter source</a> · <a href="https://www.usgs.gov/landsat-missions/landsat-collection-2-surface-temperature">USGS temperature scaling</a> · <a href="https://github.com/Permian-Global-Research/rsi/blob/main/R/get_stac_data.R">rsi acquisition defaults</a></p><p>Run fetch_peter_snapshot.py, validate_heat.R, and report_heat.R under scripts/heat. Detailed CSVs include per-date values, source reconciliation, geometry checks, thresholds, and population coverage.</p>',
 '<ul>',paste0('<li><a href="',names(tables),'.csv">',names(tables),'</a></li>',collapse=''),'<li><a href="quality_coverage_sensitivity.csv">Quality coverage sensitivities</a></li><li><a href="scene_coverage.csv">Scene coverage</a></li><li><a href="geometry_audit.csv">Geometry audit</a></li><li><a href="daily_reconciliation.csv">Daily source reconciliation</a></li></ul></html>'),file.path(root,'review.html'))
print(correlations);print(coverage[coverage$minimum_land_fraction==.5,]);print(thresholds[thresholds$weighting=='total_population',]);print(overlap[overlap$weighting=='total_population',]);print(quality_change)
