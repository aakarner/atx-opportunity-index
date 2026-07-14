# R package setup for the Austin Opportunity Index project
#
# Run this file directly from the repository root to install and validate the
# complete package set:
#
#   Rscript 00_setup_packages.R
#
# Analysis scripts source this file and call setup_project_packages() with the
# subset they use. This keeps installation logic centralized while avoiding
# unnecessary package conflicts and heavyweight initialization in every script.

project_required_packages <- c(
  # Core analysis and spatial data
  "cluster",
  "dplyr",
  "ggplot2",
  "h3jsr",
  "patchwork",
  "purrr",
  "readr",
  "readxl",
  "scales",
  "sf",
  "tibble",
  "tidycensus",
  "tidyr",
  "tidyverse",
  "tigris",

  # Data access and cleaning
  "curl",
  "httr",
  "httr2",
  "janitor",
  "jsonlite",
  "lehdr",
  "lubridate",
  "socratadata",

  # Mapping and exploratory spatial workflows
  "ggspatial",
  "h3r",
  "leaflet",
  "osmdata",
  "rmapshaper",
  "units",

  # Accessibility pipeline and reproducibility utilities
  "digest",
  "r5r",
  "rJavaEnv",
  "zip"
)

configure_cran_repository <- function() {
  repos <- getOption("repos")

  if (is.null(repos)) {
    repos <- character()
  }

  if (
    !"CRAN" %in% names(repos) ||
      is.na(repos[["CRAN"]]) ||
      repos[["CRAN"]] %in% c("", "@CRAN@")
  ) {
    repos[["CRAN"]] <- "https://cloud.r-project.org"
    options(repos = repos)
  }

  invisible(getOption("repos"))
}

configure_r_library <- function(require_writable = FALSE) {
  libraries <- .libPaths()
  user_library <- path.expand(Sys.getenv("R_LIBS_USER"))

  if (nzchar(user_library) && dir.exists(user_library)) {
    libraries <- unique(c(user_library, libraries))
    .libPaths(libraries)
  }

  writable_libraries <- libraries[file.access(libraries, mode = 2) == 0]

  if (length(writable_libraries) > 0) {
    return(invisible(writable_libraries[[1]]))
  }

  if (!require_writable) {
    return(invisible(NA_character_))
  }

  install_library <- user_library
  if (!nzchar(install_library)) {
    install_library <- file.path(
      path.expand("~"),
      "R",
      paste0(R.version$major, ".", strsplit(R.version$minor, "\\.")[[1]][1]),
      "library"
    )
  }

  dir.create(install_library, recursive = TRUE, showWarnings = FALSE)

  if (!dir.exists(install_library) || file.access(install_library, mode = 2) != 0) {
    stop("No writable R package library is available: ", install_library)
  }

  .libPaths(unique(c(install_library, libraries)))
  invisible(install_library)
}

setup_project_packages <- function(
  packages = project_required_packages,
  install_missing = TRUE,
  load_packages = TRUE
) {
  packages <- unique(as.character(packages))

  unknown_packages <- setdiff(packages, project_required_packages)
  if (length(unknown_packages) > 0) {
    stop(
      "Packages are not listed in project_required_packages: ",
      paste(unknown_packages, collapse = ", ")
    )
  }

  configure_cran_repository()
  configure_r_library(require_writable = FALSE)

  installed <- rownames(installed.packages())
  missing <- setdiff(packages, installed)
  installed_now <- character()

  if (length(missing) > 0 && install_missing) {
    install_library <- configure_r_library(require_writable = TRUE)
    message("Installing missing R packages: ", paste(missing, collapse = ", "))
    install.packages(missing, lib = install_library, dependencies = NA)
    installed_now <- missing
  }

  still_missing <- setdiff(packages, rownames(installed.packages()))
  if (length(still_missing) > 0) {
    stop(
      "Required R packages remain unavailable: ",
      paste(still_missing, collapse = ", "),
      ". Spatial packages may require GDAL, GEOS, PROJ, and udunits; ",
      "socratadata may require Rust/Cargo when a binary is unavailable."
    )
  }

  loaded <- character()
  if (load_packages) {
    load_success <- vapply(
      packages,
      function(package) {
        tryCatch(
          {
            suppressPackageStartupMessages(
              library(
                package,
                character.only = TRUE,
                quietly = TRUE,
                warn.conflicts = FALSE
              )
            )
            TRUE
          },
          error = function(error) {
            message("Could not load ", package, ": ", conditionMessage(error))
            FALSE
          }
        )
      },
      logical(1)
    )

    if (any(!load_success)) {
      stop(
        "Failed to load required R packages: ",
        paste(packages[!load_success], collapse = ", ")
      )
    }

    loaded <- packages
  }

  message(
    "Project package setup complete: ",
    length(packages),
    " available",
    if (length(installed_now) > 0) {
      paste0("; ", length(installed_now), " installed")
    } else {
      "; none installed"
    },
    if (load_packages) "; all requested packages loaded." else "."
  )

  invisible(
    list(
      requested = packages,
      installed = installed_now,
      loaded = loaded
    )
  )
}

report_external_requirements <- function() {
  message("\nExternal requirements checked separately from R packages:")

  if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) {
    message(
      "- Census API key not detected. Obtain one at ",
      "https://api.census.gov/data/key_signup.html and register it with ",
      "tidycensus::census_api_key()."
    )
  } else {
    message("- Census API key detected.")
  }

  if (!nzchar(Sys.which("java"))) {
    message("- Java not detected; the r5r accessibility workflow requires JDK 21.")
  } else {
    message("- Java detected; verify JDK 21 before running r5r.")
  }

  if (!nzchar(Sys.which("osmium"))) {
    message("- osmium not detected; it is required to prepare the OSM network.")
  } else {
    message("- osmium detected.")
  }

  invisible(NULL)
}

# Running this file directly installs and loads the complete project set. When
# sourced by another script, the caller selects and loads its own subset.
if (sys.nframe() == 0L) {
  setup_project_packages()
  report_external_requirements()
}
