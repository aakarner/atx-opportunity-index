# Attach 2023 LODES resident-worker weights and produce a compact QA summary.
# Component maps and tract aggregation are owned by the targets pipeline.

source("accessibility/config.R")

source("scripts/prepare/packages.R")
setup_project_packages(c("dplyr", "purrr", "readr", "tidyr"))

if (!file.exists(accessibility_output_path) || !file.exists(lodes_workers_path)) {
  stop("Run the LODES preparation and unweighted accessibility scripts first.")
}

access <- read_csv(accessibility_output_path, col_types = cols(h3_id = col_character()),
                   show_col_types = FALSE)
workers <- read_csv(lodes_workers_path, col_types = cols(h3_id = col_character()),
                    show_col_types = FALSE)

worker_columns <- c(
  "workers_all", "workers_low", "workers_middle", "workers_high"
)
access_columns <- c("access_total_jobs", "access_low_wage_jobs",
                    "access_middle_wage_jobs", "access_high_wage_jobs")

validate_counts <- function(x, columns, label) {
  if (!all(c("h3_id", columns) %in% names(x))) stop(label, " lacks required columns.")
  if (!nrow(x) || nrow(problems(x)) || anyNA(x$h3_id) || anyDuplicated(x$h3_id) ||
      any(!nzchar(x$h3_id))) stop(label, " needs unique, nonmissing H8 IDs and valid CSV records.")
  values <- as.matrix(x[columns])
  if (any(!is.finite(values)) || any(values < 0)) stop(label, " has invalid or missing counts.")
  if (any(abs(x[[columns[1]]] - rowSums(x[columns[-1]])) > 1e-6)) {
    stop(label, " wage groups do not reconcile.")
  }
}
validate_counts(access, access_columns, "Job accessibility")
validate_counts(workers, worker_columns, "Resident-worker weights")

access_workers <- access %>%
  select(-any_of(worker_columns)) %>%
  left_join(select(workers, h3_id, all_of(worker_columns)), by = "h3_id", relationship = "one-to-one") %>%
  # An absent cell in the complete RAC aggregation has zero workers. Missing
  # values within a source record were rejected above and are never imputed.
  mutate(across(all_of(worker_columns), ~ replace_na(.x, 0)))

# Keep weights with the H8 results so targets needs only this accessibility
# source file. Repeating this preparation replaces existing weight columns.
write_csv(access_workers, accessibility_output_path)

measure_config <- tibble(
  access_column = c(
    "access_total_jobs", "access_low_wage_jobs",
    "access_middle_wage_jobs", "access_high_wage_jobs"
  ),
  worker_column = c(
    "workers_all", "workers_low", "workers_middle", "workers_high"
  ),
  job_type = c("All jobs", "Low-wage jobs", "Middle-wage jobs", "High-wage jobs")
)

summary_table <- purrr::pmap_dfr(
  measure_config,
  function(access_column, worker_column, job_type) {
    values <- access_workers[[access_column]]
    weights <- access_workers[[worker_column]]
    valid <- !is.na(values) & weights > 0

    tibble(
      job_type = job_type,
      weighted_mean = if (any(valid)) weighted.mean(values[valid], weights[valid]) else NA_real_,
      unweighted_mean = mean(values, na.rm = TRUE),
      median = median(values, na.rm = TRUE),
      minimum = min(values, na.rm = TRUE),
      maximum = max(values, na.rm = TRUE),
      worker_count = sum(weights, na.rm = TRUE)
    )
  }
)

summary_path <- file.path(output_dir, paste0("h", h3_resolution, "_job_accessibility_summary.csv"))
write_csv(summary_table, summary_path)

print(summary_table)
message("Updated H8 accessibility output with resident-worker weights at ", accessibility_output_path)
message("Saved summary to ", summary_path)
