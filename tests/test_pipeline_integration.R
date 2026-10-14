# Integration from raw Census/City sources and prepared spatial/routing inputs,
# isolated from production outputs/cache. Run after the first pipeline build.
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
run_integration_checks <- function() {
  root <- normalizePath(".")
  cfg <- yaml::read_yaml("config/pipeline.yml")
  required <- unlist(cfg$inputs, use.names = FALSE)
  if (!all(file.exists(required))) stop("Integration checks require the configured processed snapshots.")
  if (!dir.exists(cfg$census$raw_dir) || !file.exists(cfg$displacement$path)) {
    stop("Build the pipeline once to acquire raw Census and displacement snapshots before integration checks.")
  }
  work <- tempfile("component-pipeline-test-")
  dir.create(work)
  on.exit({ setwd(root); unlink(work, recursive = TRUE) }, add = TRUE)
  stopifnot(all(file.copy(c("R", "_targets.R"), work, recursive = TRUE)))
  dir.create(file.path(work, "config"))
  stopifnot(file.copy("config/classification-review.yml", file.path(work,"config","classification-review.yml")))
  stopifnot(file.exists(cfg$rsei$path), file.exists(paste0(cfg$rsei$path,".json")))
  cfg$rsei$path <- normalizePath(cfg$rsei$path)
  cfg$rsei$refresh <- FALSE
  cfg$inputs <- lapply(cfg$inputs, normalizePath)
  stopifnot(file.copy(cfg$inputs$sites, file.path(work, "config", "example_sites.csv")))
  cfg$inputs$sites <- "config/example_sites.csv"
  # Copy mutable source fixtures. No source downloads or production writes are
  # needed, and there is no analytical reference file in this temporary project.
  census_dir <- normalizePath(cfg$census$raw_dir)
  dir.create(file.path(work, "census_sources"))
  stopifnot(all(file.copy(list.files(census_dir, full.names = TRUE), file.path(work, "census_sources"), recursive = TRUE)))
  cfg$census$raw_dir <- "census_sources"
  cfg$census$refresh <- FALSE
  stopifnot(file.copy(cfg$displacement$path, file.path(work, "displacement.geojson")))
  cfg$displacement$path <- "displacement.geojson"
  cfg$displacement$refresh <- FALSE
  cfg$output_dir <- "output/components"
  yaml::write_yaml(cfg, file.path(work, "config", "pipeline.yml"))
  setwd(work)

  # A selective report build must create every linked artifact in a clean store.
  targets::tar_make(names = review_report, reporter = "silent")
  report <- targets::tar_read(review_report)
  html <- paste(readLines(report, warn = FALSE), collapse = "\n")
  links <- regmatches(html, gregexpr('(?:src|href)="[^"]+"', html, perl = TRUE))[[1]]
  links <- sub('^[^=]+="([^"]+)"$', '\\1', links)
  local_links <- links[!grepl("^(#|[a-z]+:)", links)]
  stopifnot(length(local_links) > 0, all(file.exists(file.path(dirname(report), local_links))))

  # Rebuild every tract input from source with explicit missingness and coverage.
  inputs <- targets::tar_read(tract_inputs)
  jobs <- targets::tar_read(tract_job_access)
  stopifnot(nrow(inputs) > 0, !anyDuplicated(inputs$GEOID), setequal(inputs$GEOID, jobs$GEOID),
    all(sf::st_is_valid(inputs)), all(inputs$crash_observation_area_sqmi > 0),
    max(abs(inputs$annual_ksi_crash_density * inputs$crash_observation_years *
            inputs$crash_observation_area_sqmi - inputs$ksi_crashes_in_window)) < 1e-9)
  targets::tar_make(names = c(classification_report, web_mockup_data), reporter = "silent")
  stopifnot(all(targets::tar_read(h8_rsei)$rsei_coverage_share > .999999),
            all(targets::tar_read(tract_rsei)$rsei_coverage_share > .999999))
  before <- targets::tar_meta(fields = c(name, time), targets_only = TRUE)
  targets::tar_make(reporter = "silent")
  after <- targets::tar_meta(fields = c(name, time), targets_only = TRUE)
  stopifnot(identical(before, after), length(targets::tar_outdated(reporter = "silent")) == 0)

  # A site edit must update the profile while retaining expensive shared work.
  sites <- readr::read_csv(cfg$inputs$sites, show_col_types = FALSE)
  sites$label[1] <- "Integration test: edited example"
  readr::write_csv(sites, cfg$inputs$sites)
  targets::tar_make(reporter = "silent")
  changed <- targets::tar_meta(fields = c(name, time), targets_only = TRUE)
  cached <- c("acs_context", "tract_geometry", "tract_crash_windows", "tract_crashes",
              "job_access", "school_zones", "crash_points", "h8_geometry", "tract_h8_crosswalk",
              "tract_job_access", "flood_union", "tract_flood", "tract_components", "component_files",
              "rsei_cells", "rsei_h8_crosswalk", "rsei_tract_crosswalk", "h8_rsei", "tract_rsei")
  stopifnot(identical(before$time[match(cached, before$name)], changed$time[match(cached, changed$name)]),
            targets::tar_read(site_profiles)$label[1] == sites$label[1],
            before$time[match("site_profiles", before$name)] != changed$time[match("site_profiles", changed$name)],
            length(targets::tar_outdated(reporter = "silent")) == 0)

  # An ACS source edit changes the appropriate context value, not geometry,
  # routing, school assignments, or crash computations.
  candidate <- inputs[startsWith(inputs$GEOID, paste0(cfg$census$state_fips, cfg$census$county_fips[1])) &
    !is.na(inputs$poverty_below) & !is.na(inputs$poverty_total) & inputs$poverty_total > inputs$poverty_below + 1, ][1, ]
  stopifnot(nrow(candidate) == 1, !is.na(candidate$GEOID))
  source_path <- file.path(cfg$census$raw_dir, paste0("acs", cfg$census$acs_year, "_5year"),
    paste0("acs", cfg$census$acs_year, "_", substr(candidate$GEOID, 1, 5), "_tract_context.json"))
  raw <- jsonlite::fromJSON(source_path, simplifyVector = FALSE)
  header <- unlist(raw[[1]])
  row_number <- which(vapply(raw[-1], function(x) identical(x[[match("tract", header)]], substr(candidate$GEOID, 6, 11)), logical(1))) + 1L
  stopifnot(length(row_number) == 1)
  raw[[row_number]][[match("B17001_002E", header)]] <- as.character(candidate$poverty_below + 1)
  jsonlite::write_json(raw, source_path, auto_unbox = TRUE)
  targets::tar_make(reporter = "silent")
  after_acs <- targets::tar_meta(fields = c(name, time), targets_only = TRUE)
  unchanged <- c("census_tracts", "city_boundary", "tract_geometry", "h8_geometry", "tract_h8_crosswalk",
                 "tract_job_access", "flood_union", "tract_flood", "tract_crash_windows", "tract_crashes", "site_profiles")
  updated <- targets::tar_read(tract_inputs)
  stopifnot(identical(changed$time[match(unchanged, changed$name)], after_acs$time[match(unchanged, after_acs$name)]),
    abs(updated$poverty_rate[match(candidate$GEOID, updated$GEOID)] -
      (candidate$poverty_below + 1) / candidate$poverty_total) < 1e-12)

  # A new window radius rebuilds burdens, without invalidating source geography
  # or transit access. Its density remains a count / years / observed-area rate.
  cfg$crashes$buffer_meters <- cfg$crashes$buffer_meters / 2
  yaml::write_yaml(cfg, "config/pipeline.yml")
  targets::tar_make(reporter = "silent")
  after_buffer <- targets::tar_meta(fields = c(name, time), targets_only = TRUE)
  unchanged <- c("acs_context", "city_boundary", "tract_geometry", "h8_geometry", "tract_h8_crosswalk",
                 "tract_job_access", "flood_union", "tract_flood")
  updated <- targets::tar_read(tract_inputs)
  stopifnot(identical(after_acs$time[match(unchanged, after_acs$name)], after_buffer$time[match(unchanged, after_buffer$name)]),
    all(updated$crash_buffer_meters == cfg$crashes$buffer_meters),
    after_acs$time[match("tract_crash_windows", after_acs$name)] != after_buffer$time[match("tract_crash_windows", after_buffer$name)],
    max(abs(updated$annual_ksi_crash_density * updated$crash_observation_years *
            updated$crash_observation_area_sqmi - updated$ksi_crashes_in_window)) < 1e-9,
    length(targets::tar_outdated(reporter = "silent")) == 0)
  # Threshold changes rebuild the review branch without recomputing measurements.
  rule <- yaml::read_yaml("config/classification-review.yml")
  rule$burden_fixed[[1]]$elevated_at_least <- 125
  yaml::write_yaml(rule,"config/classification-review.yml")
  targets::tar_make(reporter = "silent")
  after_rule <- targets::tar_meta(fields=c(name,time),targets_only=TRUE)
  cached <- c("rsei_source_files","rsei_cells","rsei_h8_crosswalk","rsei_tract_crosswalk", "h8_rsei",
              "tract_rsei","h8_components","tract_components","component_maps","site_profiles")
  stopifnot(identical(after_buffer$time[match(cached,after_buffer$name)],after_rule$time[match(cached,after_rule$name)]),
    targets::tar_read(classification_thresholds)$high[targets::tar_read(classification_thresholds)$rule=="burden_100"]==125,
    length(targets::tar_outdated(reporter="silent"))==0)
  cat("Integration passed: RSEI coverage and classification-only invalidation; source-only tract rebuild, report links, no-op rerun, site/ACS edits, and crash-buffer invalidation.\n")
}
run_integration_checks()
