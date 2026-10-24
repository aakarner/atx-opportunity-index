# End-to-end test of the per-destination Data Axle scripts in a disposable
# copy of the project. Never modifies real exports or review inputs.
#
# Run from repo root: Rscript destinations/tests/test_dataaxle_pipeline.R
repo <- normalizePath(".")
test_root <- tempfile("dataaxle_test_")
dir.create(file.path(test_root, "destinations", "R"), recursive = TRUE)
dir.create(file.path(test_root, "destinations", "groceries"), recursive = TRUE)
file.copy("00_setup_packages.R", test_root)
file.copy(list.files("destinations/R", full.names = TRUE), file.path(test_root, "destinations", "R"))
file.copy(list.files("destinations/groceries", pattern = "dataaxle", full.names = TRUE),
          file.path(test_root, "destinations", "groceries"))
raw_dir <- file.path(test_root, "data/destinations/groceries/raw/dataaxle")
dir.create(raw_dir, recursive = TRUE)
raw <- data.frame(`Company Name` = "Example Market", Address = "123 Main St", City = "Austin",
  State = "TX", `ZIP Code` = "78701", `Primary NAICS` = "44511003", Latitude = 30.27,
  Longitude = -97.74, check.names = FALSE)
write.csv(raw, file.path(raw_dir, "batch.csv"), row.names = FALSE)
setwd(test_root)
rscript <- function(script) {
  log <- system2(file.path(R.home("bin"), "Rscript"), script, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(log, "status"))) stop(paste(log, collapse = "\n"))
}
run <- function() {
  rscript("destinations/groceries/02_clean_dataaxle_groceries.R")
  rscript("destinations/groceries/04_build_dataaxle_groceries_gpkg.R")
  stopifnot(file.exists("data/destinations/groceries/processed/groceries_dataaxle.gpkg"))
  read.csv("data/destinations/groceries/interim/dataaxle/dataaxle_standardized.csv", stringsAsFactors = FALSE)
}
reviews_path <- "data/destinations/manual/dataaxle_reviews.csv"
corrections_path <- "data/destinations/manual/dataaxle_coordinate_corrections.csv"
a <- run(); stopifnot(nrow(a) == 1, a$map_ready, a$analysis_ready)
b <- run(); stopifnot(identical(a, b))
r <- data.frame(collection = a$collection, destination_id = a$destination_id, record_fingerprint = a$record_fingerprint,
  review_decision = "exclude", reviewed_type = "groceries", reviewer = "test", reviewed_on = "2026-09-10",
  evidence = "Synthetic test decision", notes = "")
write.csv(r, reviews_path, row.names = FALSE)
c <- run(); stopifnot(!c$analysis_ready, c$screen_decision == "exclude", c$map_ready)
# A changed record must not silently inherit the old exclusion or inclusion.
raw$Latitude <- 30.28
write.csv(raw, file.path("data/destinations/groceries/raw/dataaxle", "batch.csv"), row.names = FALSE)
d <- run(); stopifnot(d$manual_review_status == "stale_or_incomplete", !d$analysis_ready)
r$record_fingerprint <- d$record_fingerprint; r$review_decision <- "include"
write.csv(r, reviews_path, row.names = FALSE)
e <- run(); stopifnot(e$analysis_ready, e$classification_basis == "manual_review")
# A documented coordinate correction is applied as a pair without changing the raw export.
correction <- data.frame(destination_id = e$destination_id, record_fingerprint = e$record_fingerprint,
  latitude = 30.29, longitude = -97.75, coordinate_source = "test_verified", reviewer = "test",
  reviewed_on = "2026-09-10", evidence = "Synthetic coordinate test")
write.csv(correction, corrections_path, row.names = FALSE)
fixed <- run(); stopifnot(fixed$latitude == 30.29, fixed$longitude == -97.75,
  fixed$coordinate_status == "reviewed_coordinate", fixed$analysis_ready)
correction$latitude <- 999
write.csv(correction, corrections_path, row.names = FALSE)
invalid <- run(); stopifnot(invalid$coordinate_correction_status == "invalid", !invalid$analysis_ready)
# The same address in another destination triggers the cross-destination review flag.
other <- "data/destinations/pharmacies/raw/dataaxle"
dir.create(other, recursive = TRUE)
pharmacy <- raw; pharmacy$`Company Name` <- "Example Pharmacy"
write.csv(pharmacy, file.path(other, "batch.csv"), row.names = FALSE)
shared <- run(); stopifnot(shared$shared_address, shared$screen_decision == "review")
setwd(repo)
unlink(test_root, recursive = TRUE)
cat("Per-destination reruns, manual exclusion/inclusion, stale decisions, corrections and cross-destination checks passed.\n")
