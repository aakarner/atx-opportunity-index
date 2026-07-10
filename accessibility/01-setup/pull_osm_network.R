# Download a dated Texas OSM snapshot and clip it to Central Texas.

source("accessibility/config.R")

source("setup_packages.R")
setup_project_packages(c("digest", "readr"))

if (Sys.which("osmium") == "") {
  stop("The osmium command-line tool is required to clip the OSM snapshot.")
}

if (!file.exists(osm_path)) {
  statewide_path <- tempfile("texas_", fileext = ".osm.pbf")
  on.exit(unlink(statewide_path), add = TRUE)

  message("Downloading dated Texas OSM snapshot...")
  download.file(osm_url, statewide_path, mode = "wb", quiet = FALSE)

  message("Clipping OSM snapshot to Central Texas...")
  status <- system2(
    "osmium",
    c(
      "extract",
      paste0("--bbox=", osm_bbox),
      "--strategy=complete_ways",
      "--overwrite",
      "--output", osm_path,
      statewide_path
    )
  )

  if (status != 0 || !file.exists(osm_path)) {
    stop("osmium failed to create the Central Texas network extract.")
  }
} else {
  message("Using existing OSM snapshot: ", osm_path)
}

actual_sha256 <- digest(osm_path, algo = "sha256", file = TRUE)
if (!identical(actual_sha256, osm_sha256)) {
  stop("OSM checksum does not match the pinned Central Texas extract.")
}

manifest <- data.frame(
  input = "OpenStreetMap",
  snapshot_date = osm_snapshot_date,
  source_url = osm_url,
  source_bbox = osm_bbox,
  local_file = osm_path,
  sha256 = actual_sha256
)

write_csv(manifest, file.path(r5_data_dir, "osm_manifest.csv"))
print(manifest)
