

# Network-based Job Accessibility Analysis using r5r
# Calculates accessibility to jobs via walking and transit in Travis County

options(java.parameters = '-Xmx12G')
Sys.setenv(TZ = 'America/Chicago')

library(r5r)
library(sf)
library(dplyr)
library(readr)
library(tigris)

set.seed(732)

output_dir <- "accessibility/data/processed/accessibility"


dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ===== DATA PREP =====

# Load job data by tract (ensure trct is character)
travis_lodes <- read_csv("accessibility/data/processed/lehd/travis_lodes.csv") %>%
  mutate(trct = as.character(trct))

# Get tract centroids for origin points
tracts <- tracts(state = "TX", county = "Travis", year = 2020, class = "sf")

origins <- tracts %>%
  st_transform(4326) %>%
  st_centroid() %>%
  st_coordinates() %>%
  as.data.frame() %>%
  rename(lon = X, lat = Y) %>%
  mutate(id = as.character(tracts$GEOID))

destinations <- origins %>%
  left_join(travis_lodes %>% rename(id = trct), by = "id") %>%
  select(id, lon, lat, jobs = totjobs)


# ===== ACCESSIBILITY CALCULATION =====

departure_datetime <- as.POSIXct("2020-11-09 09:00:00", format = "%Y-%m-%d %H:%M:%S")

# Set parameters
mode <- c("WALK", "TRANSIT")
max_walk_time <- 30  # Max walking to transit
max_trip_duration <- 60  # Max total travel time (minutes)
decay_function <- "step"
cutoff_time <- 45  # Accessibility cutoff (minutes)
percentiles <- c(50, 75, 90)

# --- 1. TOTAL JOBS ACCESSIBILITY ---
message("\n=== Calculating TOTAL JOBS accessibility ===")

destinations_total <- origins %>%
  left_join(travis_lodes %>% rename(id = trct), by = "id") %>%
  select(id, lon, lat, jobs = totjobs)

acc_total <- accessibility(
  r5r_core,
  origins = origins,
  destinations = destinations_total,
  opportunities_colnames = "jobs",
  mode = mode,
  departure_datetime = departure_datetime,
  time_window = 120,
  percentiles = percentiles,
  decay_function = decay_function,
  cutoffs = cutoff_time,
  max_walk_time = max_walk_time,
  max_trip_duration = max_trip_duration,
  n_threads = 8,
  progress = TRUE
)

# --- 2. LOW-WAGE JOBS ACCESSIBILITY ---
message("\n=== Calculating LOW-WAGE JOBS accessibility ===")

destinations_low <- origins %>%
  left_join(travis_lodes %>% rename(id = trct), by = "id") %>%
  select(id, lon, lat, jobs = lowjobs)

acc_low <- accessibility(
  r5r_core,
  origins = origins,
  destinations = destinations_low,
  opportunities_colnames = "jobs",
  mode = mode,
  departure_datetime = departure_datetime,
  time_window = 120,
  percentiles = percentiles,
  decay_function = decay_function,
  cutoffs = cutoff_time,
  max_walk_time = max_walk_time,
  max_trip_duration = max_trip_duration,
  n_threads = 8,
  progress = TRUE
)

# --- 3. MEDIUM-WAGE JOBS ACCESSIBILITY ---
message("\n=== Calculating MEDIUM-WAGE JOBS accessibility ===")

destinations_med <- origins %>%
  left_join(travis_lodes %>% rename(id = trct), by = "id") %>%
  select(id, lon, lat, jobs = medjobs)

acc_med <- accessibility(
  r5r_core,
  origins = origins,
  destinations = destinations_med,
  opportunities_colnames = "jobs",
  mode = mode,
  departure_datetime = departure_datetime,
  time_window = 120,
  percentiles = percentiles,
  decay_function = decay_function,
  cutoffs = cutoff_time,
  max_walk_time = max_walk_time,
  max_trip_duration = max_trip_duration,
  n_threads = 8,
  progress = TRUE
)

# --- 4. HIGH-WAGE JOBS ACCESSIBILITY ---
message("\n=== Calculating HIGH-WAGE JOBS accessibility ===")

destinations_high <- origins %>%
  left_join(travis_lodes %>% rename(id = trct), by = "id") %>%
  select(id, lon, lat, jobs = highjobs)

acc_high <- accessibility(
  r5r_core,
  origins = origins,
  destinations = destinations_high,
  opportunities_colnames = "jobs",
  mode = mode,
  departure_datetime = departure_datetime,
  time_window = 120,
  percentiles = percentiles,
  decay_function = decay_function,
  cutoffs = cutoff_time,
  max_walk_time = max_walk_time,
  max_trip_duration = max_trip_duration,
  n_threads = 8,
  progress = TRUE
)

# ===== RESULTS PROCESSING =====
# Combine all accessibility measures into one result

accessibility_results <- acc_total %>%
  rename(trct = id, access_total = accessibility) %>%
  select(trct, percentile, cutoff, access_total) %>%
  left_join(
    acc_low %>% rename(trct = id, access_low = accessibility) %>% 
      select(trct, percentile, access_low),
    by = c("trct", "percentile")
  ) %>%
  left_join(
    acc_med %>% rename(trct = id, access_med = accessibility) %>% 
      select(trct, percentile, access_med),
    by = c("trct", "percentile")
  ) %>%
  left_join(
    acc_high %>% rename(trct = id, access_high = accessibility) %>% 
      select(trct, percentile, access_high),
    by = c("trct", "percentile")
  ) %>%
  # Add original job counts
  left_join(
    travis_lodes %>% select(trct, totjobs, lowjobs, medjobs, highjobs),
    by = "trct"
  )

write_csv(accessibility_results, file.path(output_dir, "unweighted_job_accessibility.csv"))

message("\n====== RESULTS SAVED ======")
message("Output: ", file.path(output_dir, "unweighted_job_accessibility.csv"))
message("Jobs reachable within ", cutoff_time, " min by walk+transit")
message("Accessibility measures:")
message("  - access_total: All jobs")
message("  - access_low: Low-wage jobs")
message("  - access_med: Medium-wage jobs")
message("  - access_high: High-wage jobs")

cat("\n")
summary(accessibility_results)

# ===== STOP R5 =====
stop_r5()
