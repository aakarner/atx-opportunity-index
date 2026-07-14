# Step 15: pull and QA/QC physical flood-hazard polygons for Austin
#
# This standalone script downloads the City of Austin's Greater Austin FEMA
# Floodplain layer from its official ArcGIS service. It retains probability-
# based physical hazard zones rather than a social-vulnerability index, clips
# the polygons to the current City boundary, and writes source and QA/QC files.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "sf", "tigris", "httr2", "jsonlite", "digest"
))

options(tigris_use_cache = TRUE)
options(timeout = max(300, getOption("timeout")))

# ---- Source and processing settings -----------------------------------------

dataset_title <- "Greater Austin FEMA Floodplain"
dataset_id <- "93kh-rg74"
dataset_page_url <- paste0(
  "https://data.austintexas.gov/dataset/Greater-Austin-FEMA-Floodplain/",
  dataset_id
)
arcgis_layer_endpoint <- paste0(
  "https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/",
  "INLANDWATERS_greater_austin_fema_floodplain/FeatureServer/0"
)
city_boundary_year <- 2024
analysis_equal_area_crs <- 5070
page_size <- 1000L

raw_dir <- "data/raw/austin_flood_hazard"
processed_dir <- "data/processed/flood_hazard"
qaqc_dir <- "data/qaqc/flood_hazard"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(qaqc_dir, showWarnings = FALSE, recursive = TRUE)

metadata_path <- file.path(raw_dir, "fema_floodplain_arcgis_metadata.json")
object_ids_path <- file.path(raw_dir, "fema_floodplain_object_ids.json")
processed_gpkg_path <- file.path(
  processed_dir,
  "austin_fema_floodplain.gpkg"
)

refresh_download <- str_to_lower(Sys.getenv(
  "REFRESH_AUSTIN_FLOOD_HAZARD",
  unset = "false"
)) %in% c("1", "true", "yes")
retrieved_at_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

# ---- Download helpers --------------------------------------------------------

perform_request <- function(url, query = list(), timeout_seconds = 300) {
  request_object <- request(url)
  if (length(query) > 0) {
    request_object <- do.call(req_url_query, c(list(request_object), query))
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
  if (file.exists(path)) invisible(file.remove(path))
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

# ---- Download source metadata and stable GeoJSON pages ----------------------

cat("Downloading floodplain source metadata and object identifiers...\n")
metadata <- download_json_file(
  arcgis_layer_endpoint,
  metadata_path,
  query = list(f = "pjson")
)
object_id_response <- download_json_file(
  paste0(arcgis_layer_endpoint, "/query"),
  object_ids_path,
  query = list(where = "1=1", returnIdsOnly = "true", f = "json")
)

if (!is.null(metadata$error)) stop("ArcGIS layer metadata returned an error.")
if (!is.null(object_id_response$error)) {
  stop("ArcGIS object-ID query returned an error.")
}

object_ids <- sort(unique(as.integer(object_id_response$objectIds)))
object_ids <- object_ids[is.finite(object_ids)]
if (length(object_ids) < 1) {
  stop("The official floodplain service returned no object identifiers.")
}

id_pages <- split(object_ids, ceiling(seq_along(object_ids) / page_size))
page_manifest <- vector("list", length(id_pages))

for (page_index in seq_along(id_pages)) {
  page_ids <- id_pages[[page_index]]
  page_path <- file.path(
    raw_dir,
    sprintf("fema_floodplain_page_%03d.geojson", page_index)
  )
  reuse_page <- file.exists(page_path) && !refresh_download

  if (reuse_page) {
    existing_page <- tryCatch(
      st_read(page_path, quiet = TRUE, stringsAsFactors = FALSE),
      error = function(error) NULL
    )
    reuse_page <- !is.null(existing_page) &&
      nrow(existing_page) == length(page_ids) &&
      all(c("OBJECTID", "FLOOD_ZONE") %in% names(existing_page))
    rm(existing_page)
  }

  if (!reuse_page) {
    cat(
      "Downloading floodplain page ", page_index, " of ",
      length(id_pages), "...\n",
      sep = ""
    )
    response <- perform_request(
      paste0(arcgis_layer_endpoint, "/query"),
      query = list(
        where = "1=1",
        outFields = paste(
          "OBJECTID", "UNIQUE_GIS_ID", "FLOOD_ZONE", "FLOODWAY",
          "SOURCE_CITATION", "FIRM_PANEL", "EFFECTIVE_DATE", "COUNTY",
          "MODIFIED_DATE",
          sep = ","
        ),
        orderByFields = "OBJECTID",
        resultOffset = (page_index - 1L) * page_size,
        resultRecordCount = length(page_ids),
        returnGeometry = "true",
        outSR = "4326",
        f = "geojson"
      )
    )
    write_response_body(response, page_path)
  } else {
    cat("Reusing cached floodplain page ", page_index, "...\n", sep = "")
  }

  page_check <- st_read(
    page_path,
    quiet = TRUE,
    stringsAsFactors = FALSE
  )
  if (nrow(page_check) != length(page_ids)) {
    stop(
      "Unexpected row count in ", page_path, ": expected ",
      length(page_ids), ", found ", nrow(page_check), "."
    )
  }
  page_manifest[[page_index]] <- tibble(
    page = page_index,
    expected_rows = length(page_ids),
    downloaded_rows = nrow(page_check),
    minimum_objectid = min(as.integer(page_check$OBJECTID), na.rm = TRUE),
    maximum_objectid = max(as.integer(page_check$OBJECTID), na.rm = TRUE),
    raw_file = page_path,
    sha256 = digest::digest(file = page_path, algo = "sha256"),
    reused_cached_page = reuse_page
  )
  rm(page_check)
}

page_manifest <- bind_rows(page_manifest)
write_csv(
  page_manifest,
  file.path(qaqc_dir, "fema_floodplain_pagination_manifest.csv")
)
if (sum(page_manifest$downloaded_rows) != length(object_ids)) {
  stop("Downloaded floodplain row counts do not match the source object IDs.")
}

# ---- Combine, validate, classify, and clip ----------------------------------

cat("Combining and validating floodplain polygons...\n")
floodplain_pages <- map(
  page_manifest$raw_file,
  ~st_read(.x, quiet = TRUE, stringsAsFactors = FALSE)
)
floodplain_all <- do.call(rbind, floodplain_pages) %>%
  rename_with(str_to_lower) %>%
  mutate(
    flood_zone = str_squish(str_to_upper(flood_zone)),
    floodway = str_squish(str_to_upper(coalesce(floodway, ""))),
    one_percent_annual_chance = flood_zone %in% c("A", "AE", "AO"),
    point_two_percent_annual_chance =
      flood_zone == ".2 PCT ANNUAL CHANCE FLOOD HAZARD",
    regulatory_floodway = str_detect(floodway, "FLOODWAY")
  ) %>%
  st_transform(analysis_equal_area_crs) %>%
  st_make_valid()

if (nrow(floodplain_all) != length(object_ids)) {
  stop("Combined floodplain row count does not match the source object IDs.")
}
if (anyDuplicated(floodplain_all$objectid) > 0) {
  stop("Floodplain OBJECTID values are not unique.")
}
if (any(st_is_empty(floodplain_all))) {
  stop("The downloaded floodplain layer contains empty geometries.")
}

recognized_zone <- floodplain_all$one_percent_annual_chance |
  floodplain_all$point_two_percent_annual_chance |
  floodplain_all$flood_zone %in% c(
    "X PROTECTED BY LEVEE", "AREA NOT INCLUDED"
  )
if (any(!recognized_zone)) {
  stop(
    "Unrecognized FEMA flood-zone values: ",
    str_c(unique(floodplain_all$flood_zone[!recognized_zone]), collapse = ", ")
  )
}

cat("Pulling and applying the City of Austin boundary...\n")
austin_boundary <- tigris::places(
  state = "TX",
  year = city_boundary_year,
  class = "sf"
) %>%
  filter(NAME == "Austin") %>%
  st_transform(analysis_equal_area_crs) %>%
  st_make_valid()
if (nrow(austin_boundary) != 1) {
  stop("Expected one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

floodplain_austin <- suppressWarnings(
  floodplain_all %>%
    st_filter(austin_boundary, .predicate = st_intersects) %>%
    st_intersection(st_geometry(austin_boundary))
) %>%
  st_collection_extract("POLYGON", warn = FALSE) %>%
  st_make_valid()
floodplain_austin <- floodplain_austin[!st_is_empty(floodplain_austin), ]
if (nrow(floodplain_austin) < 1) {
  stop("No floodplain polygons remained after clipping to Austin.")
}

# ---- Write processed data and QA/QC -----------------------------------------

cat("Writing processed flood-hazard and QA/QC outputs...\n")
if (file.exists(processed_gpkg_path)) file.remove(processed_gpkg_path)
st_write(
  floodplain_austin,
  processed_gpkg_path,
  layer = "austin_fema_floodplain",
  quiet = TRUE
)

zone_counts <- floodplain_all %>%
  st_drop_geometry() %>%
  count(flood_zone, sort = TRUE, name = "source_polygon_count")
write_csv(zone_counts, file.path(qaqc_dir, "fema_flood_zone_counts.csv"))

county_counts <- floodplain_all %>%
  st_drop_geometry() %>%
  count(county, sort = TRUE, name = "source_polygon_count")
write_csv(county_counts, file.path(qaqc_dir, "fema_floodplain_county_counts.csv"))

qaqc_summary <- tribble(
  ~metric, ~value,
  "dataset_title", dataset_title,
  "dataset_id", dataset_id,
  "dataset_page_url", dataset_page_url,
  "arcgis_layer_endpoint", arcgis_layer_endpoint,
  "retrieved_at_utc", retrieved_at_utc,
  "source_object_count", as.character(length(object_ids)),
  "downloaded_polygon_count", as.character(nrow(floodplain_all)),
  "austin_clipped_polygon_count", as.character(nrow(floodplain_austin)),
  "one_percent_source_polygon_count",
  as.character(sum(floodplain_all$one_percent_annual_chance)),
  "point_two_percent_source_polygon_count",
  as.character(sum(floodplain_all$point_two_percent_annual_chance)),
  "regulatory_floodway_source_polygon_count",
  as.character(sum(floodplain_all$regulatory_floodway)),
  "city_boundary_year", as.character(city_boundary_year),
  "analysis_equal_area_crs", as.character(analysis_equal_area_crs),
  "processed_file", processed_gpkg_path
)
write_csv(
  qaqc_summary,
  file.path(qaqc_dir, "austin_fema_floodplain_qaqc_summary.csv")
)

cat(
  "Flood-hazard pull complete.\n",
  "  Source polygons: ", nrow(floodplain_all), "\n",
  "  Austin-clipped polygons: ", nrow(floodplain_austin), "\n",
  "  Processed file: ", processed_gpkg_path, "\n",
  sep = ""
)
