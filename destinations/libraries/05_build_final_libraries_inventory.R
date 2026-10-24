# Build the final Austin metro public-library inventory.
#
# Data Axle is the metro-wide baseline. Obvious organizations, support groups,
# and obsolete duplicates are removed. Current City of Austin locations are
# used to standardize Austin names and to add verified omissions.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf"))
source("destinations/R/destination_paths.R")

dataaxle_path <- file.path(
  destination_dir("libraries", "processed"), "libraries_dataaxle.gpkg"
)
city_path <- file.path(
  destination_dir("libraries", "processed"), "libraries_austin_open_data.gpkg"
)
output_path <- file.path(
  destination_dir("libraries", "processed"), "libraries_final.gpkg"
)
stopifnot(file.exists(dataaxle_path), file.exists(city_path))

excluded_names <- c(
  "Atheist Community Of Austin",
  "Friends-The Jonestown Cmnty",
  "Texas Library Assn",
  "Liberty Hill Pubc Library Dist"
)

dataaxle <- st_read(dataaxle_path, layer = "candidates_libraries", quiet = TRUE) |>
  st_transform(26914)
city <- st_read(city_path, layer = "libraries", quiet = TRUE) |>
  st_transform(26914)

excluded <- dataaxle |>
  filter(name %in% excluded_names)
stopifnot(nrow(excluded) == length(excluded_names))

dataaxle_keep <- dataaxle |>
  filter(!name %in% excluded_names, analysis_ready)

# Standardize Austin Public Library names from the government source when the
# points coincide. A 50 m threshold accommodates small coordinate differences.
distance_matrix <- st_distance(dataaxle_keep, city)
nearest_city <- apply(distance_matrix, 1, which.min)
nearest_distance <- as.numeric(
  distance_matrix[cbind(seq_len(nrow(dataaxle_keep)), nearest_city)]
)
city_match <- nearest_distance <= 50
matched_city_names <- city$destination_name[nearest_city]
matched_city_ids <- city$destination_id[nearest_city]

dataaxle_final <- dataaxle_keep |>
  mutate(
    original_dataaxle_name = name,
    library_name = if_else(
      city_match,
      matched_city_names,
      name
    ),
    city_destination_id = if_else(
      city_match,
      matched_city_ids,
      NA_character_
    ),
    library_type = "general public library",
    inventory_source = if_else(
      city_match,
      "Data Axle; City of Austin Open Data",
      "Data Axle"
    ),
    screening_basis = if_else(
      city_match,
      "Data Axle location confirmed and named by City of Austin",
      "Named public or community library with public-facing library identity"
    ),
    source_reference = if_else(
      city_match,
      "Data Axle export; City of Austin dataset tc36-hn4j",
      "Data Axle custom export"
    )
  ) |>
  transmute(
    library_id = destination_id,
    library_name,
    library_type,
    address,
    city,
    county,
    state,
    zip,
    website,
    phone,
    latitude,
    longitude,
    inventory_source,
    source_record_id = destination_id,
    city_destination_id,
    original_dataaxle_name,
    screening_basis,
    source_reference,
    geom
  )

# Add active City facilities missing from Data Axle. Recycled Reads is not
# added because the bookstore permanently closed on 17 January 2026.
city_add_names <- c(
  "Central Library",
  "Austin History Center - John Henry Faulk Building"
)
city_add <- city |>
  filter(destination_name %in% city_add_names) |>
  mutate(
    library_type = if_else(
      destination_name == "Central Library",
      "general public library",
      "specialized library and archive"
    ),
    address = case_when(
      destination_name == "Central Library" ~ "710 W Cesar Chavez St",
      TRUE ~ "800 Guadalupe St"
    ),
    city = "Austin",
    county = "Travis",
    state = "TX",
    zip = if_else(destination_name == "Central Library", "78701", "78701"),
    website = case_when(
      destination_name == "Central Library" ~ "https://library.austintexas.gov/central-library",
      TRUE ~ "https://library.austintexas.gov/austin-history-center"
    ),
    phone = if_else(destination_name == "Central Library", "512-974-7400", "512-974-7480"),
    inventory_source = "City of Austin Open Data",
    source_record_id = destination_id,
    city_destination_id = destination_id,
    original_dataaxle_name = NA_character_,
    screening_basis = if_else(
      destination_name == "Central Library",
      "Active full-service Austin Public Library omitted by Data Axle",
      "Active public Austin Public Library history collection and reading room omitted by Data Axle"
    ),
    source_reference = "City of Austin dataset tc36-hn4j"
  ) |>
  transmute(
    library_id = paste0("coa_", destination_id),
    library_name = destination_name,
    library_type,
    address,
    city,
    county,
    state,
    zip,
    website,
    phone,
    latitude,
    longitude,
    inventory_source,
    source_record_id,
    city_destination_id,
    original_dataaxle_name,
    screening_basis,
    source_reference,
    geom
  )

final <- bind_rows(dataaxle_final, city_add) |>
  st_transform(4326) |>
  arrange(county, city, library_name)

stopifnot(
  nrow(dataaxle) == 55,
  nrow(excluded) == 4,
  nrow(dataaxle_final) == 51,
  nrow(city_add) == 2,
  nrow(final) == 53,
  !anyDuplicated(final$library_id),
  all(st_is_valid(final)),
  !any(final$library_name == "Recycled Reads Bookstore")
)

if (file.exists(output_path)) file.remove(output_path)
st_write(final, output_path, layer = "libraries", quiet = TRUE)

message("Final libraries: ", nrow(final))
message("Retained from Data Axle: ", nrow(dataaxle_final))
message("Added from City of Austin: ", nrow(city_add))
message("Excluded from Data Axle: ", nrow(excluded))
print(st_drop_geometry(excluded)[, c("name", "address", "city")])
