# Filter the TSBP roster to the metro and screen community pharmacies
#
# Runs after destinations/pharmacies/01_pull_tsbp_pharmacies.R. No network calls.
#
# Keeps Texas licenses in the five metro counties. screening_group marks
# preliminary community-pharmacy candidates: Active status, a Community
# Pharmacy or Community Sterile Compounding class, and CLOSED DOOR = N. Other
# classes and statuses (including probation) stay in the full extract for
# review. Candidates are not verified walk-in access.
#
# Writes:
#   data/destinations/pharmacies/interim/tsbp/tsbp_pharmacies_austin_metro.csv
#   data/destinations/pharmacies/interim/tsbp/tsbp_community_pharmacy_candidates.csv
#   data/destinations/pharmacies/qaqc/tsbp/county_summary.csv, manifest.json
#
# Run from the repository root:
#   Rscript destinations/pharmacies/02_clean_tsbp_pharmacies.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")

raw_path    <- file.path(destination_dir("pharmacies", "raw", "tsbp", create = FALSE), "phydsk.csv")
interim_dir <- destination_dir("pharmacies", "interim", "tsbp")
qa_dir      <- destination_dir("pharmacies", "qaqc", "tsbp")
if (!file.exists(raw_path)) stop("Missing ", raw_path, ". Run 01_pull_tsbp_pharmacies.R first.")

keep_fields <- c("LIC_NBR", "ENTITY_NBR", "PHARMACY_NAME", "ADDRESS1", "ADDRESS2", "CITY",
  "STATE", "ZIP", "COUNTY", "PHONE", "LIC_STATUS", "LIC_EXPR_DATE", "LIC_ORIG_DATE",
  "DISP ACTN", "CLASS", "OWNERSHIP", "PHY TYPE", "CLOSED DOOR", "HR24 SERVICE",
  "HOME DELIVERY", "INFUSION", "CMPNDING-NONSTERILE", "DISABLED", "TRANSLATE", "SPANISH",
  "VIETNAMESE", "SIGNLANG", "MEDICAID", "DISP PRESCRPT")
community_classes <- c("Community Pharmacy", "Community Sterile Compounding")
metro_counties <- toupper(destination_metro_counties)

# Keep values exactly as supplied (no trimming, blanks stay blank).
raw <- readr::read_csv(raw_path, col_types = readr::cols(.default = readr::col_character()),
  locale = readr::locale(encoding = "cp1252"), trim_ws = FALSE, na = character(),
  show_col_types = FALSE)
missing_fields <- setdiff(keep_fields, names(raw))
if (length(missing_fields)) stop("TSBP schema changed; missing: ", paste(missing_fields, collapse = ", "))

metro <- raw |>
  filter(trimws(STATE) == "TX", trimws(COUNTY) %in% metro_counties) |>
  select(all_of(keep_fields)) |>
  mutate(
    screening_group = if_else(
      LIC_STATUS == "Active" & CLASS %in% community_classes & `CLOSED DOOR` == "N",
      "community_candidate", "review_other_class_or_status"),
    coordinate_status = "not_geocoded"
  )
stopifnot(!anyDuplicated(metro$LIC_NBR))

write_csv(metro, file.path(interim_dir, "tsbp_pharmacies_austin_metro.csv"), na = "")
write_csv(filter(metro, screening_group == "community_candidate"),
          file.path(interim_dir, "tsbp_community_pharmacy_candidates.csv"), na = "")

county_summary <- metro |>
  mutate(COUNTY = factor(COUNTY, levels = sort(metro_counties))) |>
  group_by(county = COUNTY, .drop = FALSE) |>
  summarise(all_licenses = n(), active = sum(LIC_STATUS == "Active"),
            community_candidates = sum(screening_group == "community_candidate"), .groups = "drop")
write_csv(county_summary, file.path(qa_dir, "county_summary.csv"))

manifest <- list(
  raw_path = raw_path, raw_sha256 = unname(file_sha256(raw_path)), raw_encoding = "cp1252",
  prepared_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  statewide_file_records = nrow(raw), metro_license_records = nrow(metro),
  community_candidates = sum(metro$screening_group == "community_candidate"),
  note = paste("No coordinates in source. Active community classes and CLOSED DOOR=N are",
               "preliminary candidates, not verified walk-in access.")
)
jsonlite::write_json(manifest, file.path(qa_dir, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)
print(county_summary)
message("Metro licenses: ", nrow(metro), "; community candidates: ", manifest$community_candidates)
