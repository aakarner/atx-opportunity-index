.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
out<-'output/components/industrial-air-burden';r<-readRDS(file.path(out,'analysis.rds'));x<-r$scores
classes<-c('Below review band','Secondary review','High burden','Unavailable')
summary<-do.call(rbind,lapply(classes,function(k){
  use<-x$industrial_air_status==k
  data.frame(status=k,hexes=sum(use),residents=sum(x$total_population[use],na.rm=TRUE),
    residents_percent=100*sum(x$total_population[use],na.rm=TRUE)/sum(x$total_population,na.rm=TRUE),
    children=sum(x$children_under_18[use],na.rm=TRUE),
    children_percent=100*sum(x$children_under_18[use],na.rm=TRUE)/sum(x$children_under_18,na.rm=TRUE))
}))
write.csv(summary,file.path(out,'summary.csv'),row.names=FALSE)
g<-merge(st_transform(r$geometry,26914),x,by='h3_id',sort=FALSE)
g$industrial_air_status<-factor(g$industrial_air_status,levels=classes)
t<-theme_void(base_size=12)+theme(plot.title=element_text(face='bold'),legend.position='bottom',plot.margin=margin(10,10,10,10))
p1<-ggplot(g)+geom_sf(aes(fill=industrial_air_score),color=NA)+
  scale_fill_viridis_c(option='magma',direction=-1,limits=c(0,100),na.value='#b5bdc1',name='Industrial-air burden score')+
  labs(title='Continuous burden score')+t
p2<-ggplot(g)+geom_sf(aes(fill=industrial_air_status),color=NA)+
  scale_fill_manual(values=c('Below review band'='#dce5e5','Secondary review'='#e6a34a','High burden'='#943958','Unavailable'='#b5bdc1'),name=NULL)+
  guides(fill=guide_legend(ncol=1))+labs(title='High burden and secondary review')+t
p<-p1+p2+plot_annotation(title='Industrial air burden | Adopted score and flags',
  subtitle='100 points at ToxConc 622.7. High burden at 351.1; secondary review from 100 to below 351.1.',
  caption='Thresholds rounded here; exact frozen values are retained in policy and exports. RSEI v2.3.12, reporting year 2022.\nFull-hex area-weighted modeled industrial concentration. These screening bands are not health standards.')
ggsave(file.path(out,'industrial_air_map.png'),p,width=12,height=8,dpi=160,bg='white')
ggsave(file.path(out,'industrial_air_map.pdf'),p,width=12,height=8)
esc<-function(v){v<-gsub('&','&amp;',as.character(v),fixed=TRUE);gsub('<','&lt;',v,fixed=TRUE)}
tab<-function(d){d[]<-lapply(d,function(v)if(is.numeric(v))round(v,2)else v);paste0('<div class="scroll"><table><tr>',paste0('<th>',esc(names(d)),'</th>',collapse=''),'</tr>',paste(apply(d,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table></div>')}
html<-paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Industrial air burden</title><style>body{font:17px/1.5 system-ui;max-width:1120px;margin:36px auto;padding:0 24px;color:#18343e}img{max-width:100%;height:auto}.scroll{overflow:auto}table{border-collapse:collapse;font-size:14px}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}.note{background:#edf3f5;padding:18px;border-left:4px solid #39728a}a{color:#176484}</style><h1>Industrial air burden</h1><p>Adopted November 10, 2026 · 1,029 current origins · EPA RSEI v2.3.12, reporting year 2022</p><div class="note"><b>Score = min(100, 100 × ToxConc / 622.73023119285699).</b> High burden: ToxConc ≥351.10409694733289. Secondary review: 100 ≤ ToxConc &lt;351.10409694733289. Below 100: below the review band. Missing or incomplete modeled-grid coverage: unavailable.</div><img src="industrial_air_map.png" alt="Industrial-air burden score and adopted high-burden and secondary-review categories"><h2>Results</h2>',tab(summary),'<p>All 1,029 origins have scores. The median is 8.39, and 52 origins reach the 100-point cap. Raw concentrations remain available above the cap. The secondary review band preserves visibility of the 231 origins identified by the old threshold that fall below the new high-burden cutoff. It does not count as a high-burden flag or add score points.</p><h2>Interpretation</h2><p>These are fixed local screening benchmarks derived from the original equal-hex distribution, not health standards. Population summarizes the locations in each band and never affects the score. Whole-hex estimates cover approximately 963,741 known residents and 172,174 children; 71 origins lack population estimates. These are not measurements of personal pollution exposure.</p><p>RSEI ToxConc represents modeled industrial-air concentration weighted by relative inhalation toxicity. It does not include the population multiplier in EPA’s separate RSEI Score. This source covers TRI-related industrial releases, not total air pollution or traffic pollution. Hex values are full-cell area-weighted means from the native 810 m EPA grid. Mapping to hexes does not increase source resolution, and the aggregated data cannot identify which facility or chemical causes a hotspot. Values describe reporting year 2022, not 2026 emissions.</p><p>Scores and high/secondary flags are exported separately. The secondary review band is exclusive of the high-burden band, while a separate review-or-high field preserves the broader ≥100 screen. Missing values remain unavailable. Overall burden weights and traffic scoring remain open; public-map publication is separate.</p><p><a href="scores.csv">Scores and flags</a> · <a href="summary.csv">Population summary</a> · <a href="industrial_air_burden.gpkg">GIS layer</a> · <a href="metadata.json">Frozen policy and provenance</a> · <a href="industrial_air_map.pdf">PDF map</a> · <a href="../industrial-air-review/review.html">Earlier comparison</a></p></html>')
writeLines(html,file.path(out,'review.html'))
print(summary)
