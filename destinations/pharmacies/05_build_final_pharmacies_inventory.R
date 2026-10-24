# Build the final pharmacy-site inventory.
#
# TSBP active, open-door community-pharmacy licenses define eligibility.
# Data Axle supplies preferred coordinates only when address, phone, brand, or
# name evidence establishes a strong identity match. Data Axle-only records are
# not added without an eligible TSBP license.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "h3jsr"))
source("destinations/R/destination_paths.R")

tsbp_path <- file.path(
  destination_dir("pharmacies", "interim", "tsbp", create = FALSE),
  "tsbp_community_pharmacy_candidates.csv"
)
geocode_path <- file.path(
  destination_dir("pharmacies", "interim", "tsbp", create = FALSE),
  "geocoding", "census_combined.csv"
)
dataaxle_path <- file.path(
  destination_dir("pharmacies", "processed"), "pharmacies_dataaxle.gpkg"
)
output_path <- file.path(
  destination_dir("pharmacies", "processed"), "pharmacies_final.gpkg"
)
manual_coordinates_path <- "destinations/pharmacies/manual_coordinate_overrides.csv"
stopifnot(
  file.exists(tsbp_path), file.exists(geocode_path), file.exists(dataaxle_path),
  file.exists(manual_coordinates_path)
)

clean_text <- function(x) {
  x <- iconv(coalesce(x, ""), to = "ASCII//TRANSLIT")
  tolower(trimws(gsub(" +", " ", gsub("[^a-zA-Z0-9 ]", " ", x))))
}
phone_key <- function(x) gsub("[^0-9]", "", coalesce(x, ""))
house_number <- function(x) {
  z <- clean_text(x)
  ifelse(grepl("^[0-9]+", z), sub("^([0-9]+).*", "\\1", z), "")
}
name_key <- function(x) {
  z <- clean_text(x)
  z <- gsub(
    "\\b(pharmacy|pharmacies|drug|drugs|store|supercenter|market|food|grocery|company|co|inc|llc|lp|at|inside|no|number)\\b",
    " ", z
  )
  trimws(gsub(" +", " ", gsub("\\b[0-9]+\\b", " ", z)))
}
brand_key <- function(name, parent = "") {
  z <- toupper(paste(parent, name))
  case_when(
    grepl("SAM.?S", z) ~ "SAMS",
    grepl("H-?E-?B|HEB", z) ~ "HEB",
    grepl("WALGREEN", z) ~ "WALGREENS",
    grepl("CVS", z) ~ "CVS",
    grepl("WALMART|WAL-MART", z) ~ "WALMART",
    grepl("COSTCO", z) ~ "COSTCO",
    grepl("RANDALL", z) ~ "RANDALLS",
    TRUE ~ ""
  )
}

tsbp <- read_csv(
  tsbp_path, col_types = cols(.default = col_character()), show_col_types = FALSE
)
geocodes <- read_csv(
  geocode_path,
  col_names = c(
    "LIC_NBR", "submitted_address", "match_status", "match_type",
    "matched_address", "coordinates", "tiger_line_id", "street_side",
    "geocode_pass"
  ),
  col_types = cols(.default = col_character()), show_col_types = FALSE
) |>
  separate_wider_delim(
    coordinates, delim = ",", names = c("census_longitude", "census_latitude"),
    too_few = "align_start"
  ) |>
  mutate(
    census_longitude = as.numeric(census_longitude),
    census_latitude = as.numeric(census_latitude)
  )

dataaxle_sf <- st_read(dataaxle_path, layer = "candidates_pharmacies", quiet = TRUE)
dataaxle <- st_drop_geometry(dataaxle_sf)
manual_coordinates <- read_csv(
  manual_coordinates_path,
  col_types = cols(LIC_NBR = col_character(), .default = col_guess()),
  show_col_types = FALSE
) |>
  select(
    LIC_NBR, manual_latitude = latitude, manual_longitude = longitude,
    review_decision
  )

tsbp <- tsbp |>
  left_join(select(geocodes, LIC_NBR, match_status, census_longitude, census_latitude),
            by = "LIC_NBR") |>
  left_join(manual_coordinates, by = "LIC_NBR") |>
  mutate(
    ts_i = row_number(), zip5 = substr(ZIP, 1, 5),
    house_key = house_number(ADDRESS1), phone_key = phone_key(PHONE),
    name_key = name_key(PHARMACY_NAME), brand_key = brand_key(PHARMACY_NAME)
  )
dataaxle <- dataaxle |>
  mutate(
    da_i = row_number(), zip5 = substr(zip, 1, 5),
    house_key = house_number(address), phone_key = phone_key(phone),
    name_key = name_key(name), brand_key = brand_key(name, parent_name)
  )

match_one <- function(i) {
  candidates <- which(dataaxle$zip5 == tsbp$zip5[i])
  if (!length(candidates)) {
    candidates <- which(tolower(dataaxle$city) == tolower(tsbp$CITY[i]))
  }
  if (!length(candidates)) {
    return(c(da_i = NA, house = 0, phone = 0, brand = 0,
             name_similarity = 0, score = 0))
  }
  house_match <- dataaxle$house_key[candidates] != "" &
    dataaxle$house_key[candidates] == tsbp$house_key[i]
  phone_match <- dataaxle$phone_key[candidates] != "" &
    dataaxle$phone_key[candidates] == tsbp$phone_key[i]
  brand_match <- tsbp$brand_key[i] != "" &
    dataaxle$brand_key[candidates] == tsbp$brand_key[i]
  denominator <- pmax(nchar(tsbp$name_key[i]), nchar(dataaxle$name_key[candidates]))
  name_similarity <- ifelse(
    denominator > 0,
    1 - as.numeric(adist(tsbp$name_key[i], dataaxle$name_key[candidates])) / denominator,
    0
  )
  score <- 5 * phone_match + 3 * house_match + 2 * brand_match + name_similarity
  k <- which.max(score)
  accepted <- phone_match[k] |
    (house_match[k] & brand_match[k]) |
    (house_match[k] & name_similarity[k] >= 0.45) |
    name_similarity[k] >= 0.88
  if (!accepted) {
    return(c(da_i = NA, house = house_match[k], phone = phone_match[k],
             brand = brand_match[k], name_similarity = name_similarity[k],
             score = score[k]))
  }
  c(
    da_i = dataaxle$da_i[candidates[k]], house = house_match[k],
    phone = phone_match[k], brand = brand_match[k],
    name_similarity = name_similarity[k], score = score[k]
  )
}

match_matrix <- t(vapply(seq_len(nrow(tsbp)), match_one, numeric(6)))
matches <- as_tibble(match_matrix) |>
  rename(
    dataaxle_i = da_i, address_number_match = house,
    phone_match = phone, brand_match = brand, match_score = score
  )

tsbp <- bind_cols(tsbp, matches) |>
  mutate(
    dataaxle_match = !is.na(dataaxle_i),
    dataaxle_destination_id = if_else(
      dataaxle_match, dataaxle$destination_id[dataaxle_i], NA_character_
    ),
    dataaxle_name = if_else(dataaxle_match, dataaxle$name[dataaxle_i], NA_character_),
    dataaxle_address = if_else(dataaxle_match, dataaxle$address[dataaxle_i], NA_character_),
    dataaxle_latitude = if_else(dataaxle_match, dataaxle$latitude[dataaxle_i], NA_real_),
    dataaxle_longitude = if_else(dataaxle_match, dataaxle$longitude[dataaxle_i], NA_real_),
    census_coordinate_available = match_status == "Match" &
      is.finite(census_latitude) & is.finite(census_longitude),
    manual_coordinate_available = review_decision == "include_manual_verified" &
      is.finite(manual_latitude) & is.finite(manual_longitude),
    latitude = case_when(
      dataaxle_match ~ dataaxle_latitude,
      census_coordinate_available ~ census_latitude,
      manual_coordinate_available ~ manual_latitude,
      TRUE ~ NA_real_
    ),
    longitude = case_when(
      dataaxle_match ~ dataaxle_longitude,
      census_coordinate_available ~ census_longitude,
      manual_coordinate_available ~ manual_longitude,
      TRUE ~ NA_real_
    ),
    coordinate_source = case_when(
      dataaxle_match & census_coordinate_available ~ "Data Axle preferred over Census geocode",
      dataaxle_match ~ "Data Axle recovered missing Census geocode",
      census_coordinate_available ~ "US Census batch geocoder",
      manual_coordinate_available ~ "Manual review: verified address coordinate",
      TRUE ~ "unresolved"
    ),
    site_key = if_else(
      dataaxle_match,
      paste0("dataaxle_", dataaxle_destination_id),
      paste("tsbp", house_key, clean_text(CITY), zip5, sep = "_")
    )
  )

resolved <- tsbp |>
  filter(is.finite(latitude), is.finite(longitude),
         destination_coordinate_status(latitude, longitude) == "plausible_unverified")

# One accessibility destination per physical pharmacy site. Multiple eligible
# licenses at the same matched site are retained in the license-list fields.
site_licenses <- resolved |>
  group_by(site_key) |>
  summarise(
    license_numbers = paste(sort(unique(LIC_NBR)), collapse = "; "),
    licensed_names = paste(sort(unique(PHARMACY_NAME)), collapse = "; "),
    license_count = n_distinct(LIC_NBR),
    .groups = "drop"
  )
site_primary <- resolved |>
  group_by(site_key) |>
  slice_max(match_score, n = 1, with_ties = FALSE) |>
  ungroup() |>
  left_join(site_licenses, by = "site_key") |>
  transmute(
    pharmacy_id = site_key,
    pharmacy_name = PHARMACY_NAME,
    license_numbers,
    licensed_names,
    license_count,
    address = ADDRESS1,
    address_2 = ADDRESS2,
    city = CITY,
    state = STATE,
    zip = ZIP,
    county = COUNTY,
    phone = PHONE,
    ownership = OWNERSHIP,
    pharmacy_class = CLASS,
    home_delivery = `HOME DELIVERY`,
    disabled_access = DISABLED,
    medicaid = MEDICAID,
    latitude,
    longitude,
    coordinate_source,
    dataaxle_destination_id,
    dataaxle_name,
    dataaxle_address,
    match_phone = as.logical(phone_match),
    match_address_number = as.logical(address_number_match),
    match_brand = as.logical(brand_match),
    match_name_similarity = name_similarity,
    source = "Texas State Board of Pharmacy; Data Axle coordinate supplement",
    source_reference = "https://www.pharmacy.texas.gov/dbsearch/tables.asp"
  )

final <- st_as_sf(site_primary, coords = c("longitude", "latitude"), crs = 4326,
                  remove = FALSE) |>
  add_h3_cells() |>
  arrange(county, city, pharmacy_name)

stopifnot(
  nrow(tsbp) == 318,
  sum(tsbp$dataaxle_match) == 280,
  sum(tsbp$dataaxle_match & !tsbp$census_coordinate_available) == 46,
  sum(tsbp$manual_coordinate_available) == 5,
  nrow(final) == 316,
  !anyDuplicated(final$pharmacy_id),
  all(st_is_valid(final))
)

if (file.exists(output_path)) file.remove(output_path)
st_write(final, output_path, layer = "pharmacies", quiet = TRUE)

message("Final unique pharmacy sites: ", nrow(final))
message("Eligible TSBP licenses: ", nrow(tsbp))
message("TSBP licenses matched to Data Axle coordinates: ", sum(tsbp$dataaxle_match))
message("Missing Census geocodes recovered by Data Axle: ",
        sum(tsbp$dataaxle_match & !tsbp$census_coordinate_available))
message("Missing geocodes resolved by manual review: ",
        sum(tsbp$manual_coordinate_available))
message("Eligible licenses still unresolved: ",
        sum(!is.finite(tsbp$latitude) | !is.finite(tsbp$longitude)))
