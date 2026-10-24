extract_prepared_auto_matrix <- function(matrix_path, origin_ids, destination_ids,
                                         output_path, maximum_minutes = 60,
                                         h3_resolution = 8,
                                         python = Sys.getenv(
                                           "ATX_ACCESSIBILITY_PYTHON",
                                           "accessibility/.venv/bin/python"
                                         )) {
  required <- c(matrix_path, python, "accessibility/scripts/extract_prepared_matrix.py")
  missing <- required[!file.exists(required)]
  if (length(missing)) stop("Missing matrix dependency: ", paste(missing, collapse = ", "))
  if (!length(origin_ids) || !length(destination_ids)) stop("Origin and destination IDs cannot be empty.")

  work <- tempfile("accessibility_matrix_")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  origins_path <- file.path(work, "origins.csv")
  destinations_path <- file.path(work, "destinations.csv")
  config_path <- file.path(work, "config.json")
  utils::write.csv(data.frame(id = unique(origin_ids)), origins_path, row.names = FALSE)
  utils::write.csv(data.frame(id = unique(destination_ids)), destinations_path, row.names = FALSE)
  jsonlite::write_json(
    list(
      matrix = normalizePath(matrix_path), origins = normalizePath(origins_path),
      destinations = normalizePath(destinations_path),
      output = normalizePath(file.path(dirname(output_path)), mustWork = TRUE) |>
        file.path(basename(output_path)),
      maximum_minutes = maximum_minutes, h3_resolution = h3_resolution
    ),
    config_path, auto_unbox = TRUE
  )
  status <- system2(
    python,
    c("accessibility/scripts/extract_prepared_matrix.py", shQuote(config_path))
  )
  if (status != 0 || !file.exists(output_path)) stop("Prepared-matrix extraction failed.")
  readr::read_csv(output_path, show_col_types = FALSE)
}

standardize_r5_matrix <- function(matrix, travel_cost = "travel_time_p50") {
  required <- c("from_id", "to_id", travel_cost)
  missing <- setdiff(required, names(matrix))
  if (length(missing)) stop("R5 matrix is missing: ", paste(missing, collapse = ", "))
  data.frame(
    from_id = as.character(matrix$from_id),
    to_id = as.character(matrix$to_id),
    travel_time = as.numeric(matrix[[travel_cost]])
  )
}
