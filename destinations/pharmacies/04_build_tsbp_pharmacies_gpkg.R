# Build the TSBP pharmacy GeoPackage from the saved Census geocodes
#
# Runs after destinations/pharmacies/03_geocode_tsbp_pharmacies.R. No network calls.
#
# Writes:
#   data/destinations/pharmacies/processed/pharmacies_tsbp.gpkg
#     layers: all_matched_licenses, community_pharmacy_candidates
#   data/destinations/pharmacies/processed/pharmacies_tsbp.csv   every license
#   data/destinations/pharmacies/qaqc/tsbp/geocoding_review.csv  unmatched
#
# Run from the repository root:
#   Rscript destinations/pharmacies/04_build_tsbp_pharmacies_gpkg.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")

interim_dir   <- destination_dir("pharmacies", "interim", "tsbp", create = FALSE)
source_path   <- file.path(interim_dir, "tsbp_pharmacies_austin_metro.csv")
response_path <- file.path(interim_dir, "geocoding", "census_combined.csv")
qa_dir        <- destination_dir("pharmacies", "qaqc", "tsbp")
stopifnot(file.exists(source_path), file.exists(response_path))

x <- read_csv(source_path, col_types = cols(.default = col_character()), show_col_types = FALSE)
g <- read_csv(response_path, col_names = c("LIC_NBR", "submitted_address", "match_status", "match_type",
  "matched_address", "coordinates", "tiger_line_id", "street_side", "geocode_pass"),
  col_types = cols(.default = col_character()), show_col_types = FALSE)
stopifnot(!anyDuplicated(g$LIC_NBR), setequal(x$LIC_NBR, g$LIC_NBR))

g <- g |>
  separate_wider_delim(coordinates, delim = ",", names = c("longitude", "latitude"), too_few = "align_start") |>
  mutate(longitude = as.numeric(longitude), latitude = as.numeric(latitude))

x <- x |>
  select(-coordinate_status) |>
  left_join(g, by = "LIC_NBR") |>
  mutate(
    coordinate_source = "US Census batch geocoder",
    geocode_benchmark = "Public_AR_Current",
    coordinate_status = case_when(
      match_status != "Match" | is.na(match_status) ~ "unmatched",
      !is.finite(latitude) | !is.finite(longitude) ~ "invalid_coordinate",
      destination_coordinate_status(latitude, longitude) != "plausible_unverified" ~ "outside_region_review",
      TRUE ~ "census_matched"
    )
  )
keep <- x$coordinate_status == "census_matched"
x <- add_h3_cells(x, keep = keep)

write_csv(x, destination_output_path("pharmacies", "tsbp", "csv"))
write_csv(x[!keep, ], file.path(qa_dir, "geocoding_review.csv"))

target <- destination_output_path("pharmacies", "tsbp", "gpkg")
write_point_layer(x[keep, ], target, "all_matched_licenses", "LIC_NBR")
write_point_layer(x[keep & x$screening_group == "community_candidate", ], target,
                  "community_pharmacy_candidates", "LIC_NBR")

print(count(x, screening_group, coordinate_status), n = Inf)
message("Saved ", target)
