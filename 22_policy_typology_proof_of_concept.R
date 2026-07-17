# Step 22: produce the deadline-ready five-cluster policy typology
#
# This is the only clustering script whose results are documented in the
# submitted Methods and Data Report. Other clustering routines in the
# repository are upstream references, supplemental analyses, or experiments.
#
# This mostly standalone analysis reads the tract-level analytical file created
# by step 20, but it does not reuse the cluster assignments from that workflow.
# It estimates a prespecified five-cluster k-means solution using the earlier
# reference indicators plus simplified built-form and observed resident-needs
# inputs. The submitted specification favors transparent, policy-facing shares:
# one-unit housing, housing built since 2010, older adults, and observed
# disability prevalence. The prior compositional/logit and age-standardized
# inputs are retained as explicitly labeled sensitivity models.
#
# Poverty and race/ethnicity are excluded from clustering and retained as the
# only demonstration overlays and cluster cross-tabs. All deliverables are
# isolated under output/proof_of_concept.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "sf", "cluster", "patchwork", "scales"
))

# ---- Settings ---------------------------------------------------------------

analysis_file <- "output/austin_opportunity_data.rds"
output_dir <- "output/proof_of_concept"
selected_k <- 5
candidate_k <- 1:10
stability_k <- 2:6
random_seed <- 123
nstart <- 100
gap_bootstraps <- 100
stability_bootstraps <- 100
stability_sample_share <- 0.80
poverty_overlay_quantile <- 0.75
minimum_acs_universe <- 100
disability_moe_threshold <- 0.10
overlay_cluster_boundary_linewidth <- 0.70

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(analysis_file)) {
  stop("Missing ", analysis_file, ". Run 20_austin_opportunity_index.R first.")
}

# ---- Prespecified policy-typology inputs ------------------------------------

model_inputs <- tribble(
  ~variable, ~indicator, ~domain, ~post_scale_weight,
  "housing_market_profile_cluster",
  "Housing-market profile (home value and rent)",
  "Housing market", 1,
  "family_service_fit_cluster",
  "Family/service-fit profile (household size and children)",
  "Household and family profile", 1,
  "log_transit_jobs_45min_cluster",
  "Transit access to jobs",
  "Access", 1,
  "log_hazard_facilities_1mi_cluster",
  "EPA hazard-candidate facilities within one mile",
  "Environmental exposure", 1,
  "log_annual_ksi_crash_density_cluster",
  "Annual KSI crash density within one mile",
  "Traffic safety", 1,
  "single_family_share_cluster",
  "Share of housing units in one-unit detached or attached structures",
  "Built form", 1 / sqrt(2),
  "recent_construction_share_cluster",
  "Observed share of housing stock built since 2010",
  "Built form", 1 / sqrt(2),
  "older_adult_need_cluster",
  "Share age 65 or older",
  "Resident service needs", 1 / sqrt(2),
  "observed_disability_prevalence_cluster",
  "Observed disability prevalence",
  "Resident service needs", 1 / sqrt(2)
) %>%
  mutate(
    squared_distance_weight = post_scale_weight^2,
    clustering_role = "Cluster-defining policy-typology input"
  )

domain_weights <- model_inputs %>%
  group_by(domain) %>%
  summarise(
    input_count = n(),
    squared_distance_weight = sum(squared_distance_weight),
    .groups = "drop"
  ) %>%
  mutate(
    share_of_total_squared_distance =
      squared_distance_weight / sum(squared_distance_weight)
  )

if (any(abs(domain_weights$squared_distance_weight - 1) > 1e-10)) {
  stop("Every conceptual domain must contribute one squared-distance unit.")
}

# Alternative formulations isolate the effect of the two simplifications and
# preserve the immediately preceding step-20-derived formulation as a
# sensitivity.
sensitivity_specs <- list(
  primary_simplified = model_inputs,
  age_standardized_disability = model_inputs %>%
    mutate(
      variable = if_else(
        variable == "observed_disability_prevalence_cluster",
        "age_standardized_disability_need_cluster",
        variable
      ),
      indicator = if_else(
        indicator == "Observed disability prevalence",
        "Age-standardized disability prevalence",
        indicator
      )
    ),
  transformed_built_form = model_inputs %>%
    filter(domain != "Built form") %>%
    bind_rows(tribble(
      ~variable, ~indicator, ~domain, ~post_scale_weight,
      "built_form_intensity_cluster",
      "Low-intensity versus attached and multifamily structure mix",
      "Built form", 1 / sqrt(3),
      "multifamily_scale_cluster",
      "Attached-small versus medium/large structure mix",
      "Built form", 1 / sqrt(3),
      "recent_stock_cluster",
      "Logit-transformed share of housing stock built since 2010",
      "Built form", 1 / sqrt(3)
    )) %>%
    mutate(
      squared_distance_weight = post_scale_weight^2,
      clustering_role = "Sensitivity model input"
    ),
  preceding_proof_of_concept = model_inputs %>%
    filter(!domain %in% c("Built form", "Resident service needs")) %>%
    bind_rows(tribble(
      ~variable, ~indicator, ~domain, ~post_scale_weight,
      "built_form_intensity_cluster",
      "Low-intensity versus attached and multifamily structure mix",
      "Built form", 1 / sqrt(3),
      "multifamily_scale_cluster",
      "Attached-small versus medium/large structure mix",
      "Built form", 1 / sqrt(3),
      "recent_stock_cluster",
      "Logit-transformed share of housing stock built since 2010",
      "Built form", 1 / sqrt(3),
      "older_adult_need_cluster",
      "Share age 65 or older",
      "Resident service needs", 1 / sqrt(2),
      "age_standardized_disability_need_cluster",
      "Age-standardized disability prevalence",
      "Resident service needs", 1 / sqrt(2)
    )) %>%
    mutate(
      squared_distance_weight = post_scale_weight^2,
      clustering_role = "Sensitivity model input"
    )
)

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

reliable_median_impute <- function(value, reliable) {
  reliable <- coalesce(reliable, FALSE) & is.finite(value)
  reference_median <- median(value[reliable], na.rm = TRUE)
  if (!is.finite(reference_median)) {
    stop("No reliable observations are available for median substitution.")
  }
  if_else(reliable, value, reference_median)
}

build_weighted_matrix <- function(data, specification) {
  raw <- data %>%
    st_drop_geometry() %>%
    select(all_of(specification$variable)) %>%
    as.matrix()
  scaled <- scale(raw)
  weighted <- sweep(
    scaled,
    MARGIN = 2,
    STATS = specification$post_scale_weight,
    FUN = "*"
  )
  if (any(!is.finite(weighted))) {
    stop("A clustering specification contains non-finite values.")
  }
  list(raw = raw, scaled = scaled, weighted = weighted)
}

make_descriptive_labels <- function(center_table) {
  remaining <- center_table$cluster
  take_max <- function(variable_name) {
    eligible <- center_table %>% filter(cluster %in% remaining)
    selected <- eligible$cluster[which.max(eligible[[variable_name]])]
    remaining <<- setdiff(remaining, selected)
    selected
  }

  transit_rich <- take_max("log_transit_jobs_45min_cluster")
  high_cost_family <- take_max("housing_market_profile_cluster")
  family_low_access <- take_max("family_service_fit_cluster")
  disability_service_needs <-
    take_max("observed_disability_prevalence_cluster")
  established_moderate <- remaining

  if (length(established_moderate) != 1) {
    stop("Could not assign one descriptive label to every cluster.")
  }

  setNames(
    c(
      "Transit-Rich Small-Household Higher-Exposure Areas",
      "High-Cost Family Areas with Older-Adult Service Needs",
      "Family-Oriented Low-Access Lower-Exposure Areas",
      "Moderate-Access Areas with Disability-Service Needs",
      "Established Moderate-Access Lower-Exposure Areas"
    ),
    as.character(c(
      transit_rich,
      high_cost_family,
      family_low_access,
      disability_service_needs,
      established_moderate
    ))
  )
}

# ---- Read and validate inputs -----------------------------------------------

cat("Reading tract-level analytical inputs from step 20...\n")

analysis_data <- readRDS(analysis_file) %>%
  st_make_valid()

required_columns <- c(
  "GEOID",
  setdiff(
    unique(map_chr(
      unlist(map(sensitivity_specs, ~.x$variable), use.names = FALSE),
      identity
    )),
    c(
      "single_family_share_cluster",
      "recent_construction_share_cluster",
      "observed_disability_prevalence_cluster"
    )
  ),
  "median_home_value", "median_rent", "avg_household_size",
  "children_household_share", "transit_jobs_45min",
  "hazard_facilities_1mi", "annual_ksi_crash_density",
  "detached_units", "attached_units", "structure_units_total",
  "structure_composition_reliable", "stock_age_reliable",
  "low_intensity_structure_share", "attached_small_structure_share",
  "medium_large_structure_share", "recent_2010_plus_share",
  "older_adult_share", "older_adult_reliable",
  "disability_population_total", "disability_population_with",
  "raw_disability_rate", "raw_disability_rate_moe",
  "age_standardized_disability_rate",
  "cluster_input_imputed",
  "poverty_total", "poverty_below",
  "poverty_rate", "race_ethnicity_total", "nh_white_alone",
  "nh_black_alone", "nh_asian_alone", "hispanic_latino_any_race",
  "people_of_color_share"
)
missing_columns <- setdiff(required_columns, names(analysis_data))
if (length(missing_columns) > 0) {
  stop(
    "The step-20 analytical file is missing: ",
    str_c(missing_columns, collapse = ", ")
  )
}
if (anyDuplicated(analysis_data$GEOID) > 0) {
  stop("Tract GEOIDs must be unique.")
}

# Construct the transparent proof-of-concept measures from published ACS
# estimates. The upstream broad-composition reliability flag is used for the
# one-unit share because the compact step-20 file does not retain every source
# component MOE. The raw numerator, denominator, and plausibility checks remain
# explicit here; a future production pull can retain and propagate the exact
# one-unit-share MOE directly.
analysis_data <- analysis_data %>%
  mutate(
    single_family_structure_units = detached_units + attached_units,
    single_family_structure_share = if_else(
      structure_units_total > 0,
      single_family_structure_units / structure_units_total,
      NA_real_
    ),
    single_family_share_reliable =
      coalesce(structure_composition_reliable, FALSE) &
      !is.na(single_family_structure_units) &
      single_family_structure_units >= 0 &
      single_family_structure_units <= structure_units_total,
    recent_construction_share_reliable =
      coalesce(stock_age_reliable, FALSE) &
      is.finite(recent_2010_plus_share),
    observed_disability_prevalence = raw_disability_rate,
    observed_disability_prevalence_reliable =
      !is.na(disability_population_total) &
      disability_population_total >= minimum_acs_universe &
      !is.na(disability_population_with) &
      disability_population_with >= 0 &
      disability_population_with <= disability_population_total &
      is.finite(raw_disability_rate_moe) &
      raw_disability_rate_moe <= disability_moe_threshold,
    single_family_share_cluster = reliable_median_impute(
      single_family_structure_share,
      single_family_share_reliable
    ),
    recent_construction_share_cluster = reliable_median_impute(
      recent_2010_plus_share,
      recent_construction_share_reliable
    ),
    observed_disability_prevalence_cluster = reliable_median_impute(
      observed_disability_prevalence,
      observed_disability_prevalence_reliable
    ),
    simplified_built_form_input_imputed =
      !single_family_share_reliable |
      !recent_construction_share_reliable,
    resident_service_needs_input_imputed =
      !coalesce(older_adult_reliable, FALSE) |
      !observed_disability_prevalence_reliable,
    base_policy_input_imputed = coalesce(cluster_input_imputed, FALSE),
    any_primary_input_imputed =
      base_policy_input_imputed |
      simplified_built_form_input_imputed |
      resident_service_needs_input_imputed
  )

complete_index <- complete.cases(
  st_drop_geometry(analysis_data)[, model_inputs$variable, drop = FALSE]
)
model_data <- analysis_data[complete_index, ]
if (nrow(model_data) < 50) {
  stop("Too few complete tracts for the policy typology.")
}

primary_matrices <- build_weighted_matrix(model_data, model_inputs)
raw_matrix <- primary_matrices$raw
unweighted_scaled_matrix <- primary_matrices$scaled
weighted_scaled_matrix <- primary_matrices$weighted

# ---- Fit candidate k values and prespecified k = 5 --------------------------

cat("Evaluating candidate cluster counts and fitting k = 5...\n")

set.seed(random_seed)
diagnostic_fits <- lapply(candidate_k, function(k) {
  kmeans(
    weighted_scaled_matrix,
    centers = k,
    nstart = nstart,
    iter.max = 100
  )
})

model_distance <- dist(weighted_scaled_matrix)
wss <- vapply(diagnostic_fits, function(x) x$tot.withinss, numeric(1))
average_silhouette <- c(
  NA_real_,
  vapply(
    diagnostic_fits[-1],
    function(x) mean(cluster::silhouette(x$cluster, model_distance)[, 3]),
    numeric(1)
  )
)
total_sum_squares <- diagnostic_fits[[1]]$totss
calinski_harabasz <- c(
  NA_real_,
  vapply(seq_along(diagnostic_fits)[-1], function(index) {
    k <- candidate_k[index]
    fit <- diagnostic_fits[[index]]
    between_ss <- total_sum_squares - fit$tot.withinss
    (between_ss / (k - 1)) /
      (fit$tot.withinss / (nrow(weighted_scaled_matrix) - k))
  }, numeric(1))
)

set.seed(random_seed)
stability_sample_size <- floor(
  nrow(weighted_scaled_matrix) * stability_sample_share
)
stability_sample_indices <- replicate(
  stability_bootstraps,
  sample.int(
    nrow(weighted_scaled_matrix),
    size = stability_sample_size,
    replace = FALSE
  ),
  simplify = FALSE
)
stability_summary <- map_dfr(stability_k, function(k) {
  full_fit <- diagnostic_fits[[which(candidate_k == k)]]
  set.seed(random_seed + 100 * k)
  ari <- map_dbl(stability_sample_indices, function(index) {
    sample_fit <- kmeans(
      weighted_scaled_matrix[index, , drop = FALSE],
      centers = k,
      nstart = nstart,
      iter.max = 100
    )
    adjusted_rand_index(full_fit$cluster[index], sample_fit$cluster)
  })
  tibble(
    k = k,
    subsample_stability_median_ari = median(ari, na.rm = TRUE),
    subsample_stability_p10_ari = as.numeric(quantile(
      ari, 0.10, na.rm = TRUE, names = FALSE
    ))
  )
})

set.seed(random_seed)
gap_result <- cluster::clusGap(
  weighted_scaled_matrix,
  FUNcluster = function(x, k) {
    kmeans(x, centers = k, nstart = nstart, iter.max = 100)
  },
  K.max = max(candidate_k),
  B = gap_bootstraps,
  verbose = FALSE
)
gap_one_se_k <- cluster::maxSE(
  gap_result$Tab[, "gap"],
  gap_result$Tab[, "SE.sim"],
  method = "Tibs2001SEmax"
)

smallest_cluster <- vapply(
  diagnostic_fits,
  function(x) min(table(x$cluster)),
  numeric(1)
)
largest_cluster <- vapply(
  diagnostic_fits,
  function(x) max(table(x$cluster)),
  numeric(1)
)
diagnostics <- tibble(
  k = candidate_k,
  within_cluster_sum_squares = wss,
  incremental_wss_reduction_percent = c(
    NA_real_,
    100 * (head(wss, -1) - tail(wss, -1)) / head(wss, -1)
  ),
  average_silhouette = average_silhouette,
  calinski_harabasz = calinski_harabasz,
  smallest_cluster = smallest_cluster,
  largest_cluster = largest_cluster,
  smallest_cluster_share = smallest_cluster / nrow(weighted_scaled_matrix),
  gap_statistic = gap_result$Tab[, "gap"],
  gap_standard_error = gap_result$Tab[, "SE.sim"],
  prespecified_policy_typology = k == selected_k,
  gap_one_se_recommendation = k == gap_one_se_k
) %>%
  left_join(stability_summary, by = "k")

selected_fit <- diagnostic_fits[[which(candidate_k == selected_k)]]

specification_sensitivity <- imap_dfr(
  sensitivity_specs,
  function(spec_table, specification_name) {
    specification_domain_weights <- spec_table %>%
      group_by(domain) %>%
      summarise(
        squared_distance_weight = sum(post_scale_weight^2),
        .groups = "drop"
      )
    if (
      any(abs(
        specification_domain_weights$squared_distance_weight - 1
      ) > 1e-10)
    ) {
      stop(
        "Sensitivity specification ", specification_name,
        " does not preserve equal conceptual-domain weights."
      )
    }

    matrices <- build_weighted_matrix(model_data, spec_table)
    if (specification_name == "primary_simplified") {
      fit <- selected_fit
    } else {
      set.seed(random_seed + match(
        specification_name,
        names(sensitivity_specs)
      ))
      fit <- kmeans(
        matrices$weighted,
        centers = selected_k,
        nstart = nstart,
        iter.max = 100
      )
    }
    model_distance <- dist(matrices$weighted)
    pca_result <- prcomp(
      matrices$weighted,
      center = FALSE,
      scale. = FALSE
    )
    total_sum_squares <- sum(scale(matrices$weighted, scale = FALSE)^2)
    between_sum_squares <- total_sum_squares - fit$tot.withinss
    calinski_harabasz_value <-
      (between_sum_squares / (selected_k - 1)) /
      (fit$tot.withinss / (nrow(matrices$weighted) - selected_k))

    tibble(
      specification = specification_name,
      input_count = nrow(spec_table),
      conceptual_domain_count = n_distinct(spec_table$domain),
      average_silhouette = mean(
        cluster::silhouette(fit$cluster, model_distance)[, 3]
      ),
      calinski_harabasz = calinski_harabasz_value,
      first_pc_variance_share = summary(pca_result)$importance[2, 1],
      smallest_cluster = min(table(fit$cluster)),
      largest_cluster = max(table(fit$cluster)),
      adjusted_rand_vs_primary = adjusted_rand_index(
        selected_fit$cluster,
        fit$cluster
      )
    )
  }
)

unweighted_centers <- as_tibble(unweighted_scaled_matrix) %>%
  mutate(cluster = selected_fit$cluster) %>%
  group_by(cluster) %>%
  summarise(across(everything(), mean), .groups = "drop")
cluster_labels <- make_descriptive_labels(unweighted_centers)

label_levels <- c(
  "Transit-Rich Small-Household Higher-Exposure Areas",
  "Moderate-Access Areas with Disability-Service Needs",
  "Established Moderate-Access Lower-Exposure Areas",
  "Family-Oriented Low-Access Lower-Exposure Areas",
  "High-Cost Family Areas with Older-Adult Service Needs"
)
cluster_palette <- c(
  "Transit-Rich Small-Household Higher-Exposure Areas" = "#d95f02",
  "Moderate-Access Areas with Disability-Service Needs" = "#7570b3",
  "Established Moderate-Access Lower-Exposure Areas" = "#1b9e77",
  "Family-Oriented Low-Access Lower-Exposure Areas" = "#66a61e",
  "High-Cost Family Areas with Older-Adult Service Needs" = "#e7298a"
)

poverty_threshold <- quantile(
  model_data$poverty_rate,
  poverty_overlay_quantile,
  na.rm = TRUE,
  names = FALSE
)
policy_data <- model_data %>%
  mutate(
    policy_cluster = selected_fit$cluster,
    policy_cluster_label = factor(
      unname(cluster_labels[as.character(policy_cluster)]),
      levels = label_levels
    ),
    higher_poverty_overlay = poverty_rate >= poverty_threshold
  )
if (any(is.na(policy_data$policy_cluster_label))) {
  stop("Every clustered tract must receive a descriptive label.")
}

# ---- Cluster-defining profiles ----------------------------------------------

cluster_profiles <- policy_data %>%
  st_drop_geometry() %>%
  group_by(policy_cluster, policy_cluster_label) %>%
  summarise(
    tract_count = n(),
    average_median_home_value = mean(median_home_value, na.rm = TRUE),
    average_median_rent = mean(median_rent, na.rm = TRUE),
    average_household_size = mean(avg_household_size, na.rm = TRUE),
    average_households_with_children_share =
      mean(children_household_share, na.rm = TRUE),
    average_transit_jobs_45min = mean(transit_jobs_45min, na.rm = TRUE),
    average_hazard_facilities_1mi =
      mean(hazard_facilities_1mi, na.rm = TRUE),
    average_annual_ksi_crash_density =
      mean(annual_ksi_crash_density, na.rm = TRUE),
    average_single_family_structure_share =
      mean(single_family_structure_share, na.rm = TRUE),
    average_low_intensity_structure_share =
      mean(low_intensity_structure_share, na.rm = TRUE),
    average_attached_small_structure_share =
      mean(attached_small_structure_share, na.rm = TRUE),
    average_medium_large_structure_share =
      mean(medium_large_structure_share, na.rm = TRUE),
    average_recent_2010_plus_share =
      mean(recent_2010_plus_share, na.rm = TRUE),
    average_older_adult_share = mean(older_adult_share, na.rm = TRUE),
    estimated_residents_with_disabilities =
      sum(disability_population_with, na.rm = TRUE),
    disability_measure_universe =
      sum(disability_population_total, na.rm = TRUE),
    population_weighted_observed_disability_prevalence =
      estimated_residents_with_disabilities / disability_measure_universe,
    average_observed_disability_prevalence =
      mean(observed_disability_prevalence, na.rm = TRUE),
    average_age_standardized_disability_rate =
      mean(age_standardized_disability_rate, na.rm = TRUE),
    share_with_simplified_built_form_input_imputed =
      mean(simplified_built_form_input_imputed, na.rm = TRUE),
    share_with_resident_service_needs_input_imputed =
      mean(resident_service_needs_input_imputed, na.rm = TRUE),
    share_with_base_policy_input_imputed =
      mean(base_policy_input_imputed, na.rm = TRUE),
    .groups = "drop"
  )

cluster_centers_scaled <- unweighted_centers %>%
  mutate(
    policy_cluster_label =
      unname(cluster_labels[as.character(cluster)]),
    .after = cluster
  )

# ---- Poverty demonstration overlay ------------------------------------------

poverty_crosstab <- policy_data %>%
  st_drop_geometry() %>%
  group_by(policy_cluster, policy_cluster_label) %>%
  summarise(
    tract_count = n(),
    poverty_universe = sum(poverty_total, na.rm = TRUE),
    population_below_poverty = sum(poverty_below, na.rm = TRUE),
    population_weighted_poverty_rate =
      population_below_poverty / poverty_universe,
    average_tract_poverty_rate = mean(poverty_rate, na.rm = TRUE),
    higher_poverty_tract_count = sum(higher_poverty_overlay, na.rm = TRUE),
    higher_poverty_tract_share = mean(higher_poverty_overlay, na.rm = TRUE),
    overlay_threshold = poverty_threshold,
    .groups = "drop"
  )

# Estimated counts support service planning after the place typology is formed.
# They do not enter k-means because tract counts would largely reproduce tract
# population size and boundary design rather than a neighborhood characteristic.
disability_service_crosstab <- policy_data %>%
  st_drop_geometry() %>%
  group_by(policy_cluster, policy_cluster_label) %>%
  summarise(
    tract_count = n(),
    disability_measure_universe =
      sum(disability_population_total, na.rm = TRUE),
    estimated_residents_with_disabilities =
      sum(disability_population_with, na.rm = TRUE),
    population_weighted_observed_disability_prevalence =
      estimated_residents_with_disabilities / disability_measure_universe,
    average_tract_observed_disability_prevalence =
      mean(observed_disability_prevalence, na.rm = TRUE),
    average_age_standardized_disability_rate =
      mean(age_standardized_disability_rate, na.rm = TRUE),
    .groups = "drop"
  )

# ---- Race/ethnicity demonstration overlay -----------------------------------

race_long <- policy_data %>%
  st_drop_geometry() %>%
  transmute(
    policy_cluster,
    policy_cluster_label,
    race_ethnicity_total,
    nh_white = nh_white_alone,
    nh_black = nh_black_alone,
    nh_asian = nh_asian_alone,
    hispanic_latino = hispanic_latino_any_race,
    other_multiracial = pmax(
      0,
      race_ethnicity_total -
        nh_white_alone -
        nh_black_alone -
        nh_asian_alone -
        hispanic_latino_any_race
    )
  ) %>%
  pivot_longer(
    c(
      nh_white, nh_black, nh_asian,
      hispanic_latino, other_multiracial
    ),
    names_to = "race_ethnicity_group",
    values_to = "population"
  ) %>%
  mutate(
    race_ethnicity_group = recode(
      race_ethnicity_group,
      nh_white = "Non-Hispanic White",
      nh_black = "Non-Hispanic Black",
      nh_asian = "Non-Hispanic Asian",
      hispanic_latino = "Hispanic or Latino",
      other_multiracial = "Other or multiracial"
    )
  )

overall_race_shares <- race_long %>%
  group_by(race_ethnicity_group) %>%
  summarise(population = sum(population, na.rm = TRUE), .groups = "drop") %>%
  mutate(overall_population_share = population / sum(population)) %>%
  select(race_ethnicity_group, overall_population_share)

race_ethnicity_crosstab <- race_long %>%
  group_by(
    policy_cluster,
    policy_cluster_label,
    race_ethnicity_group
  ) %>%
  summarise(population = sum(population, na.rm = TRUE), .groups = "drop") %>%
  group_by(policy_cluster, policy_cluster_label) %>%
  mutate(cluster_population_share = population / sum(population)) %>%
  ungroup() %>%
  left_join(overall_race_shares, by = "race_ethnicity_group") %>%
  mutate(
    representation_ratio =
      cluster_population_share / overall_population_share
  )

# Pool each overlay's numerator and ACS universe so the summaries answer how
# many residents are represented and what share of the relevant population
# they comprise. These weighted summaries describe cluster populations; the
# mapped tract rates remain unchanged and do not enter k-means.
equity_overlay_counts_by_cluster <- policy_data %>%
  st_drop_geometry() %>%
  group_by(policy_cluster, policy_cluster_label) %>%
  summarise(
    poverty_tract_count = sum(
      !is.na(poverty_total) & !is.na(poverty_below)
    ),
    poverty_universe = sum(poverty_total, na.rm = TRUE),
    population_below_poverty = sum(poverty_below, na.rm = TRUE),
    race_ethnicity_tract_count = sum(
      !is.na(race_ethnicity_total) & !is.na(nh_white_alone)
    ),
    race_ethnicity_universe = sum(race_ethnicity_total, na.rm = TRUE),
    people_of_color_population = sum(
      pmax(0, race_ethnicity_total - nh_white_alone),
      na.rm = TRUE
    ),
    .groups = "drop"
  )

equity_overlay_counts_overall <- policy_data %>%
  st_drop_geometry() %>%
  summarise(
    poverty_tract_count = sum(
      !is.na(poverty_total) & !is.na(poverty_below)
    ),
    poverty_universe = sum(poverty_total, na.rm = TRUE),
    population_below_poverty = sum(poverty_below, na.rm = TRUE),
    race_ethnicity_tract_count = sum(
      !is.na(race_ethnicity_total) & !is.na(nh_white_alone)
    ),
    race_ethnicity_universe = sum(race_ethnicity_total, na.rm = TRUE),
    people_of_color_population = sum(
      pmax(0, race_ethnicity_total - nh_white_alone),
      na.rm = TRUE
    )
  ) %>%
  mutate(
    policy_cluster = NA_integer_,
    policy_cluster_label = "All Austin tracts",
    .before = 1
  )

equity_overlay_counts <- bind_rows(
  equity_overlay_counts_by_cluster,
  equity_overlay_counts_overall
)

poverty_overlay_summary <- equity_overlay_counts %>%
  transmute(
    policy_cluster,
    policy_cluster_label,
    overlay = "Poverty",
    tract_count = poverty_tract_count,
    population_count = population_below_poverty,
    population_universe = poverty_universe,
    total_share = population_count / population_universe
  )

people_of_color_overlay_summary <- equity_overlay_counts %>%
  transmute(
    policy_cluster,
    policy_cluster_label,
    overlay = "People of color",
    tract_count = race_ethnicity_tract_count,
    population_count = people_of_color_population,
    population_universe = race_ethnicity_universe,
    total_share = population_count / population_universe
  )

equity_overlay_summary <- bind_rows(
  poverty_overlay_summary,
  people_of_color_overlay_summary
) %>%
  arrange(overlay, is.na(policy_cluster), policy_cluster)

# ---- Model and role summaries -----------------------------------------------

pca <- prcomp(weighted_scaled_matrix, center = FALSE, scale. = FALSE)
model_summary <- tibble(
  specification = paste(
    "Prespecified five-cluster policy typology with transparent",
    "domain-balanced built-form and observed resident-needs shares"
  ),
  complete_tracts = nrow(model_data),
  input_count = nrow(model_inputs),
  conceptual_domain_count = nrow(domain_weights),
  first_pc_variance_share = summary(pca)$importance[2, 1],
  silhouette_recommended_k =
    diagnostics$k[which.max(diagnostics$average_silhouette)],
  calinski_harabasz_recommended_k =
    diagnostics$k[which.max(diagnostics$calinski_harabasz)],
  gap_one_se_recommended_k = gap_one_se_k,
  prespecified_policy_k = selected_k,
  k5_average_silhouette =
    diagnostics$average_silhouette[diagnostics$k == selected_k],
  k5_calinski_harabasz =
    diagnostics$calinski_harabasz[diagnostics$k == selected_k],
  k5_stability_median_ari =
    diagnostics$subsample_stability_median_ari[
      diagnostics$k == selected_k
    ],
  k5_stability_p10_ari =
    diagnostics$subsample_stability_p10_ari[
      diagnostics$k == selected_k
    ],
  k5_smallest_cluster =
    diagnostics$smallest_cluster[diagnostics$k == selected_k],
  k5_smallest_cluster_share =
    diagnostics$smallest_cluster_share[diagnostics$k == selected_k],
  older_adult_disability_input_correlation = cor(
    model_data$older_adult_need_cluster,
    model_data$observed_disability_prevalence_cluster
  ),
  single_family_recent_construction_input_correlation = cor(
    model_data$single_family_share_cluster,
    model_data$recent_construction_share_cluster
  ),
  adjusted_rand_vs_age_standardized_sensitivity =
    specification_sensitivity$adjusted_rand_vs_primary[
      specification_sensitivity$specification ==
        "age_standardized_disability"
    ],
  adjusted_rand_vs_transformed_built_form_sensitivity =
    specification_sensitivity$adjusted_rand_vs_primary[
      specification_sensitivity$specification == "transformed_built_form"
    ],
  adjusted_rand_vs_preceding_proof_of_concept =
    specification_sensitivity$adjusted_rand_vs_primary[
      specification_sensitivity$specification ==
        "preceding_proof_of_concept"
    ],
  demonstration_overlay_count = 2,
  demonstration_overlays = "Poverty; race/ethnicity",
  service_planning_overlay = "Estimated residents with disabilities",
  poverty_used_in_clustering = FALSE,
  race_ethnicity_used_in_clustering = FALSE
)

overlay_roles <- tribble(
  ~indicator, ~role, ~interpretation,
  "Poverty rate",
  "Post-clustering overlay and cluster cross-tab",
  "Economic constraint is demonstrated without defining or naming clusters",
  "Race and ethnicity",
  "Post-clustering overlay and cluster cross-tab",
  "Population composition is demonstrated without defining or naming clusters",
  "Estimated residents with disabilities",
  "Post-clustering service-planning overlay",
  paste(
    "Counts show the potential scale of service demand without causing",
    "populous tracts to define the place typology"
  )
)

sensitivity_input_roles <- imap_dfr(
  sensitivity_specs,
  ~mutate(.x, specification = .y, .before = 1)
)

proof_of_concept_data <- policy_data %>%
  select(
    GEOID,
    any_of("NAME"),
    policy_cluster,
    policy_cluster_label,
    all_of(model_inputs$variable),
    median_home_value,
    median_rent,
    avg_household_size,
    children_household_share,
    transit_jobs_45min,
    hazard_facilities_1mi,
    annual_ksi_crash_density,
    single_family_structure_units,
    single_family_structure_share,
    single_family_share_reliable,
    low_intensity_structure_share,
    attached_small_structure_share,
    medium_large_structure_share,
    recent_2010_plus_share,
    recent_construction_share_reliable,
    older_adult_share,
    older_adult_reliable,
    disability_population_total,
    disability_population_with,
    observed_disability_prevalence,
    raw_disability_rate_moe,
    observed_disability_prevalence_reliable,
    age_standardized_disability_rate,
    base_policy_input_imputed,
    simplified_built_form_input_imputed,
    resident_service_needs_input_imputed,
    any_primary_input_imputed,
    poverty_total,
    poverty_below,
    poverty_rate,
    higher_poverty_overlay,
    race_ethnicity_total,
    nh_white_alone,
    nh_black_alone,
    nh_asian_alone,
    hispanic_latino_any_race,
    people_of_color_share,
    geometry
  )

qaqc_summary <- tribble(
  ~metric, ~value,
  "analysis_source_file", analysis_file,
  "clustered_tracts", as.character(nrow(policy_data)),
  "prespecified_cluster_count", as.character(selected_k),
  "minimum_cluster_size",
  as.character(min(cluster_profiles$tract_count)),
  "tracts_with_single_family_share_imputation",
  as.character(sum(!policy_data$single_family_share_reliable, na.rm = TRUE)),
  "tracts_with_recent_construction_share_imputation",
  as.character(sum(
    !policy_data$recent_construction_share_reliable,
    na.rm = TRUE
  )),
  "tracts_with_observed_disability_prevalence_imputation",
  as.character(sum(
    !policy_data$observed_disability_prevalence_reliable,
    na.rm = TRUE
  )),
  "tracts_with_base_policy_input_imputation",
  as.character(sum(policy_data$base_policy_input_imputed, na.rm = TRUE)),
  "tracts_with_any_primary_input_imputation",
  as.character(sum(policy_data$any_primary_input_imputed, na.rm = TRUE)),
  "tracts_missing_poverty_rate",
  as.character(sum(is.na(policy_data$poverty_rate))),
  "tracts_missing_race_ethnicity_overlay",
  as.character(sum(is.na(policy_data$people_of_color_share))),
  "poverty_overlay_threshold", as.character(poverty_threshold),
  "single_family_share_reliability_basis",
  paste(
    "Step-20 broad structure-composition screen; exact one-unit-share",
    "component MOE is not retained in the compact analytical file"
  ),
  "poverty_used_in_clustering", "false",
  "race_ethnicity_used_in_clustering", "false"
)

# ---- Maps and diagnostic figure ---------------------------------------------

cluster_boundaries <- policy_data %>%
  st_transform(5070) %>%
  group_by(policy_cluster_label) %>%
  summarise(.groups = "drop") %>%
  st_make_valid() %>%
  st_transform(st_crs(policy_data))

cluster_map <- ggplot(policy_data) +
  geom_sf(
    aes(fill = policy_cluster_label),
    color = "white",
    linewidth = 0.08
  ) +
  scale_fill_manual(
    values = cluster_palette,
    labels = ~str_wrap(.x, width = 30),
    drop = FALSE
  ) +
  labs(
    title = "Austin five-cluster policy typology",
    subtitle = paste(
      "Prespecified policy resolution using household, place, built-form,",
      "access, exposure, and service-needs dimensions"
    ),
    fill = NULL,
    caption = paste(
      "Poverty and race/ethnicity do not define or name the clusters;",
      "they are demonstrated separately as overlays."
    )
  ) +
  theme_void(base_size = 11) +
  theme(
    legend.position = "right",
    legend.title = element_blank(),
    legend.text = element_text(size = 8),
    legend.key.spacing.y = grid::unit(0.45, "cm")
  ) +
  guides(fill = guide_legend(ncol = 1, title = NULL))

poverty_map <- ggplot(policy_data) +
  geom_sf(aes(fill = poverty_rate), color = NA) +
  geom_sf(
    data = cluster_boundaries,
    fill = NA,
    color = "white",
    linewidth = overlay_cluster_boundary_linewidth
  ) +
  scale_fill_viridis_c(
    option = "C",
    labels = label_percent(accuracy = 1),
    name = "Poverty rate"
  ) +
  labs(
    title = "Poverty overlay",
    subtitle = "Displayed after clustering; white lines show policy clusters"
  ) +
  theme_void(base_size = 11) +
  theme(legend.position = "bottom")

race_map <- ggplot(policy_data) +
  geom_sf(aes(fill = people_of_color_share), color = NA) +
  geom_sf(
    data = cluster_boundaries,
    fill = NA,
    color = "white",
    linewidth = overlay_cluster_boundary_linewidth
  ) +
  scale_fill_viridis_c(
    option = "D",
    labels = label_percent(accuracy = 1),
    name = "People of color"
  ) +
  labs(
    title = "Race/ethnicity overlay",
    subtitle = "Displayed after clustering; white lines show policy clusters"
  ) +
  theme_void(base_size = 11) +
  theme(legend.position = "bottom")

equity_overlay_map <- poverty_map + race_map +
  plot_annotation(
    title = "Demonstration equity overlays",
    caption = paste(
      "Overlay values do not enter k-means and are not used to name",
      "or rank the policy clusters."
    )
  )

diagnostic_plot <- diagnostics %>%
  filter(k >= 2) %>%
  select(
    k, average_silhouette, calinski_harabasz,
    subsample_stability_median_ari
  ) %>%
  pivot_longer(-k, names_to = "diagnostic", values_to = "value") %>%
  filter(is.finite(value)) %>%
  mutate(
    diagnostic = recode(
      diagnostic,
      average_silhouette = "Average silhouette",
      calinski_harabasz = "Calinski-Harabasz",
      subsample_stability_median_ari =
        "80% subsample stability (median ARI)"
    )
  ) %>%
  ggplot(aes(k, value)) +
  geom_line(color = "#2c7fb8", linewidth = 0.8) +
  geom_point(color = "#2c7fb8", size = 1.8) +
  geom_vline(
    xintercept = selected_k,
    linetype = "dashed",
    color = "#d95f02"
  ) +
  facet_wrap(~diagnostic, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = 2:max(candidate_k)) +
  labs(
    title = "Policy-typology cluster diagnostics",
    subtitle = paste(
      "The dashed line marks the prespecified five-cluster",
      "policy resolution"
    ),
    x = "Number of clusters (k)",
    y = NULL
  ) +
  theme_minimal(base_size = 11)

ggsave(
  file.path(output_dir, "policy_typology_cluster_map.png"),
  cluster_map,
  width = 12,
  height = 8,
  dpi = 300,
  bg = "white"
)
ggsave(
  file.path(output_dir, "policy_typology_equity_overlays.png"),
  equity_overlay_map,
  width = 14,
  height = 7.5,
  dpi = 300,
  bg = "white"
)
ggsave(
  file.path(output_dir, "policy_typology_diagnostics.png"),
  diagnostic_plot,
  width = 9,
  height = 10,
  dpi = 300,
  bg = "white"
)

# ---- Write compact proof-of-concept deliverables ----------------------------

write_csv(
  st_drop_geometry(policy_data) %>%
    select(
      GEOID, policy_cluster, policy_cluster_label,
      higher_poverty_overlay, poverty_rate, people_of_color_share,
      disability_population_with, observed_disability_prevalence
    ),
  file.path(output_dir, "policy_typology_assignments.csv")
)
saveRDS(
  proof_of_concept_data,
  file.path(output_dir, "policy_typology_data.rds")
)
write_csv(
  cluster_profiles,
  file.path(output_dir, "policy_typology_cluster_profiles.csv")
)
write_csv(
  cluster_centers_scaled,
  file.path(output_dir, "policy_typology_cluster_centers_scaled.csv")
)
write_csv(
  diagnostics,
  file.path(output_dir, "policy_typology_diagnostics.csv")
)
write_csv(
  model_summary,
  file.path(output_dir, "policy_typology_model_summary.csv")
)
write_csv(
  model_inputs,
  file.path(output_dir, "policy_typology_indicator_roles.csv")
)
write_csv(
  domain_weights,
  file.path(output_dir, "policy_typology_domain_weights.csv")
)
write_csv(
  overlay_roles,
  file.path(output_dir, "policy_typology_overlay_roles.csv")
)
write_csv(
  sensitivity_input_roles,
  file.path(output_dir, "policy_typology_sensitivity_input_roles.csv")
)
write_csv(
  specification_sensitivity,
  file.path(output_dir, "policy_typology_specification_sensitivity.csv")
)
write_csv(
  poverty_crosstab,
  file.path(output_dir, "policy_typology_poverty_crosstab.csv")
)
write_csv(
  disability_service_crosstab,
  file.path(output_dir, "policy_typology_disability_service_crosstab.csv")
)
write_csv(
  race_ethnicity_crosstab,
  file.path(output_dir, "policy_typology_race_ethnicity_crosstab.csv")
)
write_csv(
  equity_overlay_summary,
  file.path(output_dir, "policy_typology_equity_overlay_summary.csv")
)
write_csv(
  poverty_overlay_summary,
  file.path(output_dir, "policy_typology_poverty_overlay_summary.csv")
)
write_csv(
  people_of_color_overlay_summary,
  file.path(output_dir, "policy_typology_people_of_color_overlay_summary.csv")
)
write_csv(
  qaqc_summary,
  file.path(output_dir, "policy_typology_qaqc_summary.csv")
)

cat("\nFive-cluster proof of concept complete.\n")
print(model_summary, width = Inf)
cat("\nCluster sizes and labels:\n")
print(
  cluster_profiles %>%
    select(policy_cluster, policy_cluster_label, tract_count),
  n = Inf
)
cat("\nOutputs written under ", output_dir, "/.\n", sep = "")
