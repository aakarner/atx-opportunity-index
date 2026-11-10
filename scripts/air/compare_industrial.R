.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
source('R/industrial_air_review.R')
out<-'output/components/industrial-air-review';dir.create(out,recursive=TRUE,showWarnings=FALSE)
spec<-yaml::read_yaml('config/industrial-air-review.yml')
geometry<-targets::tar_read(h8_components)
pop<-as.data.frame(targets::tar_read(dam_inputs)$population)
stopifnot(!anyDuplicated(geometry$h3_id),!anyDuplicated(pop$h3_id),setequal(geometry$h3_id,pop$h3_id),
  nrow(geometry)==spec$reference_origins,all(geometry$rsei_year==spec$reporting_year),
  all(geometry$rsei_version==spec$source_version))
fields<-c('h3_id','rsei_tox_conc','rsei_coverage_share','rsei_record_area_share','rsei_status','rsei_year','rsei_version')
x<-merge(st_drop_geometry(geometry)[,fields],pop[,c('h3_id','total_population','children_under_18')],by='h3_id',sort=TRUE)
if(any(x$rsei_coverage_share<1-1e-6 & is.finite(x$rsei_tox_conc)))stop('Incomplete RSEI coverage must not yield a concentration')
q<-quantile(x$rsei_tox_conc,c(.9,.95),type=7,na.rm=TRUE)
if(abs(q[1]-spec$candidate_high_concentration)>1e-8||abs(q[2]-spec$candidate_full_burden_concentration)>1e-8)
  stop('Current data differ from pinned review reference; explicitly review new anchors')
x<-cbind(x,industrial_air_candidates(x$rsei_tox_conc,spec))
centers<-st_coordinates(h3jsr::cell_to_point(x$h3_id));x$longitude<-centers[,1];x$latitude<-centers[,2]
write.csv(x,file.path(out,'origin_comparison.csv'),row.names=FALSE,na='')
write.csv(x[x$flag_comparison=='Flag removed at higher cutoff',],file.path(out,'removed_flags.csv'),row.names=FALSE,na='')
rules<-list(existing_100=x$flag_mockup_100,candidate_p90=x$flag_candidate_p90,
  removed_flag=x$flag_mockup_100 & !x$flag_candidate_p90,score_capped=x$candidate_score_capped)
summary<-do.call(rbind,lapply(names(rules),function(k){
  use<-rules[[k]] %in% TRUE;w<-x$total_population;c<-x$children_under_18
  data.frame(rule=k,flagged_hexes=sum(use),hexes_percent=100*mean(use),
    known_residents=sum(w[use],na.rm=TRUE),residents_percent=100*sum(w[use],na.rm=TRUE)/sum(w,na.rm=TRUE),
    known_children=sum(c[use],na.rm=TRUE),children_percent=100*sum(c[use],na.rm=TRUE)/sum(c,na.rm=TRUE),
    flagged_hexes_with_positive_population=sum(use & is.finite(w) & w>0),
    flagged_hexes_with_zero_population=sum(use & is.finite(w) & w==0),
    flagged_hexes_with_unknown_population=sum(use & !is.finite(w)))
}))
write.csv(summary,file.path(out,'flag_population_summary.csv'),row.names=FALSE)
distribution<-do.call(rbind,lapply(c('rsei_tox_conc','candidate_industrial_score'),function(k){
  v<-x[[k]];z<-quantile(v,c(0,.25,.5,.75,.9,.95,1),na.rm=TRUE)
  data.frame(measure=k,available=sum(is.finite(v)),minimum=z[1],p25=z[2],median=z[3],p75=z[4],p90=z[5],p95=z[6],maximum=z[7])
}))
write.csv(distribution,file.path(out,'distributions.csv'),row.names=FALSE)
examples<-data.frame(ToxConc=c(0,50,100,spec$candidate_high_concentration,spec$candidate_full_burden_concentration,1000))
examples<-cbind(examples,industrial_air_candidates(examples$ToxConc,spec))
write.csv(examples,file.path(out,'score_examples.csv'),row.names=FALSE,na='')
sourcefiles<-targets::tar_read(rsei_source_files)
manifest<-jsonlite::read_json(sourcefiles[grepl('json$',sourcefiles)])
jsonlite::write_json(list(spec=spec,source_manifest=manifest,
  reference_csv_sha256=digest::digest(file=file.path(out,'origin_comparison.csv'),algo='sha256'),
  geometry_sha256=digest::digest(geometry[,c('h3_id','geometry')],algo='sha256'),
  population_total=sum(x$total_population,na.rm=TRUE),children_total=sum(x$children_under_18,na.rm=TRUE),
  unknown_population_origins=sum(!is.finite(x$total_population)),
  qualification='Review only. Thresholds are local screening choices, not health standards. Model covers TRI-related industrial air releases, not total air pollution.'),
  file.path(out,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,na='null',digits=17)
g<-merge(st_transform(geometry[,c('h3_id','geometry')],26914),x,by='h3_id',sort=FALSE)
st_write(g,file.path(out,'industrial_air_review.gpkg'),layer='candidate_scores_and_flags',delete_layer=TRUE,quiet=TRUE)
theme_map<-theme_void(base_size=12)+theme(plot.title=element_text(face='bold'),legend.position='bottom',plot.margin=margin(10,10,10,10))
map_score<-ggplot(g)+geom_sf(aes(fill=candidate_industrial_score),color=NA)+
  scale_fill_viridis_c(option='magma',direction=-1,limits=c(0,100),na.value='#b5bdc1',name='Candidate burden score')+
  labs(title='Proposed continuous score')+theme_map
map_change<-ggplot(g)+geom_sf(aes(fill=flag_comparison),color=NA)+
  scale_fill_manual(values=c('Flagged under both'='#943958','Flag removed at higher cutoff'='#e6a34a',
    'Below both cutoffs'='#dce5e5','Unavailable'='#b5bdc1'),name=NULL,
    breaks=c('Flagged under both','Flag removed at higher cutoff','Below both cutoffs','Unavailable'))+
  guides(fill=guide_legend(ncol=1))+labs(title='What changes with the higher cutoff')+theme_map
p<-map_score+map_change+plot_annotation(title='Industrial air burden | Scoring and flag comparison',
  subtitle='Candidate score reaches 100 at ToxConc 622.7. Compare existing flag at 100 with proposed flag at 351.1.',
  caption='2022 EPA RSEI v2.3.12; full-hex area-weighted toxicity-weighted concentration. Neither threshold is a health standard.\nPurple cells remain flagged; orange cells lose the flag. No production rule or public-map change has been adopted.')
ggsave(file.path(out,'comparison_map.png'),p,width=12,height=8,dpi=160,bg='white')
ggsave(file.path(out,'comparison_map.pdf'),p,width=12,height=8)
flag_map<-function(field,title){d<-g;d$flag<-ifelse(is.na(d[[field]]),'Unavailable',ifelse(d[[field]],'Flagged','Below cutoff'))
  ggplot(d)+geom_sf(aes(fill=flag),color=NA)+scale_fill_manual(values=c('Flagged'='#943958','Below cutoff'='#dce5e5','Unavailable'='#b5bdc1'),name=NULL)+labs(title=title)+theme_map}
p<-flag_map('flag_mockup_100','Existing: ToxConc at least 100')+flag_map('flag_candidate_p90','Proposed: ToxConc at least 351.1')+
  plot_annotation(title='Alternative high-burden flags',caption='Same raw concentrations and geography. The proposed flag is nested within the existing flag; no locations are newly flagged.')
ggsave(file.path(out,'flag_maps.png'),p,width=12,height=8,dpi=160,bg='white')
# Population weighting describes where residents are assigned, not their measured exposure.
v<-x$rsei_tox_conc;order<-order(v);ref<-data.frame(concentration=v[order],
  hex_fraction=seq_along(v)/length(v),resident_fraction=cumsum(replace(x$total_population[order],is.na(x$total_population[order]),0))/sum(x$total_population,na.rm=TRUE))
curves<-rbind(data.frame(concentration=ref$concentration,fraction=ref$hex_fraction,reference='Hexes (equal weight)'),
  data.frame(concentration=ref$concentration,fraction=ref$resident_fraction,reference='Known estimated residents'))
p1<-ggplot(curves,aes(concentration,100*fraction,color=reference))+geom_step(linewidth=.8)+scale_x_log10()+
  geom_vline(xintercept=c(100,spec$candidate_high_concentration),linetype=2,color='#777777')+
  scale_color_manual(values=c('Hexes (equal weight)'='#356e80','Known estimated residents'='#c26e24'),name=NULL)+
  labs(title='Concentration distribution',subtitle='Dashed lines: 100 and 351.1; logarithmic horizontal axis',x='RSEI toxicity-weighted concentration',y='Cumulative share (%)')+
  theme_minimal(base_size=12)+theme(legend.position='bottom')
p2<-ggplot(x,aes(candidate_industrial_score))+geom_histogram(binwidth=5,boundary=0,fill='#356e80',color='white')+
  coord_cartesian(xlim=c(0,100))+geom_vline(xintercept=100*c(100,spec$candidate_high_concentration)/spec$candidate_full_burden_concentration,linetype=2,color='#c26e24')+
  labs(title='Proposed score distribution',subtitle='Raw concentration differences retained below the cap',x='Candidate burden score',y='Hexes')+theme_minimal(base_size=12)
ggsave(file.path(out,'distribution.png'),p1+p2,width=12,height=5.5,dpi=160,bg='white')
esc<-function(v){v<-gsub('&','&amp;',as.character(v),fixed=TRUE);gsub('<','&lt;',v,fixed=TRUE)}
tab<-function(d){d[]<-lapply(d,function(v)if(is.numeric(v))round(v,2)else v);paste0('<div class="scroll"><table><tr>',paste0('<th>',esc(names(d)),'</th>',collapse=''),'</tr>',paste(apply(d,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table></div>')}
short<-summary[,c('rule','flagged_hexes','known_residents','residents_percent','known_children','children_percent')]
html<-paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Industrial air scoring comparison</title><style>body{font:17px/1.5 system-ui;max-width:1120px;margin:36px auto;padding:0 24px;color:#18343e}h1,h2{line-height:1.2}img{max-width:100%;height:auto}.scroll{overflow:auto}table{border-collapse:collapse;font-size:14px}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}.note{background:#fff1db;border-left:4px solid #c28936;padding:18px}a{color:#176484}</style><h1>Industrial air scoring comparison</h1><p>November 10, 2026 · 1,029 current origins · EPA RSEI v2.3.12, reporting year 2022</p><div class="note"><b>Review only.</b> Candidate score = min(100, 100 × ToxConc / 622.73023119285699). Compare the existing mockup flag of ToxConc ≥100 with a proposed flag at ≥351.10409694733289. The latter is the current unweighted 90th percentile; the score anchor is the 95th percentile. Neither is a health standard. No production rule or public-map change is made.</div><img src="comparison_map.png" alt="Candidate industrial-air burden score and locations that lose their flag under the higher threshold"><h2>Population and classification changes</h2>',tab(short),'<p>The proposed flag removes 231 of the 334 existing flags, retaining 103. Approximately 259,352 known residents are in hexes that would lose their flag. This is a narrower screening definition, not an improvement in air quality. Population estimates refer to whole hexes and do not establish personal exposure. The denominator is about 963,741 known residents and 172,174 children; 71 origins lack population estimates.</p><img src="flag_maps.png" alt="Maps of existing and proposed industrial-air flags"><h2>How the candidate score behaves</h2>',tab(distribution),'<img src="distribution.png" alt="Concentration distributions by hex and population, and the candidate score distribution">',tab(examples[,c('ToxConc','candidate_industrial_score','flag_mockup_100','flag_candidate_p90')]),'<p>Zero concentration would receive zero points, without subtracting the observed minimum. The median observed concentration receives about 8.4 points, and the upper 5% are capped at 100. Raw concentrations remain available above the cap. Changing the flag does not change this continuous score: the old flag corresponds to about 16.1 points and the proposed flag to about 56.4 points. A percentile-score alternative would assign a median near 50 and emphasize geographic ordering more than concentration differences; it is not used here.</p><h2>Decision to make</h2><p>The candidate continuous score and flag can be chosen separately. A 90th-percentile flag concentrates attention on the high modeled-concentration tail. Retaining the 100 flag provides broader screening. Another display option is to retain 100 as a secondary review band while using 351.1 for a high-burden flag; that would be an additional decision, not a rule adopted by this report.</p><h2>Source and interpretation</h2><p>ToxConc is modeled industrial-air concentration weighted by relative inhalation toxicity. It does not include the population multiplier in EPA’s separate RSEI Score. The source represents TRI-related industrial releases, not total air pollution, traffic pollution or measured personal exposure. Concentration is averaged by overlap area over full H8 cells from native 810 m EPA grid cells; the hex map does not increase the underlying resolution. The aggregated source cannot identify which facility or chemical causes a hotspot. These are 2022 emissions-model results, not 2026 measurements.</p><p>References are the same 1,029 current origins, equally weighted, with R type-7 quantiles. All have complete modeled-grid coverage and finite concentrations. Population only summarizes consequences of the candidate rules and does not set the score or threshold. Missing measurements would remain unavailable. Updating the reference requires explicit review; candidates are pinned in config/industrial-air-review.yml.</p><p><a href="origin_comparison.csv">All origin scores and flags</a> · <a href="removed_flags.csv">Origins losing the flag, with center coordinates</a> · <a href="flag_population_summary.csv">Full population comparison</a> · <a href="industrial_air_review.gpkg">GIS layer</a> · <a href="metadata.json">Source and candidate provenance</a> · <a href="comparison_map.pdf">PDF map</a></p></html>')
writeLines(html,file.path(out,'review.html'))
print(summary);print(distribution);print(examples)
