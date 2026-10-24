# Prepare the four selected CMS NPPES facility categories for geocoding.
#
# One row is retained per active organization NPI. General Clinic/Center
# records remain a review group because code 261Q00000X does not establish
# urgent-care service.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "digest"))
source("destinations/R/destination_paths.R")
source("destinations/R/census_batch_geocoder.R")

input_path <- file.path(
  destination_dir("healthcare", "interim", "cms_nppes", create = FALSE),
  "nppes_austin_metro_healthcare_providers.csv"
)
output_dir <- destination_dir("healthcare", "interim", "cms_nppes")
qa_dir <- destination_dir("healthcare", "qaqc", "cms_nppes")
stopifnot(file.exists(input_path))

clean_value <- function(x) {
  x <- trimws(x)
  x[x %in% c("", "<UNAVAIL>", "<UNAVAILABLE>")] <- NA_character_
  x
}

raw <- readr::read_csv(
  input_path, col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
)

facilities <- raw |>
  distinct(NPI, .keep_all = TRUE) |>
  transmute(
    npi = NPI,
    organization_name = coalesce(
      clean_value(`Provider Other Organization Name`),
      clean_value(`Provider Organization Name (Legal Business Name)`)
    ),
    legal_business_name = clean_value(`Provider Organization Name (Legal Business Name)`),
    other_organization_name = clean_value(`Provider Other Organization Name`),
    address = clean_value(`Provider First Line Business Practice Location Address`),
    address_2 = clean_value(`Provider Second Line Business Practice Location Address`),
    city = clean_value(`Provider Business Practice Location Address City Name`),
    state = clean_value(`Provider Business Practice Location Address State Name`),
    zip = substr(clean_value(`Provider Business Practice Location Address Postal Code`), 1, 5),
    phone = clean_value(`Provider Business Practice Location Address Telephone Number`),
    taxonomy_code = matched_taxonomy_code,
    taxonomy_label,
    destination_domain,
    candidate_status = if_else(
      destination_domain == "general_clinic_review",
      "review_general_clinic", "selected_taxonomy_candidate"
    ),
    source = "CMS NPPES September 14 2026 V2"
  ) |>
  mutate(
    address_key = map_chr(
      paste(address, city, state, zip, sep = "|"),
      ~ digest::digest(.x, algo = "xxhash64", serialize = FALSE)
    )
  )

stopifnot(!anyDuplicated(facilities$npi), all(facilities$state == "TX"))

readr::write_csv(
  facilities,
  file.path(output_dir, "nppes_selected_healthcare_facilities.csv"), na = ""
)

addresses <- facilities |>
  distinct(address_key, address, city, state, zip) |>
  mutate(address = strip_secondary_unit(address))

# Headerless format required by the Census batch geocoder.
readr::write_csv(
  addresses,
  file.path(output_dir, "nppes_selected_healthcare_geocoder_input.csv"),
  col_names = FALSE, na = ""
)

summary <- facilities |>
  count(destination_domain, candidate_status, name = "n_organization_npis") |>
  arrange(destination_domain)
readr::write_csv(summary, file.path(qa_dir, "nppes_selected_facility_summary.csv"))
print(summary, n = Inf)
