.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
root<-'output/components/street-safety';r<-readRDS(file.path(root,'analysis.rds'))
summary<-do.call(rbind,lapply(r$results,function(x){
  ok<-is.finite(x$street_safety_score);q<-quantile(x$street_safety_score[ok],c(0,.25,.5,.75,.9,1))
  data.frame(radius_miles=x$radius_miles[1],available=sum(ok),unavailable=sum(!ok),
    minimum=q[1],p25=q[2],median=q[3],p75=q[4],p90=q[5],maximum=q[6],
    crash_high=sum(x$crash_high,na.rm=TRUE),gap_high=sum(x$pedestrian_high,na.rm=TRUE),
    either_high=sum(x$any_high,na.rm=TRUE),both_high=sum(x$crash_high & x$pedestrian_high,na.rm=TRUE),
    high_with_missing_score=sum(x$any_high & !ok,na.rm=TRUE),
    incomplete_flag_assessment=sum(is.na(x$any_high)),
    known_residents_covered_percent=100*sum(x$total_population[ok],na.rm=TRUE)/sum(x$total_population,na.rm=TRUE),
    known_children_covered_percent=100*sum(x$children_under_18[ok],na.rm=TRUE)/sum(x$children_under_18,na.rm=TRUE),
    known_population=sum(x$total_population,na.rm=TRUE),unknown_population_origins=sum(is.na(x$total_population)))
}))
write.csv(summary,file.path(root,'summary.csv'),row.names=FALSE)
flags<-do.call(rbind,lapply(r$results,function(x){z<-as.data.frame(table(x$flag_detail));names(z)<-c('flag','origins');z$radius_miles<-x$radius_miles[1];z}))
write.csv(flags,file.path(root,'flags.csv'),row.names=FALSE)
pair<-merge(r$results$primary,r$results$sensitivity,by='h3_id',suffixes=c('_half','_quarter'))
paired<-is.finite(pair$street_safety_score_half)&is.finite(pair$street_safety_score_quarter)
flagpair<-!is.na(pair$any_high_half)&!is.na(pair$any_high_quarter)
sens<-data.frame(paired_scores=sum(paired),spearman=cor(pair$street_safety_score_half[paired],pair$street_safety_score_quarter[paired],method='spearman'),
  median_absolute_score_change=median(abs(pair$street_safety_score_half[paired]-pair$street_safety_score_quarter[paired])),
  p90_absolute_score_change=quantile(abs(pair$street_safety_score_half[paired]-pair$street_safety_score_quarter[paired]),.9),
  paired_flag_statuses=sum(flagpair),flag_changes=sum(pair$any_high_half[flagpair]!=pair$any_high_quarter[flagpair]),
  quarter_only_high=sum(!pair$any_high_half[flagpair]&pair$any_high_quarter[flagpair]),
  half_only_high=sum(pair$any_high_half[flagpair]&!pair$any_high_quarter[flagpair]))
write.csv(sens,file.path(root,'sensitivity_summary.csv'),row.names=FALSE)
geo<-lapply(r$results,function(x)merge(r$geometry,x,by='h3_id',sort=FALSE))
theme_map<-theme_void(base_size=12)+theme(plot.title=element_text(face='bold'),legend.position='bottom',plot.margin=margin(12,12,12,12))
score_map<-function(g,col,title)ggplot(g)+geom_sf(aes(fill=.data[[col]]),color=NA)+
  scale_fill_viridis_c(option='magma',direction=-1,limits=c(0,100),na.value='#b5bdc1',name='Burden score')+labs(title=title)+theme_map
flag_map<-ggplot(geo$primary)+geom_sf(aes(fill=flag_status),color=NA)+
  scale_fill_manual(values=c('High component burden'='#c64638','Below both flags'='#73a7a6','Incomplete assessment'='#b5bdc1'),
    breaks=c('High component burden','Below both flags','Incomplete assessment'),name=NULL)+labs(title='Warnings retained independently of score')+theme_map+
  guides(fill=guide_legend(ncol=1))
p<-score_map(geo$primary,'street_safety_score','Combined street-safety burden')+flag_map+
  plot_annotation(title='Street safety | Half-mile neighborhoods',
    subtitle='50% fatal/serious-injury crash score + 50% pedestrian-gap score · Higher = greater burden',
    caption='Gray score cells are unavailable. Flags: crash density >=4.277/year/sq. mile OR >=50% of inventoried network missing.\nCity-clipped windows around hex centers; 2020-2024 crashes and November 2026 pedestrian inventory. Below flags does not mean safe.')
ggsave(file.path(root,'primary_map.png'),p,width=12,height=8,dpi=160)
ggsave(file.path(root,'primary_map.pdf'),p,width=12,height=8)
p<-score_map(geo$primary,'crash_score','Crash burden')+score_map(geo$primary,'pedestrian_gap_score','Pedestrian gaps')+
  plot_annotation(title='The two components | Half-mile neighborhoods',caption='Common 0–100 burden scale. Crash score: linear to the frozen 95th-percentile density, capped at 100.\nPedestrian score: percentage of inventoried completed-plus-planned length still missing. Gray = unavailable.')
ggsave(file.path(root,'components.png'),p,width=12,height=8,dpi=160)
p<-score_map(geo$primary,'street_safety_score','Primary: half mile')+score_map(geo$sensitivity,'street_safety_score','Sensitivity: quarter mile')+
  plot_annotation(title='Combined score sensitivity',caption='Identical scoring anchors and flags at both radii; colors are directly comparable. Gray = unavailable.')
ggsave(file.path(root,'sensitivity_maps.png'),p,width=12,height=8,dpi=160)
all<-do.call(rbind,r$results);all$radius<-factor(all$radius_miles,levels=c(.5,.25),labels=c('Half mile','Quarter mile'))
p1<-ggplot(all[is.finite(all$street_safety_score),],aes(street_safety_score))+geom_histogram(binwidth=5,boundary=0,fill='#356e80',color='white')+
  facet_wrap(~radius,ncol=1)+coord_cartesian(xlim=c(0,100))+labs(title='Combined score distribution',x='Burden score',y='Origins')+theme_minimal()
p2<-ggplot(r$results$primary,aes(crash_score,pedestrian_gap_score))+geom_vline(xintercept=100*r$policy$scoring$crash_high_burden_density/r$policy$scoring$crash_full_burden_density,linetype=2,color='#c64638')+
  geom_hline(yintercept=50,linetype=2,color='#c64638')+geom_point(alpha=.45,color='#356e80',na.rm=TRUE)+coord_equal(xlim=c(0,100),ylim=c(0,100))+
  labs(title='Component scores: half mile',subtitle='Dashed lines mark component flags',x='Crash score',y='Pedestrian-gap score')+theme_minimal()
ggsave(file.path(root,'distribution.png'),p1+p2,width=11,height=6,dpi=160)
esc<-function(x){x<-gsub('&','&amp;',as.character(x),fixed=TRUE);gsub('<','&lt;',x,fixed=TRUE)}
tab<-function(x){x[]<-lapply(x,function(v)if(is.numeric(v))round(v,2)else v);paste0('<table><tr>',paste0('<th>',esc(names(x)),'</th>',collapse=''),'</tr>',paste(apply(x,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table>')}
primary<-r$results$primary
summary_display<-data.frame(Metric=c('Available origins','Unavailable origins','Median score','75th percentile score','90th percentile score','Any high-component flag','Both components high','Known residents represented (%)'),
  Half_mile=c(summary$available[1],summary$unavailable[1],summary$median[1],summary$p75[1],summary$p90[1],summary$either_high[1],summary$both_high[1],summary$known_residents_covered_percent[1]),
  Quarter_mile=c(summary$available[2],summary$unavailable[2],summary$median[2],summary$p75[2],summary$p90[2],summary$either_high[2],summary$both_high[2],summary$known_residents_covered_percent[2]))
unavailable<-as.data.frame(table(primary$status[!is.finite(primary$street_safety_score)]));names(unavailable)<-c('reason','origins')
write.csv(unavailable,file.path(root,'unavailable.csv'),row.names=FALSE)
html<-paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Combined street-safety burden</title><style>body{font:17px/1.5 system-ui;max-width:1120px;margin:36px auto;padding:0 24px;color:#18343e}h1,h2{line-height:1.2}img{max-width:100%;height:auto}table{display:block;overflow:auto;border-collapse:collapse;font-size:13px}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}.note{background:#edf3f5;border-left:4px solid #39728a;padding:18px}a{color:#176484}</style><h1>Combined street-safety burden</h1><p>Half mile primary · Quarter mile sensitivity · 1,029 current origins · Adopted scoring rules, November 9, 2026</p><div class="note"><b>Combined score = 50% crash score + 50% pedestrian-gap score.</b> Higher means greater burden. Crash score = min(100, 100 × annual KSI density / 6.1118601065110614). Pedestrian score = percentage of inventoried completed-plus-planned length still unbuilt. A high-component warning is retained when density >=4.2772765182635766 or gap score >=50, independently of the average.</div><img src="primary_map.png" alt="Half-mile combined street-safety scores and independent high-burden flags"><h2>Distribution and coverage</h2>',tab(summary_display),'<img src="distribution.png" alt="Score distributions and relationship between component scores"><h2>Component detail</h2><img src="components.png" alt="Separate crash and pedestrian-gap burden maps">',tab(flags),'<h2>Unavailable scores</h2>',tab(unavailable),'<p>The combined score requires both components; weights are never redistributed when a component is missing. A known high component still triggers a warning when the other is missing. Without a known high component, missing data produce an incomplete assessment, not a passing result. Whole-hex population estimates summarize assigned results, not residents actually served by sidewalks; unknown population is excluded.</p><h2>Quarter-mile sensitivity</h2>',tab(sens),'<img src="sensitivity_maps.png" alt="Half- and quarter-mile combined scores using identical anchors"><h2>Interpretation</h2><p>Crash density is annual unique fatal or suspected serious-injury crashes per observed square mile, for all road users, using 2020-2024. It is not adjusted for travel exposure. The 95th- and 90th-percentile anchors are frozen from the original half-mile results across all 1,029 origins (unweighted R type-7 quantiles); they are local reference levels, not safety standards. Both radii use those same anchors. Zero recorded crashes does not establish safety. Overlapping origin windows are not independent.</p><p>The gap measure uses the City’s November 9 inventory and counts planned sidewalks/shared streets as missing, with completed shared streets counted as completed. Potential sidewalks are excluded from the main measure. Unknown inventory and empty main denominators remain unavailable. Planned segments carrying past completion dates retain review flags and a separate sensitivity in the data. The measure does not establish route continuity, crossing safety, sidewalk condition or ADA compliance.</p><p>All circles are clipped to the pinned City full- and limited-purpose footprint. The data retain actual observation area, area share, five-year crash counts and network lengths. Small observed areas and sparse counts warrant caution. This is a separate burden domain: it does not alter benefit scores or flood-development eligibility.</p><p><a href="primary.csv">Half-mile scores and flags</a> · <a href="sensitivity.csv">Sensitivity summary</a> · <a href="quarter_mile.csv">Quarter-mile scores and flags</a> · <a href="street_safety.gpkg">GIS layers</a> · <a href="metadata.json">Policy and provenance</a> · <a href="primary_map.pdf">PDF map</a></p></html>')
write.csv(r$results$sensitivity,file.path(root,'quarter_mile.csv'),row.names=FALSE,na='')
html<-sub('href="sensitivity.csv"','href="sensitivity_summary.csv"',html,fixed=TRUE)
writeLines(html,file.path(root,'review.html'))
print(summary);print(flags);print(sens);print(unavailable)
