# Shared package loader for source preparation. Installation is explicit:
# Rscript scripts/setup_pipeline.R --sources
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))

setup_project_packages <- function(packages, load_packages = TRUE) {
  packages <- unique(packages)
  missing <- setdiff(packages, rownames(utils::installed.packages()))
  if (length(missing)) stop("Missing packages: ", paste(missing, collapse = ", "),
                            ". Run Rscript scripts/setup_pipeline.R --sources.")
  if (load_packages) {
    for (package in packages) {
      suppressPackageStartupMessages(library(package, character.only = TRUE, warn.conflicts = FALSE))
    }
  }
  invisible(packages)
}
