# TEA 2026 (2025-26) economically disadvantaged campus outcomes, AISD only.
# Standalone source preparation; does not replace the current school indicator.
source("scripts/prepare/pull_school_indicators.R")

subgroup_sources <- list(
  reading = list(dataset = "D1_STAAR1", keys = c("CR022", "CR222")),
  math = list(dataset = "D1_STAAR2", keys = c("CM022", "CM222")),
  growth = list(dataset = "D2_A", keys = c("D2_A_0", "D2_A_R", "D2_A_M"))
)
subgroup_url <- function(spec) paste0(
  "https://rptsvr1.tea.texas.gov/cgi/sas/broker/?_service=marykay",
  "&_program=perfrept.perfmast.sas&_debug=0&ccyy=2026&dsname=", spec$dataset,
  "&sumlev=C&", paste0("key=", spec$keys, collapse = "&"),
  "&datafmt=C&prgopt=reports/acct/dd/dd_get_data.sas")

read_subgroup_source <- function(path, districts = "227901") {
  headers <- readLines(path, n = 2, warn = FALSE)
  if (length(headers) != 2 || !grepl("^CAMPUS,", headers[2]) ||
      !grepl("2025-26", headers[1], fixed = TRUE)) stop("Wrong subgroup export/year: ", path)
  x <- read_csv(path, skip = 1, col_types = cols(.default = col_character()),
                show_col_types = FALSE, progress = FALSE)
  if (nrow(problems(x)) || !nrow(x) || anyNA(x$CAMPUS) || anyDuplicated(x$CAMPUS) ||
      any(!grepl("^[0-9]{9}$", x$CAMPUS))) stop("Invalid subgroup campus records.")
  labels <- read_csv(path, n_max = 1, col_names = FALSE,
    col_types = cols(.default = col_character()), show_col_types = FALSE)
  list(data = filter(x, substr(CAMPUS, 1, 6) %in% districts),
    dictionary = tibble(field = names(x), label = as.character(labels[1, ])), rows = nrow(x))
}

pooled_growth <- function(rn, rd, rr, mn, md, mr) {
  # Require both published subject scores and counts; never reconstruct a masked rate.
  good <- !is.na(rn) & !is.na(rd) & !is.na(rr) & !is.na(mn) & !is.na(md) &
    !is.na(mr) & rd > 0 & md > 0
  ifelse(good, 100 * (rn + mn) / (rd + md), NA_real_)
}

run_school_subgroups <- function(districts = "227901", scope = "aisd") {
  raw <- "data/raw/tea_accountability/subgroups_2026"
  qa <- if (scope == "aisd") "data/qaqc/school_subgroups" else file.path("data/qaqc", paste0(scope,"_school_subgroups"))
  processed <- "data/processed/school_indicators"
  for (p in c(raw, qa, processed)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  dictionaries <- manifests <- sources <- list()
  for (name in names(subgroup_sources)) {
    path <- file.path(raw, paste0(name, ".csv")); url <- subgroup_url(subgroup_sources[[name]])
    cached <- file.exists(path)
    if (!cached) {
      tmp <- paste0(path, ".partial")
      bytes <- request(url) |> req_retry(max_tries = 3) |> req_timeout(120) |>
        req_perform() |> resp_body_raw()
      writeBin(bytes, tmp); read_subgroup_source(tmp)
      if (!file.rename(tmp, path)) stop("Cannot finalize source file.")
    }
    parsed <- read_subgroup_source(path, districts)
    sources[[name]] <- parsed$data
    dictionaries[[name]] <- mutate(parsed$dictionary, source = name)
    manifests[[name]] <- tibble(source = name, url = url, path = path,
      accountability_year = 2026, school_year = "2025-26", statewide_rows = parsed$rows,
      aisd_rows = nrow(parsed$data), sha256 = digest::digest(file = path, algo = "sha256"),
      cached_file_modified_utc = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE), reused_cache = cached)
  }
  dictionary <- bind_rows(dictionaries)
  long <- list()
  for (subject in c("reading", "math")) {
    letter <- if (subject == "reading") "R" else "M"
    for (group in c("A", "E")) {
      for (measure in c("achievement", "growth")) {
        src <- if (measure == "growth") "growth" else subject
        x <- sources[[src]]
        prefix <- paste0("CD", group, "00A", letter)
        fields <- if (measure == "growth") paste0(prefix, "0200026", c("N", "D", "R")) else
          c(paste0(prefix, "01226N"), paste0(prefix, "01026D"), paste0(prefix, "01226R"))
        if (!all(fields %in% names(x))) stop("Missing expected fields: ", paste(fields, collapse = ", "))
        z <- tibble(campus_id = x$CAMPUS, year = 2026L, school_year = "2025-26",
          subject = subject, group = if (group == "E") "Economically disadvantaged" else "All students",
          measure = measure, numerator_field = fields[1], denominator_field = fields[2], rate_field = fields[3],
          numerator_token = x[[fields[1]]], denominator_token = x[[fields[2]]], rate_token = x[[fields[3]]]) |>
          mutate(numerator = tea_number(numerator_token), denominator = tea_number(denominator_token),
                 rate = tea_number(rate_token), low_n_20 = !is.na(denominator) & denominator < 20,
                 status = case_when(is.na(rate) ~ "Missing or masked rate",
                   is.na(denominator) ~ "Missing or masked denominator", denominator == 0 ~ "No evaluated tests",
                   denominator < 20 ~ "Available; fewer than 20 evaluated tests", TRUE ~ "Available"))
        # Growth includes bonus points and the published subgroup raw score can exceed 100.
        upper <- if (measure == "growth") 125 else 100
        if (any(z$rate > upper, na.rm = TRUE) || any(z$numerator > z$denominator * upper / 100, na.rm = TRUE))
          stop("Out-of-range source values.")
        check <- with(z, !is.na(rate) & !is.na(numerator) & !is.na(denominator) & denominator > 0)
        if (any(abs(z$rate[check] - 100 * z$numerator[check] / z$denominator[check]) > 0.501))
          stop("Published rate/count disagreement.")
        long[[length(long) + 1L]] <- z
      }
    }
  }
  long <- bind_rows(long)
  baseline_path <- file.path(processed, paste0(scope,"_campus_year.csv"))
  baseline <- read_csv(baseline_path, col_types = cols(campus_id = col_character()), show_col_types = FALSE) |>
    filter(year == 2026)
  if (!nrow(baseline) || anyDuplicated(baseline$campus_id)) stop("Missing/duplicate 2026 baseline.")
  wide <- baseline |> select(campus_id, campus_name, district_id, school_type, grade_span, enrollment,
    econ_disadv_pct, eligible, exclusion_reason, overall_growth = growth) |>
    mutate(year = 2026L, school_year = "2025-26")
  for (subject in c("reading", "math")) for (measure in c("achievement", "growth")) {
    z <- filter(long, subject == !!subject, measure == !!measure, group == "Economically disadvantaged")
    idx <- match(wide$campus_id, z$campus_id)
    prefix <- paste0("ed_", if (measure == "achievement") "meets" else "growth", "_", subject)
    for (field in c("rate", "numerator", "denominator", "status")) wide[[paste0(prefix, "_", field)]] <- z[[field]][idx]
    all <- filter(long, subject == !!subject, measure == !!measure, group == "All students")
    all_idx <- match(wide$campus_id, all$campus_id)
    wide[[paste0(prefix, "_test_share_pct")]] <- 100 * z$denominator[idx] / all$denominator[all_idx]
  }
  wide$ed_growth_pooled_unrounded <- with(wide, pooled_growth(ed_growth_reading_numerator,
    ed_growth_reading_denominator, ed_growth_reading_rate, ed_growth_math_numerator,
    ed_growth_math_denominator, ed_growth_math_rate))
  wide$ed_growth_pooled <- floor(wide$ed_growth_pooled_unrounded + 0.5)
  wide$minimum_subgroup_tests <- do.call(pmin, wide[c("ed_meets_reading_denominator",
    "ed_meets_math_denominator", "ed_growth_reading_denominator", "ed_growth_math_denominator")])
  wide$ed_growth_minus_overall <- wide$ed_growth_pooled - wide$overall_growth
  # Independently reconcile the newly downloaded overall growth to our saved indicator.
  g <- sources$growth; idx <- match(wide$campus_id, g$CAMPUS)
  wide$fresh_overall_growth <- tea_number(g$CDA00A00200026R[idx])
  wide$baseline_matches_fresh <- !is.na(wide$overall_growth) & !is.na(wide$fresh_overall_growth) &
    wide$overall_growth == wide$fresh_overall_growth
  if (any(wide$eligible & !wide$baseline_matches_fresh)) stop("Eligible overall-growth baseline changed; review before comparison.")
  # Verify the pooling method against TEA's published all-student combined score.
  pooled_all <- pooled_growth(tea_number(g$CDA00AR0200026N[idx]), tea_number(g$CDA00AR0200026D[idx]),
    tea_number(g$CDA00AR0200026R[idx]), tea_number(g$CDA00AM0200026N[idx]),
    tea_number(g$CDA00AM0200026D[idx]), tea_number(g$CDA00AM0200026R[idx]))
  if (any(wide$eligible & (is.na(pooled_all) | floor(pooled_all + 0.5) != wide$overall_growth)))
    stop("Subject pooling does not reproduce the existing growth measure.")
  shares <- wide[grepl("test_share_pct$", names(wide))]
  if (any(vapply(shares, function(x) any(is.finite(x) & (x < 0 | x > 100)), logical(1)))) stop("Invalid subgroup test share.")
  write_csv(long, file.path(processed, paste0(scope,"_subgroup_outcomes_2026_long.csv")), na = "")
  write_csv(wide, file.path(processed, paste0(scope,"_subgroup_comparison_2026.csv")), na = "")
  write_csv(bind_rows(manifests), file.path(qa, "source_manifest.csv"))
  write_csv(dictionary, file.path(qa, "source_field_dictionary.csv"))
  write_csv(filter(long, status != "Available"), file.path(qa, "masked_and_small_groups.csv"), na = "")
  write_csv(tibble(path = baseline_path, sha256 = digest::digest(file = baseline_path, algo = "sha256")),
            file.path(qa, "baseline_manifest.csv"))
  message("Saved 2025-26 ", scope, " subgroup outcomes; eligible overall scores agree with baseline.")
  invisible(wide)
}

if (sys.nframe() == 0L) run_school_subgroups()
