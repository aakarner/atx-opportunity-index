# Standalone comparison; leaves the targets pipeline's selected indicator intact.
source("scripts/prepare/packages.R")
setup_project_packages(c("sf", "dplyr", "tidyr", "readr", "ggplot2", "digest"))

subgroup_metrics <- c(ed_meets_reading_rate = "Low-income achievement: reading",
  ed_meets_math_rate = "Low-income achievement: math", ed_growth_reading_rate = "Low-income growth: reading",
  ed_growth_math_rate = "Low-income growth: math", ed_growth_pooled = "Low-income growth: combined")
percentile <- function(x) if (length(x) > 1) 100 * (rank(x, ties.method = "average") - 1) / (length(x) - 1) else NA_real_
rho <- function(x, y) if (length(x) >= 5 && length(unique(x)) > 1 && length(unique(y)) > 1)
  cor(x, y, method = "spearman") else NA_real_

compare_school_subgroups <- function() {
  out <- "output/school_subgroups"
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  input <- "data/processed/school_indicators/aisd_subgroup_comparison_2026.csv"
  zone_path <- "data/processed/school_indicators/aisd_growth_assignments_2025_26.gpkg"
  x <- read_csv(input, col_types = cols(campus_id = col_character()), show_col_types = FALSE)
  zones <- bind_rows(lapply(c("elementary", "middle", "high"), function(level) {
    st_read(zone_path, layer = level, quiet = TRUE) |> st_drop_geometry() |>
      select(campus_id, usable_growth)
  })) |> distinct()
  if (anyDuplicated(zones$campus_id)) stop("Ambiguous zone campus IDs.")
  zidx <- match(zones$campus_id, x$campus_id)
  if (anyNA(zidx) || any(zones$usable_growth != x$overall_growth[zidx], na.rm = TRUE)) stop("Zone baseline mismatch.")
  x <- x |> mutate(in_2025_26_zones = campus_id %in% zones$campus_id,
    complete_comparison = eligible & if_all(all_of(c("overall_growth", names(subgroup_metrics))), ~ !is.na(.x)) &
      !is.na(minimum_subgroup_tests) & minimum_subgroup_tests > 0)
  write_csv(x, file.path(out, "campus_comparison.csv"), na = "")
  coverage <- x |> group_by(school_type) |> summarise(tea_campuses = n(), eligible_campuses = sum(eligible),
    zoned = sum(in_2025_26_zones), zoned_eligible = sum(in_2025_26_zones & eligible),
    zoned_complete = sum(in_2025_26_zones & complete_comparison),
    zoned_complete_min20 = sum(in_2025_26_zones & complete_comparison & minimum_subgroup_tests >= 20, na.rm = TRUE),
    .groups = "drop")
  write_csv(coverage, file.path(out, "coverage.csv"))
  summaries <- ranks <- list()
  for (scope in c("2025-26 attendance-zone campuses", "All eligible AISD campuses")) {
    for (threshold in c(1, 10, 20, 30)) {
      sample <- filter(x, complete_comparison, minimum_subgroup_tests >= threshold,
        scope == "All eligible AISD campuses" | in_2025_26_zones)
      for (type in unique(sample$school_type)) {
        s <- filter(sample, school_type == type)
        overall_rank <- percentile(s$overall_growth)
        for (metric in names(subgroup_metrics)) {
          subgroup_rank <- percentile(s[[metric]])
          summaries[[length(summaries) + 1L]] <- tibble(scope = scope, minimum_tests_per_subject_measure = threshold,
            school_type = type, metric = metric, n = nrow(s),
            spearman_vs_overall_growth = rho(s$overall_growth, s[[metric]]),
            spearman_vs_econ_disadv_pct = rho(s$econ_disadv_pct, s[[metric]]),
            median_absolute_percentile_shift = median(abs(subgroup_rank - overall_rank), na.rm = TRUE),
            maximum_absolute_percentile_shift = if (nrow(s) > 1) max(abs(subgroup_rank - overall_rank)) else NA_real_)
          if (scope == "2025-26 attendance-zone campuses" && threshold %in% c(1, 20)) {
            ranks[[length(ranks) + 1L]] <- s |> transmute(campus_id, campus_name, school_type,
              minimum_tests_per_subject_measure = threshold, minimum_subgroup_tests,
              econ_disadv_pct, overall_growth, metric = metric, subgroup_value = .data[[metric]],
              overall_growth_percentile = overall_rank, subgroup_percentile = subgroup_rank,
              percentile_shift = subgroup_rank - overall_rank)
          }
        }
      }
    }
  }
  summaries <- bind_rows(summaries); ranks <- bind_rows(ranks)
  write_csv(summaries, file.path(out, "metric_comparisons.csv"), na = "")
  write_csv(ranks, file.path(out, "campus_rank_comparisons.csv"), na = "")
  changes <- ranks |> filter(minimum_tests_per_subject_measure == 20, metric == "ed_growth_pooled") |>
    group_by(school_type) |> slice_max(abs(percentile_shift), n = 5, with_ties = FALSE) |> ungroup()
  write_csv(changes, file.path(out, "largest_growth_rank_shifts_min20.csv"), na = "")
  focal <- c("ed_meets_reading_rate", "ed_meets_math_rate", "ed_growth_pooled")
  plot_data <- x |> filter(in_2025_26_zones, complete_comparison) |>
    mutate(school_type = factor(school_type, levels = c("Elementary", "Middle", "High")),
      small_group = factor(ifelse(minimum_subgroup_tests < 20, "At least one denominator <20", "All denominators ≥20"))) |>
    pivot_longer(all_of(focal), names_to = "metric", values_to = "value") |>
    mutate(metric = factor(metric, levels = focal, labels = subgroup_metrics[focal]))
  p <- ggplot(plot_data, aes(overall_growth, value, shape = small_group)) +
    geom_point(color = "#245a75", size = 2.3, alpha = 0.8) + facet_grid(school_type ~ metric) +
    scale_shape_manual(values = c("At least one denominator <20" = 1, "All denominators ≥20" = 16)) +
    labs(title = "AISD: outcomes for economically disadvantaged students",
      subtitle = "2025–26 results · campuses in the matched 2025–26 attendance zones",
      x = "Overall academic growth (existing measure)", y = "Subgroup score / Meets Grade Level (%)", shape = NULL,
      caption = "Achievement: percentage of assessments at Meets or above. Combined growth: pooled points per evaluated test, rounded.\nSame complete campus sample within each level. Open circles flag small denominators. Descriptive outcomes, not causal school effects.") +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom", plot.caption = element_text(hjust = 0))
  ggsave(file.path(out, "subgroup_vs_overall_growth.png"), p, width = 12, height = 9, dpi = 180, bg = "white")
  write_csv(tibble(path = c(input, zone_path), sha256 = vapply(c(input, zone_path),
    function(p) digest::digest(file = p, algo = "sha256"), character(1))), file.path(out, "input_manifest.csv"))
  capture.output({
    cat("AISD 2025-26 SUBGROUP COMPARISON (TEA 2026)\n")
    cat("Economically disadvantaged classification is individual; CEP free meals do not classify everyone as low income.\n")
    cat("Growth combines annual growth and accelerated-learning points; not a percentage of students who improved.\n")
    cat("Pooled subgroup growth uses sums of points / sums of tests, not an average of rounded subject scores.\n")
    cat("Denominators count evaluated tests, not unique children across subjects.\n")
    cat("Minimum-20 sensitivity requires at least 20 in EACH subgroup subject/measure; this is an analytical choice, not TEA's rule.\n\n")
    print(coverage, width = Inf)
    cat("\nATTENDANCE-ZONE COMMON SAMPLE, ALL AVAILABLE\n")
    print(filter(summaries, scope == "2025-26 attendance-zone campuses", minimum_tests_per_subject_measure == 1,
      metric %in% focal), width = Inf, n = Inf)
    cat("\nATTENDANCE-ZONE COMMON SAMPLE, EACH DENOMINATOR >=20\n")
    print(filter(summaries, scope == "2025-26 attendance-zone campuses", minimum_tests_per_subject_measure == 20,
      metric %in% focal), width = Inf, n = Inf)
    cat("\nLARGEST SUBGROUP-GROWTH RANK SHIFTS, MINIMUM 20\n")
    print(changes, width = Inf, n = Inf)
  }, file = file.path(out, "summary.txt"))
  writeLines(capture.output(sessionInfo()), file.path(out, "session_info.txt"))
  message("Comparison written to ", normalizePath(out))
  invisible(summaries)
}

if (sys.nframe() == 0L) compare_school_subgroups()
