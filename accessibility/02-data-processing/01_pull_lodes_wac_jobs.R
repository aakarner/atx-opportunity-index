# Prepare 2023 LODES job destinations and resident-worker weights at H8.

source("accessibility/config.R")

Sys.setenv(R_USER_CACHE_DIR = cache_dir)

source("00_setup_packages.R")
setup_project_packages(c("dplyr", "h3jsr", "lehdr", "readr"))

lodes_cache_dir <- file.path(cache_dir, "lehdr")
dir.create(lodes_cache_dir, recursive = TRUE, showWarnings = FALSE)

xwalk_url <- "https://lehd.ces.census.gov/data/lodes/LODES8/tx/tx_xwalk.csv.gz"
xwalk_path <- file.path(lodes_cache_dir, "tx_xwalk.csv.gz")

if (!file.exists(xwalk_path)) {
  message("Downloading the LODES 2020-block geography crosswalk...")
  download.file(xwalk_url, xwalk_path, mode = "wb", quiet = FALSE)
}

xwalk <- read_csv(
  xwalk_path,
  col_types = cols_only(
    tabblk2020 = col_character(),
    blklatdd = col_double(),
    blklondd = col_double()
  ),
  show_col_types = FALSE
)

message("Downloading/reading 2023 WAC job data...")
wac <- grab_lodes(
  state = "tx",
  year = lodes_year,
  version = "LODES8",
  lodes_type = "wac",
  job_type = "JT00",
  segment = "S000",
  agg_geo = "block",
  download_dir = lodes_cache_dir,
  use_cache = TRUE
) %>%
  transmute(
    block_geoid = w_geocode,
    total_jobs = C000,
    low_wage_jobs = CE01,
    middle_wage_jobs = CE02,
    high_wage_jobs = CE03
  ) %>%
  filter(substr(block_geoid, 1, 5) %in% unname(austin_msa_county_fips)) %>%
  left_join(xwalk, by = c("block_geoid" = "tabblk2020")) %>%
  filter(!is.na(blklondd), !is.na(blklatdd))

wac$h3_id <- point_to_cell(
  data.frame(lon = wac$blklondd, lat = wac$blklatdd),
  res = h3_resolution
)

h3_jobs <- wac %>%
  group_by(h3_id) %>%
  summarise(
    across(
      c(total_jobs, low_wage_jobs, middle_wage_jobs, high_wage_jobs),
      ~ sum(.x, na.rm = TRUE)
    ),
    .groups = "drop"
  )

message("Downloading/reading 2023 RAC resident-worker data...")
rac <- grab_lodes(
  state = "tx",
  year = lodes_year,
  version = "LODES8",
  lodes_type = "rac",
  job_type = "JT00",
  segment = "S000",
  agg_geo = "block",
  download_dir = lodes_cache_dir,
  use_cache = TRUE
) %>%
  transmute(
    block_geoid = h_geocode,
    workers_all = C000,
    workers_low = CE01,
    workers_middle = CE02,
    workers_high = CE03
  ) %>%
  filter(substr(block_geoid, 1, 5) %in% unname(analysis_county_fips)) %>%
  left_join(xwalk, by = c("block_geoid" = "tabblk2020")) %>%
  filter(!is.na(blklondd), !is.na(blklatdd))

rac$h3_id <- point_to_cell(
  data.frame(lon = rac$blklondd, lat = rac$blklatdd),
  res = h3_resolution
)

h3_workers <- rac %>%
  group_by(h3_id) %>%
  summarise(
    across(starts_with("workers_"), ~ sum(.x, na.rm = TRUE)),
    .groups = "drop"
  )

# Preserve a direct 2020-tract aggregation for the step-20 functional-role
# experiment; the submitted step-22 clusters use the H8 accessibility measure,
# not this experimental tract functional-role coordinate.
# LODES8 block identifiers and 2024 ACS tract estimates both use 2020 Census
# tract definitions, so this avoids unnecessarily converting block counts to
# H8 and area-apportioning them back to tracts.
tract_jobs <- wac %>%
  filter(substr(block_geoid, 1, 5) %in% unname(analysis_county_fips)) %>%
  mutate(GEOID = substr(block_geoid, 1, 11)) %>%
  group_by(GEOID) %>%
  summarise(
    across(
      c(total_jobs, low_wage_jobs, middle_wage_jobs, high_wage_jobs),
      ~sum(.x, na.rm = TRUE)
    ),
    .groups = "drop"
  )

tract_workers <- rac %>%
  mutate(GEOID = substr(block_geoid, 1, 11)) %>%
  group_by(GEOID) %>%
  summarise(
    across(starts_with("workers_"), ~sum(.x, na.rm = TRUE)),
    .groups = "drop"
  )

tract_functional_role <- full_join(
  tract_jobs,
  tract_workers,
  by = "GEOID"
) %>%
  mutate(
    across(
      c(
        total_jobs, low_wage_jobs, middle_wage_jobs, high_wage_jobs,
        workers_all, workers_low, workers_middle, workers_high
      ),
      ~coalesce(.x, 0)
    ),
    jobs_resident_worker_balance =
      (total_jobs - workers_all) / (total_jobs + workers_all + 1),
    local_jobs_and_workers = total_jobs + workers_all
  ) %>%
  arrange(GEOID)

if (
  any(nchar(tract_functional_role$GEOID) != 11) ||
    any(!grepl("^[0-9]{11}$", tract_functional_role$GEOID)) ||
    anyDuplicated(tract_functional_role$GEOID) > 0
) {
  stop("Tract functional-role GEOIDs must be unique 11-digit identifiers.")
}

if (any(
  tract_functional_role$total_jobs !=
    tract_functional_role$low_wage_jobs +
      tract_functional_role$middle_wage_jobs +
      tract_functional_role$high_wage_jobs |
    tract_functional_role$workers_all !=
      tract_functional_role$workers_low +
      tract_functional_role$workers_middle +
      tract_functional_role$workers_high
)) {
  stop("LODES tract wage groups do not reconcile to all jobs/workers.")
}

if (any(!is.finite(unlist(
  tract_functional_role %>% select(-GEOID)
)))) {
  stop("LODES tract functional-role output contains a non-finite value.")
}

write_csv(h3_jobs, lodes_jobs_path)
write_csv(h3_workers, lodes_workers_path)
write_csv(tract_functional_role, lodes_tract_function_path)

message("Saved ", nrow(h3_jobs), " H8 job destination cells to ", lodes_jobs_path)
message("Saved ", nrow(h3_workers), " H8 worker cells to ", lodes_workers_path)
message(
  "Saved ", nrow(tract_functional_role),
  " tract functional-role records to ", lodes_tract_function_path
)
