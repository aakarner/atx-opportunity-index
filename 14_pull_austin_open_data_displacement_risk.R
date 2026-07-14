# Step 14: pull and QA/QC the City of Austin displacement-risk tract layer
#
# The source is the City of Austin's 2022 displacement-risk geography. It is an
# updated City implementation of the three-part framework developed for the UT
# Austin Uprooted study: resident vulnerability, demographic change, and
# housing-market change. It should therefore be described as derived from the
# Uprooted framework—not as the original 2016 Uprooted typology.
#
# Authentication is optional for this small public Socrata dataset. If an app
# token is available, set AUSTIN_OPEN_DATA_APP_TOKEN in the process environment.
# Never place a token or secret directly in this script or commit one to Git.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "sf", "httr2", "jsonlite", "digest", "scales"
))

options(timeout = max(300, getOption("timeout")))

# ---- User-facing settings ----------------------------------------------------

dataset_id <- "t8nv-zcp9"
dataset_title <- "City of Austin Displacement Risk Areas 2022"
dataset_page_url <- paste0(
  "https://data.austintexas.gov/Locations-and-Maps/",
  "City-of-Austin-Displacement-Risk-Areas-2022/", dataset_id
)
metadata_endpoint <- paste0(
  "https://data.austintexas.gov/api/views/", dataset_id
)
geojson_endpoint <- paste0(
  "https://data.austintexas.gov/resource/", dataset_id, ".geojson"
)
uprooted_project_url <- paste0(
  "https://sites.utexas.edu/gentrificationproject/",
  "austin-uprooted-report-maps/"
)
uprooted_methodology_url <- paste0(
  "https://sites.utexas.edu/gentrificationproject/",
  "gentrification-mapping-methodology/"
)

raw_dir <- "data/raw/austin_open_data_displacement_risk"
processed_dir <- "data/processed/displacement_risk"
qaqc_dir <- "data/qaqc/displacement_risk"
analysis_data_path <- "output/austin_opportunity_data.rds"

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

raw_metadata_path <- file.path(
  raw_dir,
  "city_of_austin_displacement_risk_areas_2022_metadata.json"
)
raw_geojson_path <- file.path(
  raw_dir,
  "city_of_austin_displacement_risk_areas_2022.geojson"
)
processed_gpkg_path <- file.path(
  processed_dir,
  "city_of_austin_displacement_risk_areas_2022.gpkg"
)
processed_csv_path <- file.path(
  processed_dir,
  "austin_displacement_risk_by_tract.csv"
)

app_token <- Sys.getenv("AUSTIN_OPEN_DATA_APP_TOKEN", unset = "")
retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

# ---- Helpers -----------------------------------------------------------------

perform_request <- function(url, query = list()) {
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
    req_retry(max_tries = 4) %>%
    req_timeout(seconds = 180) %>%
    req_perform()
}

write_response_body <- function(response, path) {
  writeBin(resp_body_raw(response), path)
  invisible(path)
}

clean_geoid <- function(x) {
  numeric_geoid <- suppressWarnings(as.numeric(as.character(x)))
  if_else(
    is.na(numeric_geoid),
    NA_character_,
    sprintf("%011.0f", numeric_geoid)
  )
}

collapse_values <- function(x) {
  values <- sort(unique(as.character(x)))
  values[is.na(values) | values == ""] <- "<missing>"
  paste(values, collapse = " | ")
}

# ---- Download exact source files --------------------------------------------

cat("Downloading Austin Open Data metadata...\n")
metadata_response <- perform_request(metadata_endpoint)
write_response_body(metadata_response, raw_metadata_path)

metadata <- jsonlite::fromJSON(raw_metadata_path, simplifyVector = TRUE)

cat("Downloading displacement-risk GeoJSON...\n")
geojson_response <- perform_request(
  geojson_endpoint,
  query = list(`$limit` = 5000L)
)
write_response_body(geojson_response, raw_geojson_path)

# ---- Read, normalize, and repair source geography ----------------------------

source_layer <- st_read(
  raw_geojson_path,
  quiet = TRUE,
  stringsAsFactors = FALSE
)

expected_fields <- c(
  "tractce22", "geoid22", "gentrifica", "vulnerabil", "demographi",
  "housing_ma", "displaceme", "descriptio"
)
missing_fields <- setdiff(expected_fields, names(source_layer))
if (length(missing_fields) > 0) {
  stop(
    "Austin displacement-risk source is missing expected fields: ",
    paste(missing_fields, collapse = ", ")
  )
}

source_row_count <- nrow(source_layer)
source_crs <- st_crs(source_layer)$input
valid_before <- st_is_valid(source_layer)
invalid_reasons <- st_is_valid(source_layer, reason = TRUE)

if (is.na(st_crs(source_layer))) {
  stop("The displacement-risk source has no coordinate reference system.")
}

source_layer <- source_layer %>%
  st_transform(4326) %>%
  st_make_valid()

if (any(!st_is_valid(source_layer))) {
  stop("Invalid displacement-risk geometries remain after st_make_valid().")
}

displacement_levels <- c(
  "No published displacement-risk designation",
  "Vulnerable",
  "Active Displacement Risk",
  "Chronic Displacement Risk"
)

displacement_risk <- source_layer %>%
  mutate(
    GEOID = clean_geoid(geoid22),
    source_tract_code = str_pad(as.character(tractce22), 6, pad = "0"),
    displacement_risk_source = str_squish(as.character(displaceme)),
    displacement_risk_category = case_when(
      displacement_risk_source == "N/A" ~
        "No published displacement-risk designation",
      displacement_risk_source %in% displacement_levels ~
        displacement_risk_source,
      TRUE ~ NA_character_
    ),
    displacement_risk_category = factor(
      displacement_risk_category,
      levels = displacement_levels,
      ordered = FALSE
    ),
    vulnerable_population = case_when(
      str_to_upper(vulnerabil) == "YES" ~ TRUE,
      str_to_upper(vulnerabil) == "NO" ~ FALSE,
      TRUE ~ NA
    ),
    demographic_change = case_when(
      str_to_upper(demographi) == "YES" ~ TRUE,
      str_to_upper(demographi) == "NO" ~ FALSE,
      TRUE ~ NA
    ),
    housing_market_category = na_if(str_squish(housing_ma), "N/A"),
    gentrification_typology = na_if(str_squish(gentrifica), "N/A"),
    neighborhood_label = na_if(str_squish(neighborho), ""),
    source_description = na_if(str_squish(descriptio), "")
  ) %>%
  select(
    GEOID,
    source_tract_code,
    displacement_risk_category,
    displacement_risk_source,
    vulnerable_population,
    demographic_change,
    housing_market_category,
    gentrification_typology,
    neighborhood_label,
    source_description,
    geometry
  )

if (anyDuplicated(displacement_risk$GEOID) > 0) {
  stop("The processed displacement-risk layer contains duplicate GEOIDs.")
}

if (any(is.na(displacement_risk$GEOID))) {
  stop("The processed displacement-risk layer contains missing GEOIDs.")
}

if (any(is.na(displacement_risk$displacement_risk_category))) {
  stop(
    "Unrecognized displacement-risk categories: ",
    collapse_values(
      displacement_risk$displacement_risk_source[
        is.na(displacement_risk$displacement_risk_category)
      ]
    )
  )
}

# ---- Check exact-GEOID coverage of the current proof of concept --------------

source_geoids <- displacement_risk$GEOID
analysis_geoids <- character()
analysis_coverage_available <- file.exists(analysis_data_path)

if (analysis_coverage_available) {
  analysis_data <- readRDS(analysis_data_path)
  if (!"GEOID" %in% names(analysis_data)) {
    stop(analysis_data_path, " does not contain a GEOID field.")
  }

  analysis_geoids <- sort(unique(as.character(analysis_data$GEOID)))
  coverage_qaqc <- full_join(
    tibble(GEOID = source_geoids, in_displacement_source = TRUE),
    tibble(GEOID = analysis_geoids, in_current_analysis = TRUE),
    by = "GEOID"
  ) %>%
    mutate(
      across(
        c(in_displacement_source, in_current_analysis),
        ~ replace_na(.x, FALSE)
      ),
      coverage_status = case_when(
        in_displacement_source & in_current_analysis ~ "matched",
        in_displacement_source ~ "source_only",
        TRUE ~ "analysis_only"
      )
    ) %>%
    arrange(coverage_status, GEOID)
} else {
  coverage_qaqc <- tibble(
    GEOID = source_geoids,
    in_displacement_source = TRUE,
    in_current_analysis = NA,
    coverage_status = "analysis_output_not_available"
  )
}

write_csv(
  coverage_qaqc,
  file.path(qaqc_dir, "displacement_risk_analysis_coverage.csv")
)

# ---- Write processed data and QA/QC -----------------------------------------

if (file.exists(processed_gpkg_path)) {
  invisible(file.remove(processed_gpkg_path))
}

st_write(
  displacement_risk,
  processed_gpkg_path,
  layer = "displacement_risk_tracts",
  quiet = TRUE
)

displacement_risk %>%
  st_drop_geometry() %>%
  mutate(displacement_risk_category = as.character(displacement_risk_category)) %>%
  write_csv(processed_csv_path, na = "")

category_counts <- displacement_risk %>%
  st_drop_geometry() %>%
  count(displacement_risk_category, name = "tracts", .drop = FALSE) %>%
  mutate(
    displacement_risk_category = as.character(displacement_risk_category),
    share = tracts / sum(tracts)
  )

component_counts <- bind_rows(
  displacement_risk %>%
    st_drop_geometry() %>%
    count(value = as.character(vulnerable_population), name = "tracts") %>%
    mutate(field = "vulnerable_population"),
  displacement_risk %>%
    st_drop_geometry() %>%
    count(value = as.character(demographic_change), name = "tracts") %>%
    mutate(field = "demographic_change"),
  displacement_risk %>%
    st_drop_geometry() %>%
    count(value = housing_market_category, name = "tracts") %>%
    mutate(field = "housing_market_category"),
  displacement_risk %>%
    st_drop_geometry() %>%
    count(value = gentrification_typology, name = "tracts") %>%
    mutate(field = "gentrification_typology")
) %>%
  select(field, value, tracts) %>%
  arrange(field, desc(tracts), value)

write_csv(
  category_counts,
  file.path(qaqc_dir, "displacement_risk_category_counts.csv")
)
write_csv(
  component_counts,
  file.path(qaqc_dir, "displacement_risk_component_counts.csv")
)

invalid_geometry_qaqc <- tibble(
  source_row = which(!valid_before),
  GEOID = clean_geoid(source_layer$geoid22[!valid_before]),
  source_validity_reason = invalid_reasons[!valid_before],
  valid_after_repair = st_is_valid(displacement_risk[!valid_before, ])
)
write_csv(
  invalid_geometry_qaqc,
  file.path(qaqc_dir, "displacement_risk_geometry_repairs.csv")
)

qa_value <- function(metric_name, value, note = NA_character_) {
  tibble(
    metric = metric_name,
    value = as.character(value),
    note = note
  )
}

qaqc_summary <- bind_rows(
  qa_value("dataset_id", dataset_id),
  qa_value("dataset_title", dataset_title),
  qa_value("retrieved_at_utc", retrieved_at_utc),
  qa_value("source_page_url", dataset_page_url),
  qa_value("source_crs", source_crs),
  qa_value("source_rows", source_row_count),
  qa_value("processed_rows", nrow(displacement_risk)),
  qa_value("unique_geoids", n_distinct(displacement_risk$GEOID)),
  qa_value("invalid_geometries_before_repair", sum(!valid_before)),
  qa_value("invalid_geometries_after_repair", sum(!st_is_valid(displacement_risk))),
  qa_value("missing_geoids", sum(is.na(displacement_risk$GEOID))),
  qa_value("duplicate_geoids", sum(duplicated(displacement_risk$GEOID))),
  qa_value(
    "analysis_coverage_check_available",
    analysis_coverage_available,
    paste0("Checked against ", analysis_data_path)
  ),
  qa_value(
    "analysis_tracts_matched_by_geoid",
    if (analysis_coverage_available) {
      sum(coverage_qaqc$coverage_status == "matched")
    } else {
      NA_integer_
    }
  ),
  qa_value(
    "analysis_tracts_without_source_record",
    if (analysis_coverage_available) {
      sum(coverage_qaqc$coverage_status == "analysis_only")
    } else {
      NA_integer_
    }
  ),
  qa_value(
    "source_tracts_outside_analysis_universe",
    if (analysis_coverage_available) {
      sum(coverage_qaqc$coverage_status == "source_only")
    } else {
      NA_integer_
    }
  ),
  qa_value(
    "raw_metadata_sha256",
    digest::digest(file = raw_metadata_path, algo = "sha256")
  ),
  qa_value(
    "raw_geojson_sha256",
    digest::digest(file = raw_geojson_path, algo = "sha256")
  ),
  qa_value(
    "provenance_note",
    paste0(
      "City-updated implementation derived from the UT Austin Uprooted ",
      "framework; not the original 2016 typology."
    )
  ),
  qa_value("original_uprooted_project_url", uprooted_project_url),
  qa_value("original_uprooted_methodology_url", uprooted_methodology_url),
  qa_value(
    "category_interpretation_note",
    paste0(
      "Source N/A is retained as 'No published displacement-risk ",
      "designation'; it is not treated as missing data."
    )
  )
)

write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "displacement_risk_qaqc_summary.csv")
)

source_metadata <- tibble(
  item = c(
    "dataset_id", "dataset_title", "dataset_page_url", "api_metadata_url",
    "api_geojson_url", "city_description", "city_update_frequency",
    "city_department", "original_uprooted_project_url",
    "original_uprooted_methodology_url"
  ),
  value = c(
    dataset_id,
    dataset_title,
    dataset_page_url,
    metadata_endpoint,
    geojson_endpoint,
    metadata$description,
    metadata$metadata$custom_fields$`Publishing Information`$`Update Frequency`,
    metadata$metadata$custom_fields$Ownership$`Department name`,
    uprooted_project_url,
    uprooted_methodology_url
  )
)
write_csv(
  source_metadata,
  file.path(qaqc_dir, "displacement_risk_source_metadata.csv")
)

# A simple visual check of geometry and category assignments.
map_palette <- c(
  "No published displacement-risk designation" = "#D9D9D9",
  "Vulnerable" = "#FEC44F",
  "Active Displacement Risk" = "#FC8D59",
  "Chronic Displacement Risk" = "#B30000"
)

qaqc_map <- ggplot(displacement_risk) +
  geom_sf(
    aes(fill = displacement_risk_category),
    color = "white",
    linewidth = 0.08
  ) +
  scale_fill_manual(
    values = map_palette,
    drop = FALSE,
    name = "Published category"
  ) +
  coord_sf(datum = NA) +
  labs(
    title = "City of Austin displacement-risk areas, 2022",
    subtitle = "City-updated implementation derived from the Uprooted framework",
    caption = paste0(
      "Source: Austin Open Data dataset ", dataset_id,
      ". Geometry repaired where needed; no categories imputed."
    )
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "bottom",
    legend.box = "vertical"
  ) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE))

ggsave(
  file.path(qaqc_dir, "displacement_risk_qaqc_map.png"),
  qaqc_map,
  width = 8,
  height = 8,
  dpi = 220,
  bg = "white"
)

cat("\nDisplacement-risk pull and processing complete.\n")
cat("  Source records: ", source_row_count, "\n", sep = "")
cat("  Invalid source geometries repaired: ", sum(!valid_before), "\n", sep = "")
if (analysis_coverage_available) {
  cat(
    "  Current analysis tracts matched by GEOID: ",
    sum(coverage_qaqc$coverage_status == "matched"),
    " of ", length(analysis_geoids), "\n",
    sep = ""
  )
}
cat("  Processed CSV: ", processed_csv_path, "\n", sep = "")
cat("  Processed GeoPackage: ", processed_gpkg_path, "\n", sep = "")
cat("  QA/QC files: ", qaqc_dir, "\n", sep = "")
