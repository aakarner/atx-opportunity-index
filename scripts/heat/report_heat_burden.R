.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
root<-'output/components/heat-burden';r<-readRDS(file.path(root,'analysis.rds'));x<-r$scores
classes<-c('Below flag','Below flag; limited observations','High heat','High heat; limited observations','Unavailable')
labels<-c('Below high-heat flag','Below flag; fewer than 8 dates','High heat','High heat; fewer than 8 dates','Unavailable')
counts<-data.frame(class=classes,origins=vapply(classes,function(k)sum(x$heat_review_class==k),integer(1)))
write.csv(counts,file.path(root,'flag_counts.csv'),row.names=FALSE)
groups<-list(scored=is.finite(x$heat_score),high_heat=x$heat_high,limited_observations=x$heat_thin_coverage,
  high_heat_and_limited=x$heat_high & x$heat_thin_coverage)
coverage<-do.call(rbind,lapply(names(groups),function(k)do.call(rbind,lapply(c('total_population','children_under_18'),function(n){
  use<-groups[[k]] %in% TRUE;w<-x[[n]];known<-is.finite(w)
  data.frame(group=k,population_measure=n,origins=sum(use),known_population=sum(w[known]),
    population_in_group=sum(w[known&use]),percent_known_population=100*sum(w[known&use])/sum(w[known]),
    unknown_population_origins=sum(!known))
}))))
write.csv(coverage,file.path(root,'population_coverage.csv'),row.names=FALSE)
q<-quantile(x$heat_score,c(0,.25,.5,.75,.9,1),na.rm=TRUE)
summary<-data.frame(metric=c('Origins scored','High relative heat','Limited observations','High heat with limited observations',
  'Median heat score','Minimum eligible dates','Median eligible dates','Maximum eligible dates'),
  value=c(sum(is.finite(x$heat_score)),sum(x$heat_high,na.rm=TRUE),sum(x$heat_thin_coverage,na.rm=TRUE),
    sum(x$heat_high&x$heat_thin_coverage,na.rm=TRUE),q[3],min(x$dates_half_land),median(x$dates_half_land),max(x$dates_half_land)))
write.csv(summary,file.path(root,'summary.csv'),row.names=FALSE)
geo<-merge(st_transform(r$geometry,26914),x,by='h3_id',sort=FALSE)
geo$review<-factor(geo$heat_review_class,levels=classes,labels=labels)
theme_map<-theme_void(base_size=12)+theme(plot.title=element_text(face='bold'),legend.position='bottom',plot.margin=margin(12,12,12,12))
p1<-ggplot(geo)+geom_sf(aes(fill=heat_score),color=NA)+
  scale_fill_viridis_c(option='magma',direction=-1,limits=c(0,100),na.value='#b5bdc1',name='Heat burden score')+
  labs(title='Relative daytime surface heat')+theme_map
p2<-ggplot(geo)+geom_sf(aes(fill=review),color=NA)+
  scale_fill_manual(values=setNames(c('#dce5e5','#6e9fae','#cf543d','#713c87','#b5bdc1'),labels),name=NULL)+
  guides(fill=guide_legend(ncol=1))+
  labs(title='High heat and observation quality')+theme_map
p<-p1+p2+plot_annotation(title='Heat burden | Adopted prototype score',
  subtitle='High heat: score at least 90. Scores retained and flagged when fewer than 8 dates qualify.',
  caption='2026 daytime satellite observations; at least half the land area must be observed for a date to qualify.\nFull hexagons shown; calculations exclude water. Relative surface temperature is not air temperature or a health-risk threshold.')
ggsave(file.path(root,'heat_map.png'),p,width=12,height=8,dpi=160,bg='white')
ggsave(file.path(root,'heat_map.pdf'),p,width=12,height=8)
x$quality<-ifelse(x$heat_thin_coverage,'Fewer than 8 dates','At least 8 dates')
p3<-ggplot(x,aes(heat_score,fill=quality))+geom_histogram(binwidth=10,boundary=0,color='white')+
  scale_fill_manual(values=c('At least 8 dates'='#356e80','Fewer than 8 dates'='#d5a448'),name=NULL)+
  geom_vline(xintercept=90,linetype=2,color='#c64638')+coord_cartesian(xlim=c(0,100))+
  labs(title='Score distribution',subtitle='Approximately uniform by construction: this is a percentile',x='Heat burden score',y='Hexagons')+
  theme_minimal(base_size=12)+theme(legend.position='bottom')
p4<-ggplot(x,aes(dates_half_land,fill=heat_high))+geom_bar()+
  scale_fill_manual(values=c('FALSE'='#6e9fae','TRUE'='#cf543d'),labels=c('Below high-heat flag','High heat'),name=NULL)+
  geom_vline(xintercept=7.5,linetype=2)+scale_x_continuous(breaks=4:13)+
  labs(title='Eligible observation dates',subtitle='Dashed line separates limited-observation flags',x='Dates with at least 50% land coverage',y='Hexagons')+
  theme_minimal(base_size=12)+theme(legend.position='bottom')
ggsave(file.path(root,'distribution.png'),p3+p4,width=11,height=5.5,dpi=160,bg='white')
# Context remains unweighted in the heat score; do not add it as another burden.
p5<-ggplot(x,aes(heat_score,quality_hot_pixel_share,color=quality))+geom_point(alpha=.6,size=1.5)+
  scale_color_manual(values=c('At least 8 dates'='#356e80','Fewer than 8 dates'='#d5a448'),name=NULL)+
  geom_vline(xintercept=90,linetype=2)+labs(title='Extreme surface heat as context',
    subtitle='Hot-pixel share is displayed, but contributes no additional score',x='Heat burden score',
    y='Observed pixel-date area at or above 120 F (%)')+theme_minimal(base_size=12)+theme(legend.position='bottom')
ggsave(file.path(root,'hot_pixel_context.png'),p5,width=8,height=5.5,dpi=160,bg='white')
esc<-function(v){v<-gsub('&','&amp;',as.character(v),fixed=TRUE);gsub('<','&lt;',v,fixed=TRUE)}
tab<-function(d){d[]<-lapply(d,function(v)if(is.numeric(v))round(v,2)else v);paste0('<div class="scroll"><table><tr>',paste0('<th>',esc(names(d)),'</th>',collapse=''),'</tr>',paste(apply(d,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table></div>')}
pop_display<-coverage[coverage$group!='scored',c('group','population_measure','population_in_group','percent_known_population')]
html<-paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Heat burden score</title><style>body{font:17px/1.5 system-ui;max-width:1120px;margin:36px auto;padding:0 24px;color:#18343e}h1,h2{line-height:1.2}img{max-width:100%;height:auto}table{border-collapse:collapse;font-size:14px}.scroll{overflow:auto}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}.note{background:#edf3f5;border-left:4px solid #39728a;padding:18px}a{color:#176484}</style><h1>Heat burden score</h1><p>Adopted November 10, 2026 · 1,029 current hexagons · Daytime satellite observations, May–September 2026</p><div class="note"><b>Heat score = reconstructed relative percentile, on a 0–100 scale.</b> Higher indicates relatively hotter daytime land surfaces. Flag high heat at score ≥90. Retain scores and add a limited-observation flag for fewer than eight eligible dates. At least 50% of each hex’s land area must have valid observations for a date to qualify.</div><img src="heat_map.png" alt="Relative heat burden map and separate high-heat and limited-observation flags"><h2>Results</h2>',tab(summary),'<p>Of 103 high-heat hexes, 82 have at least eight eligible dates and 21 have fewer. All 1,029 origins have a score. A low score means relatively cooler within this reference, not that conditions are safe.</p>',tab(counts),'<h2>Population represented</h2>',tab(pop_display),'<p>All known estimated population is assigned a heat score. Population summaries use whole-hex estimates, not actual temperature exposure; 71 origins have unknown population and are excluded from population denominators. Child population means residents under 18.</p><h2>Score and observation distributions</h2><img src="distribution.png" alt="Heat score histogram and number of observation dates"><p>The median is approximately 50 by construction. That is a relative position, not a measure of absolute thermal severity. Eligible-date counts range from four to thirteen (median eight). Limited observations are a coverage warning, not a formal statistical confidence interval.</p><h2>Hot-pixel context</h2><img src="hot_pixel_context.png" alt="Heat score versus observed hot-pixel share"><p>The share above 120°F pools valid pixel-area observations on eligible dates. It is not the share of days, residents, or fixed land area above that temperature. It is context only and has no extra weight in the heat score. The temperature is land-surface temperature, not an air-temperature health threshold.</p><h2>Method and reference</h2><p>For each eligible date, rank mean land-surface temperatures across observed current hexes using equal-hex empirical CDF ranks, keeping ties together. Average each hex’s available daily percentiles equally across dates, then rank those averages across all scored reference hexes. The adopted reference is pinned by input hashes. Display filters and observation flags never rerank surviving cells. An origin with no eligible observations would remain unavailable.</p><p>Scores describe one season of daytime satellite snapshots; they do not measure nighttime or indoor heat, personal exposure, or a long-term climate normal. Different observation dates and clear-pixel availability can affect rankings. Upstream cloud masking and completeness of scene selection were not independently reconstructed; the supplied rasters and extraction were validated in the preceding review.</p><p>Heat retains full-hex land support, rather than the half-mile circles used for street safety. This report does not combine heat with other burdens or benefits, and does not change flood eligibility. Air-pollution scoring and overall burden weights remain open.</p><p><a href="scores.csv">Scores, flags and context</a> · <a href="population_coverage.csv">Population summary</a> · <a href="daily_reference.csv">Eligible dates and daily ranks</a> · <a href="heat_burden.gpkg">GIS layer</a> · <a href="metadata.json">Frozen policy and provenance</a> · <a href="heat_map.pdf">PDF map</a> · <a href="../heat-validation/review.html">Earlier source validation</a></p></html>')
writeLines(html,file.path(root,'review.html'))
print(summary);print(counts);print(coverage)
