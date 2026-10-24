#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1]] else "accessibility/output/working"
manifests <- list.files(root, "run_manifest[.]json$", recursive = TRUE, full.names = TRUE)
if (!length(manifests)) stop("No run manifests found under ", root)

required_result_fields <- c(
  "geography_id", "destination", "mode", "period", "scenario", "measure",
  "opportunity_field", "parameter_name", "parameter_value", "access_value", "is_reachable"
)

`%||%` <- function(x, y) if (is.null(x)) y else x

rows <- lapply(manifests, function(path) {
  manifest <- jsonlite::read_json(path, simplifyVector = TRUE)
  result_path <- manifest$result
  qa_path <- manifest$qa
  if (!file.exists(result_path) || !file.exists(qa_path)) {
    stop("Manifest references missing output: ", path)
  }
  result <- read_csv(result_path, show_col_types = FALSE)
  missing <- setdiff(required_result_fields, names(result))
  if (length(missing)) stop(path, " result is missing: ", paste(missing, collapse = ", "))
  if (anyDuplicated(result[c("geography_id", "opportunity_field", "parameter_value")])) {
    stop(path, " contains duplicate result keys.")
  }
  data.frame(
    scenario = manifest$scenario, destination = manifest$destination,
    mode = manifest$mode, period = manifest$period, measure = manifest$measure,
    inventory_records = manifest$inventory_records,
    matrix_excluded_records = manifest$matrix_excluded_records %||% 0,
    origin_records = manifest$origin_records,
    result_rows = nrow(result), unreachable_rows = sum(!result$is_reachable),
    manifest = path, result = result_path, qa = qa_path,
    stringsAsFactors = FALSE
  )
})

inventory <- bind_rows(rows) |> arrange(destination, mode, period, scenario)
output <- file.path(root, "run_inventory.csv")
write_csv(inventory, output)
message("Validated ", nrow(inventory), " runs and wrote ", output)
