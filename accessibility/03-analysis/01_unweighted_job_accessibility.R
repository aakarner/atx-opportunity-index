# Calculate City of Austin H8 access to 2023 jobs on the pinned 2026 network.

source("accessibility/config.R")

Sys.setenv(R_USER_CACHE_DIR = cache_dir)
options(java.parameters = "-Xmx12G")
Sys.setenv(TZ = "America/Chicago")

source("scripts/prepare/packages.R")
setup_project_packages(c(
  "dplyr", "h3jsr", "readr", "sf", "tidyr", "r5r", "yaml", "httr2", "jsonlite", "digest"
))

if (!file.exists(lodes_jobs_path)) {
  stop(
    paste0(
      "Missing LODES destinations. Run accessibility/02-data-processing/",
      "01_pull_lodes_wac_jobs.R first."
    )
  )
}

jobs <- read_csv(lodes_jobs_path, show_col_types = FALSE)
job_points <- cell_to_point(jobs$h3_id)
job_coordinates <- st_coordinates(job_points)

destinations <- jobs %>%
  transmute(
    id = h3_id,
    lon = job_coordinates[, "X"],
    lat = job_coordinates[, "Y"],
    total_jobs,
    low_wage_jobs,
    middle_wage_jobs,
    high_wage_jobs
  )

source("R/municipal_boundary.R")
austin_boundary <- load_municipal_boundary(municipal_config_path)
origin_ids <- municipal_h8_ids(austin_boundary,h3_resolution)
origin_coordinates <- st_coordinates(cell_to_point(origin_ids))
origins <- data.frame(id=origin_ids,lon=origin_coordinates[,"X"],lat=origin_coordinates[,"Y"])
# Regenerate the inexpensive origin list from the shared, pinned footprint.
write_csv(mutate(origins,h3_resolution=h3_resolution,
  city_boundary_snapshot=austin_boundary$boundary_snapshot,
  city_boundary_sha256=austin_boundary$boundary_sha256),origins_path)

source("accessibility/01-setup/r5r_setup.R")
on.exit(stop_r5(r5r_network), add = TRUE)

departure_datetime <- as.POSIXct(
  departure_datetime_text,
  format = "%Y-%m-%d %H:%M:%S",
  tz = "America/Chicago"
)

message(
  "Calculating H8 accessibility for ", nrow(origins), " City of Austin cells ",
  "to ", nrow(destinations), " job cells..."
)

available_cores <- parallel::detectCores(logical = FALSE)
if (is.na(available_cores) || available_cores < 1) {
  available_cores <- 1L
}

access_long <- accessibility(
  r5r_network = r5r_network,
  origins = origins,
  destinations = destinations,
  opportunities_colnames = c(
    "total_jobs", "low_wage_jobs", "middle_wage_jobs", "high_wage_jobs"
  ),
  mode = c("WALK", "TRANSIT"),
  departure_datetime = departure_datetime,
  time_window = time_window_minutes,
  percentiles = travel_time_percentile,
  decay_function = "step",
  cutoffs = access_cutoff_minutes,
  max_walk_time = max_walk_minutes,
  max_trip_duration = max_trip_minutes,
  n_threads = available_cores,
  progress = TRUE
)

access_results <- access_long %>%
  as_tibble() %>%
  select(id, opportunity, percentile, cutoff, accessibility) %>%
  pivot_wider(
    names_from = opportunity,
    values_from = accessibility,
    names_prefix = "access_"
  ) %>%
  left_join(origins, by = "id") %>%
  rename(h3_id = id) %>%
  mutate(
    network_snapshot = osm_snapshot_date,
    gtfs_snapshot = gtfs_snapshot_date,
    jobs_year = lodes_year,
    departure_datetime = departure_datetime_text,
    city_boundary_snapshot = austin_boundary$boundary_snapshot,
    city_boundary_sha256 = austin_boundary$boundary_sha256
  )

write_csv(access_results, accessibility_output_path)

message("Saved ", nrow(access_results), " H8 accessibility records to ", accessibility_output_path)
