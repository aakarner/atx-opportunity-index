# Download, validate, and prepare the pinned CapMetro GTFS snapshot for R5.

source("accessibility/config.R")

library(digest)
library(dplyr)
library(readr)

if (!file.exists(gtfs_source_path)) {
  message("Downloading pinned CapMetro GTFS snapshot...")
  download.file(gtfs_url, gtfs_source_path, mode = "wb", quiet = FALSE)
} else {
  message("Using existing source GTFS snapshot: ", gtfs_source_path)
}

source_sha256 <- digest(gtfs_source_path, algo = "sha256", file = TRUE)
if (!identical(source_sha256, gtfs_source_sha256)) {
  stop("Source GTFS checksum does not match the pinned snapshot.")
}

required_members <- c(
  "agency.txt", "routes.txt", "stop_times.txt", "stops.txt", "trips.txt"
)
archive_members <- unzip(gtfs_source_path, list = TRUE)$Name
missing_members <- setdiff(required_members, archive_members)

if (length(missing_members) > 0) {
  stop("GTFS archive is missing: ", paste(missing_members, collapse = ", "))
}

if (!any(c("calendar.txt", "calendar_dates.txt") %in% archive_members)) {
  stop("GTFS archive must contain calendar.txt or calendar_dates.txt.")
}

if ("calendar.txt" %in% archive_members) {
  calendar <- read_csv(
    unz(gtfs_source_path, "calendar.txt"),
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )
  service_dates <- seq.Date(
    as.Date(min(calendar$start_date), format = "%Y%m%d"),
    as.Date(max(calendar$end_date), format = "%Y%m%d"),
    by = "day"
  )
} else {
  calendar_dates <- read_csv(
    unz(gtfs_source_path, "calendar_dates.txt"),
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )
  service_dates <- as.Date(
    calendar_dates$date[calendar_dates$exception_type == "1"],
    format = "%Y%m%d"
  )
}

service_start <- min(service_dates, na.rm = TRUE)
service_end <- max(service_dates, na.rm = TRUE)
departure_date <- as.Date(substr(departure_datetime_text, 1, 10))

if (!departure_date %in% service_dates) {
  stop(
    "Configured departure date has no scheduled GTFS service. Available range: ",
    service_start, " to ", service_end, "."
  )
}

# CapMetro supplies min_transfer_time but leaves transfer_type blank. GTFS
# defines type 2 for a required minimum transfer time. Filling it preserves the
# intended semantics and prevents R5's GTFS parser from flagging every row.
repair_dir <- tempfile("capmetro_gtfs_")
dir.create(repair_dir)
on.exit(unlink(repair_dir, recursive = TRUE), add = TRUE)
unzip(gtfs_source_path, exdir = repair_dir)

repaired_transfer_rows <- 0L
transfers_path <- file.path(repair_dir, "transfers.txt")
if (file.exists(transfers_path)) {
  transfers <- read_csv(
    transfers_path,
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )
  repair_rows <- (is.na(transfers$transfer_type) | transfers$transfer_type == "") &
    !is.na(transfers$min_transfer_time) & transfers$min_transfer_time != ""
  repaired_transfer_rows <- sum(repair_rows)
  transfers$transfer_type[repair_rows] <- "2"
  write_csv(transfers, transfers_path, na = "")
}

if (file.exists(gtfs_path)) {
  unlink(gtfs_path)
}
gtfs_output_path <- file.path(normalizePath(getwd()), gtfs_path)
zip::zipr(
  zipfile = gtfs_output_path,
  files = list.files(repair_dir, full.names = TRUE),
  root = repair_dir
)

processed_sha256 <- digest(gtfs_path, algo = "sha256", file = TRUE)

manifest <- data.frame(
  input = "CapMetro GTFS",
  snapshot_date = gtfs_snapshot_date,
  source_url = gtfs_url,
  source_file = gtfs_source_path,
  source_sha256 = source_sha256,
  r5_file = gtfs_path,
  r5_sha256 = processed_sha256,
  repaired_transfer_rows = repaired_transfer_rows,
  service_start = service_start,
  service_end = service_end
)

write_csv(manifest, file.path(r5_data_dir, "gtfs_manifest.csv"))
print(manifest)
