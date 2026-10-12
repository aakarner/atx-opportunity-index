# Join attendance assignments to growth and audit changes between snapshots.
# Run pull_school_boundaries.R for both years and pull_school_indicators.R first.
# Run from the repository root. No downloads or tract weighting here.
source("scripts/prepare/packages.R")
setup_project_packages(c("sf", "dplyr", "readr", "ggplot2", "digest"))

school_levels <- c("elementary", "middle", "high")

# Deterministic name matching; never accept a fuzzy match or a legacy zone code
# alone. These three aliases reconcile literal names in the cached GIS/TEA data.
school_name_key <- function(x) {
  x <- trimws(sub("/.*$", "", x)) # English half of bilingual assignment label
  x <- sub("^Reassignment\\s+", "", x, ignore.case = TRUE)
  # Explicit accent folding avoids platform-specific iconv apostrophes.
  x <- toupper(chartr("áéíóúüñÁÉÍÓÚÜÑ", "aeiouunAEIOUUN", x))
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("\\bEARLY COLLEGE\\b|\\bELEMENTARY\\b|\\bMIDDLE\\b|\\bHIGH SCHOOL\\b|\\bH S\\b|\\bECHS\\b|\\bES\\b|\\bEL\\b|\\bMS\\b|\\bHS\\b", " ", x)
  x <- gsub(" +", " ", trimws(x))
  recode(x, "TRAVIS HEIGHTS" = "TRAVIS HTS", "WOOLDRIGE" = "WOOLDRIDGE",
         "MARSHALL" = "GENERAL MARSHALL")
}

match_assignments <- function(x, campuses, level) {
  expected_type <- c(elementary = "Elementary", middle = "Middle", high = "High")[[level]]
  lookup <- campuses |> filter(school_type == expected_type) |>
    mutate(name_key = school_name_key(campus_name))
  if (anyNA(lookup$name_key) || anyDuplicated(lookup$name_key)) stop("Ambiguous TEA name keys.")
  x$name_key <- school_name_key(x$assigned_school_label)
  index <- match(x$name_key, lookup$name_key)
  if (anyNA(index)) stop("Unmatched labels: ", paste(x$assigned_school_label[is.na(index)], collapse = "; "))
  code_field <- c(elementary = "ELEM_", middle = "MID_", high = "HIGH_")[[level]]
  codes <- suppressWarnings(as.integer(x[[code_field]]))
  x$legacy_code_campus_id <- ifelse(is.na(codes) | codes <= 0, NA_character_,
                                   paste0("227901", sprintf("%03d", codes)))
  scores <- lookup[index, ]
  x$campus_id <- scores$campus_id
  x$campus_name <- scores$campus_name
  x$legacy_code_agrees <- ifelse(is.na(x$legacy_code_campus_id), NA,
                                x$legacy_code_campus_id == x$campus_id)
  # A disagreement is expected only in explicitly labeled reassignment polygons.
  if (any(!x$reassignment_flag & (is.na(x$legacy_code_agrees) | !x$legacy_code_agrees))) {
    stop("Non-reassignment code/name disagreement requires review.")
  }
  x$match_method <- ifelse(x$legacy_code_agrees %in% TRUE,
                          "Normalized name and code agree", "Receiving name; legacy code not usable")
  x$accountability_year <- scores$year
  x$growth_school_year <- "2025-26"
  x$reported_growth <- scores$growth
  x$growth_token <- scores$growth_token
  x$paired_accountability <- scores$paired
  x$grade_span <- scores$grade_span
  x$score_status <- ifelse(!scores$eligible, scores$exclusion_reason,
                           ifelse(is.na(scores$growth), "Growth missing or suppressed", "Available"))
  # Do not condition this growth-only join on achievement, Part B, or poverty.
  x$usable_growth <- ifelse(x$score_status == "Available", scores$growth, NA_real_)
  x$score_predates_assignment_year <- x$assignment_school_year != x$growth_school_year
  x$campus_score_scope <- "Campus-wide; program-specific access and outcomes not distinguished"
  x
}

polygon_parts <- function(x) {
  x <- st_make_valid(x)
  x <- suppressWarnings(st_collection_extract(x, "POLYGON"))
  x <- suppressWarnings(st_cast(x, "MULTIPOLYGON"))
  x[!st_is_empty(x) & as.numeric(st_area(x)) > 0, ]
}

empty_mask <- function() st_sfc(st_multipolygon(), crs = 5070)

ambiguous_mask <- function(x) {
  hits <- st_intersects(x)
  pieces <- list()
  for (i in seq_len(nrow(x))) {
    for (j in hits[[i]][hits[[i]] > i]) {
      z <- suppressWarnings(st_intersection(st_geometry(x[i, ]), st_geometry(x[j, ])))
      if (length(z) && sum(as.numeric(st_area(z))) > 0) pieces[[length(pieces) + 1L]] <- z
    }
  }
  if (!length(pieces)) return(empty_mask())
  st_union(do.call(c, pieces))
}

compare_assignments <- function(old, new, level) {
  # Dissolve same-campus pieces before identifying conflicting assignments.
  dissolve <- function(x) {
    names(x)[names(x) == attr(x, "sf_column")] <- "geometry"
    st_geometry(x) <- "geometry"
    x |> st_transform(5070) |> group_by(campus_id) |>
      summarise(campus_name = first(campus_name), usable_growth = first(usable_growth),
                .groups = "drop")
  }
  a <- dissolve(old); b <- dissolve(new)
  footprint <- st_union(c(st_union(a), st_union(b)))
  mask <- st_union(c(ambiguous_mask(a), ambiguous_mask(b)))
  if (any(!st_is_empty(mask))) {
    a <- polygon_parts(suppressWarnings(st_difference(a, mask)))
    b <- polygon_parts(suppressWarnings(st_difference(b, mask)))
  }
  a <- rename(a, old_campus_id = campus_id, old_campus_name = campus_name,
              old_growth = usable_growth)
  b <- rename(b, new_campus_id = campus_id, new_campus_name = campus_name,
              new_growth = usable_growth)
  shared <- polygon_parts(suppressWarnings(st_intersection(a, b))) |>
    mutate(assignment_status = ifelse(old_campus_id == new_campus_id, "Unchanged", "Changed"))
  old_only <- polygon_parts(suppressWarnings(st_difference(a, st_union(b)))) |>
    mutate(assignment_status = "No 2026-27 coverage")
  new_only <- polygon_parts(suppressWarnings(st_difference(b, st_union(a)))) |>
    mutate(assignment_status = "No 2025-26 coverage")
  unclear <- st_sf(assignment_status = "Ambiguous source overlap", geometry = mask) |>
    polygon_parts()
  result <- bind_rows(shared, old_only, new_only, unclear) |>
    mutate(school_level = level, area_sq_m = as.numeric(st_area(geometry)),
           sub_square_meter_piece = area_sq_m < 1,
           reviewable_assignment_change = assignment_status == "Changed" & area_sq_m >= 1,
           growth_difference = new_growth - old_growth,
           growth_difference_meaning = "Different assigned campuses; same 2025-26 score vintage")
  # Area accounting includes tiny numerical fragments rather than hiding them.
  footprint_area <- as.numeric(st_area(footprint))
  if (abs(sum(result$area_sq_m) - footprint_area) > max(1, footprint_area * 1e-8)) {
    stop("Change overlay failed area conservation: ", level)
  }
  if (any(!st_is_valid(result)) || any(st_is_empty(result))) stop("Invalid change overlay.")
  result
}

write_gpkg <- function(layers, path) {
  temporary <- sub("\\.gpkg$", ".partial.gpkg", path)
  if (file.exists(temporary)) unlink(temporary)
  for (name in names(layers)) st_write(layers[[name]], temporary, layer = name, quiet = TRUE)
  if (!file.rename(temporary, path)) stop("Cannot finalize ", path)
}

run_school_access <- function() {
  processed <- "data/processed/school_indicators"
  out <- "data/qaqc/school_assignments"
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  panel_path <- file.path(processed, "aisd_campus_year.csv")
  boundary_paths <- setNames(file.path(processed, paste0("aisd_assignments_",
                                 c("2025_26", "2026_27"), ".gpkg")), c("2025-26", "2026-27"))
  inputs <- c(panel_path, boundary_paths)
  if (any(!file.exists(inputs))) stop("Run scripts/prepare/pull_school_boundaries.R for both years and scripts/prepare/pull_school_indicators.R first.")
  campuses <- read_csv(panel_path, col_types = cols(campus_id = col_character(),
    district_id = col_character(), growth_token = col_character()), show_col_types = FALSE) |>
    filter(year == 2026)
  if (!nrow(campuses) || anyDuplicated(campuses$campus_id) ||
      any(campuses$district_id != "227901")) stop("Invalid TEA 2026 AISD input.")
  all_scored <- list(); coverage <- list()
  for (yr in names(boundary_paths)) {
    scored <- setNames(lapply(school_levels, function(level) {
      x <- st_read(boundary_paths[[yr]], layer = level, quiet = TRUE)
      if (any(x$assignment_school_year != yr) || anyDuplicated(x$source_object_id) ||
          any(st_is_empty(x)) || any(!st_is_valid(x))) stop("Invalid boundary input.")
      match_assignments(x, campuses, level)
    }), school_levels)
    all_scored[[yr]] <- scored
    write_gpkg(scored, file.path(processed, paste0("aisd_growth_assignments_", gsub("-", "_", yr), ".gpkg")))
    crosswalk <- bind_rows(lapply(scored, st_drop_geometry))
    write_csv(crosswalk, file.path(out, paste0("campus_crosswalk_", gsub("-", "_", yr), ".csv")), na = "")
    coverage[[yr]] <- crosswalk |> group_by(assignment_school_year, school_level) |>
      summarise(polygons = n(), matched_campuses = n_distinct(campus_id),
                polygons_with_usable_growth = sum(!is.na(usable_growth)),
                campuses_with_usable_growth = n_distinct(campus_id[!is.na(usable_growth)]),
                .groups = "drop")
  }
  coverage <- bind_rows(coverage)
  write_csv(coverage, file.path(out, "score_coverage.csv"))
  changes <- setNames(lapply(school_levels, function(level) {
    message("Comparing ", level, " assignments...")
    compare_assignments(all_scored[["2025-26"]][[level]], all_scored[["2026-27"]][[level]], level)
  }), school_levels)
  write_gpkg(changes, file.path(processed, "aisd_assignment_changes_2025_26_to_2026_27.gpkg"))
  change_attributes <- bind_rows(lapply(changes, st_drop_geometry))
  area_summary <- change_attributes |> group_by(school_level, assignment_status) |>
    summarise(area_sq_km = sum(area_sq_m) / 1e6, pieces = n(),
              sub_square_meter_area_sq_m = sum(area_sq_m[sub_square_meter_piece]), .groups = "drop") |>
    group_by(school_level) |>
    mutate(percent_of_union_area = 100 * area_sq_km / sum(area_sq_km)) |> ungroup()
  write_csv(area_summary, file.path(out, "assignment_change_area.csv"))
  transitions <- change_attributes |> filter(assignment_status == "Changed") |>
    group_by(school_level, old_campus_id, old_campus_name, new_campus_id, new_campus_name,
             old_growth, new_growth, growth_difference) |>
    summarise(area_sq_km = sum(area_sq_m) / 1e6, .groups = "drop") |>
    arrange(school_level, desc(area_sq_km))
  # Retain numerical slivers in the full audit, but keep the review table useful.
  write_csv(transitions, file.path(out, "changed_campus_pairs_all.csv"), na = "")
  write_csv(filter(transitions, area_sq_km >= 1e-6),
            file.path(out, "changed_campus_pairs.csv"), na = "")
  exception_fields <- c("assignment_school_year", "school_level", "source_object_id",
    "assigned_school_label", "campus_id", "campus_name", "accountability_year",
    "reported_growth", "usable_growth", "paired_accountability", "grade_span", "score_status")
  missing_scores <- bind_rows(lapply(all_scored, function(layers) {
    bind_rows(lapply(layers, function(x) st_drop_geometry(x) |> select(all_of(exception_fields))))
  })) |>
    filter(score_status != "Available")
  write_csv(missing_scores, file.path(out, "score_exceptions.csv"), na = "")
  provenance_inputs <- c(inputs, "scripts/prepare/build_school_assignments.R",
    "data/qaqc/school_indicators/source_manifest.csv",
    "data/qaqc/aisd_boundaries/2025_26/source_manifest.csv",
    "data/qaqc/aisd_boundaries/2026_27/source_manifest.csv")
  write_csv(tibble(path = unname(provenance_inputs),
    sha256 = vapply(provenance_inputs, function(p) digest::digest(file = p, algo = "sha256"), character(1)),
    processed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)), file.path(out, "input_manifest.csv"))

  map_data <- bind_rows(changes) |>
    mutate(school_level = factor(school_level, levels = school_levels),
           assignment_status = factor(assignment_status, levels = c("Unchanged", "Changed",
             "Ambiguous source overlap", "No 2025-26 coverage", "No 2026-27 coverage")))
  p <- ggplot(map_data) + geom_sf(aes(fill = assignment_status), color = NA) +
    facet_wrap(~school_level, nrow = 1) +
    scale_fill_manual(values = c("Unchanged" = "#e0e3e5", "Changed" = "#cf602e",
      "Ambiguous source overlap" = "#803e91", "No 2025-26 coverage" = "#267caa",
      "No 2026-27 coverage" = "#dbc451"), drop = FALSE) +
    labs(title = "AISD attendance assignments: 2025–26 to 2026–27", fill = NULL,
      subtitle = "Orange areas have a different assigned campus in the published locator layers",
      caption = "Source: AISD ArcGIS snapshots. Overlapping assignments are flagged separately.\nThis compares geography, not numbers of students; campus-wide growth predates the 2026–27 changes.") +
    theme_void(base_size = 11) + theme(legend.position = "bottom",
      plot.caption = element_text(hjust = 0), strip.text = element_text(face = "bold")) +
    guides(fill = guide_legend(nrow = 2, byrow = TRUE))
  ggsave(file.path(out, "assignment_changes.png"), p, width = 12, height = 6, dpi = 180, bg = "white")
  capture.output({
    cat("AISD ATTENDANCE-ZONE GROWTH BASELINE AND ASSIGNMENT CHANGES\n")
    cat("Growth vintage: 2025-26 (TEA 2026, raw CD2A). No weighted access score.\n")
    cat("Matches require normalized names within school level; legacy codes audited separately.\n")
    cat("Excluded scores remain missing; reported values and reasons retained for review.\n")
    cat("2026-27 scores are provisional receiving-campus proxies from 2025-26.\n\n")
    print(coverage, width = Inf)
    cat("\nAREA COMPARISON (land area, not population; all numerical fragments retained)\n")
    print(area_summary, n = Inf, width = Inf)
    cat("\nSUBSTANTIVE CHANGED PAIRS (at least 1 square meter in aggregate)\n")
    print(filter(transitions, area_sq_km >= 1e-6), n = Inf, width = Inf)
  }, file = file.path(out, "access_summary.txt"))
  writeLines(capture.output(sessionInfo()), file.path(out, "session_info.txt"))
  message("School access joins and change audit saved to ", normalizePath(out))
  invisible(list(coverage = coverage, changes = area_summary, transitions = transitions))
}

if (sys.nframe() == 0L) run_school_access()
