source("accessibility/R/accessibility_measures.R")
source("accessibility/R/accessibility_scenarios.R")

travel <- data.frame(
  from_id = c("a", "a", "b", "b"),
  to_id = c("x", "y", "x", "y"),
  travel_time = c(5, 15, 10, 4)
)
land_use <- data.frame(
  id = c("a", "b", "x", "y"),
  facilities = c(0, 0, 2, 3),
  population = c(10, 20, 0, 0)
)

cumulative <- calculate_accessibility(
  travel, land_use, "cumulative_opportunities", "facilities",
  parameters = list(cutoff_minutes = 10),
  metadata = list(mode = "drive", period = "test")
)
stopifnot(
  identical(cumulative$id, c("a", "b")),
  identical(cumulative$facilities, c(2, 5)),
  all(cumulative$measure == "cumulative_opportunities"),
  all(cumulative$mode == "drive")
)

closest <- calculate_accessibility(
  travel, land_use, "kth_nearest_time", "facilities",
  parameters = list(k = 2)
)
stopifnot(identical(closest$travel_time, c(5, 4)))

completed_closest <- complete_origin_results(
  data.frame(
    geography_id = "a", destination = "test", mode = "transit", period = "test",
    scenario = "test", measure = "kth_nearest_time", opportunity_field = "facilities",
    parameter_name = "k", parameter_value = 1, access_value = 5,
    is_reachable = TRUE
  ),
  c("a", "b"), "kth_nearest_time"
)
stopifnot(nrow(completed_closest) == 2, is.na(completed_closest$access_value[[2]]),
          !completed_closest$is_reachable[[2]])

completed_cumulative <- complete_origin_results(
  transform(completed_closest[1, ], measure = "cumulative_opportunities"),
  c("a", "b"), "cumulative_opportunities"
)
stopifnot(completed_cumulative$access_value[[2]] == 0,
          completed_cumulative$is_reachable[[2]])

gravity <- calculate_accessibility(
  travel, land_use, "gravity_access", "facilities",
  parameters = list(decay = list(type = "exponential", decay_value = 0.1))
)
stopifnot(all(is.finite(gravity$facilities)), all(gravity$facilities >= 0))

config <- read_accessibility_scenarios()
scenarios <- accessibility_scenario_table(config)
stopifnot(nrow(scenarios) == length(config$measures))

cat("Destination accessibility configuration and measure checks passed.\n")
