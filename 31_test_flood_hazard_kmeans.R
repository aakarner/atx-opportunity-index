# Step 31: test physical flood hazard in a simple k-means specification
#
# This focused experiment compares the current five-input proof-of-concept
# model with the same model plus one physical flood-hazard coordinate: the
# share of each City-clipped tract in FEMA's 1%-annual-chance floodplain.
# Socioeconomic and demographic indicators remain post-clustering overlays.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "sf", "cluster", "patchwork", "scales"
))

# ---- Inputs and settings -----------------------------------------------------

analysis_file <- "output/austin_opportunity_data.rds"
floodplain_file <- paste0(
  "data/processed/flood_hazard/",
  "austin_fema_floodplain.gpkg"
)
output_dir <- "output"
equal_area_crs <- 5070
random_seed <- 123
nstart <- 50
selected_k <- 5
candidate_k <- 1:8
stability_k <- 2:6
stability_bootstraps <- 100
stability_sample_share <- 0.80
gap_bootstraps <- 100
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(analysis_file)) {
  stop("Missing ", analysis_file, ". Run 20_austin_opportunity_index.R first.")
}
if (!file.exists(floodplain_file)) {
  stop("Missing ", floodplain_file, ". Run 15_pull_austin_flood_hazard.R first.")
}

# ---- Helpers ----------------------------------------------------------------

choose_two <- function(x) x * (x - 1) / 2

adjusted_rand_index <- function(first_assignment, second_assignment) {
  complete <- !is.na(first_assignment) & !is.na(second_assignment)
  contingency <- table(
    first_assignment[complete],
    second_assignment[complete]
  )
  n <- sum(contingency)
  if (n < 2) return(NA_real_)

  observed <- sum(choose_two(contingency))
  row_pairs <- sum(choose_two(rowSums(contingency)))
  column_pairs <- sum(choose_two(colSums(contingency)))
  total_pairs <- choose_two(n)
  expected <- row_pairs * column_pairs / total_pairs
  maximum <- (row_pairs + column_pairs) / 2
  if (maximum == expected) return(NA_real_)
  (observed - expected) / (maximum - expected)
}

align_cluster_labels <- function(reference_assignment, candidate_assignment) {
  reference_levels <- sort(unique(reference_assignment))
  candidate_levels <- sort(unique(candidate_assignment))
  if (
    length(reference_levels) != length(candidate_levels) ||
      !identical(reference_levels, candidate_levels)
  ) {
    stop("Cluster-label alignment requires matching consecutive label sets.")
  }

  k <- length(reference_levels)
  permutation_grid <- expand.grid(
    rep(list(reference_levels), k),
    KEEP.OUT.ATTRS = FALSE
  )
  permutation_grid <- permutation_grid[
    apply(permutation_grid, 1, n_distinct) == k,
    ,
    drop = FALSE
  ]
  agreement <- apply(permutation_grid, 1, function(mapping) {
    sum(reference_assignment == mapping[candidate_assignment])
  })
  best_mapping <- as.integer(permutation_grid[which.max(agreement), ])

  list(
    assignment = best_mapping[candidate_assignment],
    mapping = best_mapping,
    agreement_share = max(agreement) / length(reference_assignment)
  )
}

calculate_hazard_share <- function(tracts, hazard_polygons, output_name) {
  hazard_union <- st_sf(
    hazard_type = output_name,
    geometry = st_union(st_geometry(hazard_polygons))
  ) %>%
    st_make_valid()
  if (nrow(hazard_union) != 1 || st_is_empty(hazard_union)) {
    stop("Could not construct the ", output_name, " hazard union.")
  }

  overlap <- suppressWarnings(
    st_intersection(tracts %>% select(GEOID), hazard_union)
  ) %>%
    mutate(overlap_area_m2 = as.numeric(st_area(geometry))) %>%
    st_drop_geometry() %>%
    group_by(GEOID) %>%
    summarise(overlap_area_m2 = sum(overlap_area_m2), .groups = "drop")

  tracts %>%
    st_drop_geometry() %>%
    select(GEOID, tract_area_m2) %>%
    left_join(overlap, by = "GEOID") %>%
    mutate(
      overlap_area_m2 = coalesce(overlap_area_m2, 0),
      hazard_share = pmin(1, pmax(0, overlap_area_m2 / tract_area_m2))
    ) %>%
    select(GEOID, hazard_share) %>%
    rename(!!output_name := hazard_share)
}

fit_model <- function(data, variables, model_key, sample_indices) {
  raw_matrix <- data %>%
    st_drop_geometry() %>%
    select(all_of(variables)) %>%
    as.matrix()
  if (any(!is.finite(raw_matrix))) {
    stop("Non-finite input in model: ", model_key)
  }
  scaled_matrix <- scale(raw_matrix)
  if (any(!is.finite(scaled_matrix))) {
    stop("Non-finite scaled input in model: ", model_key)
  }

  set.seed(random_seed)
  fits <- lapply(candidate_k, function(k) {
    kmeans(scaled_matrix, centers = k, nstart = nstart)
  })
  distances <- dist(scaled_matrix)
  wss <- vapply(fits, function(x) x$tot.withinss, numeric(1))
  total_sum_squares <- fits[[1]]$totss
  silhouette <- c(
    NA_real_,
    vapply(
      fits[-1],
      function(x) mean(cluster::silhouette(x$cluster, distances)[, 3]),
      numeric(1)
    )
  )
  calinski_harabasz <- c(
    NA_real_,
    vapply(seq_along(fits)[-1], function(index) {
      k <- candidate_k[index]
      fit <- fits[[index]]
      between_ss <- total_sum_squares - fit$tot.withinss
      (between_ss / (k - 1)) /
        (fit$tot.withinss / (nrow(scaled_matrix) - k))
    }, numeric(1))
  )

  stability <- map_dfr(stability_k, function(k) {
    full_fit <- fits[[which(candidate_k == k)]]
    set.seed(
      random_seed + 100 * k +
        match(model_key, c("baseline", "plus_flood"))
    )
    ari <- map_dbl(sample_indices, function(index) {
      subsample_fit <- kmeans(
        scaled_matrix[index, , drop = FALSE],
        centers = k,
        nstart = nstart
      )
      adjusted_rand_index(full_fit$cluster[index], subsample_fit$cluster)
    })
    tibble(
      k = k,
      stability_median_ari = median(ari, na.rm = TRUE),
      stability_p10_ari = as.numeric(quantile(
        ari, 0.10, na.rm = TRUE, names = FALSE
      ))
    )
  })

  set.seed(random_seed)
  gap <- cluster::clusGap(
    scaled_matrix,
    FUNcluster = function(x, k) kmeans(x, centers = k, nstart = nstart),
    K.max = max(candidate_k),
    B = gap_bootstraps,
    verbose = FALSE
  )
  gap_one_se_k <- cluster::maxSE(
    gap$Tab[, "gap"],
    gap$Tab[, "SE.sim"],
    method = "Tibs2001SEmax"
  )

  smallest_cluster <- vapply(
    fits,
    function(x) min(table(x$cluster)),
    numeric(1)
  )
  diagnostics <- tibble(
    model = model_key,
    input_count = length(variables),
    k = candidate_k,
    within_cluster_sum_squares = wss,
    incremental_wss_reduction_percent = c(
      NA_real_,
      100 * (head(wss, -1) - tail(wss, -1)) / head(wss, -1)
    ),
    average_silhouette = silhouette,
    calinski_harabasz = calinski_harabasz,
    smallest_cluster = smallest_cluster,
    smallest_cluster_share = smallest_cluster / nrow(scaled_matrix),
    gap_statistic = gap$Tab[, "gap"],
    gap_standard_error = gap$Tab[, "SE.sim"],
    gap_one_se_recommendation = candidate_k == gap_one_se_k
  ) %>%
    left_join(stability, by = "k")

  list(
    variables = variables,
    diagnostics = diagnostics,
    selected_fit = fits[[which(candidate_k == selected_k)]],
    gap_one_se_k = gap_one_se_k
  )
}

# ---- Construct tract-level physical hazard shares ---------------------------

cat("Reading tract analysis data and FEMA floodplain polygons...\n")
analysis_data <- readRDS(analysis_file) %>% st_make_valid()
floodplain <- st_read(floodplain_file, quiet = TRUE) %>% st_make_valid()

required_flood_columns <- c(
  "one_percent_annual_chance",
  "point_two_percent_annual_chance",
  "regulatory_floodway"
)
missing_flood_columns <- setdiff(required_flood_columns, names(floodplain))
if (length(missing_flood_columns) > 0) {
  stop(
    "Floodplain file is missing: ",
    str_c(missing_flood_columns, collapse = ", ")
  )
}

tracts_equal_area <- analysis_data %>%
  select(GEOID) %>%
  st_transform(equal_area_crs) %>%
  mutate(tract_area_m2 = as.numeric(st_area(geometry)))
floodplain_equal_area <- floodplain %>% st_transform(equal_area_crs)
if (any(tracts_equal_area$tract_area_m2 <= 0)) {
  stop("Tract geometries must have positive area.")
}

sfha_share <- calculate_hazard_share(
  tracts_equal_area,
  floodplain_equal_area %>% filter(one_percent_annual_chance),
  "fema_one_percent_land_share"
)
point_two_share <- calculate_hazard_share(
  tracts_equal_area,
  floodplain_equal_area %>% filter(point_two_percent_annual_chance),
  "fema_point_two_percent_land_share"
)
floodway_share <- calculate_hazard_share(
  tracts_equal_area,
  floodplain_equal_area %>% filter(regulatory_floodway),
  "fema_regulatory_floodway_land_share"
)

analysis_with_flood <- analysis_data %>%
  left_join(sfha_share, by = "GEOID") %>%
  left_join(point_two_share, by = "GEOID") %>%
  left_join(floodway_share, by = "GEOID") %>%
  mutate(
    across(starts_with("fema_"), ~coalesce(.x, 0)),
    # This reduces the leverage of a few highly inundated tracts while retaining
    # true zeros and a monotonic physical-hazard ordering.
    log_fema_one_percent_land_share =
      log1p(100 * fema_one_percent_land_share)
  )

# ---- Compare the compact five- and six-input models -------------------------

baseline_vars <- c(
  "housing_market_profile_cluster",
  "family_service_fit_cluster",
  "log_transit_jobs_45min_cluster",
  "log_hazard_facilities_1mi_cluster",
  "log_annual_ksi_crash_density_cluster"
)
flood_model_vars <- c(baseline_vars, "log_fema_one_percent_land_share")
missing_model_columns <- setdiff(flood_model_vars, names(analysis_with_flood))
if (length(missing_model_columns) > 0) {
  stop(
    "Analysis file is missing model inputs: ",
    str_c(missing_model_columns, collapse = ", ")
  )
}

model_data <- analysis_with_flood %>%
  filter(if_all(all_of(flood_model_vars), is.finite))
if (nrow(model_data) < 50) {
  stop("Too few complete tracts for the flood-hazard k-means comparison.")
}

set.seed(random_seed)
sample_size <- floor(nrow(model_data) * stability_sample_share)
sample_indices <- replicate(
  stability_bootstraps,
  sample.int(nrow(model_data), size = sample_size, replace = FALSE),
  simplify = FALSE
)

cat("Fitting the five-input baseline and six-input flood-hazard model...\n")
models <- list(
  baseline = fit_model(model_data, baseline_vars, "baseline", sample_indices),
  plus_flood = fit_model(
    model_data,
    flood_model_vars,
    "plus_flood",
    sample_indices
  )
)

diagnostics <- map_dfr(models, "diagnostics") %>%
  mutate(
    model_label = recode(
      model,
      baseline = "Five-input baseline",
      plus_flood = "Baseline + FEMA 1% flood hazard"
    )
  )
baseline_assignment <- models$baseline$selected_fit$cluster
flood_assignment <- models$plus_flood$selected_fit$cluster
flood_alignment <- align_cluster_labels(
  baseline_assignment,
  flood_assignment
)
flood_assignment_aligned <- flood_alignment$assignment

model_summary <- diagnostics %>%
  group_by(model, model_label, input_count) %>%
  summarise(
    silhouette_recommended_k = k[which.max(average_silhouette)],
    calinski_harabasz_recommended_k = k[which.max(calinski_harabasz)],
    gap_one_se_recommended_k = k[gap_one_se_recommendation][1],
    k5_average_silhouette = average_silhouette[k == selected_k],
    k5_calinski_harabasz = calinski_harabasz[k == selected_k],
    k5_stability_median_ari = stability_median_ari[k == selected_k],
    k5_stability_p10_ari = stability_p10_ari[k == selected_k],
    k5_smallest_cluster = smallest_cluster[k == selected_k],
    k5_smallest_cluster_share = smallest_cluster_share[k == selected_k],
    .groups = "drop"
  ) %>%
  mutate(
    k5_adjusted_rand_vs_baseline = c(
      1,
      adjusted_rand_index(baseline_assignment, flood_assignment)
    ),
    k5_membership_agreement_with_baseline = c(
      1,
      flood_alignment$agreement_share
    )
  )

assignments <- model_data %>%
  st_drop_geometry() %>%
  transmute(
    GEOID,
    baseline_k5_cluster = baseline_assignment,
    flood_k5_cluster_raw = flood_assignment,
    flood_k5_cluster_aligned = flood_assignment_aligned,
    membership_changed_after_alignment =
      baseline_k5_cluster != flood_k5_cluster_aligned,
    fema_one_percent_land_share,
    fema_point_two_percent_land_share,
    fema_regulatory_floodway_land_share
  )

profile_vars <- unique(c(
  baseline_vars,
  "fema_one_percent_land_share",
  "fema_point_two_percent_land_share",
  "fema_regulatory_floodway_land_share"
))
profiles <- imap_dfr(models, function(result, model_key) {
  profile_assignment <- if (model_key == "plus_flood") {
    flood_assignment_aligned
  } else {
    baseline_assignment
  }
  model_data %>%
    st_drop_geometry() %>%
    mutate(cluster = profile_assignment) %>%
    group_by(cluster) %>%
    summarise(
      tract_count = n(),
      across(all_of(profile_vars), ~median(.x, na.rm = TRUE)),
      .groups = "drop"
    ) %>%
    mutate(model = model_key, .before = 1)
})

# Overlay sorting is descriptive QA, not a pass/fail test.
overlay_vars <- c(
  "median_income", "poverty_rate", "educational_attainment",
  "employment_rate", "no_vehicle_share", "older_adult_share",
  "age_standardized_disability_rate", "people_of_color_share"
)
available_overlay_vars <- intersect(overlay_vars, names(model_data))
overlay_sorting <- imap_dfr(models, function(result, model_key) {
  map_dfr(available_overlay_vars, function(variable_name) {
    overlay_value <- model_data[[variable_name]]
    cluster_value <- factor(result$selected_fit$cluster)
    complete <- is.finite(overlay_value) & !is.na(cluster_value)
    cluster_means <- tapply(
      overlay_value[complete],
      cluster_value[complete],
      mean
    )
    overall_mean <- mean(overlay_value[complete])
    between_ss <- sum(
      table(cluster_value[complete]) * (cluster_means - overall_mean)^2
    )
    total_ss <- sum((overlay_value[complete] - overall_mean)^2)
    tibble(
      model = model_key,
      overlay = variable_name,
      eta_squared = if_else(total_ss > 0, between_ss / total_ss, NA_real_),
      minimum_cluster_mean = min(cluster_means),
      maximum_cluster_mean = max(cluster_means)
    )
  })
})

correlation_vars <- c(baseline_vars, available_overlay_vars)
flood_correlations <- map_dfr(correlation_vars, function(variable_name) {
  tibble(
    variable = variable_name,
    variable_role = if_else(
      variable_name %in% baseline_vars,
      "cluster_input",
      "overlay"
    ),
    spearman_correlation_with_flood_hazard = cor(
      model_data$fema_one_percent_land_share,
      model_data[[variable_name]],
      method = "spearman",
      use = "pairwise.complete.obs"
    )
  )
}) %>%
  arrange(desc(abs(spearman_correlation_with_flood_hazard)))

# ---- Maps, diagnostic figure, and outputs -----------------------------------

map_data <- model_data %>%
  mutate(
    baseline_k5_cluster = factor(baseline_assignment),
    flood_k5_cluster = factor(
      flood_assignment_aligned,
      levels = levels(baseline_k5_cluster)
    )
  )

hazard_map <- ggplot(map_data) +
  geom_sf(aes(fill = fema_one_percent_land_share), color = NA) +
  scale_fill_viridis_c(
    option = "C",
    labels = label_percent(accuracy = 1),
    name = "Share of tract"
  ) +
  labs(
    title = "Physical flood-hazard exposure",
    subtitle = paste(
      "Share of City-clipped tract land in FEMA's",
      "1%-annual-chance floodplain"
    ),
    caption = "Source: City of Austin Greater Austin FEMA Floodplain"
  ) +
  theme_void() +
  theme(legend.position = "right")

baseline_map <- ggplot(map_data) +
  geom_sf(
    aes(fill = baseline_k5_cluster),
    color = "white",
    linewidth = 0.05
  ) +
  labs(title = "Five-input baseline", fill = "Cluster") +
  theme_void() +
  theme(legend.position = "bottom")

flood_cluster_map <- ggplot(map_data) +
  geom_sf(
    aes(fill = flood_k5_cluster),
    color = "white",
    linewidth = 0.05
  ) +
  labs(title = "Baseline + flood hazard", fill = "Cluster") +
  theme_void() +
  theme(legend.position = "bottom")

diagnostic_plot <- diagnostics %>%
  filter(k >= 2) %>%
  select(
    model_label, k, average_silhouette,
    calinski_harabasz, stability_median_ari
  ) %>%
  pivot_longer(
    c(average_silhouette, calinski_harabasz, stability_median_ari),
    names_to = "diagnostic",
    values_to = "value"
  ) %>%
  filter(is.finite(value)) %>%
  mutate(
    diagnostic = recode(
      diagnostic,
      average_silhouette = "Average silhouette",
      calinski_harabasz = "Calinski-Harabasz",
      stability_median_ari = "80% subsample stability (median ARI)"
    )
  ) %>%
  ggplot(aes(k, value, color = model_label)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  geom_vline(
    xintercept = selected_k,
    linetype = "dashed",
    color = "grey45"
  ) +
  facet_wrap(~diagnostic, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = 2:max(candidate_k)) +
  labs(
    title = "Does physical flood hazard strengthen a multi-cluster solution?",
    subtitle = "Dashed line marks the prespecified five-cluster proof of concept",
    x = "Number of clusters (k)",
    y = NULL,
    color = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(
  file.path(output_dir, "flood_hazard_exposure_map.png"),
  hazard_map,
  width = 8.5,
  height = 7,
  dpi = 300,
  bg = "white"
)
ggsave(
  file.path(output_dir, "flood_hazard_kmeans_map_comparison.png"),
  baseline_map + flood_cluster_map,
  width = 13,
  height = 7,
  dpi = 300,
  bg = "white"
)
ggsave(
  file.path(output_dir, "flood_hazard_kmeans_diagnostics.png"),
  diagnostic_plot,
  width = 9,
  height = 10,
  dpi = 300,
  bg = "white"
)

write_csv(
  diagnostics,
  file.path(output_dir, "flood_hazard_kmeans_diagnostics.csv")
)
write_csv(
  model_summary,
  file.path(output_dir, "flood_hazard_kmeans_model_summary.csv")
)
write_csv(
  assignments,
  file.path(output_dir, "flood_hazard_kmeans_assignments.csv")
)
write_csv(
  profiles,
  file.path(output_dir, "flood_hazard_kmeans_profiles.csv")
)
write_csv(
  overlay_sorting,
  file.path(output_dir, "flood_hazard_overlay_sorting.csv")
)
write_csv(
  flood_correlations,
  file.path(output_dir, "flood_hazard_correlations.csv")
)

cat("\nFlood-hazard k-means comparison complete.\n")
print(model_summary, n = Inf)
cat(
  "\nMedian FEMA 1% land share: ",
  percent(median(model_data$fema_one_percent_land_share), accuracy = 0.1),
  "; maximum: ",
  percent(max(model_data$fema_one_percent_land_share), accuracy = 0.1),
  ".\n",
  sep = ""
)
cat("Outputs written under output/ with the prefix flood_hazard_.\n")
