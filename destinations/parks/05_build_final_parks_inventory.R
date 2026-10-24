# Build the final Austin metro parks inventory from ParkServe Open Access parks.
#
# Retention policy:
#   - retain ParkServe records with Park_Access = 3 and operational/open status;
#   - do not exclude by ownership, manager, designation, acreage, or development;
#   - identify specialized sites for a later sensitivity analysis;
#   - add government-source omissions only after the same public-access criteria
#     have been verified (none are added by this baseline build).
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "jsonlite"))
source("destinations/R/destination_paths.R")

input_gpkg <- file.path(
  destination_dir("parks", "processed"),
  "parks_parkserve_austin_metro.gpkg"
)
metadata_path <- file.path(
  destination_dir("parks", "raw", "parkserve", create = FALSE),
  "layer.json"
)
output_gpkg <- file.path(destination_dir("parks", "processed"), "parks_final.gpkg")
city_path <- file.path(
  destination_dir("parks", "raw", "austin_open_data", create = FALSE),
  "parks.geojson"
)
boundary_path <- "accessibility/data/cache/tigris/tl_2024_48_place.shp"

stopifnot(
  file.exists(input_gpkg), file.exists(metadata_path),
  file.exists(city_path), file.exists(boundary_path)
)

domain_table <- function(metadata, field_name) {
  field <- Filter(function(x) identical(x$name, field_name), metadata$fields)[[1]]
  bind_rows(lapply(field$domain$codedValues, function(x) {
    tibble(code = as.character(x$code), label = trimws(x$name))
  }))
}

metadata <- fromJSON(metadata_path, simplifyVector = FALSE)
designation_domain <- domain_table(metadata, "park_designation")
manager_domain <- domain_table(metadata, "park_manager_type") |>
  bind_rows(
    tibble(code = "SPECIAL_DISTRICT", label = "Special District or Authority"),
    tibble(code = "UNKNOWN", label = "Unknown")
  ) |>
  distinct(code, .keep_all = TRUE)

parks <- st_read(input_gpkg, layer = "open_access_parks", quiet = TRUE) |>
  st_transform(26914) |>
  st_make_valid() |>
  st_transform(4326) |>
  mutate(
    park_size_acres = suppressWarnings(as.numeric(park_size_acres)),
    park_access = as.character(park_access),
    park_status = trimws(as.character(park_status))
  )

# Reassert the source rule rather than trusting the input layer name alone.
parks <- parks |>
  filter(park_access == "3", grepl("^OPEN", toupper(coalesce(park_status, ""))))

if (anyDuplicated(parks$parkid)) {
  stop("ParkServe parkid is not unique; resolve duplicates before building the final layer.")
}

general_designations <- c("LP", "LREC", "REC", "SREC", "SP")
conservation_designations <- c(
  "CONE", "LCA", "NCA", "NWR", "PCON", "RNA", "SCA", "WPA",
  "WA", "WSA", "SW", "WSR", "NF", "NG", "NLS", "NP", "NRA"
)

final_parks <- parks |>
  left_join(designation_domain, by = c("park_designation" = "code")) |>
  rename(park_designation_label = label) |>
  left_join(manager_domain, by = c("park_manager_type" = "code")) |>
  rename(park_manager_type_label = label) |>
  mutate(
    park_designation_label = coalesce(park_designation_label, park_designation, "Unknown"),
    park_manager_type_label = coalesce(park_manager_type_label, park_manager_type, "Unknown"),
    specialized_access = case_when(
      grepl("golf|cemeter", park_name, ignore.case = TRUE) ~ "golf or cemetery",
      park_designation %in% conservation_designations ~ "conservation or natural area",
      park_manager_type %in% c("PRIV", "HOA") |
        park_designation %in% c("PAGR", "PCON", "PPRK", "PREC") ~
        "privately managed open access",
      park_designation %in% general_designations ~ "general recreation",
      TRUE ~ "other specialized or unknown"
    ),
    source = "Trust for Public Land ParkServe",
    source_addition = "ParkServe primary",
    source_reference = "https://www.tpl.org/parkserve/about"
  ) |>
  transmute(
    park_id = parkid,
    park_name,
    park_designation = park_designation_label,
    park_manager_type = park_manager_type_label,
    park_local_manager,
    county = park_county,
    acreage = park_size_acres,
    park_access = "Open Access",
    specialized_access,
    source,
    source_addition,
    source_reference,
    geom
  ) |>
  arrange(county, park_name, park_id)

# Transfer selected City of Austin attributes only for conservative reciprocal
# one-to-one matches. City fields supplement ParkServe and never control whether
# a ParkServe Open Access record is retained.
name_key <- function(x) {
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x[is.na(x)] <- ""
  x <- tolower(gsub("[^[:alnum:] ]", " ", x))
  x <- gsub(
    "\\b(neighborhood|metropolitan|district|regional|pocket|public|park|parks|preserve|greenbelt)\\b",
    " ", x
  )
  trimws(gsub(" +", " ", x))
}

austin_boundary <- st_read(boundary_path, quiet = TRUE) |>
  filter(NAME == "Austin") |>
  st_make_valid() |>
  st_transform(26914)

city <- st_read(city_path, quiet = TRUE) |>
  st_transform(26914) |>
  st_make_valid() |>
  mutate(
    austin_asset_id = coalesce(
      na_if(trimws(as.character(asset_mgmt_id)), ""),
      paste0("object_", objectid)
    )
  )
city <- city[lengths(st_intersects(city, austin_boundary)) > 0, ] |>
  group_by(austin_asset_id) |>
  summarise(
    austin_park_name = first(location_name),
    austin_park_type = first(park_type),
    austin_development_status = first(development_status),
    austin_asset_status = first(asset_status),
    austin_restrictions = first(restrictions),
    austin_owner_name = first(owner_name),
    austin_managing_name = first(managing_name),
    .groups = "drop"
  )

ps_match <- final_parks |>
  st_transform(26914)

nearby <- st_is_within_distance(city, ps_match, dist = 100)
pairs <- tibble(
  city_i = rep(seq_len(nrow(city)), lengths(nearby)),
  ps_i = unlist(nearby)
)

if (nrow(pairs)) {
  pairs <- pairs |>
    mutate(
      austin_asset_id = city$austin_asset_id[city_i],
      park_id = ps_match$park_id[ps_i],
      distance_m = as.numeric(st_distance(
        city[city_i, ], ps_match[ps_i, ], by_element = TRUE
      )),
      name_similarity = {
        a <- name_key(city$austin_park_name[city_i])
        b <- name_key(ps_match$park_name[ps_i])
        denominator <- pmax(nchar(a), nchar(b))
        ifelse(denominator > 0, 1 - diag(adist(a, b)) / denominator, 0)
      },
      match_score = if_else(distance_m < 0.001, 1, 0) +
        name_similarity - distance_m / 1000
    )

  city_best <- pairs |>
    group_by(austin_asset_id) |>
    slice_max(match_score, n = 1, with_ties = FALSE) |>
    ungroup()
  parkserve_best <- pairs |>
    group_by(park_id) |>
    slice_max(match_score, n = 1, with_ties = FALSE) |>
    ungroup()

  confirmed <- city_best |>
    inner_join(
      select(parkserve_best, austin_asset_id, park_id),
      by = c("austin_asset_id", "park_id")
    ) |>
    filter(distance_m <= 100, name_similarity >= 0.60) |>
    select(austin_asset_id, park_id, distance_m, name_similarity) |>
    left_join(st_drop_geometry(city), by = "austin_asset_id") |>
    mutate(austin_match_method = "reciprocal best; name similarity >= 0.60; within 100 m")

  final_parks <- final_parks |>
    left_join(confirmed, by = "park_id")
} else {
  final_parks <- final_parks |>
    mutate(
      austin_asset_id = NA_character_,
      distance_m = NA_real_,
      name_similarity = NA_real_,
      austin_park_name = NA_character_,
      austin_park_type = NA_character_,
      austin_development_status = NA_character_,
      austin_asset_status = NA_character_,
      austin_restrictions = NA_character_,
      austin_owner_name = NA_character_,
      austin_managing_name = NA_character_,
      austin_match_method = NA_character_
    )
}

final_parks <- final_parks |>
  rename(
    austin_match_distance_m = distance_m,
    austin_name_similarity = name_similarity
  )

stopifnot(
  nrow(final_parks) > 0,
  !anyDuplicated(final_parks$park_id),
  all(final_parks$park_access == "Open Access"),
  all(!is.na(final_parks$specialized_access)),
  all(st_is_valid(final_parks))
)

if (file.exists(output_gpkg)) file.remove(output_gpkg)
st_write(final_parks, output_gpkg, layer = "parks", quiet = TRUE)

message("Final parks inventory: ", nrow(final_parks), " ParkServe Open Access parks")
message(
  "City of Austin attributes transferred for ",
  sum(!is.na(final_parks$austin_asset_id)),
  " conservative reciprocal matches"
)
print(
  final_parks |>
    st_drop_geometry() |>
    count(county, specialized_access, name = "parks") |>
    arrange(county, specialized_access)
)
