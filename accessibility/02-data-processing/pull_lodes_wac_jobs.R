# Prepare 2023 LODES job destinations and resident-worker weights at H8.

source("accessibility/config.R")

Sys.setenv(R_USER_CACHE_DIR = cache_dir)

source("setup_packages.R")
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

write_csv(h3_jobs, lodes_jobs_path)
write_csv(h3_workers, lodes_workers_path)

message("Saved ", nrow(h3_jobs), " H8 job destination cells to ", lodes_jobs_path)
message("Saved ", nrow(h3_workers), " H8 worker cells to ", lodes_workers_path)
