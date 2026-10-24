# Run from repo root: Rscript destinations/tests/test_dataaxle.R
# Unit tests for the Data Axle normalization and screening helpers.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_helpers.R")
source("destinations/R/dataaxle_config.R")
fixture <- tempfile(fileext=".csv")
raw <- tibble::tibble(`Company Name`="Example Market", Address="123 Main St",
 City="Austin", State="TX", `ZIP Code`="78701", `Primary NAICS`="44511003",
 Latitude="30.27", Longitude="-97.74")
readr::write_csv(raw, fixture)
a <- ax_read(fixture, "groceries")
# Repeated batches must not inflate counts or invalidate existing reviews.
one <- ax_screen(ax_consolidate(a), dataaxle_rules, dataaxle_bbox, dataaxle_rule_version)
two <- ax_screen(ax_consolidate(dplyr::bind_rows(a,a)), dataaxle_rules, dataaxle_bbox, dataaxle_rule_version)
stopifnot(nrow(two)==1, two$source_records==2, one$record_fingerprint==two$record_fingerprint)
# A summary row missing coordinates must inherit the paired detail coordinates.
summary_row <- a; summary_row$latitude_raw <- NA; summary_row$longitude_raw <- NA
joined <- ax_consolidate(dplyr::bind_rows(summary_row,a))
stopifnot(joined$latitude==30.27, joined$longitude == -97.74)
# Conflicting details must remain visible and require review.
b <- a; b$latitude_raw <- "30.50"; b$naics <- "44523005"
conflict <- ax_screen(ax_consolidate(dplyr::bind_rows(a,b)), dataaxle_rules, dataaxle_bbox, dataaxle_rule_version)
stopifnot(conflict$coordinate_conflict, conflict$decision=="review", conflict$record_fingerprint != one$record_fingerprint)
# Do not fabricate paired coordinates out of separate incomplete records.
a_lat <- a; a_lat$longitude_raw <- NA
a_lon <- a; a_lon$latitude_raw <- NA
stopifnot(is.na(ax_consolidate(dplyr::bind_rows(a_lat,a_lon))$latitude))
# Distinct companies at a shared address are not silently collapsed.
raw2 <- dplyr::bind_rows(raw, dplyr::mutate(raw, `Company Name`="Another Market"))
readr::write_csv(raw2, fixture)
shared <- ax_screen(ax_consolidate(ax_read(fixture,"groceries")), dataaxle_rules, dataaxle_bbox, dataaxle_rule_version)
stopifnot(nrow(shared)==2, all(shared$shared_address), all(shared$decision=="review"))
# Unknown collections are map candidates, but never automatically included.
unknown <- a; unknown$collection <- "new_category"
stopifnot(ax_screen(ax_consolidate(unknown), dataaxle_rules, dataaxle_bbox, dataaxle_rule_version)$decision=="review")
unlink(fixture)
cat("Data Axle normalization, batch deduplication, fingerprint and screening tests passed.\n")
