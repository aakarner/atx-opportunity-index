# Geocode unique practice addresses for the selected CMS NPPES facilities.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "httr2"))
source("destinations/R/destination_paths.R")
source("destinations/R/census_batch_geocoder.R")

input_path <- file.path(
  destination_dir("healthcare", "interim", "cms_nppes", create = FALSE),
  "nppes_selected_healthcare_geocoder_input.csv"
)
output_path <- file.path(
  destination_dir("healthcare", "interim", "cms_nppes"),
  "nppes_selected_healthcare_geocoder_response.csv"
)
stopifnot(file.exists(input_path))

if (!file.exists(output_path) || identical(Sys.getenv("REFRESH_NPPES_GEOCODE"), "true")) {
  census_submit_batch(input_path, output_path)
} else {
  message("Reusing saved geocoder response: ", output_path)
}

result <- census_read_response(output_path) |>
  census_split_coordinates()
message("Matched addresses: ", sum(result$match_status == "Match"), " / ", nrow(result))

