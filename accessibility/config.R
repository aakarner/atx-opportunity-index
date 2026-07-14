# Shared configuration for the Austin accessibility pipeline.
#
# This bundle measures access on the latest pinned transit/street network to
# the latest available employment distribution. Source vintages intentionally
# differ because each dataset is released on a different schedule.

acs_year <- 2024
lodes_year <- 2023
city_boundary_year <- 2024
h3_resolution <- 8L

analysis_county_fips <- c(
  Travis = "48453",
  Williamson = "48491",
  Hays = "48209"
)

austin_msa_county_fips <- c(
  Bastrop = "48021",
  Caldwell = "48055",
  Hays = "48209",
  Travis = "48453",
  Williamson = "48491"
)

# Pinned CapMetro feed archived by MobilityDatabase. Its scheduled service
# window is June 23 through August 16, 2026.
gtfs_snapshot_date <- "2026-06-25"
gtfs_url <- paste0(
  "https://files.mobilitydatabase.org/mdb-150/",
  "mdb-150-202606250209/mdb-150-202606250209.zip"
)
gtfs_source_filename <- "capmetro_gtfs_source_20260625.zip"
gtfs_filename <- "capmetro_gtfs_r5_20260625.zip"
gtfs_source_sha256 <- "9d0ef3a61f1a7aa7b675a0f6849803043f4fedafb89365df01c8a19c9585a3cb"

# Dated Geofabrik snapshot aligned with the GTFS archive date. The statewide
# source is clipped to a Central Texas bounding box before R5 network setup.
osm_snapshot_date <- "2026-06-25"
osm_url <- paste0(
  "https://download.geofabrik.de/north-america/us/",
  "texas-260625.osm.pbf"
)
osm_filename <- "central_texas_osm_20260625.osm.pbf"
osm_bbox <- "-98.50,29.30,-96.50,31.20"
osm_sha256 <- "3252f7a533056ba4f16f3d76eb8768e024deef048c4f47b8fc612103c5155054"

# A typical Monday morning within the pinned GTFS service window. The
# two-hour window represents departures from 7:00 through 8:59 a.m.
departure_datetime_text <- "2026-07-13 07:00:00"
time_window_minutes <- 120L
access_cutoff_minutes <- 45L
max_walk_minutes <- 30L
max_trip_minutes <- 60L
travel_time_percentile <- 50L

accessibility_root <- "accessibility"
accessibility_data_dir <- file.path(accessibility_root, "data")
downloads_dir <- file.path(accessibility_data_dir, "downloads")
r5_data_dir <- file.path(accessibility_data_dir, "r5_setup")
lodes_data_dir <- file.path(accessibility_data_dir, "processed", "lehd")
processed_access_dir <- file.path(accessibility_data_dir, "processed", "accessibility")
cache_dir <- file.path(accessibility_data_dir, "cache")
output_dir <- file.path(accessibility_root, "output")

gtfs_source_path <- file.path(downloads_dir, gtfs_source_filename)
gtfs_path <- file.path(r5_data_dir, gtfs_filename)
osm_path <- file.path(r5_data_dir, osm_filename)
lodes_jobs_path <- file.path(
  lodes_data_dir,
  paste0("austin_msa_h", h3_resolution, "_jobs_", lodes_year, ".csv")
)
lodes_workers_path <- file.path(
  lodes_data_dir,
  paste0("austin_h", h3_resolution, "_workers_", lodes_year, ".csv")
)
lodes_tract_function_path <- file.path(
  lodes_data_dir,
  paste0("austin_tract_functional_role_", lodes_year, ".csv")
)
accessibility_output_path <- file.path(
  output_dir,
  paste0("h", h3_resolution, "_job_accessibility.csv")
)
origins_path <- file.path(
  processed_access_dir,
  paste0("austin_h", h3_resolution, "_origins.csv")
)

dir.create(downloads_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(r5_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(lodes_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_access_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
options(tigris_use_cache = TRUE)

# Prefer the project-local JDK 21 installed by rJavaEnv when available. r5r
# currently requires Java 21 rather than an arbitrary system Java version.
java_home_candidates <- list.dirs(
  file.path(accessibility_data_dir, "java", "rjavaenv"),
  recursive = TRUE,
  full.names = TRUE
)
project_java_home <- java_home_candidates[basename(java_home_candidates) == "21"][1]

if (!is.na(project_java_home) && dir.exists(project_java_home)) {
  project_java_home <- normalizePath(project_java_home)
  Sys.setenv(
    JAVA_HOME = project_java_home,
    PATH = paste(file.path(project_java_home, "bin"), Sys.getenv("PATH"), sep = .Platform$path.sep)
  )
}
