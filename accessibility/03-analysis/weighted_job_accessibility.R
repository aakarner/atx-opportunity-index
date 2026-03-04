

# Calculates worker-type-weighted accessibility for job categories
# Uses LODES RAC (Residence Area Characteristics) for worker distribution
# RAC-Weighted Job Accessibility Analysis

library(readr)
library(tidyverse)
library(sf)
library(tigris)
library(ggplot2)
library(ggspatial)
library(lehdr)

# ===== LOAD ACCESSIBILITY RESULTS =====
cat("=== Loading Accessibility Results ===\n")

acc_results <- read_csv("accessibility/data/processed/accessibility/unweighted_job_accessibility.csv", show_col_types = FALSE) %>%
  mutate(trct = as.character(trct))

cat("✓ Accessibility results loaded\n")
cat("  Columns:", paste(names(acc_results), collapse = ", "), "\n")

# ===== DOWNLOAD LODES DATA =====
# RAC = Residence Area Characteristics (where workers live from home)
# WAC = Workplace Area Characteristics (job distribution by wage at work)
# Strategy: Use RAC for total workers, WAC for wage distribution, 
#           estimate worker demographics by local job wage mix

cat("\n=== Downloading LODES Data ===\n")
cat("Step 1: RAC data (where workers live)...\n")
cat("Step 2: Job distribution from existing travis_lodes.csv...\n")
cat("Estimating workers by income level based on local job wage structure...\n")

# RAC = Workers at their HOME location
rac_data <- grab_lodes(
  state = "tx",
  year = 2020,
  lodes_type = "rac",
  job_type = "JT00",
  segment = "S000"  # Main segment with C000
) %>%
  filter(substr(h_geocode, 1, 5) == "48453") %>%
  mutate(trct = substr(h_geocode, 1, 11)) %>%
  group_by(trct) %>%
  summarize(
    workers_all = sum(C000, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(trct = as.character(trct))

# Load Travis LODES jobs (already has CE01/CE02/CE03 breakdown from WAC S000)
# This file was created by accessibility_jobs_clean.R with correct wage breakdowns
travis_jobs <- read_csv("accessibility/data/processed/lehd/travis_lodes.csv", show_col_types = FALSE) %>%
  mutate(trct = as.character(trct))

# Merge RAC (workers at home) with job wage distribution (from WAC)
# Calculate wage-specific job proportions for weighting
rac_data <- rac_data %>%
  left_join(travis_jobs, by = "trct") %>%
  mutate(
    job_total = totjobs,
    # Distribute workers by proportion of jobs in each wage category
    workers_low = workers_all * (lowjobs / pmax(job_total, 1)),
    workers_med = workers_all * (medjobs / pmax(job_total, 1)),
    workers_high = workers_all * (highjobs / pmax(job_total, 1))
  ) %>%
  select(trct, workers_all, workers_low, workers_med, workers_high)

cat("✓ LODES data loaded\n")
cat("  RAC tracts with worker data:", nrow(rac_data), "\n")
cat("  Total workers:\n")
cat("    All:", format(sum(rac_data$workers_all, na.rm = TRUE), big.mark = ","), "\n")
cat("    Low-wage (estimated):", format(sum(rac_data$workers_low, na.rm = TRUE), big.mark = ","), "\n")
cat("    Mid-wage (estimated):", format(sum(rac_data$workers_med, na.rm = TRUE), big.mark = ","), "\n")
cat("    High-wage (estimated):", format(sum(rac_data$workers_high, na.rm = TRUE), big.mark = ","), "\n")
cat("  Note: Wage-specific estimates based on local job wage distribution\n")

# ===== LOAD TRACT GEOMETRIES =====
tracts <- tracts(state = "TX", county = "Travis", year = 2020, class = "sf")

# ===== COMBINE ACCESSIBILITY + WORKER DATA =====
cat("\n=== Assembling Data ===\n")

# Filter to 50th percentile (can change to 75 or 90 if desired)
acc_rac <- acc_results %>%
  filter(percentile == 50) %>%
  select(trct, access_total, access_low, access_med, access_high,
         cutoff, totjobs, lowjobs, medjobs, highjobs) %>%
  left_join(rac_data, by = "trct") %>%
  # Fill missing worker values with 0
  mutate(across(starts_with("workers_"), 
                ~replace_na(., 0)))

cat("✓ Data combined\n")
cat("  Tracts with accessibility data:", nrow(acc_rac), "\n")
cat("  Sample:\n")
print(head(acc_rac, 3))

# ===== CALCULATE WORKER-WEIGHTED ACCESSIBILITY =====
cat("\n====== WORKER-WEIGHTED ACCESSIBILITY ======\n")
cat("Accessibility cutoff: 45 minutes (walk + transit)\n\n")

# 1. ALL JOBS weighted by ALL WORKERS
weighted_all <- weighted.mean(
  acc_rac$access_total[!is.na(acc_rac$access_total)],
  acc_rac$workers_all[!is.na(acc_rac$access_total)],
  na.rm = TRUE
)

# 2. LOW-WAGE JOBS weighted by LOW-WAGE WORKERS
weighted_low <- weighted.mean(
  acc_rac$access_low[!is.na(acc_rac$access_low)],
  acc_rac$workers_low[!is.na(acc_rac$access_low)],
  na.rm = TRUE
)

# 3. MID-WAGE JOBS weighted by MID-WAGE WORKERS
weighted_med <- weighted.mean(
  acc_rac$access_med[!is.na(acc_rac$access_med)],
  acc_rac$workers_med[!is.na(acc_rac$access_med)],
  na.rm = TRUE
)

# 4. HIGH-WAGE JOBS weighted by HIGH-WAGE WORKERS
weighted_high <- weighted.mean(
  acc_rac$access_high[!is.na(acc_rac$access_high)],
  acc_rac$workers_high[!is.na(acc_rac$access_high)],
  na.rm = TRUE
)

# Print results
cat("ALL JOBS (weighted by all workers):\n")
cat("  Weighted mean:  ", format(weighted_all, big.mark = ","), " jobs\n")
cat("  Unweighted mean:", format(mean(acc_rac$access_total, na.rm = TRUE), big.mark = ","), " jobs\n")
cat("  Median:         ", format(median(acc_rac$access_total, na.rm = TRUE), big.mark = ","), " jobs\n\n")

cat("LOW-WAGE JOBS (weighted by low-wage workers):\n")
cat("  Weighted mean:  ", format(weighted_low, big.mark = ","), " jobs\n")
cat("  Unweighted mean:", format(mean(acc_rac$access_low, na.rm = TRUE), big.mark = ","), " jobs\n")
cat("  Median:         ", format(median(acc_rac$access_low, na.rm = TRUE), big.mark = ","), " jobs\n\n")

cat("MID-WAGE JOBS (weighted by mid-wage workers):\n")
cat("  Weighted mean:  ", format(weighted_med, big.mark = ","), " jobs\n")
cat("  Unweighted mean:", format(mean(acc_rac$access_med, na.rm = TRUE), big.mark = ","), " jobs\n")
cat("  Median:         ", format(median(acc_rac$access_med, na.rm = TRUE), big.mark = ","), " jobs\n\n")

cat("HIGH-WAGE JOBS (weighted by high-wage workers):\n")
cat("  Weighted mean:  ", format(weighted_high, big.mark = ","), " jobs\n")
cat("  Unweighted mean:", format(mean(acc_rac$access_high, na.rm = TRUE), big.mark = ","), " jobs\n")
cat("  Median:         ", format(median(acc_rac$access_high, na.rm = TRUE), big.mark = ","), " jobs\n\n")

# ===== SUMMARY TABLE =====
summary_table <- tibble(
  Job_Type = c("All Jobs", "Low-Wage", "Mid-Wage", "High-Wage"),
  Weighted_Mean = round(c(weighted_all, weighted_low, weighted_med, weighted_high), 0),
  Unweighted_Mean = round(c(
    mean(acc_rac$access_total, na.rm = TRUE),
    mean(acc_rac$access_low, na.rm = TRUE),
    mean(acc_rac$access_med, na.rm = TRUE),
    mean(acc_rac$access_high, na.rm = TRUE)
  ), 0),
  Median = round(c(
    median(acc_rac$access_total, na.rm = TRUE),
    median(acc_rac$access_low, na.rm = TRUE),
    median(acc_rac$access_med, na.rm = TRUE),
    median(acc_rac$access_high, na.rm = TRUE)
  ), 0),
  Min = c(
    min(acc_rac$access_total, na.rm = TRUE),
    min(acc_rac$access_low, na.rm = TRUE),
    min(acc_rac$access_med, na.rm = TRUE),
    min(acc_rac$access_high, na.rm = TRUE)
  ),
  Max = c(
    max(acc_rac$access_total, na.rm = TRUE),
    max(acc_rac$access_low, na.rm = TRUE),
    max(acc_rac$access_med, na.rm = TRUE),
    max(acc_rac$access_high, na.rm = TRUE)
  ),
  Worker_Count = c(
    sum(acc_rac$workers_all, na.rm = TRUE),
    sum(acc_rac$workers_low, na.rm = TRUE),
    sum(acc_rac$workers_med, na.rm = TRUE),
    sum(acc_rac$workers_high, na.rm = TRUE)
  )
)

cat("=== SUMMARY TABLE ===\n")
print(summary_table)

# ===== SAVE RESULTS =====
dir.create("output", recursive = TRUE, showWarnings = FALSE)

write_csv(summary_table, "accessibility/output/rac_weighted_job_accessibility_summary.csv")
write_csv(acc_rac, "accessibility/output/rac_weighted_accessibility_job_full.csv")

cat("\n✓ Results saved to output/ folder\n")

# ===== VISUALIZATIONS =====
cat("\n=== Creating Visualizations ===\n")

# 1. Comparison bar chart
p_comparison <- summary_table %>%
  select(Job_Type, Weighted_Mean, Unweighted_Mean) %>%
  gather(key = "Type", value = "Accessibility", -Job_Type) %>%
  ggplot(aes(x = Job_Type, y = Accessibility, fill = Type)) +
  geom_col(position = "dodge", alpha = 0.8) +
  labs(
    title = "Worker-Type-Weighted Job Accessibility",
    subtitle = "Jobs reachable within 45 min via walk + transit (50th percentile)",
    x = "Job Type",
    y = "Jobs Accessible",
    fill = "Weighting Method"
  ) +
  scale_y_continuous(labels = scales::label_comma()) +
  scale_fill_manual(values = c("Weighted_Mean" = "steelblue", "Unweighted_Mean" = "lightgray")) +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("accessibility/output/accessibility_comparison_by_job_type.png", p_comparison, width = 10, height = 6)
cat("✓ Saved: accessibility_comparison_by_job_type.png\n")

# 2. Box plots showing distribution
p_distribution <- acc_rac %>%
  select(access_total, access_low, access_med, access_high) %>%
  gather(key = "Job_Type", value = "Accessibility") %>%
  mutate(Job_Type = fct_recode(Job_Type,
    "All Jobs" = "access_total",
    "Low-Wage" = "access_low",
    "Mid-Wage" = "access_med",
    "High-Wage" = "access_high"
  )) %>%
  ggplot(aes(x = Job_Type, y = Accessibility, fill = Job_Type)) +
  geom_boxplot(alpha = 0.7) +
  geom_jitter(width = 0.2, alpha = 0.3, size = 1) +
  labs(
    title = "Distribution of Job Accessibility by Type",
    subtitle = "Across 200+ Census Tracts",
    x = "Job Type",
    y = "Jobs Accessible (45 min)",
    fill = "Job Type"
  ) +
  scale_y_continuous(labels = scales::label_comma()) +
  theme_bw() +
  theme(legend.position = "none")

ggsave("accessibility/output/accessibility_distribution_by_job_type.png", p_distribution, width = 10, height = 6)
cat("✓ Saved: accessibility_distribution_by_job_type.png\n")

# 3. Maps: one for each job type
tracts_acc <- tracts %>%
  st_transform(4326) %>%
  mutate(GEOID = as.character(GEOID)) %>%
  left_join(acc_rac, by = c("GEOID" = "trct"))

# All jobs map
p_all <- ggplot() +
  geom_sf(data = tracts_acc, aes(fill = access_total, color = access_total), size = 0.1) +
  scale_fill_viridis_c(name = "Jobs\nAccessible", labels = scales::label_comma(), direction = -1) +
  scale_color_viridis_c(guide = "none", direction = -1) +
  labs(title = "All Jobs", subtitle = "Jobs reachable in 45 minutes via walk + transit\n(50th percentile - median experience)") +
  xlab(NULL) + ylab(NULL) +
  theme_bw() +
  annotation_scale(location = "bl", width_hint = 0.2) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(), 
        panel.grid = element_blank(), plot.title = element_text(face = "bold"))

# Low-wage jobs map
p_low <- ggplot() +
  geom_sf(data = tracts_acc, aes(fill = access_low, color = access_low), size = 0.1) +
  scale_fill_viridis_c(name = "Jobs\nAccessible", labels = scales::label_comma(), direction = -1) +
  scale_color_viridis_c(guide = "none", direction = -1) +
  labs(title = "Low-Wage Jobs", subtitle = "Jobs reachable in 45 minutes via walk + transit\n(50th percentile - median experience)") +
  xlab(NULL) + ylab(NULL) +
  theme_bw() +
  annotation_scale(location = "bl", width_hint = 0.2) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(), 
        panel.grid = element_blank(), plot.title = element_text(face = "bold"))

# Mid-wage jobs map
p_med <- ggplot() +
  geom_sf(data = tracts_acc, aes(fill = access_med, color = access_med), size = 0.1) +
  scale_fill_viridis_c(name = "Jobs\nAccessible", labels = scales::label_comma(), direction = -1) +
  scale_color_viridis_c(guide = "none", direction = -1) +
  labs(title = "Mid-Wage Jobs", subtitle = "Jobs reachable in 45 minutes via walk + transit\n(50th percentile - median experience)") +
  xlab(NULL) + ylab(NULL) +
  theme_bw() +
  annotation_scale(location = "bl", width_hint = 0.2) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(), 
        panel.grid = element_blank(), plot.title = element_text(face = "bold"))

# High-wage jobs map
p_high <- ggplot() +
  geom_sf(data = tracts_acc, aes(fill = access_high, color = access_high), size = 0.1) +
  scale_fill_viridis_c(name = "Jobs\nAccessible", labels = scales::label_comma(), direction = -1) +
  scale_color_viridis_c(guide = "none", direction = -1) +
  labs(title = "High-Wage Jobs", subtitle = "Jobs reachable in 45 minutes via walk + transit\n(50th percentile - median experience)") +
  xlab(NULL) + ylab(NULL) +
  theme_bw() +
  annotation_scale(location = "bl", width_hint = 0.2) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(), 
        panel.grid = element_blank(), plot.title = element_text(face = "bold"))

# Combine maps
p_maps <- cowplot::plot_grid(p_all, p_low, p_med, p_high, nrow = 2, ncol = 2)
ggsave("accessibility/output/accessibility_maps_by_job_type.png", p_maps, width = 16, height = 14)
cat("✓ Saved: accessibility_maps_by_job_type.png\n")

cat("\n====== ANALYSIS COMPLETE ======\n")
cat("Output files saved to: output/\n")
cat("  - rac_weighted_accessibility_summary.csv\n")
cat("  - rac_weighted_accessibility_full.csv\n")
cat("  - accessibility_comparison_by_job_type.png\n")
cat("  - accessibility_distribution_by_job_type.png\n")
cat("  - accessibility_maps_by_job_type.png\n")
