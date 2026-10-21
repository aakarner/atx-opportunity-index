write_pipeline_csv <- function(x, directory, filename) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(directory, filename)
  temporary <- paste0(path, ".partial")
  readr::write_csv(x, temporary, na = "")
  if (!file.rename(temporary, path)) stop("Could not finalize ", path)
  path
}

write_runtime_info <- function(directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(directory, "runtime.txt")
  writeLines(c("Runtime at target execution (dependency lock deferred to migration stage 2)",
               capture.output(sessionInfo()), capture.output(sf::sf_extSoftVersion())), path)
  path
}
