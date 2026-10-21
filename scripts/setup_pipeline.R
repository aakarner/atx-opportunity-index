# Explicit installation only. Analytical targets never install packages.
if (!file.exists("_targets.R")) stop("Run this command from the repository root.")
args <- commandArgs(trailingOnly = TRUE)
if (any(!args %in% "--sources")) stop("Usage: Rscript scripts/setup_pipeline.R [--sources]")
dir.create(".R-library", showWarnings = FALSE)
.libPaths(c(normalizePath(".R-library"), .libPaths()))
required <- c("targets", "yaml", "sf", "h3jsr", "dplyr", "readr", "ggplot2", "digest",
              "httr2", "jsonlite", "rappdirs")
if ("--sources" %in% args) required <- unique(c(required, "tidyverse", "tidyr", "tigris",
  "httr2", "jsonlite", "scales", "lehdr", "r5r", "rJavaEnv", "zip"))
# Check installation without initializing Java/r5r during dependency setup.
missing <- setdiff(required, rownames(utils::installed.packages()))
if (length(missing)) install.packages(missing, lib = ".R-library", repos = "https://cloud.r-project.org")
stopifnot(all(required %in% rownames(utils::installed.packages())))
cat("Pipeline dependencies available. Run Rscript scripts/run_pipeline.R\n")
