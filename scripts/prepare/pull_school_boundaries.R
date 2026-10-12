# Snapshot public AISD assignment layers for 2025-26 or 2026-27.
# Rscript scripts/prepare/pull_school_boundaries.R [2025-26|2026-27] (default 2026-27).
# Run from repo root. Preserves reassignment labels; does not infer TEA IDs or
# attach scores. The source's old zone codes may refer to closed campuses.
source("scripts/prepare/packages.R")
setup_project_packages(c("sf", "httr2", "jsonlite", "readr", "dplyr", "digest"))

args <- commandArgs(trailingOnly = TRUE)
school_year <- if (length(args)) args[[1]] else "2026-27"
if (length(args) > 1L || !school_year %in% c("2025-26", "2026-27")) {
  stop("Usage: Rscript scripts/prepare/pull_school_boundaries.R [2025-26|2026-27]")
}
year_slug <- gsub("-", "_", school_year)
raw_dir <- file.path("data/raw/aisd_boundaries", year_slug)
processed_dir <- "data/processed/school_indicators"
qaqc_dir <- file.path("data/qaqc/aisd_boundaries", year_slug)
for (p in c(raw_dir, processed_dir, qaqc_dir)) dir.create(p, recursive = TRUE, showWarnings = FALSE)

if (school_year == "2026-27") {
  app_id <- "5f909a8aff0c42148e389ee49e7847ce"
  webmap_id <- "0b14b8e1f73945a6832d9df3b5b52e5b"
  service_name <- "Reassignments"
  layer_ids <- c(9L, 3L, 1L)
  assignment_fields <- c("Campus", "Campus", "HIGH_DESC")
} else {
  app_id <- "e1ba75fe20044ef38cb2b75909332298"
  webmap_id <- "f7e36f4653ca4e43b8cb21147e1884bc"
  service_name <- "SY_25_26_School_Locator_App_WFL1"
  layer_ids <- c(0L, 2L, 1L)
  assignment_fields <- c("ELEM_DESC", "MID_DESC", "HIGH_DESC")
}
service <- paste0("https://services2.arcgis.com/5HXFPHsCivNoDso0/arcgis/rest/services/",
                  service_name, "/FeatureServer")
app_url <- paste0("https://aisd.maps.arcgis.com/apps/instant/lookup/index.html?appid=", app_id)
layers <- data.frame(level = c("elementary", "middle", "high"),
                     layer_id = layer_ids, assignment_field = assignment_fields)
retrieved_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

# Each run retrieves a fresh, dated-by-manifest snapshot of these small public
# layers. Validate downloads before replacing cached files.
fetch_json <- function(url, filename, query = list(f = "pjson")) {
  req <- request(url)
  req <- do.call(req_url_query, c(list(req), query))
  response <- req |> req_retry(max_tries = 3) |> req_timeout(120) |> req_perform()
  bytes <- resp_body_raw(response)
  value <- jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE)
  if (!is.null(value$error)) stop("ArcGIS error: ", jsonlite::toJSON(value$error))
  temporary <- paste0(filename, ".partial")
  writeBin(bytes, temporary)
  if (!file.rename(temporary, filename)) stop("Could not finalize ", filename)
  value
}

item_root <- "https://www.arcgis.com/sharing/rest/content/items/"
app <- fetch_json(paste0(item_root, app_id), file.path(raw_dir, "app_metadata.json"))
app_data <- fetch_json(paste0(item_root, app_id, "/data"), file.path(raw_dir, "app_configuration.json"))
webmap <- fetch_json(paste0(item_root, webmap_id, "/data"), file.path(raw_dir, "webmap.json"))
if (!identical(app_data$values$webmap, webmap_id) ||
    !grepl(substr(school_year, 3, 7), app$title, fixed = TRUE)) stop("Assignment app changed; review source configuration.")
map_urls <- vapply(webmap$operationalLayers, function(x) x$url, character(1))
gpkg <- file.path(processed_dir, paste0("aisd_assignments_", year_slug, ".gpkg"))
temporary_gpkg <- file.path(processed_dir, paste0("aisd_assignments_", year_slug, ".partial.gpkg"))
if (file.exists(temporary_gpkg)) unlink(temporary_gpkg)
manifest <- list(); geometry_checks <- list(); assignment_tables <- list()

for (i in seq_len(nrow(layers))) {
  level <- layers$level[i]
  endpoint <- paste0(service, "/", layers$layer_id[i])
  if (!endpoint %in% map_urls) stop("Layer no longer used by current assignment app: ", endpoint)
  map_layer <- webmap$operationalLayers[[match(endpoint, map_urls)]]
  if (!is.null(map_layer$layerDefinition$definitionExpression)) {
    stop("Map applies a layer filter; review it before exporting.")
  }
  meta <- fetch_json(endpoint, file.path(raw_dir, paste0(level, "_metadata.json")))
  if (meta$geometryType != "esriGeometryPolygon") stop("Expected polygon layer.")
  ids <- fetch_json(paste0(endpoint, "/query"), file.path(raw_dir, paste0(level, "_ids.json")),
                    list(f = "json", where = "1=1", returnIdsOnly = "true"))
  expected_ids <- sort(as.integer(unlist(ids$objectIds)))
  if (!length(expected_ids) || anyDuplicated(expected_ids)) stop("Invalid object IDs.")
  # These are small boundary layers. Fail rather than silently truncate if a
  # future source grows beyond the advertised single-request limit.
  if (length(expected_ids) > meta$maxRecordCount) stop("Layer requires paged downloading.")
  path <- file.path(raw_dir, paste0(level, ".geojson"))
  body <- fetch_json(paste0(endpoint, "/query"), path,
                    list(f = "geojson", where = "1=1", outFields = "*",
                         outSR = "4326", returnGeometry = "true"))
  if (isTRUE(body$exceededTransferLimit) || length(body$features) != length(expected_ids)) {
    stop("Incomplete boundary download: ", level)
  }
  x <- st_read(path, quiet = TRUE)
  object_field <- ids$objectIdFieldName
  if (!identical(sort(as.integer(x[[object_field]])), expected_ids)) stop("Object-ID mismatch.")
  assignment_field <- layers$assignment_field[i]
  if (!assignment_field %in% names(x)) stop("Assignment field missing.")
  # Preserve source IDs under a non-reserved name for GeoPackage.
  names(x)[names(x) == object_field] <- "source_object_id"
  x$assigned_school_label <- x[[assignment_field]]
  if (anyNA(x$assigned_school_label) || any(!nzchar(trimws(x$assigned_school_label)))) {
    stop("Missing assignment labels: ", level)
  }
  x$school_level <- level
  x$assignment_school_year <- school_year
  x$source_app <- app_url
  x$reassignment_flag <- grepl("reassign|reasigna", x$assigned_school_label, ignore.case = TRUE)
  invalid_before <- sum(!st_is_valid(x))
  if (invalid_before) x <- st_make_valid(x)
  if (any(st_is_empty(x)) || any(!st_is_valid(x))) stop("Invalid or empty polygons.")
  x <- st_cast(x, "MULTIPOLYGON", warn = FALSE)
  # Quantify overlaps without modifying source assignments or dissolving zones.
  projected <- st_transform(x, 5070)
  area_sum <- sum(as.numeric(st_area(projected)))
  union_area <- as.numeric(st_area(st_union(projected)))
  geometry_checks[[i]] <- data.frame(
    level = level, polygons = nrow(x), labels = length(unique(x$assigned_school_label)),
    reassignment_polygons = sum(x$reassignment_flag), invalid_before = invalid_before,
    invalid_after = sum(!st_is_valid(x)), union_area_sq_km = union_area / 1e6,
    overlap_excess_sq_m = max(0, area_sum - union_area)
  )
  st_write(x, temporary_gpkg, layer = level, quiet = TRUE)
  assignment_tables[[i]] <- st_drop_geometry(x)
  manifest[[i]] <- data.frame(
    level = level, school_year = school_year, app_title = app_data$values$title,
    app_url = app_url, webmap_id = webmap_id, layer_url = endpoint,
    assignment_field = assignment_field, retrieved_utc = retrieved_utc,
    source_last_edit_utc = format(as.POSIXct(meta$editingInfo$lastEditDate / 1000,
      origin = "1970-01-01", tz = "UTC"), tz = "UTC", usetz = TRUE),
    features = nrow(x), raw_file = path, sha256 = digest::digest(file = path, algo = "sha256")
  )
}

if (!file.rename(temporary_gpkg, gpkg)) stop("Could not finalize GeoPackage.")
write_csv(bind_rows(manifest), file.path(qaqc_dir, "source_manifest.csv"))
write_csv(bind_rows(geometry_checks), file.path(qaqc_dir, "geometry_checks.csv"))
write_csv(bind_rows(assignment_tables), file.path(qaqc_dir, "assignment_attributes.csv"), na = "")
print(bind_rows(geometry_checks))
message("Saved ", normalizePath(gpkg))
