

# install.packages("lehdr")
library(lehdr)
library(readr)
library(dplyr)

# Download WAC for TX 2020
wac <- grab_lodes(
  state = "tx",
  year = 2020,
  lodes_type = "wac",
  job_type = "JT00",
  segment = "S000"
)

# Manually download crosswalk
dir.create("data/processed/lehd", recursive = TRUE, showWarnings = FALSE)
xwalk_url <- "https://lehd.ces.census.gov/data/lodes/LODES8/tx/tx_xwalk.csv.gz"
xwalk_gz <- "data/processed/lehd/tx_xwalk.csv.gz"
download.file(xwalk_url, xwalk_gz, mode = "wb", quiet = FALSE)

xwalk <- read_csv(xwalk_gz, col_types = cols(.default = col_character())) %>%
  select(tabblk2020, trct)

# Aggregate WAC to Travis County tracts via crosswalk
travis_lodes <- wac %>%
  left_join(xwalk, by = c("w_geocode" = "tabblk2020")) %>%
  filter(!is.na(trct)) %>%
  group_by(trct) %>%
  summarise(
    totjobs = sum(C000, na.rm = TRUE),
    lowjobs = sum(CE01, na.rm = TRUE),
    medjobs = sum(CE02, na.rm = TRUE),
    highjobs = sum(CE03, na.rm = TRUE),
    .groups = "drop"
  )

# Save output
readr::write_csv(travis_lodes, "data/processed/lehd/travis_lodes.csv")

message("WAC Travis tracts: ", nrow(travis_lodes))
message("File saved: data/processed/lehd/travis_lodes.csv")
