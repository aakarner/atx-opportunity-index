# Pure normalization and screening helpers plus the per-destination Data Axle
# pipeline. Sourced by destinations/<destination>/0[24]_*_dataaxle_*.R,
# comparison scripts, and tests. Requires destination_paths.R and
# dataaxle_config.R to be sourced first for the pipeline functions.
ax_clean <- function(x) {
  x <- stringr::str_squish(as.character(x))
  x[x %in% c("", "NA", "N/A", "NULL")] <- NA_character_
  x
}
ax_key <- function(x) {
  x <- toupper(ax_clean(x))
  x[is.na(x)] <- ""
  stringr::str_replace_all(x, "[^A-Z0-9]", "")
}
ax_hash <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
ax_first <- function(x) {
  x <- x[!is.na(x) & nzchar(as.character(x))]
  if (length(x)) x[[1]] else NA_character_
}
ax_read <- function(path, collection) {
  raw <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                         name_repair = "check_unique", show_col_types = FALSE)
  if (nrow(readr::problems(raw))) stop("Malformed CSV: ", path)
  if (!all(c("Company Name", "Address", "City", "State", "ZIP Code") %in% names(raw)))
    stop("Missing identity/address headers in ", path)
  get <- function(...) {
    hits <- intersect(c(...), names(raw))
    out <- rep(NA_character_, nrow(raw))
    for (h in hits) out <- dplyr::coalesce(out, ax_clean(raw[[h]]))
    out
  }
  out <- tibble::tibble(
    collection = collection, source_file = path, source_row = seq_len(nrow(raw)) + 1L,
    dataaxle_id = get("IUSA Number", "ABI Number"),
    name = get("Company Name"), parent_name = get("Parent Company Name"),
    address = get("Address"), city = get("City"), state = toupper(get("State")),
    zip = stringr::str_extract(get("ZIP Code"), "^[0-9]{5}"),
    county = get("County"), website = get("Website"),
    phone = get("Phone Number Combined", "Phone Number"),
    naics = get("Primary NAICS"), naics_description = get("Primary NAICS Description"),
    sic = get("Primary SIC Code"), sic_description = get("Primary SIC Description"),
    location_type = get("Location Type"), record_type = get("Record Type"),
    latitude_raw = get("Latitude"), longitude_raw = get("Longitude")
  )
  # Exact normalized name + full address only. No fuzzy merges or removal of suites.
  out$identity_key <- paste(ax_key(out$name), ax_key(out$address), ax_key(out$city),
                             ax_key(out$state), ax_key(out$zip), sep = "|")
  missing_identity <- is.na(out$name) | is.na(out$address) | is.na(out$city) |
    is.na(out$state) | is.na(out$zip)
  out$identity_incomplete <- missing_identity
  with_id <- missing_identity & !is.na(out$dataaxle_id)
  out$identity_key[with_id] <- paste("source_id", ax_key(out$dataaxle_id[with_id]), out$identity_key[with_id], sep="|")
  without_id <- missing_identity & is.na(out$dataaxle_id)
  out$identity_key[without_id] <- paste(out$identity_key[without_id],
    basename(path), out$source_row[without_id], sep = "|")
  out$destination_id <- paste0("ax_", vapply(out$identity_key, ax_hash, character(1)))
  out
}
ax_consolidate <- function(rows) {
  fields <- c("dataaxle_id", "name", "parent_name", "address", "city", "state", "zip",
              "county", "website", "phone", "naics", "naics_description", "sic",
              "sic_description", "location_type", "record_type")
  groups <- split(rows, paste(rows$collection, rows$destination_id))
  dplyr::bind_rows(lapply(groups, function(g) {
    g <- g[order(g$source_file, g$source_row), ]
    out <- tibble::tibble(collection = g$collection[1], destination_id = g$destination_id[1])
    for (field in fields) out[[field]] <- ax_first(g[[field]])
    critical <- c("dataaxle_id", "naics", "sic", "location_type", "record_type")
    conflicts <- critical[vapply(critical, function(f)
      length(unique(stats::na.omit(g[[f]]))) > 1L, logical(1))]
    lat <- suppressWarnings(as.numeric(g$latitude_raw))
    lon <- suppressWarnings(as.numeric(g$longitude_raw))
    pairs <- which(is.finite(lat) & is.finite(lon))
    # Keep a coordinate pair from one row; never coalesce lat/lon separately.
    chosen <- if (length(pairs)) pairs[1] else NA_integer_
    out$latitude <- if (is.na(chosen)) NA_real_ else lat[chosen]
    out$longitude <- if (is.na(chosen)) NA_real_ else lon[chosen]
    pair_keys <- paste(round(lat[pairs], 6), round(lon[pairs], 6))
    out$coordinate_conflict <- length(unique(pair_keys)) > 1L
    out$attribute_conflicts <- paste(conflicts, collapse = ";")
    out$identity_incomplete <- any(g$identity_incomplete)
    out$source_records <- nrow(g)
    out$source_files <- paste(sort(unique(g$source_file)), collapse = ";")
    out$coordinate_source <- if (is.na(chosen)) "missing" else "dataaxle_unverified"
    out$naics6 <- substr(out$naics, 1, 6)
    out
  }))
}
ax_screen <- function(x, rules, bbox, version) {
  x <- dplyr::left_join(x, rules, by = c("collection", "naics" = "code"))
  x$destination_type <- dplyr::coalesce(x$destination_type, x$collection)
  x$decision <- dplyr::coalesce(x$decision, "review")
  x$reason <- dplyr::coalesce(x$reason, "Unmapped category/code; manual classification required")
  address_key <- paste(ax_key(x$address), ax_key(x$city), ax_key(x$state), ax_key(x$zip))
  site_counts <- tapply(x$destination_id, address_key, function(z) length(unique(z)))
  x$shared_address <- as.vector(site_counts[address_key]) > 1
  id_groups <- split(x$destination_id[!is.na(x$dataaxle_id)], x$dataaxle_id[!is.na(x$dataaxle_id)])
  conflicting_ids <- names(Filter(function(z) length(unique(z)) > 1, id_groups))
  x$source_id_conflict <- !is.na(x$dataaxle_id) & x$dataaxle_id %in% conflicting_ids
  x$coordinate_status <- ifelse(!is.finite(x$latitude) | !is.finite(x$longitude),
    "missing_or_invalid", ifelse(x$longitude < bbox['xmin'] | x$longitude > bbox['xmax'] |
    x$latitude < bbox['ymin'] | x$latitude > bbox['ymax'], "outside_region_bbox", "plausible_unverified"))
  for (i in seq_len(nrow(x))) {
    flags <- c(if (x$collection[i] == "community_organizations") "Community service evidence required",
      if (x$shared_address[i]) "Shared address: resolve distinct facility versus duplicate listing",
      if (x$source_id_conflict[i]) "Source ID occurs at multiple identities",
      if (x$identity_incomplete[i]) "Incomplete identity/address",
      if (nzchar(x$attribute_conflicts[i])) paste("Conflicting source attributes:", x$attribute_conflicts[i]),
      if (x$coordinate_conflict[i]) "Conflicting source coordinates",
      if (!is.na(x$location_type[i]) && grepl("headquarter", x$location_type[i], ignore.case=TRUE)) "Headquarters: confirm service at site",
      if (x$coordinate_status[i] != "plausible_unverified") x$coordinate_status[i])
    if (length(flags)) {
      x$decision[i] <- "review"
      x$reason[i] <- paste(c(x$reason[i], flags), collapse = "; ")
    }
  }
  x$rule_version <- version
  # Hash consolidated facts, not filenames/counts; adding an identical batch
  # does not invalidate a review, but adding information or changing rules does.
  fingerprint_fields <- setdiff(names(x), c("source_records", "source_files"))
  x$record_fingerprint <- vapply(seq_len(nrow(x)), function(i)
    ax_hash(paste(unlist(x[i, fingerprint_fields]), collapse = "|")), character(1))
  x
}

# ---- Per-destination pipeline ------------------------------------------------
# Used by destinations/<destination>/02_clean_dataaxle_<destination>.R and
# 04_build_dataaxle_<destination>_gpkg.R. Outputs are written per destination.
# The shared-address and source-ID checks follow dataaxle_duplicate_scope in
# dataaxle_config.R (across all destinations by default). Manual
# inputs stay in one shared folder keyed by collection (= destination name).

ax_review_columns <- c("collection", "destination_id", "record_fingerprint", "review_decision",
  "reviewed_type", "reviewer", "reviewed_on", "evidence", "notes")
ax_correction_columns <- c("destination_id", "record_fingerprint", "latitude", "longitude",
  "coordinate_source", "reviewer", "reviewed_on", "evidence")

ax_read_manual_input <- function(path, columns) {
  if (!file.exists(path)) {
    empty <- tibble::as_tibble(setNames(rep(list(character()), length(columns)), columns))
    readr::write_csv(empty, path)
  }
  z <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                       show_col_types = FALSE)
  if (!all(columns %in% names(z)) || nrow(readr::problems(z))) stop("Invalid manual input schema: ", path)
  z
}

ax_validate_manual_inputs <- function(reviews, corrections) {
  if (any(is.na(reviews$collection) | is.na(reviews$destination_id)) ||
      any(is.na(corrections$destination_id) | is.na(corrections$record_fingerprint)))
    stop("Manual input keys cannot be blank.")
  if (any(!is.na(reviews$reviewed_type) & !grepl("^[a-z][a-z0-9_]*$", reviews$reviewed_type)))
    stop("Reviewed types must use lowercase letters, digits, and underscores.")
  if (anyDuplicated(reviews[c("collection", "destination_id")])) stop("Duplicate manual review keys.")
  if (anyDuplicated(corrections[c("destination_id", "record_fingerprint")]))
    stop("Duplicate coordinate correction keys.")
  if (any(!reviews$review_decision %in% c("include", "exclude", "review")))
    stop("Review decisions must be include, exclude, or review.")
  invisible(TRUE)
}

# Apply documented human decisions. A review or correction only applies while
# its record_fingerprint still matches; changed records fall back to review.
ax_apply_manual <- function(x, reviews, corrections, bbox) {
  x$screen_decision <- x$decision
  x$classification_basis <- "provisional_rule"
  x$manual_review_status <- "not_reviewed"
  x$review_evidence <- NA_character_
  x$coordinate_correction_status <- "none"
  nonblank <- function(z) !is.na(z) & nzchar(trimws(z))
  for (i in seq_len(nrow(x))) {
    r <- reviews[reviews$collection == x$collection[i] & reviews$destination_id == x$destination_id[i], , drop = FALSE]
    if (nrow(r)) {
      valid <- isTRUE(r$record_fingerprint == x$record_fingerprint[i]) &&
        all(nonblank(unlist(r[c("reviewer", "reviewed_on", "evidence")])))
      if (valid && r$review_decision == "include")
        valid <- nonblank(r$reviewed_type) && grepl("^[a-z][a-z0-9_]*$", r$reviewed_type)
      if (valid) {
        x$screen_decision[i] <- r$review_decision
        if (nonblank(r$reviewed_type)) x$destination_type[i] <- r$reviewed_type
        x$classification_basis[i] <- "manual_review"
        x$manual_review_status[i] <- "applied"
        x$review_evidence[i] <- r$evidence
      } else {
        x$screen_decision[i] <- "review"
        x$manual_review_status[i] <- "stale_or_incomplete"
      }
    }
    k <- corrections[corrections$destination_id == x$destination_id[i] &
      corrections$record_fingerprint == x$record_fingerprint[i], , drop = FALSE]
    if (nrow(k)) {
      lat <- suppressWarnings(as.numeric(k$latitude)); lon <- suppressWarnings(as.numeric(k$longitude))
      valid <- is.finite(lat) && is.finite(lon) && lat >= bbox["ymin"] &&
        lat <= bbox["ymax"] && lon >= bbox["xmin"] && lon <= bbox["xmax"] &&
        all(nonblank(unlist(k[c("coordinate_source", "reviewer", "reviewed_on", "evidence")])))
      if (valid) {
        x$latitude[i] <- lat; x$longitude[i] <- lon
        x$coordinate_source[i] <- k$coordinate_source
        x$coordinate_status[i] <- "reviewed_coordinate"
        x$coordinate_conflict[i] <- FALSE
        x$coordinate_correction_status[i] <- "applied"
      } else x$coordinate_correction_status[i] <- "invalid"
    } else if (x$destination_id[i] %in% corrections$destination_id) {
      x$coordinate_correction_status[i] <- "stale"
    }
  }
  x$map_ready <- x$coordinate_status %in% c("plausible_unverified", "reviewed_coordinate")
  x$analysis_ready <- x$map_ready & x$screen_decision == "include" & !x$coordinate_conflict &
    !x$identity_incomplete & !x$coordinate_correction_status %in% c("stale", "invalid")
  x
}

# Stage 02: read every export in raw/dataaxle/, standardize, screen, apply
# manual decisions, and write interim + QA/QC files for one destination.
ax_clean_destination <- function(destination) {
  raw_dir <- destination_dir(destination, "raw", "dataaxle", create = FALSE)
  interim_dir <- destination_dir(destination, "interim", "dataaxle")
  qa_dir <- destination_dir(destination, "qaqc", "dataaxle")
  manual_dir <- destination_manual_dir()
  review_path <- file.path(manual_dir, "dataaxle_reviews.csv")
  correction_path <- file.path(manual_dir, "dataaxle_coordinate_corrections.csv")

  files <- sort(list.files(raw_dir, pattern = "[.]csv$", full.names = TRUE, ignore.case = TRUE))
  if (!length(files)) stop("No Data Axle CSV exports found in ", raw_dir)
  # Screen together with the other destinations when the duplicate checks are
  # cross-destination (see dataaxle_duplicate_scope), then keep this
  # destination's records.
  scope <- if (identical(dataaxle_duplicate_scope, "all_destinations")) dataaxle_destinations else destination
  all_rows <- dplyr::bind_rows(lapply(scope, function(d) {
    d_files <- sort(list.files(destination_dir(d, "raw", "dataaxle", create = FALSE),
                               pattern = "[.]csv$", full.names = TRUE, ignore.case = TRUE))
    dplyr::bind_rows(lapply(d_files, ax_read, collection = d))
  }))
  if (!destination %in% scope) {
    all_rows <- dplyr::bind_rows(all_rows, dplyr::bind_rows(lapply(files, ax_read, collection = destination)))
  }
  all_x <- ax_screen(ax_consolidate(all_rows), dataaxle_rules, dataaxle_bbox, dataaxle_rule_version)
  rows <- all_rows[all_rows$collection == destination, ]
  x <- all_x[all_x$collection == destination, ]
  if (!nrow(rows)) stop("Input exports contain no records.")

  reviews <- ax_read_manual_input(review_path, ax_review_columns)
  corrections <- ax_read_manual_input(correction_path, ax_correction_columns)
  ax_validate_manual_inputs(reviews, corrections)
  reviews <- reviews[reviews$collection == destination, , drop = FALSE]
  x <- ax_apply_manual(x, reviews, corrections, dataaxle_bbox)
  x <- add_h3_cells(x, keep = x$map_ready)
  stopifnot(!anyDuplicated(x[c("collection", "destination_id")]),
            sum(x$source_records) == nrow(rows))

  saveRDS(x, file.path(interim_dir, "dataaxle_standardized.rds"))
  readr::write_csv(x, file.path(interim_dir, "dataaxle_standardized.csv"))
  readr::write_csv(rows, file.path(qa_dir, "source_rows.csv"))
  readr::write_csv(tibble::tibble(source_file = files, sha256 = file_sha256(files),
    source_rows = vapply(files, function(p) sum(rows$source_file == p), integer(1))),
    file.path(qa_dir, "input_manifest.csv"))
  queue <- x[x$screen_decision == "review" | !x$analysis_ready, ]
  for (field in setdiff(ax_review_columns, names(queue))) queue[[field]] <- NA_character_
  readr::write_csv(queue, file.path(qa_dir, "review_queue.csv"))
  readr::write_csv(x[!x$map_ready | x$coordinate_conflict, ], file.path(qa_dir, "geocoding_queue.csv"))
  readr::write_csv(x[x$source_records > 1 | x$shared_address | x$source_id_conflict, ],
                   file.path(qa_dir, "duplicate_review.csv"))
  readr::write_csv(dplyr::anti_join(reviews, x, by = c("collection", "destination_id")),
                   file.path(qa_dir, "orphaned_reviews.csv"))
  readr::write_csv(x[x$coordinate_correction_status %in% c("stale", "invalid"), ],
                   file.path(qa_dir, "unapplied_coordinate_corrections.csv"))
  summary <- tibble::tibble(
    destination = destination, source_files = length(files), source_rows = nrow(rows),
    standardized_records = nrow(x), map_ready = sum(x$map_ready),
    analysis_ready = sum(x$analysis_ready), review_required = sum(x$screen_decision == "review"),
    excluded = sum(x$screen_decision == "exclude"), shared_address = sum(x$shared_address),
    coordinate_conflicts = sum(x$coordinate_conflict), rule_version = dataaxle_rule_version)
  readr::write_csv(summary, file.path(qa_dir, "summary.csv"))
  print(summary, width = Inf)
  message("Manual decisions: ", review_path,
          "\nData Axle coordinates are retained, not independently geocoded or verified.")
  invisible(x)
}

# Stage 04: write the GeoPackage (one layer per proposed destination type,
# all map-ready candidates) plus analysis-ready records and H3 counts.
ax_build_destination <- function(destination) {
  interim_path <- file.path(destination_dir(destination, "interim", "dataaxle", create = FALSE),
                            "dataaxle_standardized.rds")
  if (!file.exists(interim_path))
    stop("Missing ", interim_path, ". Run 02_clean_dataaxle_", destination, ".R first.")
  x <- readRDS(interim_path)
  gpkg <- destination_output_path(destination, "dataaxle", "gpkg")
  # Recreate so types removed from the inputs cannot leave stale layers.
  if (file.exists(gpkg)) unlink(gpkg)
  for (type in sort(unique(x$destination_type))) {
    selected <- x[x$destination_type == type & x$map_ready, ]
    if (nrow(selected)) write_point_layer(selected, gpkg, paste0("candidates_", type), "destination_id")
  }
  ready <- x[x$analysis_ready, ]
  readr::write_csv(ready, destination_output_path(destination, "dataaxle", "csv", "analysis_ready"))
  for (resolution in c(7, 8)) {
    column <- paste0("h3_h", resolution)
    counts <- ready |>
      dplyr::group_by(destination_type, h3_id = .data[[column]]) |>
      dplyr::summarise(destination_count = dplyr::n_distinct(destination_id), .groups = "drop")
    readr::write_csv(counts, destination_output_path(destination, "dataaxle", "csv",
                                                     paste0("h", resolution, "_counts")))
  }
  print(dplyr::count(x, destination_type, map_ready, analysis_ready), n = Inf)
  message("Candidate layers: ", gpkg)
  invisible(gpkg)
}
