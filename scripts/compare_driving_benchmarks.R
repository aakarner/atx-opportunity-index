# Resident-weighted comparison of candidate driving job benchmarks.
# Run after scripts/run_pipeline.R scoring_comparison.
if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
suppressPackageStartupMessages({library(ggplot2);library(dplyr);library(tidyr)})
spec<-yaml::read_yaml('config/benefit-scoring-review.yml')
b<-targets::tar_read(benefits);h<-targets::tar_read(h8_access);pop<-targets::tar_read(dam_inputs)$population
raw<-b$raw[match(h$h3_id,b$raw$id),];pop<-pop[match(h$h3_id,pop$h3_id),]
stopifnot(identical(raw$id,h$h3_id),identical(pop$h3_id,h$h3_id),!anyDuplicated(raw$id))
origins<-data.frame(h3_id=h$h3_id,residents=pop$total_population,children=pop$children_under_18,
  drive_15=raw$drive__jobs_cumulative__total_jobs__15,drive_30=raw$drive__jobs_cumulative__total_jobs__30,
  transit_45=h$access_total_jobs)
stopifnot(all(is.finite(origins$drive_15)),all(origins$drive_15>=0),all(origins$drive_30>=origins$drive_15),
  all(is.na(origins$residents)|is.finite(origins$residents)&origins$residents>=0))
out<-'output/components/benefit-scoring-review/driving-benchmarks'
dir.create(out,recursive=TRUE,showWarnings=FALSE)
w<-origins$residents;known<-!is.na(w);den<-sum(w[known])
wq<-function(x,w,p) {keep<-!is.na(w)&w>0;o<-order(x[keep]);x<-x[keep][o];w<-w[keep][o];sapply(p,function(q)x[which(cumsum(w)/sum(w)>=q)[1]])}
distributions<-bind_rows(lapply(c(15,30),function(m) {
  v<-origins[[paste0('drive_',m)]]
  bind_rows(data.frame(minutes=m,weighting='Residents',percentile=c(10,25,50,75,90),jobs=wq(v,w,c(.1,.25,.5,.75,.9))),
    data.frame(minutes=m,weighting='Origins',percentile=c(10,25,50,75,90),jobs=as.numeric(quantile(v,c(.1,.25,.5,.75,.9)))))
}))
scenarios<-bind_rows(lapply(c(15,30),function(m) {
  v<-origins[[paste0('drive_',m)]]
  bind_rows(lapply(spec$driving$candidate_full_credit_jobs,function(t) {
    p<-pmin(v/t,1)
    data.frame(minutes=m,full_credit_jobs=t,origin_full_percent=100*mean(v>=t),
      resident_full_percent=100*sum(w[known & v>=t])/den,resident_full_count=sum(w[known & v>=t]),
      resident_mean_points=100*weighted.mean(p[known],w[known]),
      resident_below_half_target_percent=100*sum(w[known & v<t/2])/den)
  }))
}))
# Reconcile with the earlier equal-origin comparison before changing weighting.
old<-read.csv('output/components/benefit-scoring-review/driving_thresholds.csv')
old<-old[old$minimum_fraction==.5,]
k<-match(paste(scenarios$minutes,scenarios$full_credit_jobs),paste(old$minutes,old$full_credit_jobs))
stopifnot(!anyNA(k),all(abs(scenarios$origin_full_percent-100*old$full_credit_origins[k]/old$origins[k])<1e-9))
curve<-bind_rows(lapply(c(15,30),function(m) {
  v<-origins[[paste0('drive_',m)]]
  t<-sort(unique(c(0,v,v+1,1250000)))
  data.frame(minutes=paste(m,'minutes'),jobs=t,percent=vapply(t,function(t)100*sum(w[known & v>=t])/den,numeric(1)))
}))
p<-ggplot(curve,aes(jobs,percent,color=minutes))+
  geom_step(linewidth=1.1)+
  geom_vline(xintercept=c(250000,500000,1000000),color='#c3cbd0',linetype='dotted')+
  scale_color_manual(values=c('15 minutes'='#23677e','30 minutes'='#bd6b34'))+
  scale_x_continuous(breaks=seq(0,1250000,250000),labels=scales::label_number(scale=1e-3,suffix='k'),limits=c(0,1250000))+
  scale_y_continuous(breaks=seq(0,100,20),limits=c(0,100),labels=function(x)paste0(x,'%'))+
  labs(title='How many residents would receive full job-access credit?',
    subtitle='Driving job access: 15 versus 30 minutes',x='Candidate full-credit job benchmark',
    y='Residents at locations meeting the benchmark',color=NULL,
    caption=paste0('Denominator: ',format(round(den),big.mark=','),' residents with known population weights. ',sum(!known),' of ',nrow(origins),' origins lack weights.\nWhole-hex population estimates; total jobs, not jobs matched to residents. All modeled origins have driving estimates.'))+
  theme_minimal(base_size=12)+theme(legend.position='top',panel.grid.minor=element_blank(),plot.margin=margin(15,20,15,15))
ggsave(file.path(out,'driving-full-credit-comparison.png'),p,width=9,height=5.8,dpi=180,bg='white')
ggsave(file.path(out,'driving-full-credit-comparison.pdf'),p,width=9,height=5.8)
coverage<-data.frame(origins=nrow(origins),known_weight_origins=sum(known),missing_weight_origins=sum(!known),residents=den,
  transit_full_resident_percent=100*sum(w[known & origins$transit_45>=spec$transit$full_credit_jobs])/den)
job_modes<-list('Driving default'=list(field=paste0('drive_',spec$driving$default$minutes),spec=spec$driving$default),
  'Transit'=list(field=paste0('transit_',spec$transit$minutes),spec=spec$transit),
  'Driving sensitivity'=list(field=paste0('drive_',spec$driving$sensitivity$minutes),spec=spec$driving$sensitivity))
minimums<-bind_rows(lapply(names(job_modes),function(label) {
  mode<-job_modes[[label]];v<-origins[[mode$field]]
  stopifnot(length(v)==nrow(origins),all(is.finite(v)),all(v>=0))
  bind_rows(lapply(spec$job_minimum_sensitivity_fractions,function(f) {
    threshold<-f*mode$spec$full_credit_jobs
    data.frame(mode=label,minutes=mode$spec$minutes,full_credit_jobs=mode$spec$full_credit_jobs,
      minimum_fraction=f,minimum_jobs=threshold,resident_below_percent=100*sum(w[known & v<threshold])/den,
      residents_below=sum(w[known & v<threshold]),origin_below_percent=100*mean(v<threshold))
  }))
}))
tables<-list(origin_jobs=origins,distributions=distributions,scenarios=scenarios,coverage=coverage,job_minimums=minimums)
for(n in names(tables))write.csv(tables[[n]],file.path(out,paste0(n,'.csv')),row.names=FALSE,na='')
html_table<-function(d){d[]<-lapply(d,function(x)if(is.numeric(x))format(round(x,1),trim=TRUE,big.mark=',')else x)
  paste0('<table><thead><tr>',paste0('<th>',names(d),'</th>',collapse=''),'</tr></thead><tbody>',
    paste(apply(d,1,function(r)paste0('<tr>',paste0('<td>',r,'</td>',collapse=''),'</tr>')),collapse=''),'</tbody></table>')}
display<-scenarios |> select(minutes,full_credit_jobs,resident_full_percent) |>
  pivot_wider(names_from=minutes,values_from=resident_full_percent,names_prefix='Minutes ')
names(display)[1]<-'Full-credit jobs'
dist_display<-distributions |> filter(weighting=='Residents') |> select(-weighting) |>
  pivot_wider(names_from=percentile,values_from=jobs,names_prefix='p')
writeLines(paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Driving job benchmark options</title><style>body{max-width:1000px;margin:40px auto;padding:0 20px;font:16px/1.55 system-ui;color:#243541}img{width:100%}table{border-collapse:collapse}th,td{padding:8px;border-bottom:1px solid #ccd6dc;text-align:right}th{background:#edf3f4}.table{overflow-x:auto}</style><h1>Driving job access: 15 versus 30 minutes</h1>',
  '<p>Education decision recorded: economically disadvantaged growth; full credit 70; minimum 50; published scores retained with small-sample flags. Driving full credit is now 250,000 jobs in 15 minutes, with 1,000,000 jobs in 30 minutes retained as a sensitivity. Transit full credit remains 50,000 jobs in 45 minutes. The adopted job-domain minimum is 50% of each mode/time-specific full-credit benchmark.</p>',
  '<img src="driving-full-credit-comparison.png" alt="Share of residents receiving full credit as the job benchmark increases, separately at 15 and 30 minutes">',
  '<h2>Resident-weighted distribution</h2><div class="table">',html_table(dist_display),'</div>',
  '<h2>Residents at locations earning full credit (%)</h2><div class="table">',html_table(display),'</div>',
  '<p>Points = 100 × min(reachable jobs / full-credit benchmark, 1). Exactly the benchmark earns full credit. These percentages are conditional on known resident weights. They differ from the earlier equal-origin comparison because more densely populated locations have greater weight. Unknown population is excluded, not zero-filled. These are whole-hex estimates, not exact city-clipped counts.</p>',
  '<h2>Interpretation and candidate defaults</h2><p>A 15-minute measure emphasizes nearby employment; a 30-minute measure describes a broader driving labor market. At 30 minutes, 250,000 and 500,000 jobs give full credit to nearly all represented residents and leave little distinction among most locations. Candidate defaults are 250,000 jobs at 15 minutes or 1,000,000 jobs at 30 minutes; both award full credit to roughly 44–45% of represented residents, but capture different travel-time opportunities. Similar shares do not make the standards equivalent. A stricter 15-minute alternative is 300,000 jobs.</p>',
  '<p>Adopted prototype comparison: 15 minutes / 250,000 jobs as the primary scenario, with 30 minutes / 1,000,000 as a sensitivity. These are local prototype choices, not external adequacy standards. No benchmark is selected solely to match transit coverage.</p>',
  '<h2>Job minimum options</h2><div class="table">',html_table(minimums),'</div>',
  '<p>Adopted rule: a minimum of 50% of the relevant full-credit job benchmark. This requires 125,000 jobs within 15 minutes driving, 25,000 within 45 minutes transit, or 500,000 within 30 minutes for the driving sensitivity. Equality passes; below-minimum jobs cannot be compensated by other benefit domains. Points remain linear; the separate minimum flag does not zero the score. These comparisons use the same known resident denominator. A 40% floor is the less restrictive alternative. Different passing shares reflect differences in modeled access, not a requirement to equalize mode outcomes. A 30-minute sensitivity is a different assessment, not an override for a failed 15-minute minimum.</p>',
  '<p>The education minimum of 50 is a raw-growth threshold, not a generic 50% floor to copy across domains. No empirical sufficiency claim is established by choosing half of a prototype job benchmark.</p>',
  '<h2>Coverage and comparison with transit</h2><div class="table">',html_table(coverage),'</div>',
  '<p>Transit remains 50,000 total jobs in 45 minutes. Driving uses the November 3, 2026 DAM snapshot already validated by the pipeline. These are modeled job opportunities, not actual commutes, vacancies, or jobs matched to residents’ skills. The comparison does not establish the adequacy of a chosen standard.</p>',
  '<h2>Files and reproduction</h2><p>Run <code>Rscript scripts/compare_driving_benchmarks.R</code> after refreshing <code>scoring_comparison</code>.</p><ul>',
  paste0('<li><a href="',names(tables),'.csv">',names(tables),'.csv</a></li>',collapse=''),
  '<li><a href="driving-full-credit-comparison.pdf">Figure PDF</a></li></ul></html>'),file.path(out,'review.html'))
print(dist_display);print(display);print(scenarios[scenarios$minutes==15 & scenarios$full_credit_jobs%in%c(250000,300000) | scenarios$minutes==30 & scenarios$full_credit_jobs==1000000,]);print(coverage)
