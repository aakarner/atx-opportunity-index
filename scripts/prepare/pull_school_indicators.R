# Acquire and normalize TEA campus accountability records for AISD.
# Run from the repository root. See docs/schools.md for definitions and
# historical indicator comparisons. This script writes source and coverage QA.

source("scripts/prepare/packages.R")
setup_project_packages(c("dplyr", "readr", "httr2", "digest"))

school_config <- list(
  years = 2023:2026,
  district = "227901", # Austin ISD, not every school within Austin city limits
  raw_dir = "data/raw/tea_accountability",
  processed_dir = "data/processed/school_indicators",
  qaqc_dir = "data/qaqc/school_indicators",
  refresh = tolower(Sys.getenv("REFRESH_TEA_ACCOUNTABILITY", "false")) %in%
    c("true", "1", "yes")
)

school_metrics <- c(
  achievement = "STAAR achievement (raw)",
  growth = "Academic growth (raw)",
  relative_performance = "Relative performance (scaled)"
)

# ---- Acquisition and source validation ---------------------------------------

tea_export_url <- function(year) {
  paste0(
    "https://rptsvr1.tea.texas.gov/cgi/sas/broker/",
    "?_service=marykay&_program=perfrept.perfmast.sas&_debug=0",
    "&ccyy=", year, "&dsname=RATE&sumlev=C",
    "&key=RATE&key=D1&key=D2&key=FLAG&key=PE&key=GRD&key=PAIR",
    "&datafmt=C&prgopt=reports/acct/dd/dd_get_data.sas"
  )
}

read_tea_export <- function(path, year) {
  # TEA has TWO header rows: human-readable labels, then machine field names.
  headers <- readLines(path, n = 2, warn = FALSE)
  if (length(headers) != 2L || !grepl("^CAMPUS,", headers[2])) {
    stop("Not a TEA campus CSV (possibly an HTML error): ", path)
  }
  if (!grepl(as.character(year), headers[1], fixed = TRUE)) {
    stop("Export header does not identify requested year: ", year)
  }
  x <- read_csv(path, skip = 1, col_types = cols(.default = col_character()),
                na = c("", "NA"), show_col_types = FALSE, progress = FALSE)
  required <- c(
    "CAMPUS", "CAMPNAME", "DISTRICT", "DISTNAME", "GRDTYPE", "GRDSPAN",
    "CPETALLC", "CPETECOP", "CD1A", "CD2A", "CD2AS", "CD2BS", "CD1AS",
    "CD1B", "C_RATING", "CFLDAEP", "CFLJJ", "CFLRTF", "CFLALTED",
    "CFLPAIRD", "CFLPAIRO", "CFLPAIR", "PAIRCAMP"
  )
  missing <- setdiff(required, names(x))
  if (length(missing)) stop("Missing TEA fields: ", paste(missing, collapse = ", "))
  if (nrow(problems(x))) stop("CSV parsing errors in ", path)
  if (!nrow(x) || anyDuplicated(x$CAMPUS) || anyNA(x$CAMPUS) ||
      any(!grepl("^[0-9]{9}$", x$CAMPUS))) stop("Invalid campus identifiers: ", path)
  if (any(substr(x$CAMPUS, 1, 6) != x$DISTRICT)) stop("Campus/district mismatch.")
  x
}

fetch_tea_year <- function(year, config) {
  path <- file.path(config$raw_dir, paste0("tea_", year, "_campus_rate.csv"))
  url <- tea_export_url(year)
  reused <- file.exists(path) && !config$refresh
  if (!reused) {
    message("Downloading TEA campus summary for ", year, "...")
    temporary <- paste0(path, ".partial")
    on.exit(unlink(temporary), add = TRUE)
    response <- request(url) |>
      req_user_agent("atx-opportunity-index/school-indicators") |>
      req_retry(max_tries = 3) |> req_timeout(120) |> req_perform()
    writeBin(resp_body_raw(response), temporary)
    read_tea_export(temporary, year) # Validate before replacing an existing cache.
    if (!file.rename(temporary, path)) stop("Cannot finalize ", path)
  }
  x <- read_tea_export(path, year)
  # Preserve the source's own labels beside machine field names.
  labels <- read_csv(path, col_names = FALSE, n_max = 1, show_col_types = FALSE,
                     col_types = cols(.default = col_character()), progress = FALSE)
  dictionary <- tibble(year = year, field = names(x), label = as.character(labels[1, ]))
  list(data = x, dictionary = dictionary, manifest = tibble(
    year = year, url = url, raw_file = path, statewide_rows = nrow(x),
    sha256 = digest::digest(file = path, algo = "sha256"),
    cached_file_modified_utc = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE),
    reused_cache = reused
  ))
}

# ---- Normalize scores without converting suppression codes into numbers ------

tea_number <- function(x) {
  # Exact numeric tokens only. Negative TEA sentinel values, blanks, ranges,
  # suppression marks, and text remain NA; their original tokens are exported.
  x <- trimws(x)
  good <- !is.na(x) & grepl("^[0-9]+(\\.[0-9]+)?$", x)
  out <- rep(NA_real_, length(x))
  out[good] <- as.numeric(x[good])
  out
}

normalize_aisd <- function(x, year, district) {
  x <- filter(x, DISTRICT == district)
  if (!nrow(x) || any(x$DISTNAME != "AUSTIN ISD")) stop("AISD filter failed: ", year)
  flag_fields <- c("CFLDAEP", "CFLJJ", "CFLRTF", "CFLALTED",
                   "CFLPAIRD", "CFLPAIRO", "CFLPAIR")
  if (any(vapply(x[flag_fields], function(z) any(is.na(z) | !z %in% c("Y", "N")),
                 logical(1)))) stop("Unexpected campus flag: ", year)
  out <- transmute(
    x, year = year, campus_id = CAMPUS, campus_name = CAMPNAME,
    district_id = DISTRICT, school_type = recode(GRDTYPE,
      E = "Elementary", M = "Middle", S = "High", B = "Combined", .default = "Unknown"),
    grade_span = GRDSPAN, enrollment = tea_number(CPETALLC),
    econ_disadv_pct = tea_number(CPETECOP), econ_disadv_token = CPETECOP,
    achievement = tea_number(CD1A), achievement_token = CD1A,
    growth = tea_number(CD2A), growth_token = CD2A,
    relative_performance = tea_number(CD2BS), relative_performance_token = CD2BS,
    growth_scaled = tea_number(CD2AS), achievement_scaled = tea_number(CD1AS),
    ccmr_raw = tea_number(CD1B), overall_rating = C_RATING,
    alternative_accountability = CFLALTED == "Y",
    special_setting = CFLDAEP == "Y" | CFLJJ == "Y" | CFLRTF == "Y",
    paired = CFLPAIRD == "Y" | CFLPAIRO == "Y" | CFLPAIR == "Y" |
      (!is.na(PAIRCAMP) & nzchar(trimws(PAIRCAMP)) & PAIRCAMP != CAMPUS),
    paired_campus_id = trimws(PAIRCAMP)
  )
  bounded <- c("econ_disadv_pct", names(school_metrics), "growth_scaled",
               "achievement_scaled", "ccmr_raw")
  if (any(vapply(out[bounded], function(z) any(z < 0 | z > 100, na.rm = TRUE),
                 logical(1)))) stop("Score/percentage outside 0-100: ", year)
  out |>
    mutate(
      exclusion_reason = case_when(
        alternative_accountability ~ "Alternative accountability (Part B is retest growth)",
        special_setting ~ "Disciplinary, juvenile justice, or residential treatment setting",
        paired ~ "Paired accountability record",
        school_type == "Unknown" ~ "Unknown school type",
        is.na(enrollment) | enrollment <= 0 ~ "No valid enrollment",
        is.na(overall_rating) | !overall_rating %in% LETTERS[1:6] ~ "Not rated",
        TRUE ~ "Included"
      ),
      eligible = exclusion_reason == "Included",
      complete_metrics = if_all(all_of(names(school_metrics)), ~ !is.na(.x)),
      primary_sample = eligible & complete_metrics & !is.na(econ_disadv_pct)
    )
}

# ---- Outputs -----------------------------------------------------------------

write_school_outputs <- function(panel, manifest, dictionary, config) {
  out <- config$qaqc_dir
  write_csv(panel, file.path(config$processed_dir, "aisd_campus_year.csv"), na = "")
  write_csv(manifest, file.path(out, "source_manifest.csv"), na = "")
  write_csv(dictionary, file.path(out, "source_field_dictionary.csv"), na = "")
  coverage <- panel |> group_by(year, school_type) |>
    summarise(campuses = n(), eligible_campuses = sum(eligible), common_sample = sum(primary_sample),
              achievement_available = sum(eligible & !is.na(achievement)),
              growth_available = sum(eligible & !is.na(growth)),
              relative_available = sum(eligible & !is.na(relative_performance)), .groups = "drop")
  write_csv(coverage, file.path(out, "coverage.csv"))
  write_csv(panel |> filter(!eligible | !primary_sample), file.path(out, "exclusions_and_missingness.csv"), na = "")
  writeLines(capture.output(sessionInfo()), file.path(out, "session_info.txt"))
  message("AISD indicators and source QA saved to ", normalizePath(out))
  invisible(panel)
}

prepare_school_indicators <- function(config = school_config) {
  if (!length(config$years) || anyNA(config$years) || anyDuplicated(config$years) ||
      any(config$years != as.integer(config$years))) stop("Specify unique accountability years.")
  for (path in c(config$raw_dir, config$processed_dir, config$qaqc_dir)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  sources <- lapply(config$years, fetch_tea_year, config = config)
  panel <- bind_rows(Map(function(s, y) normalize_aisd(s$data, y, config$district), sources, config$years))
  if (anyDuplicated(panel[c("year", "campus_id")])) stop("Duplicate campus-year records.")
  if (any(!config$years %in% panel$year)) stop("Missing requested years.")
  write_school_outputs(panel, bind_rows(lapply(sources, `[[`, "manifest")),
                       bind_rows(lapply(sources, `[[`, "dictionary")), config)
}

if (sys.nframe() == 0L) prepare_school_indicators()
