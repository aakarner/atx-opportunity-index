# Example: explore alternative cluster counts for the step-20 reference model.
# Run 20_austin_opportunity_index.R first. This optional example is not the
# submitted proof-of-concept analysis and deliberately preserves the separation
# between cluster inputs and post-clustering social/economic context.

# Load configuration
source("config.R")

# Install missing packages and load this script's dependencies.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf"))

analysis_path <- file.path(OUTPUT_DIR, "austin_opportunity_data.rds")
if (!file.exists(analysis_path)) {
  stop(
    "Missing ", analysis_path, ". Run Rscript 20_austin_opportunity_index.R first."
  )
}

census_data <- readRDS(analysis_path)

cluster_vars <- c(
  "housing_market_profile_cluster",
  "family_service_fit_cluster",
  "log_transit_jobs_45min_cluster",
  "log_hazard_facilities_1mi_cluster",
  "log_annual_ksi_crash_density_cluster"
)

cat("Re-estimating the step-20 reference model with", NUM_CLUSTERS, "clusters...\n")

cluster_data <- census_data %>%
  filter(cluster_complete) %>%
  st_drop_geometry() %>%
  select(all_of(cluster_vars))

cluster_data_scaled <- scale(cluster_data)

set.seed(RANDOM_SEED)
kmeans_result <- kmeans(cluster_data_scaled,
                       centers = NUM_CLUSTERS,
                       nstart = NSTART)

cat("Clustering complete. Cluster sizes:\n")
print(table(kmeans_result$cluster))

# Add the alternative assignments without allowing overlays to affect them.
custom_assignments <- rep(NA_integer_, nrow(census_data))
custom_assignments[census_data$cluster_complete] <- kmeans_result$cluster
census_data_final <- census_data %>%
  mutate(custom_cluster = factor(custom_assignments))

cat("\nSocial and economic overlays by alternative cluster:\n")
overlay_summary <- census_data_final %>%
  st_drop_geometry() %>%
  filter(!is.na(custom_cluster)) %>%
  group_by(custom_cluster) %>%
  summarise(
    n_tracts = n(),
    median_household_income = median(median_income, na.rm = TRUE),
    mean_poverty_rate = mean(poverty_rate, na.rm = TRUE),
    mean_employment_rate = mean(employment_rate, na.rm = TRUE),
    mean_educational_attainment = mean(educational_attainment, na.rm = TRUE),
    mean_no_vehicle_share = mean(no_vehicle_share, na.rm = TRUE),
    .groups = "drop"
  )
print(overlay_summary)

custom_map <- ggplot(census_data_final) +
  geom_sf(aes(fill = custom_cluster), color = "white", linewidth = 0.1) +
  scale_fill_viridis_d(name = "Cluster", na.value = "#d9d9d9") +
  labs(
    title = paste("Alternative", NUM_CLUSTERS, "-Cluster Place Profiles"),
    subtitle = paste(
      "Housing/family profiles, transit access, environmental hazards, and",
      "KSI crashes; overlays excluded"
    )
  ) +
  theme_void() +
  theme(plot.title = element_text(face = "bold"))

# Save with configuration settings
if (SAVE_PLOTS) {
  dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
  map_path <- file.path(OUTPUT_DIR, "example_custom_cluster_map.png")
  ggsave(
    map_path,
    custom_map,
    width = MAP_WIDTH,
    height = MAP_HEIGHT,
    dpi = MAP_DPI
  )
  cat("Map saved to", map_path, "\n")
}

cat("\n=== Example Complete ===\n")
cat("See config.R to change NUM_CLUSTERS and map settings.\n")
