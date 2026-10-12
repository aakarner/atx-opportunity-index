# Small fixtures for spatial behavior; no downloads or production writes.
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
suppressPackageStartupMessages(library(sf))
for (path in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(path)

rectangle <- function(left, right, bottom = 0, top = 10) {
  st_polygon(list(matrix(c(left, bottom, right, bottom, right, top,
                          left, top, left, bottom), ncol = 2, byrow = TRUE)))
}
expect_error <- function(expr) stopifnot(inherits(try(force(expr), silent = TRUE), "try-error"))

# Worker weighting, zero-worker area fallback, and no-overlap boundary fallback.
h8 <- st_sf(h3_id = c("a", "b", "c"), workers_all = c(100, 0, 0),
  access_total_jobs = c(100, 300, 20), access_low_wage_jobs = c(10, 30, 2),
  access_middle_wage_jobs = c(20, 60, 4), access_high_wage_jobs = c(70, 210, 14),
  geometry = st_sfc(rectangle(0, 10), rectangle(10, 20), rectangle(30, 40), crs = 5070))
tracts <- st_sf(GEOID = c("worker", "area", "nearest"),
  geometry = st_sfc(rectangle(0, 20), rectangle(12, 20), rectangle(41, 42), crs = 5070))
crosswalk <- build_tract_h8_crosswalk(tracts, h8)
result <- aggregate_job_access(tracts, h8, crosswalk)
stopifnot(identical(result$GEOID, tracts$GEOID),
  isTRUE(all.equal(result$transit_jobs_45min, c(100, 300, 20))),
  isTRUE(all.equal(result$transit_low_wage_jobs_45min, c(10, 30, 2))),
  identical(result$access_aggregation_method, c("area-apportioned resident-worker weighted H8 mean",
    "area-weighted H8 mean", "nearest H8 origin fallback")))

# Duplicate/overlapping hazard polygons must not double-count flooded area.
flood <- st_sf(geometry = st_sfc(rectangle(0, 10), rectangle(0, 10), crs = 5070))
flood_union <- make_flood_union(flood, 5070)
shares <- summarize_flood_tracts(tracts, flood_union)
stopifnot(isTRUE(all.equal(shares$fema_one_percent_area_share, c(.5, 0, 0))))

# A same-campus overlap is one assignment; distinct campuses are ambiguous.
zones <- st_sf(campus_id = c("one", "one", "two", "missing"),
  campus_name = c("One", "One", "Two", "Missing"), usable_growth = c(70, 70, 80, NA_real_),
  score_status = c("Available", "Available", "Available", "Paired accountability record"),
  geometry = st_sfc(rectangle(0, 6), rectangle(4, 8), rectangle(7, 10), rectangle(20, 30), crs = 5070))
sites <- st_as_sf(data.frame(site_id = c("same", "conflict", "outside", "suppressed"),
                            x = c(5, 7.5, 15, 25), y = 5), coords = c("x", "y"), crs = 5070)
scores <- school_at_sites(sites, zones)
stopifnot(scores$growth[1] == 70, all(is.na(scores$growth[-1])),
  scores$status[2] == "Ambiguous assignment overlap",
  scores$status[3] == "Outside available assignment coverage",
  scores$status[4] == "Paired accountability record")

# City's observation footprint controls the numerator AND density denominator.
city <- st_sfc(rectangle(0, 20, 0, 20), crs = 5070)
site <- st_as_sf(data.frame(site_id = "edge", x = 1, y = 10), coords = c("x", "y"), crs = 5070)
crashes <- st_as_sf(data.frame(crash_id = c("inside", "outside"), x = c(1, -1), y = c(10, 10)), coords = c("x", "y"), crs = 5070)
burden <- site_crash_burden(site, crashes, city, list(buffer_meters = 5, first_year = 2020, last_year = 2024))
stopifnot(burden$ksi_crashes_in_window == 1, burden$crash_observed_window_share < 1,
  burden$crash_observed_window_share > .5,
  abs(burden$annual_ksi_crash_density * burden$crash_observed_area_sqmi * 5 - 1) < 1e-9)

expect_error(require_unique_id(data.frame(id = c("a", "a")), "id", "fixture"))
expect_error(require_unique_id(data.frame(id = c("a", NA_character_)), "id", "fixture"))
expect_error(require_columns(data.frame(a = 1), "b", "fixture"))

# Tract crash windows use actual City geometry and count distinct event IDs.
reporting <- st_sf(GEOID = "edge", geometry = st_sfc(rectangle(0, 2, 9, 11), crs = 5070))
spec <- list(buffer_meters = 5, first_year = 2020, last_year = 2024)
windows <- prepare_tract_crash_windows(reporting, st_sf(geometry = city), spec, 5070)
events <- rbind(crashes, crashes[1, ])
events$crash_year <- 2020L
events$ksi_crash <- events$fatal_crash <- events$vulnerable_road_user_ksi_crash <- TRUE
counts <- summarize_tract_crashes(windows, events, spec)
stopifnot(counts$ksi_crashes_in_window == 1,
  abs(counts$annual_ksi_crash_density * counts$crash_observation_area_sqmi * 5 - 1) < 1e-9,
  counts$crash_observed_window_share > .5, counts$crash_observed_window_share < 1)

# Raw ACS special-value codes and zero denominators stay unavailable.
work <- tempfile("source-fixtures-"); dir.create(work)
acs_spec <- list(acs_year = 2024L, state_fips = "48", county_fips = "453")
header <- c("NAME", as.vector(rbind(paste0(census_context_variables(), "E"),
                                  paste0(census_context_variables(), "M"))), "state", "county", "tract")
row <- c("Fixture", 100, 10, 20, 4, 200, 10, 50, 5, 100, 8, 10, 3,
         -666666666, -222222222, "48", "453", "000100")
path <- file.path(work, "acs2024_48453_tract_context.json")
jsonlite::write_json(list(header, row), path, auto_unbox = TRUE)
acs <- read_acs_sources(path, acs_spec)
stopifnot(acs$poverty_rate == .2, acs$people_of_color_share == .75, acs$no_vehicle_share == .1,
          is.na(acs$median_rent), is.na(acs$median_rent_moe))
row[match("B11005_001E", header)] <- "0"
jsonlite::write_json(list(header, row), path, auto_unbox = TRUE)
stopifnot(is.na(read_acs_sources(path, acs_spec)$no_vehicle_share))

# A source N/A designation, bad source category, and absent record are distinct.
raw_displacement <- st_sf(geoid22 = c("48453000100.0", "48453000200.0", "48453000300.0"),
  displaceme = c("N/A", "Unrecognized", NA_character_),
  geometry = st_sfc(rectangle(0, 1), rectangle(1, 2), rectangle(2, 3), crs = 4326))
path <- file.path(work, "displacement.geojson")
st_write(raw_displacement, path, quiet = TRUE)
displacement <- read_displacement_source(path)
context <- join_tract_displacement(data.frame(GEOID = c(displacement$GEOID, "48453000400")), displacement)
stopifnot(identical(context$displacement_coverage_status,
  c("Matched published category", "Unrecognized source category", "Missing source category", "Outside published coverage")),
  context$displacement_risk_category_display[1] == "No published displacement-risk designation")
unlink(work, recursive = TRUE)
cat("Pipeline spatial weighting, source missingness, displacement categories, school ambiguity and crash coverage checks passed.\n")
