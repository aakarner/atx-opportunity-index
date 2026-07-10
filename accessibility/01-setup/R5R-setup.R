# Build the R5 network from the pinned GTFS and OSM snapshots.

source("accessibility/config.R")

source("setup_packages.R")
setup_project_packages(c("r5r", "digest"))

Sys.setenv(R_USER_CACHE_DIR = cache_dir)
options(java.parameters = "-Xmx12G")

missing_inputs <- c(gtfs_path, osm_path)[!file.exists(c(gtfs_path, osm_path))]
if (length(missing_inputs) > 0) {
  stop(
    "Missing routing inputs. Run the GTFS and OSM setup scripts first: ",
    paste(missing_inputs, collapse = ", ")
  )
}

network_manifest_path <- file.path(r5_data_dir, "network_input_manifest.csv")
current_inputs <- data.frame(
  gtfs_sha256 = digest::digest(gtfs_path, algo = "sha256", file = TRUE),
  osm_sha256 = digest::digest(osm_path, algo = "sha256", file = TRUE),
  r5r_version = as.character(packageVersion("r5r"))
)

rebuild_network <- !file.exists(file.path(r5_data_dir, "network.dat")) ||
  !file.exists(network_manifest_path)

if (!rebuild_network) {
  previous_inputs <- read.csv(network_manifest_path, stringsAsFactors = FALSE)
  rebuild_network <- !identical(previous_inputs, current_inputs)
}

r5r_network <- build_network(
  data_path = r5_data_dir,
  verbose = TRUE,
  overwrite = rebuild_network
)

write.csv(current_inputs, network_manifest_path, row.names = FALSE)
