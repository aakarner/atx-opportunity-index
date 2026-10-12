# Focused regression checks for reassignment matching and spatial ambiguity.
# Run from the repository root: Rscript tests/test_aisd_school_access.R
source("scripts/prepare/build_school_assignments.R")

stopifnot(identical(school_name_key(c("Sánchez ES", "Travis Heights ES",
  " Reassignment Wooldrige ES/Reasignación de Wooldrige ES", "Marshall MS")),
  c("SANCHEZ", "TRAVIS HTS", "WOOLDRIDGE", "GENERAL MARSHALL")))

campuses <- tibble(campus_id = c("227901132", "227901185"),
  campus_name = c("REILLY EL", "BLAZIER EL"), school_type = "Elementary",
  year = 2026L, growth = c(78, 71), growth_token = c("78", "71"),
  paired = c(FALSE, TRUE), grade_span = c("PK - 05", "03 - 06"),
  eligible = c(TRUE, FALSE), exclusion_reason = c("Included", "Paired accountability record"))
x <- data.frame(assigned_school_label = c("Reassignment Reilly ES/Reasignación de Reilly ES", "Blazier ES"),
  ELEM_ = c(133, 185), reassignment_flag = c(TRUE, FALSE), assignment_school_year = "2026-27")
joined <- match_assignments(x, campuses, "elementary")
stopifnot(joined$campus_id[1] == "227901132", !joined$legacy_code_agrees[1],
  joined$usable_growth[1] == 78, is.na(joined$usable_growth[2]),
  joined$reported_growth[2] == 71, all(joined$score_predates_assignment_year))
x$reassignment_flag[1] <- FALSE
stopifnot(inherits(try(match_assignments(x, campuses, "elementary"), silent = TRUE), "try-error"))
x$assigned_school_label[1] <- "Unknown ES"
stopifnot(inherits(try(match_assignments(x, campuses, "elementary"), silent = TRUE), "try-error"))

rectangle <- function(left, right) st_polygon(list(matrix(c(left, 0, right, 0,
  right, 10, left, 10, left, 0), ncol = 2, byrow = TRUE)))
zones <- function(ids, left, right) st_sf(campus_id = ids, campus_name = ids,
  usable_growth = rep(70, length(ids)),
  geom = st_sfc(Map(rectangle, left, right), crs = 5070))
old <- zones(c("a", "b"), c(0, 5), c(5, 10))
new <- zones(c("c", "d"), c(0, 5), c(6, 9))
delta <- compare_assignments(old, new, "elementary")
area <- function(x, status) sum(x$area_sq_m[x$assignment_status == status])
stopifnot(abs(area(delta, "Changed") - 80) < 1e-6,
  abs(area(delta, "Ambiguous source overlap") - 10) < 1e-6,
  abs(area(delta, "No 2026-27 coverage") - 10) < 1e-6,
  abs(sum(delta$area_sq_m) - 100) < 1e-6)

# Overlapping pieces assigned to the same campus are not an ambiguous choice.
new$campus_id <- "c"; new$campus_name <- "c"
delta <- compare_assignments(old, new, "elementary")
stopifnot(area(delta, "Ambiguous source overlap") == 0,
  abs(area(delta, "Changed") - 90) < 1e-6)
delta <- compare_assignments(old, old, "elementary")
stopifnot(abs(area(delta, "Unchanged") - 100) < 1e-6,
  area(delta, "Changed") == 0, all(delta$growth_difference == 0))
cat("AISD matching, score exclusions, and spatial comparison checks passed.\n")
