# Build a map-ready GeoPackage for the four selected CMS NPPES categories.

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")
source("destinations/R/census_batch_geocoder.R")

interim_dir <- destination_dir("healthcare", "interim", "cms_nppes", create = FALSE)
facility_path <- file.path(interim_dir, "nppes_selected_healthcare_facilities.csv")
geocode_path <- file.path(interim_dir, "nppes_selected_healthcare_geocoder_response.csv")
output_path <- file.path(
  destination_dir("healthcare", "processed"), "healthcare_cms_nppes.gpkg"
)
county_path <- file.path(interim_dir, "austin_metro_counties_2024.gpkg")
qa_dir <- destination_dir("healthcare", "qaqc", "cms_nppes")
stopifnot(file.exists(facility_path), file.exists(geocode_path), file.exists(county_path))

facilities <- readr::read_csv(
  facility_path, col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
)
geocodes <- census_read_response(geocode_path) |>
  census_split_coordinates() |>
  transmute(
    address_key = unique_id, match_status, match_type, matched_address,
    longitude, latitude
  )

x <- facilities |>
  left_join(geocodes, by = "address_key") |>
  mutate(
    coordinate_status = destination_coordinate_status(latitude, longitude),
    geocode_source = "US Census batch geocoder"
  )

unmatched <- x |>
  filter(match_status != "Match" | is.na(match_status) |
           coordinate_status != "plausible_unverified") |>
  mutate(review_reason = "address_not_geocoded")

geocoded <- x |>
  filter(match_status == "Match", coordinate_status == "plausible_unverified") |>
  sf::st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |>
  sf::st_join(
    sf::st_read(county_path, quiet = TRUE) |>
      sf::st_transform(4326) |>
      select(county = NAME),
    join = sf::st_within,
    left = TRUE
  )

outside_metro <- geocoded |>
  filter(is.na(county)) |>
  sf::st_drop_geometry() |>
  mutate(review_reason = "geocoded_outside_five_county_metro")

readr::write_csv(
  bind_rows(unmatched, outside_metro),
  file.path(qa_dir, "nppes_geocoding_review.csv"), na = ""
)

mapped <- geocoded |>
  filter(!is.na(county)) |>
  add_h3_cells()

if (file.exists(output_path)) file.remove(output_path)
for (domain in c("pharmacy", "hospital", "urgent_care", "general_clinic_review")) {
  layer <- mapped |> filter(destination_domain == domain)
  if (nrow(layer)) sf::st_write(layer, output_path, layer = domain, quiet = TRUE)
}

summary <- mapped |>
  sf::st_drop_geometry() |>
  count(destination_domain, county, name = "n") |>
  arrange(destination_domain, desc(n))
readr::write_csv(summary, file.path(qa_dir, "nppes_geocoding_summary.csv"))
print(summary, n = Inf)
message("Unmatched facility records: ", nrow(unmatched))
message("Geocoded outside five-county metro: ", nrow(outside_metro))
message("GeoPackage: ", output_path)
