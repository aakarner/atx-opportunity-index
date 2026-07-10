# Calculate City of Austin H8 access to 2023 jobs on the pinned 2026 network.

source("accessibility/config.R")

Sys.setenv(R_USER_CACHE_DIR = cache_dir)
options(java.parameters = "-Xmx12G")
Sys.setenv(TZ = "America/Chicago")

source("setup_packages.R")
setup_project_packages(c(
  "dplyr", "h3jsr", "readr", "sf", "tidyr", "tigris", "r5r"
))

if (!file.exists(lodes_jobs_path)) {
  stop("Missing LODES destinations. Run pull_lodes_wac_jobs.R first.")
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

if (file.exists(origins_path)) {
  origins <- read_csv(origins_path, show_col_types = FALSE)
  if (
    any(origins$h3_resolution != h3_resolution) ||
    any(origins$city_boundary_year != city_boundary_year)
  ) {
    stop("Cached H8 origins do not match the configured resolution/boundary year.")
  }
  origins <- select(origins, id, lon, lat)
} else {
  austin_boundary <- places(
    state = "TX",
    year = city_boundary_year,
    class = "sf"
  ) %>%
    filter(NAME == "Austin") %>%
    st_transform(4326) %>%
    st_make_valid()

  if (nrow(austin_boundary) != 1) {
    stop("Expected exactly one City of Austin boundary.")
  }

  origin_ids <- polygon_to_cells(
    st_geometry(austin_boundary),
    res = h3_resolution
  ) %>%
    unlist(use.names = FALSE) %>%
    unique()
  origin_points <- cell_to_point(origin_ids)
  origin_coordinates <- st_coordinates(origin_points)

  origins <- data.frame(
    id = origin_ids,
    lon = origin_coordinates[, "X"],
    lat = origin_coordinates[, "Y"]
  )

  write_csv(
    mutate(
      origins,
      h3_resolution = h3_resolution,
      city_boundary_year = city_boundary_year
    ),
    origins_path
  )
}

source("accessibility/01-setup/R5R-setup.R")
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
    departure_datetime = departure_datetime_text
  )

write_csv(access_results, accessibility_output_path)

message("Saved ", nrow(access_results), " H8 accessibility records to ", accessibility_output_path)
