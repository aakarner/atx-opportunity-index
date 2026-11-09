# Run after scoring_comparison; uses its validated elementary assignments/population.
suppressPackageStartupMessages({library(ggplot2); library(dplyr); library(tidyr)})
root <- 'output/components/benefit-scoring-review'
out <- file.path(root,'education-benchmarks')
dir.create(out,recursive=TRUE,showWarnings=FALSE)
spec <- yaml::read_yaml('config/benefit-scoring-review.yml')$education
stopifnot(spec$measure=='economically_disadvantaged_growth',spec$small_sample_policy=='flag_only')
campuses <- read.csv(file.path(root,'school_campuses.csv'),colClasses=c(campus_id='character'))
origins <- read.csv(file.path(root,'school_origin_population.csv'),colClasses=c(campus_id='character',site_id='character'))
stopifnot(!anyDuplicated(campuses$campus_id),!anyDuplicated(origins$site_id),all(origins$level=='elementary'))
available <- !is.na(origins$subgroup)
regional <- campuses[!is.na(campuses$subgroup),]
local <- regional[regional$campus_id %in% origins$campus_id[available],]
stopifnot(all(origins$subgroup[available]==local$subgroup[match(origins$campus_id[available],local$campus_id)]),
          all(!is.na(origins$minimum_growth_tests[available])))
flag <- spec$small_sample_tests_each_subject
groups <- list('Schools represented in prototype'=data.frame(score=local$subgroup,w=1,small=local$minimum_growth_tests<flag),
               'Residents with usable scores'=data.frame(score=origins$subgroup,w=origins$total_population,small=origins$minimum_growth_tests<flag),
               'Children with usable scores'=data.frame(score=origins$subgroup,w=origins$children_under_18,small=origins$minimum_growth_tests<flag))
weighted_quantile <- function(x,w,p) {
  keep <- !is.na(x)&!is.na(w)&w>0; x<-x[keep];w<-w[keep];o<-order(x);x<-x[o];w<-w[o]
  vapply(p,function(q)x[which(cumsum(w)/sum(w)>=q)[1]],numeric(1))
}
quantiles <- bind_rows(lapply(names(groups),function(n) {
  g<-groups[[n]];data.frame(group=n,probability=c(0,.1,.25,.5,.75,.9,1),
    growth=weighted_quantile(g$score,g$w,c(0,.1,.25,.5,.75,.9,1)))
}))
# Weighted inverse-CDF quantiles also used for school counts, keeping conventions identical.
distribution <- bind_rows(lapply(names(groups),function(n) {
  g<-groups[[n]];g<-g[!is.na(g$score)&!is.na(g$w)&g$w>0,]
  g$bin <- 5*floor(g$score/5)
  g |> group_by(bin,small) |> summarise(weight=sum(w),.groups='drop') |>
    mutate(percent=100*weight/sum(weight),group=n)
}))
summary <- bind_rows(lapply(names(groups),function(n) {
  g<-groups[[n]];g<-g[!is.na(g$score)&!is.na(g$w),]
  data.frame(group=n,weight=sum(g$w),mean_growth=weighted.mean(g$score,g$w),
    small_sample_weight=sum(g$w[g$small]),small_sample_percent=100*sum(g$w[g$small])/sum(g$w))
}))
thresholds <- bind_rows(lapply(names(groups),function(n) {
  g<-groups[[n]];g<-g[!is.na(g$score)&!is.na(g$w),]
  bind_rows(lapply(sort(unique(c(spec$candidate_full_credit_growth,spec$candidate_minimum_growth))),function(t) {
    data.frame(group=n,threshold=t,at_or_above_percent=100*sum(g$w[g$score>=t])/sum(g$w),
      below_percent=100*sum(g$w[g$score<t])/sum(g$w),below_weight=sum(g$w[g$score<t]),
      at_or_above_weight=sum(g$w[g$score>=t]))
  }))
}))
scenarios <- bind_rows(lapply(names(groups),function(n) {
  g<-groups[[n]];g<-g[!is.na(g$score)&!is.na(g$w),]
  bind_rows(lapply(spec$candidate_full_credit_growth,function(b) bind_rows(lapply(spec$candidate_minimum_growth,function(m) {
    stopifnot(m<b)
    data.frame(group=n,full_credit_growth=b,minimum_growth=m,minimum_on_point_scale=100*m/b,
      below_minimum_percent=100*sum(g$w[g$score<m])/sum(g$w),
      between_percent=100*sum(g$w[g$score>=m & g$score<b])/sum(g$w),
      full_credit_percent=100*sum(g$w[g$score>=b])/sum(g$w),
      mean_points=weighted.mean(100*pmin(g$score/b,1),g$w))
  }))))
}))
stopifnot(all(abs(with(scenarios,below_minimum_percent+between_percent+full_credit_percent)-100)<1e-9))
coverage <- bind_rows(lapply(c('total_population','children_under_18'),function(n) {
  w<-origins[[n]];data.frame(group=n,known_population=sum(w,na.rm=TRUE),
    scored_population=sum(w[available],na.rm=TRUE),unscored_population=sum(w[!available],na.rm=TRUE),
    missing_weight_origins=sum(is.na(w)))
}))
tables<-list(quantiles=quantiles,distribution=distribution,summary=summary,thresholds=thresholds,scenarios=scenarios,coverage=coverage,represented_campuses=local)
for(n in names(tables)) write.csv(tables[[n]],file.path(out,paste0(n,'.csv')),row.names=FALSE,na='')
display <- distribution |> filter(group!='Residents with usable scores') |>
  mutate(group=factor(group,levels=c('Schools represented in prototype','Children with usable scores')),
    sample=ifelse(small,'Small sample: <20 tests in either subject','At least 20 tests in each subject'))
p<-ggplot(display,aes(bin+2.5,percent,fill=sample))+
  geom_col(width=4.5)+facet_wrap(~group,ncol=1)+
  scale_fill_manual(values=c('At least 20 tests in each subject'='#27677c','Small sample: <20 tests in either subject'='#d69c54'))+
  scale_x_continuous(breaks=seq(40,100,5),limits=c(39,101))+
  labs(title='Economically disadvantaged growth at assigned elementary schools',
    subtitle=paste0(nrow(local),' represented schools · ',format(round(coverage$scored_population[2]),big.mark=','),' children with usable scores'),
    x='Growth score (five-point bins: 40-44, 45-49, ...)',y='Share of schools or children (%)',fill=NULL,
    caption='Current assignments in five districts; 2025-26 growth. Children are residents under 18, not enrolled students.\nPopulation-weighted results use whole hexes classified at routing origins. Small samples remain included.')+
  theme_minimal(base_size=12)+theme(legend.position='bottom',panel.grid.minor=element_blank(),plot.margin=margin(15,20,15,15))+
  guides(fill=guide_legend(ncol=1))
ggsave(file.path(out,'education-growth-distribution.png'),p,width=10,height=8,dpi=180,bg='white')
ggsave(file.path(out,'education-growth-distribution.pdf'),p,width=10,height=8)
html_table<-function(d) {
  d[]<-lapply(d,function(x)if(is.numeric(x))format(round(x,1),trim=TRUE,big.mark=',')else x)
  paste0('<table><thead><tr>',paste0('<th>',names(d),'</th>',collapse=''),'</tr></thead><tbody>',
    paste(apply(d,1,function(x)paste0('<tr>',paste0('<td>',x,'</td>',collapse=''),'</tr>')),collapse=''),'</tbody></table>')
}
options_table <- function(values,below=FALSE) {
  z<-data.frame('Growth threshold'=values,check.names=FALSE)
  for(n in names(groups)) {
    x<-thresholds[thresholds$group==n,]
    z[[n]]<-x[[if(below)'below_percent' else 'at_or_above_percent']][match(values,x$threshold)]
  }
  names(z)<-c('Growth threshold','Schools (%)','Residents (%)','Children (%)');z
}
qdisplay<-quantiles |> mutate(percentile=paste0('p',100*probability)) |>
  select(group,percentile,growth) |> pivot_wider(names_from=percentile,values_from=growth)
child_scenarios<-scenarios[scenarios$group=='Children with usable scores',-1]
names(child_scenarios)<-c('Full credit','Minimum growth','Minimum points','Below minimum (%)','Partial credit, meets minimum (%)','Full credit (%)','Mean points')
writeLines(paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Elementary education benchmarks</title><style>body{max-width:1080px;margin:40px auto;padding:0 20px;font:16px/1.55 system-ui;color:#243541}img{width:100%}table{border-collapse:collapse;font-size:13px}td,th{padding:8px;border-bottom:1px solid #ccd6dc;text-align:right}th{background:#edf3f4}.table{overflow-x:auto}</style><h1>Elementary education benchmark options</h1>',
  '<p>Decision recorded: use economically disadvantaged growth; retain published scores and flag fewer than 20 evaluated tests in either subject. These counts are tests, not unique students. Overall growth remains context. The adopted rule gives full credit at growth 70 and requires growth of at least 50; other scenarios remain sensitivities.</p>',
  '<img src="education-growth-distribution.png" alt="School-count and child-population distributions of economically disadvantaged growth, with small samples highlighted">',
  '<p>The main school distribution counts each of ',nrow(local),' represented campuses once. The wider five-district source includes ',nrow(regional),' scored zoned campuses, including schools with no assigned prototype origin; those additional campuses do not enter this distribution. Weighted quantiles use the inverse empirical cumulative distribution, including for school counts.</p>',
  '<h2>Distribution and sample sizes</h2><p>Small-sample flags apply to ',sum(local$minimum_growth_tests<flag),' of ',nrow(local),' represented schools and ',round(summary$small_sample_percent[3],1),'% of children with usable scores. Scores range from ',min(local$subgroup),' to ',max(local$subgroup),'.</p><div class="table">',html_table(qdisplay),'</div>',
  '<h2>Candidate benchmarks and minimums</h2><p>Full credit: compare growth 65, 70, and 75. Minimum: independently compare growth 50, 55, and 60. Points = 100 × min(growth / full-credit benchmark, 1). A score equal to the minimum passes. A below-minimum flag is separate from points and cannot be offset by another domain. These are provisional local policy scenarios, not TEA adequacy standards. Growth is a points-based measure, not the percentage of students growing; subgroup values can exceed 100.</p>',
  '<h3>Share earning full credit</h3><div class="table">',html_table(options_table(spec$candidate_full_credit_growth)),
  '</div><h3>Share falling below the minimum</h3><div class="table">',html_table(options_table(spec$candidate_minimum_growth,TRUE)),
  '</div><h2>All nine combinations: children with usable scores</h2><div class="table">',html_table(child_scenarios),'</div>',
  '<p>Adopted rule: full credit at 70 with a minimum of 50; a minimum of 55 remains a sensitivity. The first gives 50/70 × 100 = 71.4 points at the minimum. A generic 50% point floor would instead require growth 35, below every currently observed score, and would flag no scored location. Keep the raw growth minimum explicit.</p>',
  '<h2>Denominators and missing data</h2>',html_table(coverage),
  '<p>Threshold shares above are conditional on usable growth and known population weights. Unscored locations remain incomplete, not passing or failing. Missing weights are excluded, not zero-filled. Children under 18 are not necessarily public-school attendees or economically disadvantaged. Sources are the validated scoring-comparison exports in the parent directory, based on current district-published elementary locators and 2020–2024 ACS estimates. Original locator vintage caveats remain in the parent report.</p>',
  '<h2>Reproduce and download</h2><p>Run <code>Rscript scripts/compare_education_benchmarks.R</code> after refreshing the scoring comparison.</p><ul>',
  paste0('<li><a href="',names(tables),'.csv">',names(tables),'.csv</a></li>',collapse=''),
  '<li><a href="education-growth-distribution.pdf">Distribution PDF</a></li></ul></html>'),file.path(out,'review.html'))
print(summary);print(thresholds);cat('Report:',file.path(out,'review.html'),'\n')
