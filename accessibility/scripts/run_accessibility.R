#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(h3jsr)
  library(readr)
  library(sf)
})

source("accessibility/R/accessibility_measures.R")
source("accessibility/R/accessibility_scenarios.R")
source("accessibility/R/travel_matrices.R")

parse_cli <- function(args) {
  values <- list(config = "config/destination_accessibility.yml", output_dir = NULL)
  i <- 1L
  while (i <= length(args)) {
    key <- sub("^--", "", args[[i]])
    if (i == length(args) || !startsWith(args[[i]], "--")) stop("Invalid command line.")
    values[[gsub("-", "_", key)]] <- args[[i + 1L]]
    i <- i + 2L
  }
  values
}

apply_inventory_filters <- function(layer, filters) {
  if (is.null(filters)) return(layer)
  for (field in names(filters)) {
    rule <- filters[[field]]
    if (!field %in% names(layer)) stop("Inventory filter field is missing: ", field)
    if (!is.null(rule$include)) layer <- layer[layer[[field]] %in% unlist(rule$include), ]
    if (!is.null(rule$exclude)) layer <- layer[!layer[[field]] %in% unlist(rule$exclude), ]
    if (isTRUE(rule$not_missing)) layer <- layer[!is.na(layer[[field]]), ]
    if (!is.null(rule$greater_than)) layer <- layer[!is.na(layer[[field]]) & layer[[field]] > rule$greater_than, ]
  }
  layer
}

opportunity_values <- function(layer, definitions) {
  values <- lapply(definitions, function(definition) {
    if (is.numeric(definition)) rep(as.numeric(definition), nrow(layer)) else {
      field <- as.character(definition)
      if (!field %in% names(layer)) stop("Opportunity field is missing: ", field)
      as.numeric(layer[[field]])
    }
  })
  as.data.frame(values, check.names = FALSE)
}

standardize_measure_result <- function(result, scenario, destination, mode, period,
                                       opportunity_field, parameter_name = NA_character_,
                                       parameter_value = NA_real_) {
  value_fields <- setdiff(
    names(result),
    c("id", "measure", "mode", "period", "scenario", "destination",
      "opportunity_field", "parameter_name", "parameter_value")
  )
  if (length(value_fields) != 1L) {
    stop("Expected one accessibility value column; found: ", paste(value_fields, collapse = ", "))
  }
  access_value <- as.numeric(result[[value_fields]])
  data.frame(
    geography_id = as.character(result$id),
    destination = destination,
    mode = mode,
    period = period,
    scenario = scenario,
    measure = result$measure,
    opportunity_field = opportunity_field,
    parameter_name = parameter_name,
    parameter_value = parameter_value,
    access_value = ifelse(is.finite(access_value), access_value, NA_real_),
    is_reachable = is.finite(access_value),
    stringsAsFactors = FALSE
  )
}

calculate_scenario_results <- function(travel_matrix, land_use, scenario, scenario_name,
                                       destination, mode, period, origin_ids) {
  results <- list()
  for (opportunity_field in unlist(scenario$opportunity_fields)) {
    if (scenario$method == "cumulative_opportunities") {
      for (threshold in unlist(scenario$thresholds_minutes)) {
        value <- calculate_accessibility(
          travel_matrix, land_use, scenario$method, opportunity_field,
          parameters = list(cutoff_minutes = threshold)
        )
        standardized <- standardize_measure_result(
          value, scenario_name, destination, mode, period, opportunity_field,
          "cutoff_minutes", threshold
        )
        results[[length(results) + 1L]] <- complete_origin_results(
          standardized, origin_ids, scenario$method
        )
      }
    } else {
      parameters <- list(k = scenario$k, decay = scenario$decay,
                         method = scenario$catchment_method, alpha = scenario$alpha)
      value <- calculate_accessibility(
        travel_matrix, land_use, scenario$method, opportunity_field,
        demand = scenario$demand_field, parameters = parameters
      )
      standardized <- standardize_measure_result(
        value, scenario_name, destination, mode, period, opportunity_field,
        if (scenario$method == "kth_nearest_time") "k" else NA_character_,
        if (scenario$method == "kth_nearest_time") scenario$k else NA_real_
      )
      results[[length(results) + 1L]] <- complete_origin_results(
        standardized, origin_ids, scenario$method
      )
    }
  }
  bind_rows(results)
}

args <- parse_cli(commandArgs(trailingOnly = TRUE))
if (is.null(args$scenario)) stop("Provide --scenario NAME.")
config <- read_accessibility_scenarios(args$config)
scenario <- config$measures[[args$scenario]]
if (is.null(scenario)) stop("Unknown scenario: ", args$scenario)
mode <- args$mode %||% if (length(scenario$modes) == 1L) scenario$modes[[1]] else NULL
period <- args$period %||% if (length(scenario$periods) == 1L) scenario$periods[[1]] else NULL
if (is.null(mode) || !mode %in% unlist(scenario$modes)) stop("Select an allowed --mode.")
if (is.null(period) || !period %in% unlist(scenario$periods)) stop("Select an allowed --period.")

inventory_name <- scenario$inventory
inventory_spec <- config$inventories[[inventory_name]]
mode_spec <- config$modes[[mode]]
period_spec <- config$periods[[period]]
scenario_output_dir <- args$output_dir %||% file.path(
  "accessibility/output/working", args$scenario, mode, period
)
dir.create(scenario_output_dir, recursive = TRUE, showWarnings = FALSE)

grid <- st_read(config$geography$origin_grid, quiet = TRUE) |> st_transform(4326)
origin_id_field <- config$geography$origin_id
if (!origin_id_field %in% names(grid)) stop("Origin ID is absent from the grid.")
origin_ids <- as.character(grid[[origin_id_field]])
if (anyNA(origin_ids) || anyDuplicated(origin_ids)) stop("Origin IDs must be complete and unique.")
origin_points <- st_as_sf(
  st_drop_geometry(grid), coords = c("center_longitude", "center_latitude"), crs = 4326
)
origin_coordinates <- st_coordinates(origin_points)
origins_r5 <- data.frame(id = origin_ids, lon = origin_coordinates[, 1], lat = origin_coordinates[, 2])

if (identical(inventory_spec$format, "h8_csv")) {
  inventory <- read_csv(inventory_spec$path, show_col_types = FALSE) |>
    apply_inventory_filters(inventory_spec$filters)
  inventory_points <- h3jsr::cell_to_point(
    as.character(inventory[[inventory_spec$id]]), simple = FALSE
  )
} else {
  inventory <- st_read(inventory_spec$path, layer = inventory_spec$layer, quiet = TRUE) |>
    st_transform(4326) |>
    apply_inventory_filters(inventory_spec$filters)
  inventory <- inventory[!st_is_empty(inventory), ]
  inventory_points <- suppressWarnings(st_point_on_surface(inventory))
}
inventory_ids <- as.character(inventory[[inventory_spec$id]])
if (anyNA(inventory_ids) || anyDuplicated(inventory_ids)) stop("Inventory IDs must be complete and unique.")
inventory_coordinates <- st_coordinates(inventory_points)
opportunities <- opportunity_values(inventory, inventory_spec$opportunities)
matrix_excluded <- 0L
travel_matrix_records <- 0
matrix_output <- file.path(scenario_output_dir, "travel_matrix_subset.csv")
result_chunks <- NULL

if (mode_spec$backend == "prepared_matrix") {
  destination_cells <- if (identical(inventory_spec$format, "h8_csv")) inventory_ids else {
    h3jsr::point_to_cell(
      inventory_points, res = config$geography$routing_resolution, simple = TRUE
    )
  }
  inside_matrix <- destination_cells %in% origin_ids
  matrix_excluded <- sum(!inside_matrix)
  if (matrix_excluded) {
    warning(matrix_excluded, " destination records fall outside the matrix grid and were excluded.")
    destination_cells <- destination_cells[inside_matrix]
    opportunities <- opportunities[inside_matrix, , drop = FALSE]
  }
  destination_table <- cbind(id = destination_cells, opportunities) |>
    group_by(id) |>
    summarise(across(everything(), ~ sum(as.numeric(.x), na.rm = TRUE)), .groups = "drop")
  land_use <- data.frame(id = unique(c(origin_ids, destination_table$id))) |>
    left_join(destination_table, by = "id") |>
    mutate(across(all_of(names(opportunities)), ~ coalesce(.x, 0)))
  matrix_path <- gsub("\\{period\\}", period, mode_spec$matrix_template)
  batch_size <- as.integer(scenario$origin_batch_size %||% mode_spec$origin_batch_size %||% length(origin_ids))
  if (batch_size < length(origin_ids)) {
    if (!scenario$method %in% c("cumulative_opportunities", "kth_nearest_time", "gravity_access")) {
      stop("Origin batching is not valid for measure: ", scenario$method)
    }
    origin_batches <- split(origin_ids, ceiling(seq_along(origin_ids) / batch_size))
    result_chunks <- vector("list", length(origin_batches))
    for (batch_index in seq_along(origin_batches)) {
      message("Processing origin batch ", batch_index, " of ", length(origin_batches), ".")
      batch_output <- tempfile("travel_matrix_batch_", fileext = ".csv")
      travel_matrix <- extract_prepared_auto_matrix(
        matrix_path, origin_batches[[batch_index]], destination_table$id, batch_output,
        maximum_minutes = mode_spec$maximum_minutes,
        h3_resolution = config$geography$routing_resolution
      )
      travel_matrix_records <- travel_matrix_records + nrow(travel_matrix)
      result_chunks[[batch_index]] <- calculate_scenario_results(
        travel_matrix, land_use, scenario, args$scenario, inventory_name, mode, period,
        origin_batches[[batch_index]]
      )
      unlink(batch_output)
    }
    travel_matrix <- NULL
  } else {
    travel_matrix <- extract_prepared_auto_matrix(
      matrix_path, origin_ids, destination_table$id, matrix_output,
      maximum_minutes = mode_spec$maximum_minutes,
      h3_resolution = config$geography$routing_resolution
    )
    travel_matrix_records <- nrow(travel_matrix)
  }
} else if (mode_spec$backend == "r5r") {
  destinations_r5 <- data.frame(
    id = inventory_ids, lon = inventory_coordinates[, 1], lat = inventory_coordinates[, 2]
  )
  land_use <- bind_rows(
    data.frame(id = origin_ids),
    cbind(data.frame(id = inventory_ids), opportunities)
  ) |>
    group_by(id) |>
    summarise(across(everything(), ~ sum(as.numeric(.x), na.rm = TRUE)), .groups = "drop") |>
    mutate(across(all_of(names(opportunities)), ~ coalesce(.x, 0)))
  source("accessibility/01-setup/r5r_setup.R")
  on.exit(r5r::stop_r5(r5r_network), add = TRUE)
  available_cores <- parallel::detectCores(logical = FALSE)
  if (is.na(available_cores) || available_cores < 1L) available_cores <- 1L
  batch_size <- as.integer(scenario$origin_batch_size %||% mode_spec$origin_batch_size %||% nrow(origins_r5))
  if (batch_size < nrow(origins_r5) &&
      !scenario$method %in% c("cumulative_opportunities", "kth_nearest_time", "gravity_access")) {
    stop("Origin batching is not valid for measure: ", scenario$method)
  }
  origin_batches <- split(seq_len(nrow(origins_r5)), ceiling(seq_len(nrow(origins_r5)) / batch_size))
  if (length(origin_batches) > 1L) result_chunks <- vector("list", length(origin_batches))
  for (batch_index in seq_along(origin_batches)) {
    batch_rows <- origin_batches[[batch_index]]
    if (length(origin_batches) > 1L) {
      message("Processing origin batch ", batch_index, " of ", length(origin_batches), ".")
    }
    raw_matrix <- r5r::travel_time_matrix(
      r5r_core = r5r_network, origins = origins_r5[batch_rows, , drop = FALSE],
      destinations = destinations_r5, mode = c("WALK", "TRANSIT"),
      departure_datetime = as.POSIXct(period_spec$departure_local, tz = "America/Chicago"),
      time_window = period_spec$time_window_minutes,
      percentiles = mode_spec$percentile,
      max_walk_time = mode_spec$max_walk_minutes,
      max_trip_duration = mode_spec$maximum_minutes,
      n_threads = available_cores, progress = FALSE
    )
    travel_matrix <- standardize_r5_matrix(raw_matrix)
    travel_matrix_records <- travel_matrix_records + nrow(travel_matrix)
    if (length(origin_batches) > 1L) {
      result_chunks[[batch_index]] <- calculate_scenario_results(
        travel_matrix, land_use, scenario, args$scenario, inventory_name, mode, period,
        origins_r5$id[batch_rows]
      )
    }
  }
  if (length(origin_batches) == 1L) write_csv(travel_matrix, matrix_output)
} else stop("Unsupported mode backend: ", mode_spec$backend)

if (is.null(result_chunks)) {
  result_chunks <- list(calculate_scenario_results(
    travel_matrix, land_use, scenario, args$scenario, inventory_name, mode, period,
    origin_ids
  ))
}
result <- bind_rows(result_chunks) |> arrange(opportunity_field, parameter_value, geography_id)
if (anyDuplicated(result[c("geography_id", "opportunity_field", "parameter_value")])) {
  stop("Result keys are not unique.")
}

result_path <- file.path(scenario_output_dir, "accessibility.csv")
qa_path <- file.path(scenario_output_dir, "qa_summary.csv")
manifest_path <- file.path(scenario_output_dir, "run_manifest.json")
write_csv(result, result_path)
write_csv(
  result |>
    group_by(opportunity_field, parameter_name, parameter_value) |>
    summarise(
      origins = n(), unreachable = sum(!is_reachable), missing = sum(is.na(access_value)),
      minimum = if (all(is.na(access_value))) NA_real_ else min(access_value, na.rm = TRUE),
      median = if (all(is.na(access_value))) NA_real_ else median(access_value, na.rm = TRUE),
      maximum = if (all(is.na(access_value))) NA_real_ else max(access_value, na.rm = TRUE),
      .groups = "drop"
    ),
  qa_path
)
jsonlite::write_json(
  list(
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE), scenario = args$scenario,
    destination = inventory_name, mode = mode, period = period,
    measure = scenario$method, inventory_path = inventory_spec$path,
    inventory_md5 = unname(tools::md5sum(inventory_spec$path)),
    inventory_records = nrow(inventory), matrix_excluded_records = matrix_excluded,
    origin_records = length(origin_ids),
    travel_matrix_records = travel_matrix_records,
    travel_matrix_retained = file.exists(matrix_output),
    maximum_trip_minutes = mode_spec$maximum_minutes,
    maximum_walk_minutes = mode_spec$max_walk_minutes %||% NA_integer_,
    transit_percentile = mode_spec$percentile %||% NA_integer_,
    origin_batch_size = if (exists("batch_size")) batch_size else NA_integer_,
    accessibility_package = as.character(packageVersion("accessibility")),
    result = result_path, qa = qa_path
  ),
  manifest_path, auto_unbox = TRUE, pretty = TRUE
)
message("Wrote ", result_path)
