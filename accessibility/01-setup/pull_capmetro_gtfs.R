library(httr)

# ============================================================================
# CapMetro GTFS Download Script
# ============================================================================
# Downloads CapMetro GTFS feed directly from Texas data portal
# 
# Output: gtfs_data/capmetro.zip
# ============================================================================

output_dir <- "accessibility/data/gtfs_data"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("\n=== Downloading CapMetro GTFS from Texas Data Portal ===\n")

# Download GTFS feed
gtfs_download <- tryCatch(
  GET("https://data.texas.gov/download/r4v4-vz24/application/zip",
      timeout(60)),
  error = function(e) {
    cat(sprintf("✗ Download error: %s\n", e$message))
    return(NULL)
  }
)

if (is.null(gtfs_download) || status_code(gtfs_download) != 200) {
  stop(sprintf("✗ Download failed (status: %s). Check URL or network connection.",
               ifelse(is.null(gtfs_download), "NULL", status_code(gtfs_download))))
}

bin <- content(gtfs_download, "raw")

if (length(bin) <= 1000) {
  stop(sprintf("✗ File too small (%d bytes). May be error response.", length(bin)))
}

output_file <- file.path(output_dir, "capmetro.zip")
writeBin(bin, output_file)


# === Success Summary ===
cat(sprintf("✓ Downloaded (%0.1f MB)\n", length(bin) / 1024^2))
cat(sprintf("Output: %s\n", output_file))
cat(sprintf("Feed info: %s\n", feed_date_info))
cat("✓ Ready for r5r accessibility analysis\n\n")



