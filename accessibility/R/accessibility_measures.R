# Shared destination-accessibility calculations.
#
# Inputs follow the accessibility package contract:
#   travel_matrix: from_id, to_id, and one numeric travel-cost column
#   land_use_data: id plus opportunity and optional demand columns
# Outputs retain the package result and add explicit scenario metadata.

assert_accessibility_inputs <- function(travel_matrix, land_use_data, travel_cost,
                                        opportunity, demand = NULL) {
  matrix_fields <- c("from_id", "to_id", travel_cost)
  land_use_fields <- c("id", opportunity, demand)
  missing_matrix <- setdiff(matrix_fields, names(travel_matrix))
  missing_land_use <- setdiff(land_use_fields, names(land_use_data))
  if (length(missing_matrix)) {
    stop("Travel matrix is missing: ", paste(missing_matrix, collapse = ", "))
  }
  if (length(missing_land_use)) {
    stop("Land-use data is missing: ", paste(missing_land_use, collapse = ", "))
  }
  if (anyDuplicated(land_use_data$id)) stop("land_use_data$id must be unique.")
  if (anyNA(travel_matrix[[travel_cost]]) || any(travel_matrix[[travel_cost]] < 0)) {
    stop("Travel costs must be complete and nonnegative.")
  }
  if (anyNA(land_use_data[[opportunity]]) || any(land_use_data[[opportunity]] < 0)) {
    stop("Opportunity values must be complete and nonnegative.")
  }
  invisible(TRUE)
}

accessibility_decay <- function(spec) {
  type <- spec$type %||% "exponential"
  switch(
    type,
    binary = accessibility::decay_binary(cutoff = spec$cutoff_minutes),
    exponential = accessibility::decay_exponential(decay_value = spec$decay_value),
    power = accessibility::decay_power(decay_value = spec$decay_value),
    logistic = accessibility::decay_logistic(
      cutoff = spec$cutoff_minutes, sd = spec$sd
    ),
    linear = accessibility::decay_linear(cutoff = spec$cutoff_minutes),
    stop("Unsupported decay type: ", type)
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

complete_origin_results <- function(result, origin_ids, method) {
  completed <- merge(
    data.frame(geography_id = as.character(origin_ids)), result,
    by = "geography_id", all.x = TRUE, sort = FALSE
  )
  completed <- completed[match(origin_ids, completed$geography_id), ]
  metadata_fields <- c(
    "destination", "mode", "period", "scenario", "measure", "opportunity_field",
    "parameter_name", "parameter_value"
  )
  for (field in metadata_fields) completed[[field]][is.na(completed[[field]])] <- result[[field]][[1]]
  if (method %in% c("cumulative_opportunities", "gravity_access")) {
    completed$access_value[is.na(completed$access_value)] <- 0
    completed$is_reachable[is.na(completed$is_reachable)] <- TRUE
  } else {
    completed$is_reachable[is.na(completed$is_reachable)] <- FALSE
  }
  completed
}

calculate_accessibility <- function(travel_matrix, land_use_data, measure,
                                    opportunity, travel_cost = "travel_time",
                                    demand = NULL, parameters = list(),
                                    group_by = character(), metadata = list()) {
  if (!requireNamespace("accessibility", quietly = TRUE)) {
    stop("Install the R package 'accessibility' before running this workflow.")
  }
  assert_accessibility_inputs(
    travel_matrix, land_use_data, travel_cost, opportunity, demand
  )

  result <- switch(
    measure,
    cumulative_opportunities = accessibility::cumulative_cutoff(
      travel_matrix, land_use_data, opportunity, travel_cost,
      cutoff = parameters$cutoff_minutes, group_by = group_by
    ),
    kth_nearest_time = accessibility::cost_to_closest(
      travel_matrix, land_use_data, opportunity, travel_cost,
      n = parameters$k, group_by = group_by
    ),
    gravity_access = accessibility::gravity(
      travel_matrix, land_use_data, opportunity, travel_cost,
      decay_function = accessibility_decay(parameters$decay), group_by = group_by
    ),
    floating_catchment = accessibility::floating_catchment_area(
      travel_matrix, land_use_data, opportunity, travel_cost, demand,
      method = parameters$method %||% "2sfca",
      decay_function = accessibility_decay(parameters$decay), group_by = group_by
    ),
    spatial_availability = accessibility::spatial_availability(
      travel_matrix, land_use_data, opportunity, travel_cost, demand,
      decay_function = accessibility_decay(parameters$decay),
      alpha = parameters$alpha %||% 1, group_by = group_by
    ),
    stop("Unsupported accessibility measure: ", measure)
  )

  result$measure <- measure
  for (field in names(metadata)) result[[field]] <- metadata[[field]]
  result
}
