# Run from the repository root. Optional arguments are target names.
if (!file.exists("_targets.R")) stop("Run this command from the repository root.")
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
if (!requireNamespace("targets", quietly = TRUE)) stop("Run Rscript scripts/setup_pipeline.R first.")
requested <- commandArgs(trailingOnly = TRUE)
if (length(requested)) {
  targets::tar_make(names = tidyselect::all_of(requested))
} else {
  targets::tar_make()
}
