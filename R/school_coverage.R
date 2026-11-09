# Coverage denominators are known ACS-based H8 resident/child estimates, never
# enrollment or test-taker counts. Unknown weights remain explicitly unknown.
school_population_coverage <- function(schools, population, spec) {
  a <- schools$assignments[schools$assignments$kind=="H8 origin",]
  stopifnot(all(a$level=="elementary"), !anyDuplicated(a$site_id),
    setequal(a$site_id,population$h3_id))
  a <- dplyr::left_join(a,population[c("h3_id","total_population","children_under_18")],
    by=c("site_id"="h3_id"),relationship="one-to-one")
  recognized <- !is.na(a$campus_id)
  masks <- list("AISD elementary assignment"=a$aisd_assignment,
    "Five-district elementary assignment"=recognized,
    "Overall growth available"=!is.na(a$overall))
  for(n in spec$subgroup_minimum_tests) masks[[paste0("Subgroup growth; minimum ",n," tests per subject")]] <-
    !is.na(a$subgroup) & !is.na(a$minimum_growth_tests) & a$minimum_growth_tests>=n
  summary <- dplyr::bind_rows(lapply(names(masks),function(label) {
    covered <- masks[[label]]; stopifnot(!anyNA(covered))
    dplyr::bind_rows(lapply(c("total_population","children_under_18"),function(group) {
      w <- a[[group]]; known <- !is.na(w)
      stopifnot(all(is.finite(w[known]) & w[known]>=0))
      data.frame(scenario=label,population_group=group,origins=nrow(a),covered_origins=sum(covered),
        known_weight_origins=sum(known),missing_weight_origins=sum(!known),
        covered_missing_weight_origins=sum(covered & !known),
        denominator=sum(w[known]),covered_population=sum(w[known & covered]),
        uncovered_population=sum(w[known & !covered]),
        population_coverage=sum(w[known & covered])/sum(w[known]))
    }))
  }))
  by_status <- a |> dplyr::mutate(district_id=ifelse(is.na(district_id),"Unassigned/ambiguous",district_id)) |>
    dplyr::group_by(district_id,status) |> dplyr::summarise(origins=dplyr::n(),
      total_population=sum(total_population,na.rm=TRUE),children_under_18=sum(children_under_18,na.rm=TRUE),
      missing_total_population=sum(is.na(total_population)),missing_child_population=sum(is.na(children_under_18)),.groups="drop")
  list(summary=summary,by_status=by_status,origins=a)
}
