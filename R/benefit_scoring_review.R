# Compare choices before adopting a combined benefits scoring rule.
linear_benefit_points <- function(value, target) {
  stopifnot(length(target)==1L, is.finite(target), target>0,
            all(is.na(value) | (is.finite(value) & value>=0)))
  pmin(1,value/target)
}

review_rank <- function(x) {
  n <- sum(!is.na(x))
  if (n<2) return(rep(NA_real_,length(x)))
  100*(rank(x,ties.method="average",na.last="keep")-1)/(n-1)
}

education_growth_score <- function(growth, minimum_tests, spec) {
  stopifnot(spec$measure=="economically_disadvantaged_growth",spec$small_sample_policy=="flag_only",
    spec$minimum_growth>0,spec$minimum_growth<spec$full_credit_growth)
  data.frame(education_points=100*linear_benefit_points(growth,spec$full_credit_growth),
    education_minimum_met=ifelse(is.na(growth),NA,growth>=spec$minimum_growth),
    education_small_sample=ifelse(is.na(growth),NA,minimum_tests<spec$small_sample_tests_each_subject))
}

school_score_comparison <- function(paths, spec, h8, sites) {
  names(paths) <- basename(paths)
  campus <- readr::read_csv(paths[[basename(spec$inputs$school_subgroups)]],
    col_types=readr::cols(campus_id="c"),show_col_types=FALSE)
  stopifnot(!anyDuplicated(campus$campus_id), all(campus$school_year==spec$growth_year))
  campus$minimum_growth_tests <- pmin(campus$ed_growth_reading_denominator,campus$ed_growth_math_denominator)
  zones <- read_school_zones(paths[[basename(spec$inputs$school_zones)]],spec)
  origins <- h3jsr::cell_to_point(h8$h3_id)
  points <- dplyr::bind_rows(
    sf::st_sf(site_id=h8$h3_id,kind="H8 origin",geometry=origins),
    sf::st_sf(site_id=sites$site_id,kind="Example address",geometry=sf::st_geometry(sf::st_transform(sites,4326))))
  assignments <- list()
  campus_results <- list()
  for (level in names(zones)) {
    z <- zones[[level]]
    campus_index <- match(z$campus_id,campus$campus_id)
    stopifnot(all(!is.na(campus_index) | z$score_status!="Available"),
      all(z$usable_growth==campus$overall_growth[campus_index],na.rm=TRUE))
    x <- campus[match(unique(stats::na.omit(z$campus_id)),campus$campus_id),]
    x$level <- level
    eligible_ids <- unique(z$campus_id[z$score_status=="Available"])
    x$overall <- ifelse(x$campus_id %in% eligible_ids & x$eligible,x$overall_growth,NA_real_)
    # Compare published whole-point overall growth with rounded pooled subgroup growth.
    x$subgroup <- ifelse(!is.na(x$overall),x$ed_growth_pooled,NA_real_)
    paired <- !is.na(x$overall) & !is.na(x$subgroup)
    x$overall_percentile <- review_rank(ifelse(paired,x$overall,NA_real_))
    x$subgroup_percentile <- review_rank(ifelse(paired,x$subgroup,NA_real_))
    campus_results[[level]] <- x[c("campus_id","campus_name","district_id","econ_disadv_pct","enrollment","level","overall","subgroup",
      "overall_percentile","subgroup_percentile","minimum_growth_tests")]
    a <- school_at_sites(points,z)
    a$level <- level
    a$kind <- points$kind
    a$district_id <- substr(a$campus_id,1,6)
    a$aisd_assignment <- !is.na(school_at_sites(points,z[z$district_id=="227901",])$campus_id)
    ix <- match(a$campus_id,x$campus_id)
    a$overall <- a$growth
    a$subgroup <- ifelse(a$status=="Available",x$subgroup[ix],NA_real_)
    a$minimum_growth_tests <- x$minimum_growth_tests[ix]
    a$overall_percentile <- ifelse(a$status=="Available",x$overall_percentile[ix],NA_real_)
    a$subgroup_percentile <- ifelse(a$status=="Available",x$subgroup_percentile[ix],NA_real_)
    assignments[[level]] <- a
  }
  assignments <- dplyr::bind_rows(assignments)
  stopifnot(!anyDuplicated(assignments[c("site_id","level")]))
  wide <- tidyr::pivot_wider(assignments[c("site_id","kind","level","overall","subgroup",
    "overall_percentile","subgroup_percentile","minimum_growth_tests")],
    names_from="level",values_from=c("overall","subgroup","overall_percentile","subgroup_percentile","minimum_growth_tests"))
  levels <- names(spec$school_level_weights)
  weights <- unlist(spec$school_level_weights[levels])
  stopifnot(all(weights>0),all(weights==weights[1]))
  for (metric in c("overall","subgroup","overall_percentile","subgroup_percentile")) {
    mat <- as.matrix(wide[paste(metric,levels,sep="_")])
    wide[[paste0(metric,"_mean")]] <- as.vector(mat %*% weights / sum(weights))
  }
  wide$minimum_growth_tests <- do.call(pmin,wide[paste("minimum_growth_tests",levels,sep="_")])
  wide <- cbind(wide,education_growth_score(wide$subgroup_mean,wide$minimum_growth_tests,spec$education))
  wide$subgroup_minus_overall <- wide$subgroup_mean-wide$overall_mean
  summaries <- lapply(spec$subgroup_minimum_tests,function(minimum) {
    h <- wide[wide$kind=="H8 origin",]
    paired <- !is.na(h$overall_mean) & !is.na(h$subgroup_mean) &
      !is.na(h$minimum_growth_tests) & h$minimum_growth_tests>=minimum
    delta <- h$subgroup_minus_overall[paired]
    data.frame(minimum_tests_each_growth_subject=minimum,origins=nrow(h),
      complete_overall=sum(!is.na(h$overall_mean)),
      complete_subgroup=sum(!is.na(h$subgroup_mean) & h$minimum_growth_tests>=minimum,na.rm=TRUE),
      paired=sum(paired),mean_overall=mean(h$overall_mean[paired]),
      mean_subgroup=mean(h$subgroup_mean[paired]),mean_difference=mean(delta),
      median_absolute_difference=stats::median(abs(delta)),
      lower_by_at_least_10=sum(delta<= -10),higher_by_at_least_10=sum(delta>=10),
      spearman=stats::cor(h$overall_mean[paired],h$subgroup_mean[paired],method="spearman"))
  })
  list(campuses=dplyr::bind_rows(campus_results),assignments=assignments,scores=wide,
    summaries=dplyr::bind_rows(summaries))
}

driving_threshold_comparison <- function(benefits,h8,sites,spec) {
  rows <- benefits$raw[match(h8$h3_id,benefits$raw$id),]
  stopifnot(identical(rows$id,h8$h3_id))
  transit <- h8$access_total_jobs
  result <- list()
  distributions <- list()
  site_ids <- h3jsr::point_to_cell(sites,res=8)
  examples <- data.frame(site_id=sites$site_id,site=sites$label,h3_id=site_ids)
  k <- match(site_ids,rows$id)
  examples$transit_45_jobs <- transit[k]
  examples$transit_points <- linear_benefit_points(transit[k],spec$transit$full_credit_jobs)
  for (minutes in spec$driving$minutes) {
    field <- paste0("drive__jobs_cumulative__total_jobs__",minutes)
    jobs <- rows[[field]]
    stopifnot(all(is.finite(jobs)),all(jobs>=0))
    examples[[paste0("drive_",minutes,"_jobs")]] <- jobs[k]
    distributions[[as.character(minutes)]] <- data.frame(minutes,
      as.list(setNames(stats::quantile(jobs,c(0,.1,.25,.5,.75,.9,1)),c("min","p10","p25","median","p75","p90","max"))))
    for (target in spec$driving$candidate_full_credit_jobs) {
      points <- linear_benefit_points(jobs,target)
      for (floor in spec$candidate_domain_floors) {
        transit_pass <- transit>=spec$transit$full_credit_jobs
        drive_pass <- jobs>=target
        result[[length(result)+1L]] <- data.frame(minutes,full_credit_jobs=target,minimum_fraction=floor,
          origins=length(jobs),full_credit_origins=sum(drive_pass),
          below_minimum=sum(points<floor),mean_points=mean(points),
          both_full=sum(drive_pass & transit_pass),drive_only_full=sum(drive_pass & !transit_pass),
          transit_only_full=sum(!drive_pass & transit_pass))
      }
    }
  }
  stopifnot(all(examples$drive_30_jobs>=examples$drive_15_jobs))
  list(distribution=dplyr::bind_rows(distributions),thresholds=dplyr::bind_rows(result),sites=examples,
    transit=data.frame(minutes=45,target=spec$transit$full_credit_jobs,
      origins=length(transit),full_credit_origins=sum(transit>=spec$transit$full_credit_jobs),
      mean_points=mean(linear_benefit_points(transit,spec$transit$full_credit_jobs))))
}

write_scoring_comparison <- function(schools,jobs,spec,source_files,directory,coverage) {
  names(source_files) <- basename(source_files)
  root <- file.path(directory,"benefit-scoring-review")
  dir.create(root,recursive=TRUE,showWarnings=FALSE)
  tables <- list(school_campuses=schools$campuses,school_assignments=schools$assignments,
    school_origin_scores=schools$scores,school_summary=schools$summaries,
    driving_distribution=jobs$distribution,driving_thresholds=jobs$thresholds,
    example_jobs=jobs$sites,transit_reference=jobs$transit,
    school_population_coverage=coverage$summary,school_coverage_by_status=coverage$by_status,
    school_origin_population=coverage$origins,source_manifest=source_manifest(source_files))
  csvs <- vapply(names(tables),function(name) {
    p <- file.path(root,paste0(name,".csv"));readr::write_csv(tables[[name]],p,na="");p
  },character(1))
  school_sites <- subset(schools$scores,kind=="Example address")
  school_sites <- school_sites[c("site_id","overall_mean","subgroup_mean","subgroup_minus_overall","minimum_growth_tests")]
  school_sites$site_id <- jobs$sites$site[match(school_sites$site_id,jobs$sites$site_id)]
  names(school_sites) <- c("Example site","Overall growth","Subgroup growth","Difference","Smallest growth sample")
  school_summary <- data.frame(
    "Minimum tests per growth subject"=schools$summaries$minimum_tests_each_growth_subject,
    "Complete origins"=schools$summaries$paired,
    "Mean overall growth"=round(schools$summaries$mean_overall,1),
    "Mean subgroup growth"=round(schools$summaries$mean_subgroup,1),
    "Median absolute difference"=schools$summaries$median_absolute_difference,
    "Rank correlation"=round(schools$summaries$spearman,2),check.names=FALSE)
  residents <- subset(coverage$summary,population_group=="total_population")
  children <- subset(coverage$summary,population_group=="children_under_18")
  stopifnot(identical(residents$scenario,children$scenario))
  coverage_display <- data.frame(Scenario=residents$scenario,Origins=residents$covered_origins,
    "Residents covered"=round(residents$covered_population),"Residents (%)"=round(100*residents$population_coverage,1),
    "Children covered"=round(children$covered_population),"Children (%)"=round(100*children$population_coverage,1),check.names=FALSE)
  floors <- subset(jobs$thresholds,minimum_fraction==0.5)
  floors$full_credit_percent <- round(100*floors$full_credit_origins/floors$origins,1)
  floors$below_half_target_percent <- round(100*floors$below_minimum/floors$origins,1)
  floors$mean_points <- round(100*floors$mean_points,1)
  floors <- floors[c("minutes","full_credit_jobs","full_credit_percent","below_half_target_percent","mean_points")]
  names(floors) <- c("Drive minutes","Full-credit jobs","Full credit (%)","Below half target (%)","Mean points")
  plotted <- subset(schools$scores,kind=="H8 origin" & !is.na(overall_mean) & !is.na(subgroup_mean))
  plotted$sample <- ifelse(plotted$minimum_growth_tests<20,"At least one subject below 20 tests","All subjects at least 20 tests")
  plot <- ggplot2::ggplot(plotted,ggplot2::aes(overall_mean,subgroup_mean,color=sample)) +
    ggplot2::geom_abline(slope=1,intercept=0,color="grey65") +
    ggplot2::geom_point(alpha=.5,size=1.5) +
    ggplot2::coord_equal() + ggplot2::theme_minimal(base_size=12) +
    ggplot2::scale_color_manual(values=c("At least one subject below 20 tests"="#b9693b",
      "All subjects at least 20 tests"="#255c77")) +
    ggplot2::theme(legend.position="bottom",legend.title=ggplot2::element_blank(),
      plot.margin=ggplot2::margin(16,16,16,16)) +
    ggplot2::guides(color=ggplot2::guide_legend(nrow=2)) +
    ggplot2::labs(title="Assigned-school growth at Austin H8 origins",
      subtitle="Current published elementary assignments · 2025–26 outcomes",
      x="Elementary overall growth",y="Elementary economically disadvantaged growth",
      caption="Elementary schools only. Points can share campuses and overlap.")
  figure <- file.path(root,"school-growth-comparison.png")
  ggplot2::ggsave(figure,plot,width=8,height=6,dpi=160,bg="white")
  html <- paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Benefits scoring comparison</title><style>body{font:16px/1.5 system-ui;max-width:960px;margin:3rem auto;padding:0 1rem;color:#243541}h1,h2{line-height:1.2}h2{margin-top:2rem}table{border-collapse:collapse;font-size:14px}th,td{padding:.5rem;border-bottom:1px solid #ddd;text-align:left}th{background:#edf3f4}.table-scroll{overflow:auto}img{max-width:100%}a{color:#1b6475}</style>',
    '<h1>Education and driving employment comparisons</h1>',
    '<p>Education now uses only the assigned neighborhood elementary school. Coverage includes Austin, Round Rock, Pflugerville, Del Valle and Manor ISDs. We use the districts’ currently published attendance locators for 2026–27 and the same 2025–26 overall and economically disadvantaged growth measures. Middle and high schools do not enter the education measure. Employment points rise linearly to the full-credit job target and are capped at one.</p>',
    '<p>Boundary provenance: AISD explicitly labels its assignments 2026–27. Round Rock and Pflugerville live maps retain 2025–26 labels; Manor’s 2026–27 locator retains elementary boundaries labeled 24–25, matching the district’s fall-2024 boundary change notice. Del Valle uses the Current scenario, excluding future proposals. These are current district-published locators, not new district-certified GIS exports. Original source labels are retained in the map and source manifest.</p>',
    '<p>Among complete locations, the mean difference between subgroup and overall growth is ',
    round(schools$summaries$mean_difference[1],1),
    ' points. Requiring 20 tests in each growth subject reduces complete origins from ',
    schools$summaries$paired[1],' to ',
    schools$summaries$paired[schools$summaries$minimum_tests_each_growth_subject==20],
    '. These comparisons require a choice between coverage and the treatment of small samples.</p>',
    '<h2>Education at the example addresses</h2>',report_html_table(school_sites),
    '<p>Values are raw growth points at the assigned elementary campus. Raw growth is a points-based outcome and can exceed 100 for a subgroup. An unavailable elementary score leaves education unavailable. Education uses 100 × min(subgroup growth / 70, 1), with a separate raw-growth minimum of 50. Small-sample flags do not change points. The existing *_mean export fields now contain the single elementary value for compatibility.</p>',
    '<h2>Population and child coverage</h2>',report_html_table(coverage_display),
    '<p>Known-weight denominator: ',format(round(residents$denominator[1]),big.mark=","),' residents and ',
    format(round(children$denominator[1]),big.mark=","),' children under 18. Missing weights: ',residents$missing_weight_origins[1],
    ' of ',residents$origins[1],' origins. The AISD baseline is evaluated separately; cross-district overlaps can make an expanded-layer assignment ambiguous.</p>',
    '<p>Children means residents under 18, not enrolled students or test takers. Both populations use 2020–2024 ACS block-group estimates allocated with the same census-block weights; the reconstructed total matches the existing DAM population estimates. Denominators include only known weights. Missing-weight origins are reported explicitly and are not counted as zero. These are whole-hex population estimates classified by routing origin, not exact city- or attendance-boundary-clipped resident counts. Geographic assignment coverage and usable growth-score coverage are separate.</p>',
    report_html_table(coverage$by_status),
    '<h2>Education across the prototype footprint</h2>',report_html_table(school_summary),
    '<img src="school-growth-comparison.png" alt="Scatterplot comparing overall and economically disadvantaged growth across complete H8 assignments">',
    '<p>Each point represents an H8 routing origin inside the prototype footprint. Counts are unweighted origins, and neighboring origins can share schools. They are not independent campus observations. The percentile sensitivity pools zoned elementary campuses across all five districts, one vote per campus, with both growth measures available. This reference remains fixed as sample thresholds change. Minimum sample checks apply to each elementary growth subject and do not use achievement-test denominators. Minimums of 10, 20 and 30 are analytical sensitivities, not adopted exclusion rules.</p>',
    '<h2>Driving job thresholds</h2>',report_html_table(floors),
    '<p>Full credit and below-half-target percentages count all 1,029 prototype H8 origins. Mean points use a 0–100 display scale. The downloadable table also tests domain floors at 60% and 70%. These are candidate floors, awaiting a decision.</p>',
    '<h2>Transit reference</h2>',report_html_table(jobs$transit),
    '<p>The comparison awards full credit at 50,000 total jobs in 45 minutes. This implements min(jobs / 50,000, 1), so exactly 50,000 qualifies. The earlier map flag used strictly greater than 50,000.</p>',
    '<h2>Jobs at the example addresses</h2>',report_html_table(jobs$sites),
    '<h2>Decisions recorded</h2><p>Families use equal domain weights. Older adults use 75% everyday destinations and 25% employment. Single adults use 40% everyday destinations and 60% employment. Education has zero weight in those two adult profiles. Adult PSH uses 75% destinations and 25% jobs; 50/50 remains a sensitivity. User-adjustable weights should retain a fixed set of applicable domains for minimum requirements. Missing required education leaves a combined assessment incomplete.</p>',
    '<h2>Decisions remaining</h2><p>Economically disadvantaged elementary growth is selected, with published small-sample scores retained and flagged below 20 tests in either subject. Education full credit is set at growth 70 and its minimum at 50. Driving full credit is 250,000 jobs in 15 minutes, with 1,000,000 jobs in 30 minutes as a sensitivity. Job minimums are set at 50% of each mode-specific full-credit target. Destination minimums are three of four types for families/older/single and two of three for adult PSH, with groceries required. The combined score and minimum status are displayed separately. Adult PSH is provisional; a family-serving PSH preset remains outside this release. Education now has one elementary-school value rather than a school-level average. The data comparison does not establish the remaining policy choices.</p>',
    '<h2>Files</h2><ul>',paste0('<li><a href="',basename(csvs),'">',basename(csvs),'</a></li>',collapse=""),'</ul></html>')
  report <- file.path(root,"review.html");writeLines(html,report)
  c(csvs,figure,report)
}
