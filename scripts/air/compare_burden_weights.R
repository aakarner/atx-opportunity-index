.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
source('R/burden_weight_review.R')
weighted_known<-function(v,w){use<-is.finite(v)&is.finite(w)&w>0;if(any(use))weighted.mean(v[use],w[use])else NA_real_}
out<-'output/components/burden-weight-review';dir.create(out,recursive=TRUE,showWarnings=FALSE)
spec<-yaml::read_yaml('config/burden-weight-review.yml')
paths<-c(heat='output/components/heat-burden/scores.csv',street='output/components/street-safety/primary.csv',
  industrial='output/components/industrial-air-burden/scores.csv',traffic='output/components/near-road-traffic/scores.csv')
inputs<-lapply(paths,read.csv);hexes<-targets::tar_read(h8_geometry)
for(z in inputs)stopifnot(!anyDuplicated(z$h3_id),setequal(z$h3_id,hexes$h3_id))
x<-inputs$heat[,c('h3_id','longitude','latitude','total_population','children_under_18','heat_score','heat_high','heat_thin_coverage')]
for(z in inputs)for(n in c('total_population','children_under_18'))
  stopifnot(isTRUE(all.equal(x[[n]],z[[n]][match(x$h3_id,z$h3_id)],tolerance=1e-10)))
fields<-list(street=c('street_safety_score','crash_high','pedestrian_high','any_high'),
  industrial=c('industrial_air_score','industrial_air_high','industrial_air_review_band'),
  traffic=c('traffic_score','traffic_high'))
for(k in names(fields))for(n in fields[[k]])x[[if(n=='any_high')'street_safety_high' else n]]<-inputs[[k]][[n]][match(x$h3_id,inputs[[k]]$h3_id)]
for(k in names(spec$presets))x[[paste0('score_',k)]]<-review_weighted_burden(x,spec$presets[[k]]$relative_weights)
flag_fields<-c('heat_high','crash_high','pedestrian_high','industrial_air_high','traffic_high')
x<-cbind(x,review_burden_warning(x[,flag_fields]))
x$high_components<-apply(x[,flag_fields],1,function(row)paste(names(row)[which(row %in% TRUE)],collapse='; '))
x$high_domain_count<-rowSums(x[,c('heat_high','street_safety_high','industrial_air_high','traffic_high')],na.rm=TRUE)
ok<-is.finite(x$score_equal_themes)&is.finite(x$score_equal_domains)
x$themes_minus_domains<-x$score_equal_themes-x$score_equal_domains
for(k in names(spec$presets)) {
  v<-x[[paste0('score_',k)]];p<-rep(NA_real_,nrow(x))
  p[ok]<-100*(rank(v[ok],ties.method='average')-1)/(sum(ok)-1)
  x[[paste0('rank_percentile_',k)]]<-p
  for(t in c(75,90)){
    flag<-rep(NA,nrow(x));flag[ok]<-v[ok]>=quantile(v[ok],t/100,type=7)
    x[[paste0('top',t,'_',k)]]<-flag
  }
}
x$rank_change<-x$rank_percentile_equal_themes-x$rank_percentile_equal_domains
write.csv(x,file.path(out,'origin_comparison.csv'),row.names=FALSE,na='')
summary<-do.call(rbind,lapply(names(spec$presets),function(k){
  v<-x[[paste0('score_',k)]];q<-quantile(v,c(0,.25,.5,.75,.9,1),na.rm=TRUE)
  data.frame(preset=k,available=sum(is.finite(v)),unavailable=sum(!is.finite(v)),minimum=q[1],p25=q[2],median=q[3],p75=q[4],p90=q[5],maximum=q[6],
    mean=mean(v,na.rm=TRUE),resident_weighted_mean=weighted_known(v[ok],x$total_population[ok]))
}))
write.csv(summary,file.path(out,'summary.csv'),row.names=FALSE)
comparison<-data.frame(paired_origins=sum(ok),spearman=cor(x$score_equal_themes[ok],x$score_equal_domains[ok],method='spearman'),
  median_absolute_score_change=median(abs(x$themes_minus_domains[ok])),
  p90_absolute_score_change=quantile(abs(x$themes_minus_domains[ok]),.9),max_absolute_score_change=max(abs(x$themes_minus_domains[ok])),
  median_absolute_rank_change=median(abs(x$rank_change[ok])),
  p90_absolute_rank_change=quantile(abs(x$rank_change[ok]),.9),
  origins_higher_under_themes=sum(x$themes_minus_domains[ok]>1e-10),origins_lower_under_themes=sum(x$themes_minus_domains[ok]< -1e-10),
  known_residents_covered_percent=100*sum(x$total_population[ok],na.rm=TRUE)/sum(x$total_population,na.rm=TRUE),
  known_children_covered_percent=100*sum(x$children_under_18[ok],na.rm=TRUE)/sum(x$children_under_18,na.rm=TRUE))
write.csv(comparison,file.path(out,'comparison.csv'),row.names=FALSE)
tails<-do.call(rbind,lapply(c(75,90),function(t){
  a<-x[[paste0('top',t,'_equal_themes')]] %in% TRUE;b<-x[[paste0('top',t,'_equal_domains')]] %in% TRUE
  data.frame(percentile=t,themes_count=sum(a),domains_count=sum(b),shared=sum(a&b),themes_only=sum(a&!b),domains_only=sum(b&!a),
    shared_percent_of_themes=100*sum(a&b)/sum(a),
    themes_known_residents=sum(x$total_population[a],na.rm=TRUE),domains_known_residents=sum(x$total_population[b],na.rm=TRUE))
}))
write.csv(tails,file.path(out,'tail_overlap.csv'),row.names=FALSE)
warning<-do.call(rbind,lapply(unique(x$warning_status),function(k){use<-x$warning_status==k;data.frame(status=k,origins=sum(use),
  known_residents=sum(x$total_population[use],na.rm=TRUE),resident_percent=100*sum(x$total_population[use],na.rm=TRUE)/sum(x$total_population,na.rm=TRUE))}))
write.csv(warning,file.path(out,'warning_status.csv'),row.names=FALSE)
contributions<-do.call(rbind,lapply(names(spec$presets),function(k){
  w<-unlist(spec$presets[[k]]$relative_weights);w<-w/sum(w)
  do.call(rbind,lapply(names(w),function(n)data.frame(preset=k,domain=n,weight=w[[n]],
    mean_domain_score=mean(x[[n]][ok]),mean_points=w[[n]]*mean(x[[n]][ok]),
    resident_weighted_mean_points=w[[n]]*weighted_known(x[[n]][ok],x$total_population[ok]))))
}))
write.csv(contributions,file.path(out,'domain_contributions.csv'),row.names=FALSE)
changes<-x[ok,c('h3_id','longitude','latitude','total_population','heat_score','street_safety_score','industrial_air_score','traffic_score',
  'score_equal_themes','score_equal_domains','themes_minus_domains','rank_change','warning_status')]
write.csv(head(changes[order(-changes$rank_change),],15),file.path(out,'largest_rank_increases.csv'),row.names=FALSE,na='')
write.csv(head(changes[order(changes$rank_change),],15),file.path(out,'largest_rank_decreases.csv'),row.names=FALSE,na='')
jsonlite::write_json(list(spec=spec,input_sha256=as.list(vapply(paths,function(p)digest::digest(file=p,algo='sha256'),character(1))),
  population_total=sum(x$total_population,na.rm=TRUE),children_total=sum(x$children_under_18,na.rm=TRUE),
  unknown_population_origins=sum(is.na(x$total_population)),
  qualification='Weighting comparison only; top-decile/quartile ranks are diagnostics, not adopted combined-burden flags. Primary component warnings are independent of weights.'),
  file.path(out,'metadata.json'),auto_unbox=TRUE,pretty=TRUE,digits=17,na='null')
geo<-merge(st_transform(hexes,26914),x,by='h3_id',sort=FALSE)
st_write(geo,file.path(out,'burden_weight_review.gpkg'),layer='comparison',delete_layer=TRUE,quiet=TRUE)
t<-theme_void(base_size=11)+theme(plot.title=element_text(face='bold'),legend.position='bottom',plot.margin=margin(10,10,10,10))
map<-function(field,title)ggplot(geo)+geom_sf(aes(fill=.data[[field]]),color=NA)+
  scale_fill_viridis_c(option='magma',direction=-1,limits=c(0,100),na.value='#b5bdc1',name='Burden score')+labs(title=title)+t
delta_limit<-ceiling(max(abs(x$themes_minus_domains),na.rm=TRUE))
delta<-ggplot(geo)+geom_sf(aes(fill=themes_minus_domains),color=NA)+
  scale_fill_gradient2(low='#3078a0',mid='#f4f2eb',high='#c64b3d',limits=c(-delta_limit,delta_limit),na.value='#b5bdc1',name='Score difference')+
  labs(title='Three themes minus four domains')+t
p<-map('score_equal_themes','Equal thirds by theme')+map('score_equal_domains','Equal quarters by domain')+delta+
  plot_annotation(title='Burden weighting presets | Same component scores and warnings',
    subtitle='Themes: heat 1/3, street safety 1/3, industrial air 1/6, traffic 1/6. Domains: 1/4 each.',
    caption='Higher = greater burden. Red difference cells score higher under equal themes; blue score higher under equal domains.\nGray = incomplete composite (no redistribution of missing weights). Component warning flags do not change.')
ggsave(file.path(out,'comparison_maps.png'),p,width=15,height=8,dpi=160,bg='white')
ggsave(file.path(out,'comparison_maps.pdf'),p,width=15,height=8)
p1<-ggplot(x[ok,],aes(score_equal_domains,score_equal_themes))+geom_abline(slope=1,intercept=0,color='grey60')+
  geom_point(alpha=.45,color='#356e80',size=1.5)+coord_equal(xlim=c(0,100),ylim=c(0,100))+
  labs(title='Composite scores',x='Equal four domains',y='Equal three themes')+theme_minimal(base_size=12)
p2<-ggplot(x[ok,],aes(rank_percentile_equal_domains,rank_percentile_equal_themes))+geom_abline(slope=1,intercept=0,color='grey60')+
  geom_point(alpha=.45,color='#356e80',size=1.5)+coord_equal(xlim=c(0,100),ylim=c(0,100))+
  labs(title='Relative ranking among 880 complete origins',x='Four-domain rank percentile',y='Three-theme rank percentile')+theme_minimal(base_size=12)
ggsave(file.path(out,'score_rank_comparison.png'),p1+p2,width=11,height=5.5,dpi=160,bg='white')
contributions$preset_label<-ifelse(contributions$preset=='equal_themes','Equal three themes','Equal four domains')
p<-ggplot(contributions,aes(preset_label,mean_points,fill=domain))+geom_col()+
  scale_fill_manual(values=c(heat_score='#c64b3d',street_safety_score='#356e80',industrial_air_score='#713c87',traffic_score='#d5a448'),
    labels=c(heat_score='Heat',street_safety_score='Street safety',industrial_air_score='Industrial air',traffic_score='Traffic'),name=NULL)+
  labs(title='Average contribution to the composite',subtitle='Same 880 complete origins; equal-hex means',x=NULL,y='Mean score points')+
  theme_minimal(base_size=12)+theme(legend.position='bottom')
ggsave(file.path(out,'domain_contributions.png'),p,width=8,height=5.5,dpi=160,bg='white')
esc<-function(v){v<-gsub('&','&amp;',as.character(v),fixed=TRUE);gsub('<','&lt;',v,fixed=TRUE)}
tab<-function(d){d[]<-lapply(d,function(v)if(is.numeric(v))round(v,2)else v);paste0('<div class="scroll"><table><tr>',paste0('<th>',esc(names(d)),'</th>',collapse=''),'</tr>',paste(apply(d,1,function(row)paste0('<tr>',paste0('<td>',esc(row),'</td>',collapse=''),'</tr>')),collapse=''),'</table></div>')}
compact<-data.frame(metric=c('Paired origins','Spearman rank correlation','Median absolute score change','90th percentile absolute score change','Median absolute rank-percentile change','90th percentile absolute rank-percentile change','Known residents covered (%)'),
  value=c(comparison$paired_origins,comparison$spearman,comparison$median_absolute_score_change,comparison$p90_absolute_score_change,
    comparison$median_absolute_rank_change,comparison$p90_absolute_rank_change,comparison$known_residents_covered_percent))
html<-paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Burden weighting comparison</title><style>body{font:17px/1.5 system-ui;max-width:1250px;margin:36px auto;padding:0 24px;color:#18343e}img{max-width:100%;height:auto}.scroll{overflow:auto}table{border-collapse:collapse;font-size:14px}td,th{padding:8px;border-bottom:1px solid #ccd6da;text-align:left}.note{background:#edf3f5;padding:18px;border-left:4px solid #39728a}a{color:#176484}</style><h1>Burden weighting presets</h1><p>November 10, 2026 · Comparison only; default weights not yet selected</p><div class="note"><b>Equal three themes:</b> heat 1/3, street safety 1/3, industrial air 1/6, near-road traffic 1/6.<br><b>Equal four domains:</b> 1/4 each.<br>All component scores and primary flags remain fixed. Street safety retains its internal 50/50 split.</div><img src="comparison_maps.png" alt="Two composite burden maps and their score difference"><h2>Score and rank changes</h2>',tab(compact),tab(summary[,c('preset','available','unavailable','median','p75','p90','mean','resident_weighted_mean')]),'<img src="score_rank_comparison.png" alt="Score and rank comparison between the two presets"><h2>Highest-scoring locations</h2>',tab(tails),'<p>Top quartile and top decile are comparison diagnostics among complete origins, not additional high-burden flags. Ties are retained using inclusive type-7 quantile cutoffs. Rank percentiles use average ranks for ties.</p><h2>Which components contribute?</h2><img src="domain_contributions.png" alt="Average score contribution by domain under both presets">',tab(contributions[,c('preset','domain','weight','mean_domain_score','mean_points')]),'<p>The score difference equals (heat + street safety − industrial air − traffic) / 12. Thus equal themes raises scores where heat and street-safety scores together exceed the two air scores, and lowers them where air scores dominate. Heat is a percentile while the other scores retain percentages or differences in raw concentrations/density, so equal nominal weights do not guarantee equal typical contributions. This chart reports average contributions, not a causal or statistical variance decomposition.</p><h2>Warnings do not change</h2>',tab(warning),'<p>Any known primary heat, crash, pedestrian-gap, industrial-air or traffic flag triggers a high-burden warning. The crash or gap flag is retained even when the average street-safety score is moderate. A high flag plus missing information is labeled high burden with incomplete assessment; missing information without a known high flag is incomplete assessment. Industrial-air secondary review and heat limited-observation flags remain separate fields, without becoming primary high flags. The traffic sensitivity flag is not used here.</p><h2>Coverage and interpretation</h2><p>Both presets require all four domain scores and do not redistribute missing weights. There are 880 complete scores and 149 unavailable composites because pedestrian-gap data are unavailable. Available scores represent 98.53% of known estimated residents. All 1,029 origins remain in the warning assessment. Whole-hex population estimates describe assigned locations, not measured exposure; 71 origins have unknown population and are omitted from population denominators.</p><p>Both presets are prototype screening choices, not calibrated health-risk models. Flood eligibility stays separate and is not overridden by a score; benefits are not subtracted from burdens. No default preset, overall threshold or public-map change is adopted by this comparison.</p><p><a href="origin_comparison.csv">All scores, ranks and warnings</a> · <a href="largest_rank_increases.csv">Largest rank increases under equal themes</a> · <a href="largest_rank_decreases.csv">Largest rank decreases under equal themes</a> · <a href="burden_weight_review.gpkg">GIS layer</a> · <a href="metadata.json">Inputs and candidate weights</a> · <a href="comparison_maps.pdf">PDF maps</a></p></html>')
writeLines(html,file.path(out,'review.html'))
print(summary);print(comparison);print(tails);print(warning);print(contributions)
