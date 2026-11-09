# Compare integer destination-basket minimums using validated cached indicators.
if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
suppressPackageStartupMessages(library(dplyr))
b<-targets::tar_read(benefits);pop<-targets::tar_read(dam_inputs)$population
spec<-yaml::read_yaml('config/benefits.yml')
stopifnot(isTRUE(all.equal(spec,targets::tar_read(benefit_spec))))
p<-pop[match(b$scores$id,pop$h3_id),]
stopifnot(identical(b$scores$id,p$h3_id),!anyDuplicated(b$scores$id))
out<-'output/components/benefit-scoring-review/destination-minimums'
dir.create(out,recursive=TRUE,showWarnings=FALSE)
rows<-list();origin_rows<-list()
for(mode in names(spec$defaults))for(profile in c('families','older','single','supportive')) {
  minutes<-spec$defaults[[mode]];prefix<-paste(mode,minutes,sep='_')
  members<-spec$profiles[[profile]];n<-length(members)
  count<-b$scores[[paste(prefix,profile,sep='_')]]
  grocery<-b$scores[[paste(prefix,'grocery',sep='_')]]
  check<-rowSums(b$scores[paste(prefix,members,sep='_')])
  stopifnot(identical(count,check),all(is.na(grocery)|grocery%in%c(0,1)))
  origin_rows[[length(origin_rows)+1]]<-data.frame(h3_id=b$scores$id,mode,minutes,profile,
    basket_size=n,reachable_types=count,grocery_reachable=grocery,residents=p$total_population)
  for(k in 2:n)for(require_grocery in c(FALSE,TRUE)) {
    w<-p$total_population;available<-!is.na(count)&(!require_grocery|!is.na(grocery))
    known<-!is.na(w)&available
    failed<-count<k | (require_grocery & grocery==0)
    stopifnot(all(!is.na(failed[known])))
    rows[[length(rows)+1]]<-data.frame(mode,minutes,profile,basket_size=n,minimum_types=k,
      minimum_points=100*k/n,require_grocery,known_scored_residents=sum(w[known]),
      below_minimum_residents=sum(w[known & available & !is.na(failed) & failed]),
      below_minimum_percent=100*sum(w[known & available & !is.na(failed) & failed])/sum(w[known]),
      missing_population_origins=sum(is.na(w)),missing_score_origins=sum(!available))
  }
}
results<-bind_rows(rows);origins<-bind_rows(origin_rows)
write.csv(results,file.path(out,'thresholds.csv'),row.names=FALSE)
write.csv(origins,file.path(out,'origin_destinations.csv'),row.names=FALSE,na='')
recommended<-results[results$minimum_types==results$basket_size-1 & results$require_grocery,]
html_table<-function(d) {
  d[]<-lapply(d,function(x)if(is.numeric(x))format(round(x,1),trim=TRUE,big.mark=',')else x)
  paste0('<table><thead><tr>',paste0('<th>',names(d),'</th>',collapse=''),'</tr></thead><tbody>',
    paste(apply(d,1,function(r)paste0('<tr>',paste0('<td>',r,'</td>',collapse=''),'</tr>')),collapse=''),'</tbody></table>')
}
display<-recommended[c('profile','mode','minutes','minimum_types','basket_size','below_minimum_percent')]
names(display)<-c('Profile','Mode','Minutes','Required types','Basket size','Residents below minimum (%)')
writeLines(paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Everyday destination minimums</title><style>body{font:16px/1.5 system-ui;max-width:1000px;margin:40px auto;padding:0 20px;color:#243541}table{border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #ccd6dc;text-align:right}th{background:#edf3f4}.table{overflow:auto}</style><h1>Everyday destination minimums</h1>',
  '<p>Adopted prototype rule: three of four types for families, older adults, and single adults; two of three for the provisional adult PSH basket; grocery must be one of the reachable types. These rules allow at most one missing type in the current small housing-profile baskets. They do not define a rule for the exploratory eight-type general basket.</p>',
  '<p>Current time budgets are 15 minutes driving and 45 minutes transit/walking, matching the job-access defaults. Each type earns one point if at least one destination is reachable within the inclusive time budget; more establishments of the same type do not substitute for another type. Full credit requires all types. A below-minimum flag does not zero the score.</p>',
  '<h2>Effect of the adopted rule</h2><div class="table">',html_table(display),'</div>',
  '<p>Families: grocery, childcare, park, library. Older and single adults: grocery, pharmacy, urgent care, community/senior center. Provisional adult PSH: grocery, pharmacy, urgent care. These baskets remain trial definitions; the adult PSH basket does not fully describe supportive-service needs.</p>',
  '<h2>All comparisons</h2><div class="table">',html_table(results),'</div>',
  '<p>The 50% alternative requires two of four types, or two of three after rounding up. A universal 75% rule would require all three PSH types; explicit count minimums avoid hiding that consequence. Requiring groceries means parks, libraries, or other services cannot compensate for missing grocery access. The grocery condition is an adopted prototype policy choice.</p>',
  '<p>Shares use known total resident weights at origins with complete destination scores, not profile-specific populations. Older and single profiles currently have identical baskets and therefore identical destination coverage. Whole-hex populations are classified using routing-origin accessibility; unknown weights are excluded, not zero-filled. Modeled non-reach remains distinct from unknown input. Missing required input leaves assessment incomplete.</p>',
  '<p>Reproduce: <code>Rscript scripts/compare_destination_minimums.R</code>. Inputs: cached validated benefits, population, and current config/benefits.yml.</p>',
  '<p><a href="thresholds.csv">All threshold comparisons</a> · <a href="origin_destinations.csv">Origin indicators and resident weights</a></p></html>'),file.path(out,'review.html'))
print(display)
