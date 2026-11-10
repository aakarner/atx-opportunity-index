.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
out<-'output/components/near-road-traffic';r<-readRDS(file.path(out,'analysis.rds'));x<-r$scores
rules<-list(primary_50_percent=x$traffic_high,sensitivity_25_percent=x$traffic_sensitivity_high,
  sensitivity_only=x$traffic_sensitivity_high & !x$traffic_high,zero_overlap=x$traffic_buffer_share==0)
summary<-do.call(rbind,lapply(names(rules),function(k){
  use<-rules[[k]] %in% TRUE
  data.frame(rule=k,hexes=sum(use),known_residents=sum(x$total_population[use],na.rm=TRUE),
    residents_percent=100*sum(x$total_population[use],na.rm=TRUE)/sum(x$total_population,na.rm=TRUE),
    known_children=sum(x$children_under_18[use],na.rm=TRUE),
    children_percent=100*sum(x$children_under_18[use],na.rm=TRUE)/sum(x$children_under_18,na.rm=TRUE))
}))
write.csv(summary,file.path(out,'flag_population_summary.csv'),row.names=FALSE)
q<-quantile(x$traffic_score,c(0,.25,.5,.75,.9,.95,1),na.rm=TRUE)
distribution<-data.frame(available=sum(is.finite(x$traffic_score)),unavailable=sum(!is.finite(x$traffic_score)),
  zero=sum(x$traffic_score==0,na.rm=TRUE),minimum=q[1],p25=q[2],median=q[3],p75=q[4],p90=q[5],p95=q[6],maximum=q[7])
write.csv(distribution,file.path(out,'distribution.csv'),row.names=FALSE)
g<-merge(st_transform(r$geometry,26914),x,by='h3_id',sort=FALSE)
theme_map<-theme_void(base_size=12)+theme(plot.title=element_text(face='bold'),legend.position='bottom',plot.margin=margin(10,10,10,10))
p1<-ggplot(g)+geom_sf(aes(fill=traffic_score),color=NA)+scale_fill_viridis_c(option='magma',direction=-1,
  limits=c(0,100),na.value='#b5bdc1',name='Traffic exposure score')+labs(title='Share of hex near high-volume roads')+theme_map
p2<-ggplot(g)+geom_sf(aes(fill=traffic_flag_comparison),color=NA)+scale_fill_manual(
  values=c('Primary high-burden flag'='#c64b3d','Sensitivity flag only'='#e6a34a','Below both flags'='#dce5e5','Unavailable'='#b5bdc1'),
  breaks=c('Primary high-burden flag','Sensitivity flag only','Below both flags','Unavailable'),name=NULL)+
  guides(fill=guide_legend(ncol=1))+labs(title='50% flag and broader 25% sensitivity')+theme_map
p<-p1+p2+plot_annotation(title='Near-road traffic exposure | Adopted score and flag',
  subtitle='Score = percent of full hex within 300 m of roads with AADT >50,000. Primary high burden: score at least 50.',
  caption='Orange cells are flagged only under the 25% sensitivity; their primary flag remains off.\nProximity proxy, not pollutant concentration. Distance context refers to hex centers. Zero overlap does not establish clean air.')
ggsave(file.path(out,'traffic_map.png'),p,width=12,height=8,dpi=160,bg='white')
ggsave(file.path(out,'traffic_map.pdf'),p,width=12,height=8)
p<-ggplot(x[is.finite(x$traffic_score)&x$traffic_score>0,],aes(traffic_score))+
  geom_histogram(binwidth=5,boundary=0,fill='#356e80',color='white')+
  geom_vline(xintercept=c(25,50),color=c('#e6a34a','#c64b3d'),linetype=2)+coord_cartesian(xlim=c(0,100))+
  labs(title='Score distribution among hexes with some corridor overlap',
    subtitle=paste(sum(x$traffic_score==0,na.rm=TRUE),'additional hexes have zero overlap and are omitted from this histogram'),
    x='Traffic exposure score = percent overlap',y='Hexes')+theme_minimal(base_size=12)
ggsave(file.path(out,'positive_score_distribution.png'),p,width=9,height=5,dpi=160,bg='white')
esc<-function(v){v<-gsub('&','&amp;',as.character(v),fixed=TRUE);gsub('<','&lt;',v,fixed=TRUE)}
tab<-function(d){d[]<-lapply(d,function(v)if(is.numeric(v))round(v,2)else v);paste0('<div class="scroll"><table><tr>',paste0('<th>',esc(names(d)),'</th>',collapse=''),'</tr>',paste(apply(d,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table></div>')}
html<-paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Near-road traffic exposure</title><style>body{font:17px/1.5 system-ui;max-width:1120px;margin:36px auto;padding:0 24px;color:#18343e}img{max-width:100%;height:auto}.scroll{overflow:auto}table{border-collapse:collapse;font-size:14px}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}.note{background:#edf3f5;border-left:4px solid #39728a;padding:18px}a{color:#176484}</style><h1>Near-road traffic exposure</h1><p>Adopted November 10, 2026 · 1,029 current origins · TxDOT roadway snapshot</p><div class="note"><b>Score = 100 × full-hex fraction within 300 meters of roads with AADT_CUR &gt;50,000.</b> A 40% overlap gets 40 burden points. The primary high-burden flag is overlap ≥50%; the broader sensitivity uses ≥25%. The sensitivity changes the flag only, not the score.</div><img src="traffic_map.png" alt="Traffic exposure scores and primary versus sensitivity flags"><h2>Results and population</h2>',tab(summary),'<p>All 1,029 origins have scores. The primary flag identifies 123 hexes; the sensitivity identifies 201, adding 78. These summaries describe people assigned a hex value, not measured counts of people exposed to pollutants. Population summaries use whole-hex estimates; 71 origins lack population estimates and are excluded from population denominators.</p><h2>Distribution</h2>',tab(distribution),'<img src="positive_score_distribution.png" alt="Distribution of nonzero traffic exposure scores with 25 and 50 thresholds"><p>There are 717 zero-overlap hexes. Zero means no overlap with the qualifying corridors in this source, not pollution-free conditions. Missing overlap values would remain unavailable, never zero.</p><h2>Spatial method and interpretation</h2><p>Qualifying roads are buffered 300 m using round ends. Overlapping buffers are dissolved before calculating the fraction of each full hex covered, avoiding double counting. The source query includes roads outside City limits and has passed extent checks. Operations use UTM zone 14N in meters. Traffic volume, distance and overlap thresholds are prototype screening choices, not health standards.</p><p>Distance to the nearest qualifying road is retained in feet and meters as context, with no extra score weight. It is measured from the canonical H3 center; it is not a distance from a proposed development address. An address-specific check remains future work. The score is a proximity proxy, not modeled pollutant concentration or travel-adjusted crash risk.</p><p>The snapshot was retrieved November 9, 2026, with a TxDOT extraction date of November 1, 2026. The source does not supply the observation year for each AADT_CUR value, so the traffic counts are not described as 2026 observations. Query coverage does not establish that all roads have current traffic observations.</p><p>Overall burden weights and combination rules remain to be settled. This implementation does not alter benefits, flood eligibility, or the public-map deployment.</p><p><a href="scores.csv">Scores, flags and distance context</a> · <a href="flag_population_summary.csv">Population summary</a> · <a href="traffic_burden.gpkg">GIS layer</a> · <a href="metadata.json">Policy and source provenance</a> · <a href="traffic_map.pdf">PDF map</a></p></html>')
writeLines(html,file.path(out,'review.html'))
print(summary);print(distribution)
