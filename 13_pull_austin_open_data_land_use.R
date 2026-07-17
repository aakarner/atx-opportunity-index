# Step 13: pull and QA/QC the City of Austin detailed land-use inventory
#
# The source is a parcel-based inventory whose codes describe the primary
# improvements on each parcel. This script clips the inventory to the current
# analytical tract geography, preserves continuous area shares, and creates a
# transparent broad land-use category for mixed-data clustering experiments.
# Water, streets/roads, and unknown codes remain in QA totals but are excluded
# from the compositional denominator.
# These step-20 experiments are not part of the submitted step-22 results.
#
# Authentication is optional. If available, set AUSTIN_OPEN_DATA_APP_TOKEN in
# the process environment. Set REFRESH_AUSTIN_LAND_USE=true to replace cached
# raw pages; otherwise successfully downloaded pages are reused.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "sf", "tigris", "httr2", "jsonlite", "digest", "scales"
))

options(tigris_use_cache = TRUE)
options(timeout = max(600, getOption("timeout")))

# ---- Source and processing settings -----------------------------------------

dataset_id <- "7vsm-dvxg"
dataset_title <- "Land Use Inventory Detailed"
dataset_page_url <- paste0(
  "https://data.austintexas.gov/Locations-and-Maps/",
  "Land-Use-Inventory-Detailed/", dataset_id
)
metadata_endpoint <- paste0(
  "https://data.austintexas.gov/api/views/", dataset_id
)
soda_geojson_endpoint <- paste0(
  "https://data.austintexas.gov/resource/", dataset_id, ".geojson"
)
soda_json_endpoint <- paste0(
  "https://data.austintexas.gov/resource/", dataset_id, ".json"
)
arcgis_layer_endpoint <- paste0(
  "https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/",
  "PLANNINGCADASTRE_land_use_inventory/FeatureServer/0"
)

city_boundary_year <- 2024
tract_year <- 2024
analysis_county_fips <- c("453", "491", "209")
equal_area_crs <- 2277
page_size <- 25000L

raw_dir <- "data/raw/austin_open_data_land_use"
processed_dir <- "data/processed/land_use"
qaqc_dir <- "data/qaqc/land_use"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

metadata_path <- file.path(raw_dir, "land_use_inventory_metadata.json")
layer_definition_path <- file.path(
  raw_dir,
  "land_use_inventory_arcgis_layer_definition.json"
)
processed_csv_path <- file.path(
  processed_dir,
  "austin_land_use_by_tract.csv"
)
processed_gpkg_path <- file.path(
  processed_dir,
  "austin_land_use_by_tract.gpkg"
)

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")
refresh_download <- str_to_lower(Sys.getenv(
  "REFRESH_AUSTIN_LAND_USE",
  unset = "false"
)) %in% c("1", "true", "yes")
retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

# ---- Download helpers --------------------------------------------------------

perform_request <- function(url, query = list(), timeout_seconds = 300) {
  request_object <- request(url)
  if (length(query) > 0) {
    request_object <- do.call(req_url_query, c(list(request_object), query))
  }
  if (nzchar(app_token)) {
    request_object <- request_object %>%
      req_headers(`X-App-Token` = app_token)
  }

  request_object %>%
    req_user_agent("atx-opportunity-index/1.0") %>%
    req_retry(max_tries = 5) %>%
    req_timeout(seconds = timeout_seconds) %>%
    req_perform()
}

write_response_body <- function(response, path) {
  temporary_path <- paste0(path, ".partial")
  writeBin(resp_body_raw(response), temporary_path)
  if (file.exists(path)) {
    invisible(file.remove(path))
  }
  if (!file.rename(temporary_path, path)) {
    stop("Could not finalize downloaded file: ", path)
  }
  invisible(path)
}

download_json_file <- function(url, path, query = list()) {
  response <- perform_request(url, query = query)
  write_response_body(response, path)
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

cat("Downloading source metadata and coded-value definitions...\n")
metadata <- download_json_file(metadata_endpoint, metadata_path)
layer_definition <- download_json_file(
  arcgis_layer_endpoint,
  layer_definition_path,
  query = list(f = "pjson")
)

count_response <- perform_request(
  soda_json_endpoint,
  query = list(`$select` = "count(*)")
)
expected_source_rows <- as.integer(
  resp_body_json(count_response, simplifyVector = TRUE)$count[[1]]
)

if (!is.finite(expected_source_rows) || expected_source_rows < 1) {
  stop("Could not determine a valid land-use source row count.")
}

# The official ArcGIS renderer is the authoritative lookup between numeric
# LAND_USE codes and human-readable labels.
land_use_lookup <- layer_definition$drawingInfo$renderer$uniqueValueInfos %>%
  as_tibble() %>%
  transmute(
    land_use_code = as.integer(value),
    detailed_land_use = as.character(label)
  ) %>%
  distinct(land_use_code, .keep_all = TRUE) %>%
  arrange(land_use_code)

if (
  nrow(land_use_lookup) < 1 ||
    anyDuplicated(land_use_lookup$land_use_code) > 0 ||
    any(is.na(land_use_lookup$land_use_code))
) {
  stop("The ArcGIS land-use code lookup is missing or malformed.")
}

land_use_lookup <- land_use_lookup %>%
  mutate(
    broad_land_use = case_when(
      land_use_code %in% c(100, 113, 150, 160, 210, 220, 230, 240) ~
        "residential",
      land_use_code == 330 ~ "mixed_use",
      land_use_code %in% c(300, 400) ~ "commercial_office",
      land_use_code %in% c(510, 520, 530, 560, 570) ~
        "industrial_logistics",
      land_use_code %in% c(610, 620, 630, 640, 650, 670, 680) ~
        "institutional_civic",
      land_use_code %in% c(710, 720, 730, 740, 750) ~ "open_space",
      land_use_code %in% c(810, 820, 830, 840, 850, 870) ~
        "transportation_utilities",
      land_use_code %in% c(900, 910) ~ "undeveloped_agricultural",
      land_use_code == 860 ~ "streets_roads_excluded",
      land_use_code == 940 ~ "water_excluded",
      land_use_code == 999 ~ "unknown_excluded",
      TRUE ~ NA_character_
    ),
    included_in_composition = !broad_land_use %in% c(
      "streets_roads_excluded", "water_excluded", "unknown_excluded"
    )
  )

if (any(is.na(land_use_lookup$broad_land_use))) {
  stop(
    "Unmapped official land-use codes: ",
    str_c(
      land_use_lookup$land_use_code[is.na(land_use_lookup$broad_land_use)],
      collapse = ", "
    )
  )
}

write_csv(
  land_use_lookup,
  file.path(qaqc_dir, "land_use_code_lookup.csv")
)

# ---- Download stable, ordered GeoJSON pages ---------------------------------

page_offsets <- seq.int(0L, expected_source_rows - 1L, by = page_size)
page_manifest <- vector("list", length(page_offsets))

for (page_index in seq_along(page_offsets)) {
  page_offset <- page_offsets[[page_index]]
  page_path <- file.path(
    raw_dir,
    sprintf("land_use_inventory_page_%06d.geojson", page_offset)
  )
  expected_page_rows <- min(page_size, expected_source_rows - page_offset)
  reuse_page <- file.exists(page_path) && !refresh_download

  if (reuse_page) {
    existing_page <- tryCatch(
      st_read(page_path, quiet = TRUE, stringsAsFactors = FALSE),
      error = function(error) NULL
    )
    reuse_page <- !is.null(existing_page) &&
      nrow(existing_page) == expected_page_rows &&
      all(c("objectid", "land_use") %in% names(existing_page))
    rm(existing_page)
  }

  if (!reuse_page) {
    cat(
      "Downloading land-use page ", page_index, " of ",
      length(page_offsets), " (offset ", page_offset, ")...\n",
      sep = ""
    )
    response <- perform_request(
      soda_geojson_endpoint,
      query = list(
        `$select` = paste(
          "objectid", "land_use", "general_land_use", "parcel_id_10",
          "the_geom",
          sep = ","
        ),
        `$order` = "objectid",
        `$limit` = page_size,
        `$offset` = page_offset
      ),
      timeout_seconds = 600
    )
    write_response_body(response, page_path)
  } else {
    cat("Reusing cached land-use page at offset ", page_offset, "...\n", sep = "")
  }

  page_check <- st_read(
    page_path,
    quiet = TRUE,
    stringsAsFactors = FALSE
  )
  if (nrow(page_check) != expected_page_rows) {
    stop(
      "Unexpected row count in ", page_path, ": expected ",
      expected_page_rows, ", found ", nrow(page_check)
    )
  }

  page_manifest[[page_index]] <- tibble(
    page = page_index,
    offset = page_offset,
    expected_rows = expected_page_rows,
    downloaded_rows = nrow(page_check),
    minimum_objectid = min(as.integer(page_check$objectid), na.rm = TRUE),
    maximum_objectid = max(as.integer(page_check$objectid), na.rm = TRUE),
    raw_file = page_path,
    sha256 = digest::digest(file = page_path, algo = "sha256"),
    reused_cached_page = reuse_page
  )
  rm(page_check)
  gc(verbose = FALSE)
}

page_manifest <- bind_rows(page_manifest)
write_csv(
  page_manifest,
  file.path(qaqc_dir, "land_use_pagination_manifest.csv")
)

if (sum(page_manifest$downloaded_rows) != expected_source_rows) {
  stop("Paginated land-use row counts do not reconcile to the source count.")
}

# ---- Build the current analytical tract geography ---------------------------

cat("Preparing 2024 City of Austin tract geography...\n")

austin_boundary <- places(
  state = "TX",
  year = city_boundary_year,
  class = "sf"
) %>%
  filter(NAME == "Austin") %>%
  st_make_valid() %>%
  st_transform(equal_area_crs)

if (nrow(austin_boundary) != 1) {
  stop("Expected exactly one City of Austin boundary.")
}

county_tracts <- tracts(
  state = "TX",
  county = analysis_county_fips,
  year = tract_year,
  class = "sf"
) %>%
  select(GEOID, NAME) %>%
  st_make_valid() %>%
  st_transform(equal_area_crs)

analysis_tracts <- suppressWarnings(
  st_intersection(county_tracts, st_geometry(austin_boundary))
) %>%
  filter(!st_is_empty(geometry)) %>%
  mutate(tract_city_area_sqft = as.numeric(st_area(geometry))) %>%
  arrange(GEOID)

if (anyDuplicated(analysis_tracts$GEOID) > 0) {
  analysis_tracts <- analysis_tracts %>%
    group_by(GEOID, NAME) %>%
    summarise(
      tract_city_area_sqft = sum(tract_city_area_sqft),
      .groups = "drop"
    )
}

if (nrow(analysis_tracts) < 1 || anyDuplicated(analysis_tracts$GEOID) > 0) {
  stop("Could not construct a unique City-intersecting tract geography.")
}

# ---- Intersect parcel inventory with tracts page by page ---------------------

cat("Intersecting parcel land uses with City-intersecting tracts...\n")

page_area_summaries <- vector("list", nrow(page_manifest))
source_code_counts <- vector("list", nrow(page_manifest))
geometry_qaqc <- vector("list", nrow(page_manifest))
city_parcel_counts <- integer(nrow(page_manifest))

for (page_index in seq_len(nrow(page_manifest))) {
  cat(
    "Processing land-use page ", page_index, " of ",
    nrow(page_manifest), "...\n",
    sep = ""
  )

  page_data <- st_read(
    page_manifest$raw_file[[page_index]],
    quiet = TRUE,
    stringsAsFactors = FALSE
  ) %>%
    mutate(
      objectid = as.integer(objectid),
      land_use_code = as.integer(land_use)
    )

  source_code_counts[[page_index]] <- page_data %>%
    st_drop_geometry() %>%
    count(land_use_code, name = "source_parcels")

  unknown_codes <- setdiff(
    unique(page_data$land_use_code),
    land_use_lookup$land_use_code
  )
  if (length(unknown_codes) > 0) {
    stop(
      "Source contains codes absent from the official renderer lookup: ",
      str_c(unknown_codes, collapse = ", ")
    )
  }

  valid_before <- st_is_valid(page_data)
  geometry_qaqc[[page_index]] <- tibble(
    page = page_index,
    source_rows = nrow(page_data),
    invalid_before_repair = sum(!valid_before)
  )

  page_data <- page_data %>%
    st_transform(equal_area_crs) %>%
    st_make_valid() %>%
    left_join(land_use_lookup, by = "land_use_code") %>%
    st_filter(austin_boundary, .predicate = st_intersects)

  city_parcel_counts[[page_index]] <- nrow(page_data)

  if (nrow(page_data) == 0) {
    page_area_summaries[[page_index]] <- tibble(
      GEOID = character(),
      broad_land_use = character(),
      included_in_composition = logical(),
      intersected_area_sqft = numeric(),
      intersected_parcels = integer()
    )
    next
  }

  intersections <- suppressWarnings(
    st_intersection(
      page_data %>%
        select(objectid, land_use_code, broad_land_use, included_in_composition),
      analysis_tracts %>% select(GEOID)
    )
  ) %>%
    filter(!st_is_empty(geometry)) %>%
    mutate(intersected_area_sqft = as.numeric(st_area(geometry)))

  page_area_summaries[[page_index]] <- intersections %>%
    st_drop_geometry() %>%
    group_by(GEOID, broad_land_use, included_in_composition) %>%
    summarise(
      intersected_area_sqft = sum(intersected_area_sqft),
      intersected_parcels = n_distinct(objectid),
      .groups = "drop"
    )

  rm(page_data, intersections)
  gc(verbose = FALSE)
}

geometry_qaqc <- bind_rows(geometry_qaqc)
source_code_counts <- bind_rows(source_code_counts) %>%
  group_by(land_use_code) %>%
  summarise(source_parcels = sum(source_parcels), .groups = "drop") %>%
  left_join(land_use_lookup, by = "land_use_code") %>%
  arrange(land_use_code)
tract_category_area <- bind_rows(page_area_summaries) %>%
  group_by(GEOID, broad_land_use, included_in_composition) %>%
  summarise(
    intersected_area_sqft = sum(intersected_area_sqft),
    intersected_parcels = sum(intersected_parcels),
    .groups = "drop"
  )

write_csv(
  geometry_qaqc,
  file.path(qaqc_dir, "land_use_geometry_qaqc.csv")
)
write_csv(
  source_code_counts,
  file.path(qaqc_dir, "land_use_source_code_counts.csv")
)

# ---- Calculate shares and broad tract categories ----------------------------

included_broad_levels <- c(
  "residential", "mixed_use", "commercial_office",
  "industrial_logistics", "institutional_civic", "open_space",
  "transportation_utilities", "undeveloped_agricultural"
)
all_broad_levels <- c(
  included_broad_levels,
  "streets_roads_excluded", "water_excluded", "unknown_excluded"
)

tract_category_complete <- analysis_tracts %>%
  st_drop_geometry() %>%
  select(GEOID) %>%
  crossing(broad_land_use = all_broad_levels) %>%
  left_join(
    tract_category_area %>%
      select(GEOID, broad_land_use, intersected_area_sqft, intersected_parcels),
    by = c("GEOID", "broad_land_use")
  ) %>%
  mutate(
    intersected_area_sqft = replace_na(intersected_area_sqft, 0),
    intersected_parcels = replace_na(intersected_parcels, 0L)
  )

tract_area_wide <- tract_category_complete %>%
  select(GEOID, broad_land_use, intersected_area_sqft) %>%
  pivot_wider(
    names_from = broad_land_use,
    values_from = intersected_area_sqft,
    names_glue = "area_{broad_land_use}_sqft"
  )

land_use_tracts <- analysis_tracts %>%
  left_join(tract_area_wide, by = "GEOID") %>%
  mutate(
    inventory_area_sqft = rowSums(
      pick(starts_with("area_")),
      na.rm = TRUE
    ),
    composition_area_sqft = rowSums(
      pick(all_of(paste0("area_", included_broad_levels, "_sqft"))),
      na.rm = TRUE
    ),
    inventory_coverage_ratio = inventory_area_sqft / tract_city_area_sqft,
    composition_coverage_ratio = composition_area_sqft / tract_city_area_sqft
  )

for (broad_level in included_broad_levels) {
  area_column <- paste0("area_", broad_level, "_sqft")
  share_column <- paste0("share_", broad_level)
  land_use_tracts[[share_column]] <- if_else(
    land_use_tracts$composition_area_sqft > 0,
    land_use_tracts[[area_column]] / land_use_tracts$composition_area_sqft,
    NA_real_
  )
}

share_columns <- paste0("share_", included_broad_levels)
share_matrix <- as.matrix(st_drop_geometry(land_use_tracts)[, share_columns])
dominant_index <- max.col(replace(share_matrix, is.na(share_matrix), -Inf))
has_composition <- land_use_tracts$composition_area_sqft > 0

land_use_tracts$dominant_broad_land_use <- NA_character_
land_use_tracts$dominant_broad_land_use[has_composition] <-
  included_broad_levels[dominant_index[has_composition]]
land_use_tracts$dominant_land_use_share <- NA_real_
land_use_tracts$dominant_land_use_share[has_composition] <-
  apply(share_matrix[has_composition, , drop = FALSE], 1, max, na.rm = TRUE)

land_use_tracts <- land_use_tracts %>%
  mutate(
    activity_share = share_mixed_use + share_commercial_office,
    open_undeveloped_share = share_open_space + share_undeveloped_agricultural,
    normalized_land_use_diversity = if_else(
      composition_area_sqft > 0,
      (1 - rowSums(pick(all_of(share_columns))^2, na.rm = TRUE)) /
        (1 - 1 / length(share_columns)),
      NA_real_
    ),
    land_use_category_detailed = case_when(
      composition_area_sqft <= 0 ~ "Unknown / insufficient inventory",
      share_residential >= 0.60 ~ "Residential dominant",
      share_residential >= 0.25 & activity_share >= 0.15 ~
        "Mixed residential and activity",
      dominant_broad_land_use == "industrial_logistics" ~
        "Industrial and logistics",
      dominant_broad_land_use %in% c("commercial_office", "mixed_use") ~
        "Commercial and office employment",
      dominant_broad_land_use == "institutional_civic" ~
        "Institutional and civic",
      dominant_broad_land_use %in% c("open_space", "undeveloped_agricultural") ~
        "Open space and undeveloped",
      dominant_broad_land_use == "transportation_utilities" ~
        "Transportation and utilities",
      dominant_broad_land_use == "residential" ~
        "Residential and open-space mix",
      TRUE ~ "Mixed / other"
    ),
    land_use_category_detailed = factor(
      land_use_category_detailed,
      levels = c(
        "Residential dominant",
        "Residential and open-space mix",
        "Mixed residential and activity",
        "Commercial and office employment",
        "Industrial and logistics",
        "Institutional and civic",
        "Open space and undeveloped",
        "Transportation and utilities",
        "Mixed / other",
        "Unknown / insufficient inventory"
      )
    ),
    adequate_composition_coverage = coalesce(
      composition_coverage_ratio >= 0.50,
      FALSE
    ),
    land_use_category = case_when(
      land_use_category_detailed %in% c(
        "Commercial and office employment",
        "Industrial and logistics",
        "Institutional and civic",
        "Transportation and utilities"
      ) ~ "Employment and special-purpose",
      TRUE ~ as.character(land_use_category_detailed)
    ),
    land_use_category = factor(
      land_use_category,
      levels = c(
        "Residential dominant",
        "Residential and open-space mix",
        "Mixed residential and activity",
        "Employment and special-purpose",
        "Open space and undeveloped",
        "Mixed / other",
        "Unknown / insufficient inventory"
      )
    ),
    land_use_category_cluster = if_else(
      adequate_composition_coverage &
        land_use_category != "Unknown / insufficient inventory",
      as.character(land_use_category),
      NA_character_
    ),
    land_use_category_cluster = factor(
      land_use_category_cluster,
      levels = levels(land_use_category)
    ),
    category_rule_version = "tract_area_shares_v1"
  )

share_sum <- rowSums(st_drop_geometry(land_use_tracts)[, share_columns], na.rm = TRUE)
if (any(abs(share_sum[has_composition] - 1) > 1e-8)) {
  stop("Included land-use shares do not sum to one for all classified tracts.")
}

if (file.exists(processed_gpkg_path)) {
  invisible(file.remove(processed_gpkg_path))
}

st_write(
  land_use_tracts,
  processed_gpkg_path,
  layer = "tract_land_use",
  quiet = TRUE
)

land_use_tracts %>%
  st_drop_geometry() %>%
  mutate(
    across(
      c(
        land_use_category_detailed,
        land_use_category,
        land_use_category_cluster
      ),
      as.character
    )
  ) %>%
  write_csv(processed_csv_path, na = "")

category_counts <- land_use_tracts %>%
  st_drop_geometry() %>%
  count(land_use_category, name = "tracts", .drop = FALSE) %>%
  mutate(
    land_use_category = as.character(land_use_category),
    tract_share = tracts / sum(tracts)
  )

detailed_category_counts <- land_use_tracts %>%
  st_drop_geometry() %>%
  count(land_use_category_detailed, name = "tracts", .drop = FALSE) %>%
  mutate(
    land_use_category_detailed = as.character(land_use_category_detailed),
    tract_share = tracts / sum(tracts)
  )

coverage_qaqc <- land_use_tracts %>%
  st_drop_geometry() %>%
  transmute(
    GEOID,
    tract_city_area_sqft,
    inventory_area_sqft,
    composition_area_sqft,
    inventory_coverage_ratio,
    composition_coverage_ratio,
    adequate_composition_coverage,
    dominant_broad_land_use,
    dominant_land_use_share,
    land_use_category_detailed = as.character(land_use_category_detailed),
    land_use_category = as.character(land_use_category),
    land_use_category_cluster = as.character(land_use_category_cluster)
  ) %>%
  arrange(composition_coverage_ratio)

write_csv(
  category_counts,
  file.path(qaqc_dir, "land_use_category_counts.csv")
)
write_csv(
  detailed_category_counts,
  file.path(qaqc_dir, "land_use_detailed_category_counts.csv")
)
write_csv(
  coverage_qaqc,
  file.path(qaqc_dir, "land_use_tract_coverage.csv")
)
write_csv(
  tract_category_complete,
  file.path(qaqc_dir, "land_use_tract_category_areas.csv")
)

qa_value <- function(metric_name, value, note = NA_character_) {
  tibble(metric = metric_name, value = as.character(value), note = note)
}

qaqc_summary <- bind_rows(
  qa_value("dataset_id", dataset_id),
  qa_value("dataset_title", dataset_title),
  qa_value("source_page_url", dataset_page_url),
  qa_value("retrieved_at_utc", retrieved_at_utc),
  qa_value("expected_source_rows", expected_source_rows),
  qa_value("downloaded_source_rows", sum(page_manifest$downloaded_rows)),
  qa_value("raw_page_count", nrow(page_manifest)),
  qa_value("official_detailed_code_count", nrow(land_use_lookup)),
  qa_value("invalid_source_geometries_before_repair", sum(geometry_qaqc$invalid_before_repair)),
  qa_value("city_intersecting_source_parcels", sum(city_parcel_counts)),
  qa_value("city_intersecting_tracts", nrow(land_use_tracts)),
  qa_value("tracts_with_no_composition_area", sum(!has_composition)),
  qa_value(
    "tracts_below_50_percent_composition_coverage",
    sum(!land_use_tracts$adequate_composition_coverage)
  ),
  qa_value(
    "median_composition_coverage_ratio",
    median(land_use_tracts$composition_coverage_ratio, na.rm = TRUE)
  ),
  qa_value(
    "maximum_inventory_coverage_ratio",
    max(land_use_tracts$inventory_coverage_ratio, na.rm = TRUE),
    "Values materially above one may indicate overlapping source polygons."
  ),
  qa_value(
    "composition_exclusions",
    "LAND_USE 860 streets/roads; 940 water; 999 unknown"
  ),
  qa_value("category_rule_version", "tract_area_shares_v1"),
  qa_value(
    "metadata_sha256",
    digest::digest(file = metadata_path, algo = "sha256")
  ),
  qa_value(
    "layer_definition_sha256",
    digest::digest(file = layer_definition_path, algo = "sha256")
  )
)
write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "land_use_qaqc_summary.csv")
)

map_palette <- c(
  "Residential dominant" = "#F4E04D",
  "Residential and open-space mix" = "#D9C84A",
  "Mixed residential and activity" = "#E69F00",
  "Employment and special-purpose" = "#8E44AD",
  "Open space and undeveloped" = "#009E73",
  "Mixed / other" = "#CC79A7",
  "Unknown / insufficient inventory" = "#D9D9D9"
)

land_use_map <- ggplot(land_use_tracts) +
  geom_sf(aes(fill = land_use_category), color = "white", linewidth = 0.08) +
  scale_fill_manual(values = map_palette, drop = FALSE, name = "Land-use category") +
  coord_sf(datum = NA) +
  labs(
    title = "Broad tract land-use categories",
    subtitle = "Area shares from the City of Austin detailed land-use inventory",
    caption = paste0(
      "Water, streets/roads, and unknown inventory codes excluded from shares. ",
      "Source: Austin Open Data ", dataset_id, "."
    )
  ) +
  theme_void(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "bottom"
  ) +
  guides(fill = guide_legend(ncol = 2, byrow = TRUE))

ggsave(
  file.path(qaqc_dir, "land_use_qaqc_map.png"),
  land_use_map,
  width = 9,
  height = 9,
  dpi = 220,
  bg = "white"
)

cat("\nLand-use pull and tract processing complete.\n")
cat("  Source parcels: ", expected_source_rows, "\n", sep = "")
cat("  City-intersecting tracts: ", nrow(land_use_tracts), "\n", sep = "")
cat("  Processed CSV: ", processed_csv_path, "\n", sep = "")
cat("  Processed GeoPackage: ", processed_gpkg_path, "\n", sep = "")
cat("  QA/QC files: ", qaqc_dir, "\n", sep = "")
