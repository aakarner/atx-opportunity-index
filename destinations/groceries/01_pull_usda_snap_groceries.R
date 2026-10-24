# Download USDA SNAP authorized retailers for the five-county metro
#
# Source: USDA FNS SNAP Retailer Locator, ArcGIS item
#         https://www.arcgis.com/home/item.html?id=8b260f9a10b0459aa441ad8588c2251c
#
# Currently authorized SNAP retailers with store type and coordinates. SNAP
# participation is not a complete census of food retail; see
# destinations/docs/GOVERNMENT_SOURCE_CATALOG.md.
#
# Pages through the feature service 1,000 records at a time and refuses a
# snapshot assembled while the service was being edited.
#
# Writes data/destinations/groceries/raw/usda_snap/:
#   item.json, layer.json, metro_records.json, manifest.json
#
# Run from the repository root:
#   Rscript destinations/groceries/01_pull_usda_snap_groceries.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "httr2", "jsonlite", "digest"))
source("destinations/R/destination_paths.R")

item_url <- "https://www.arcgis.com/sharing/rest/content/items/8b260f9a10b0459aa441ad8588c2251c"
raw_dir <- destination_dir("groceries", "raw", "usda_snap")

arcgis_get <- function(url, params = list()) {
  result <- request(url) |>
    req_url_query(!!!params) |>
    req_retry(max_tries = 4) |>
    req_timeout(seconds = 90) |>
    req_perform() |>
    resp_body_json(simplifyVector = FALSE)
  if (!is.null(result$error)) stop("ArcGIS error: ", jsonlite::toJSON(result$error, auto_unbox = TRUE))
  result
}

county_list <- paste0("'", destination_metro_counties, "'", collapse = ",")
where <- paste0("State = 'TX' AND County IN (", county_list, ")")

item <- arcgis_get(item_url, list(f = "json"))
service <- paste0(item$url, "/0")
layer <- arcgis_get(service, list(f = "json"))
count <- arcgis_get(paste0(service, "/query"),
                    list(f = "json", where = where, returnCountOnly = "true"))$count

features <- list()
for (offset in seq(0, count - 1, by = 1000)) {
  page <- arcgis_get(paste0(service, "/query"), list(
    f = "json", where = where, outFields = "*", returnGeometry = "true", outSR = 4326,
    orderByFields = "ObjectId ASC", resultOffset = offset, resultRecordCount = 1000))
  features <- c(features, page$features)
}
object_ids <- vapply(features, function(z) as.character(z$attributes$ObjectId), character(1))
stopifnot(length(features) == count, !anyDuplicated(object_ids))

after <- arcgis_get(service, list(f = "json"))
if (!identical(after$editingInfo, layer$editingInfo)) stop("Source changed during download; rerun.")

write_raw_json <- function(x, name) {
  jsonlite::write_json(x, file.path(raw_dir, name), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, null = "null", na = "null")
}
write_raw_json(item, "item.json")
write_raw_json(layer, "layer.json")
write_raw_json(features, "metro_records.json")

manifest <- list(
  retrieved_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  item_url = item_url, service_url = service, where = where, records = count,
  source_data_updated_utc = format(as.POSIXct(layer$editingInfo$dataLastEditDate / 1000,
                                              origin = "1970-01-01", tz = "UTC"), usetz = TRUE),
  sha256 = unname(file_sha256(file.path(raw_dir, "metro_records.json")))
)
write_raw_json(manifest, "manifest.json")

store_types <- vapply(features, function(z) as.character(z$attributes$Store_Type), character(1))
print(sort(table(store_types), decreasing = TRUE))
message("Saved ", count, " SNAP retailer records to ", raw_dir)
