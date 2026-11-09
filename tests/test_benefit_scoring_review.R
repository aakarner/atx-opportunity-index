# Regression checks for partial credit, required school coverage and sample rules.
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"),.libPaths()))
source("R/benefit_scoring_review.R")
stopifnot(identical(linear_benefit_points(c(0,49000,50000,75000,NA_real_),50000),
  c(0,.98,1,1,NA_real_)))
schools <- targets::tar_read(scoring_schools)
w <- schools$scores
for (metric in c("overall","subgroup","overall_percentile","subgroup_percentile")) {
  m <- as.matrix(w[paste(metric,"elementary",sep="_")])
  value <- w[[paste0(metric,"_mean")]]
  stopifnot(identical(is.na(value),rowSums(is.na(m))>0),
    isTRUE(all.equal(value,rowMeans(m),check.attributes=FALSE)))
}
# Growth-only sample sizes must be available and checked for both subjects.
campus <- readr::read_csv("data/processed/school_indicators/expanded_subgroup_comparison_2026.csv",
  col_types=readr::cols(campus_id="c"),show_col_types=FALSE)
idx <- match(schools$campuses$campus_id,campus$campus_id)
stopifnot(isTRUE(all.equal(schools$campuses$minimum_growth_tests,
  pmin(campus$ed_growth_reading_denominator[idx],campus$ed_growth_math_denominator[idx]))))
summaries <- schools$summaries
stopifnot(all(diff(summaries$paired)<=0))
stopifnot(all(schools$assignments$level=="elementary"),
  !any(grepl("_(middle|high)$",names(w))))
coverage <- targets::tar_read(school_coverage)
cs <- coverage$summary
stopifnot(all(abs(cs$denominator-cs$covered_population-cs$uncovered_population)<1e-6),
  all(cs$population_coverage>=0 & cs$population_coverage<=1),
  all(cs$known_weight_origins+cs$missing_weight_origins==cs$origins),
  all(cs$covered_missing_weight_origins<=cs$missing_weight_origins))
for(group in unique(cs$population_group)) {
  z <- cs[cs$population_group==group,]
  stopifnot(z$covered_population[z$scenario=="Five-district elementary assignment"] >
    z$covered_population[z$scenario=="AISD elementary assignment"],
    all(diff(z$covered_population[grepl("Subgroup",z$scenario)])<=0))
}
jobs <- targets::tar_read(scoring_jobs)
stopifnot(all(jobs$thresholds$mean_points>=0 & jobs$thresholds$mean_points<=1),
  all(jobs$thresholds$both_full+jobs$thresholds$drive_only_full==jobs$thresholds$full_credit_origins),
  all(jobs$sites$drive_30_jobs>=jobs$sites$drive_15_jobs))
cat("Scoring comparison passed for partial credit, school coverage, sample thresholds and job counts.\n")
