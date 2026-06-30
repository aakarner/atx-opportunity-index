# Austin Opportunity Index Analysis
# This script pulls census data for Austin, TX, performs k-means clustering,
# and creates visualizations using ggplot and tigris

# Load required libraries
library(tidycensus)
library(tidyverse)
library(tigris)
library(sf)
library(h3jsr)

# Set options
options(tigris_use_cache = TRUE)

acs_year <- 2019
city_boundary_year <- 2024
analysis_counties <- c("Travis", "Williamson", "Hays")
transit_threshold_minutes <- 45
accessibility_file <- "accessibility/output/h8_job_accessibility.csv"
accessibility_equal_area_crs <- 5070
output_dir <- "output"

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Define variables for opportunity index
# Using American Community Survey 5-year estimates
census_vars <- c(
  # Economic opportunity indicators
  median_income = "B19013_001",      # Median household income
  poverty_total = "B17001_001",      # Poverty universe
  poverty_below = "B17001_002",      # Population below poverty level
  labor_force = "B23025_002",        # Labor force
  employed = "B23025_004",           # Employed population
  
  # Educational opportunity indicators
  education_total = "B15003_001",    # Population 25 years and over
  bachelors = "B15003_022",          # Bachelor's degree
  masters = "B15003_023",            # Master's degree
  professional = "B15003_024",       # Professional school degree
  doctorate = "B15003_025",          # Doctorate degree
  
  # Housing opportunity indicators
  median_home_value = "B25077_001",   # Median home value
  median_rent = "B25064_001",         # Median gross rent

  # Family and household indicators
  households_total = "B11005_001",     # Total households
  households_with_children = "B11005_002", # Households with people under 18
  avg_household_size = "B25010_001",   # Average household size
  
  # Transportation context
  no_vehicle_households = "B08201_002" # Households with no vehicle available
)

# Pull census data for the three counties that contain the City of Austin.
# The tract proof of concept retains its 2019 ACS vintage for a controlled
# comparison while replacing only the legacy accessibility measure. The final
# H8 analysis will use the 2024 ACS integration target.
cat(
  "Pulling ACS data for ",
  str_c(analysis_counties, collapse = ", "),
  " counties, TX...\n",
  sep = ""
)

census_data <- map(
  analysis_counties,
  ~ get_acs(
    geography = "tract",
    variables = census_vars,
    state = "TX",
    county = .x,
    year = acs_year,
    survey = "acs5",
    geometry = TRUE,
    output = "wide"
  )
) %>%
  bind_rows()

# Use a recent municipal boundary so the analysis covers the full City of
# Austin, including portions in Williamson and Hays counties.
cat("Pulling City of Austin boundary...\n")

austin_boundary <- places(
  state = "TX",
  year = city_boundary_year
) %>%
  filter(NAME == "Austin") %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(austin_boundary) != 1) {
  stop("Expected exactly one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

cat("Reading H8 job accessibility results...\n")

if (!file.exists(accessibility_file)) {
  stop(
    "Missing ", accessibility_file,
    ". Run the accessibility pipeline through weighted_job_accessibility.R first."
  )
}

h8_access <- read_csv(accessibility_file, show_col_types = FALSE)

required_access_columns <- c(
  "h3_id", "access_total_jobs", "workers_all",
  "network_snapshot", "gtfs_snapshot", "jobs_year"
)
missing_access_columns <- setdiff(required_access_columns, names(h8_access))

if (length(missing_access_columns) > 0) {
  stop(
    "The H8 accessibility output is missing: ",
    str_c(missing_access_columns, collapse = ", "),
    ". Rerun accessibility/03-analysis/weighted_job_accessibility.R."
  )
}

access_jobs_year <- unique(h8_access$jobs_year)
network_snapshot <- unique(h8_access$network_snapshot)
gtfs_snapshot <- unique(h8_access$gtfs_snapshot)

if (
  length(access_jobs_year) != 1 ||
  length(network_snapshot) != 1 ||
  length(gtfs_snapshot) != 1
) {
  stop("Expected one jobs year and one network/GTFS snapshot in the H8 output.")
}

access_snapshot_label <- if_else(
  network_snapshot == gtfs_snapshot,
  paste0("GTFS/OSM snapshot ", network_snapshot),
  paste0(
    "GTFS snapshot ", gtfs_snapshot,
    "; OSM snapshot ", network_snapshot
  )
)

# Clean column names and prepare data
cat("Cleaning and preparing data...\n")

census_data_clean <- census_data %>%
  select(-ends_with("M")) %>%  # Remove margin of error columns
  rename_with(~str_remove(., "E$"), ends_with("E") & !all_of("NAME")) %>%
  st_transform(4326)  # Transform to WGS84 for mapping

county_tract_count <- nrow(census_data_clean)

# Clipping changes tract geometry only; ACS attributes remain tract-level
# estimates and are not re-estimated for the portion inside the city.
census_data_clean <- suppressWarnings(
  census_data_clean %>%
    st_filter(austin_boundary, .predicate = st_intersects) %>%
    st_intersection(st_geometry(austin_boundary))
) %>%
  st_make_valid()

cat(
  "Clipped ",
  county_tract_count,
  " three-county tracts to ",
  nrow(census_data_clean),
  " tracts intersecting the City of Austin boundary.\n",
  sep = ""
)

# Aggregate origin-level H8 accessibility to clipped census tracts. H8
# resident-worker counts are apportioned to tract intersections by area and
# used as weights. If an intersecting tract has no resident-worker weight, use
# overlap area instead. Because the H8 origin set is center-in-polygon, a small
# number of City-boundary tract fragments may not intersect an origin hex;
# assign those the nearest H8 origin as a transparent validation fallback.
cat("Aggregating H8 accessibility to census tracts...\n")

h8_access_sf <- st_sf(
  h8_access,
  geometry = cell_to_polygon(h8_access$h3_id),
  crs = 4326
) %>%
  st_make_valid() %>%
  st_transform(accessibility_equal_area_crs) %>%
  mutate(h8_area_m2 = as.numeric(st_area(geometry)))

tracts_equal_area <- census_data_clean %>%
  select(GEOID) %>%
  st_transform(accessibility_equal_area_crs)

tract_h8_overlap <- suppressWarnings(
  st_intersection(
    tracts_equal_area,
    h8_access_sf %>%
      select(h3_id, access_total_jobs, workers_all, h8_area_m2)
  )
) %>%
  mutate(
    overlap_area_m2 = as.numeric(st_area(geometry)),
    h8_area_share = overlap_area_m2 / h8_area_m2,
    allocated_workers = workers_all * h8_area_share
  )

tract_access <- tract_h8_overlap %>%
  st_drop_geometry() %>%
  group_by(GEOID) %>%
  summarise(
    access_h8_cells = n_distinct(h3_id),
    access_worker_weight = sum(allocated_workers, na.rm = TRUE),
    access_overlap_area_m2 = sum(overlap_area_m2, na.rm = TRUE),
    worker_weighted_access = if_else(
      access_worker_weight > 0,
      sum(access_total_jobs * allocated_workers, na.rm = TRUE) /
        access_worker_weight,
      NA_real_
    ),
    area_weighted_access = weighted.mean(
      access_total_jobs,
      overlap_area_m2,
      na.rm = TRUE
    ),
    transit_jobs_45min = coalesce(
      worker_weighted_access,
      area_weighted_access
    ),
    access_aggregation_method = if_else(
      access_worker_weight > 0,
      "area-apportioned resident-worker weighted H8 mean",
      "area-weighted H8 mean"
    ),
    .groups = "drop"
  ) %>%
  select(
    GEOID, access_h8_cells, access_worker_weight,
    access_overlap_area_m2, transit_jobs_45min,
    access_aggregation_method
  )

tracts_without_h8_overlap <- tracts_equal_area %>%
  anti_join(tract_access, by = "GEOID")

if (nrow(tracts_without_h8_overlap) > 0) {
  nearest_h8_index <- st_nearest_feature(
    tracts_without_h8_overlap,
    h8_access_sf
  )

  nearest_h8_access <- h8_access_sf[nearest_h8_index, ] %>%
    st_drop_geometry()

  nearest_tract_access <- tibble(
    GEOID = tracts_without_h8_overlap$GEOID,
    access_h8_cells = 1L,
    access_worker_weight = nearest_h8_access$workers_all,
    access_overlap_area_m2 = 0,
    transit_jobs_45min = nearest_h8_access$access_total_jobs,
    access_aggregation_method = "nearest H8 origin fallback"
  )

  tract_access <- bind_rows(tract_access, nearest_tract_access)
}

census_data_clean <- census_data_clean %>%
  left_join(tract_access, by = "GEOID")

cat(
  "H8 access assigned to ",
  sum(!is.na(census_data_clean$transit_jobs_45min)),
  " of ",
  nrow(census_data_clean),
  " ACS tracts; ",
  sum(census_data_clean$access_aggregation_method == "nearest H8 origin fallback"),
  " used the boundary fallback.\n",
  sep = ""
)

impute_median <- function(x) {
  replace_na(x, median(x, na.rm = TRUE))
}

# Calculate opportunity index components
# Normalize variables (higher values = more opportunity)
cat("Calculating opportunity index components...\n")

census_data_normalized <- census_data_clean %>%
  mutate(
    poverty_rate = poverty_below / poverty_total,
    employment_rate = employed / labor_force,
    educational_attainment = (bachelors + masters + professional + doctorate) / education_total,
    children_household_share = households_with_children / households_total,
    no_vehicle_share = no_vehicle_households / households_total,
    log_transit_jobs_45min = log1p(transit_jobs_45min),
    missing_cluster_input = if_any(
      c(
        median_income, poverty_rate, employment_rate, educational_attainment,
        median_home_value, median_rent, avg_household_size,
        children_household_share, no_vehicle_share, transit_jobs_45min
      ),
      is.na
    ),
    across(
      c(
        median_income, poverty_rate, employment_rate, educational_attainment,
        median_home_value, median_rent, avg_household_size,
        children_household_share, no_vehicle_share, log_transit_jobs_45min
      ),
      impute_median,
      .names = "{.col}_cluster"
    ),
    housing_cost_cluster = scale(median_home_value_cluster + median_rent_cluster)[,1],

    # Economic opportunity (normalize to 0-1 scale)
    econ_score = (
      scale(median_income_cluster)[,1] -
      scale(poverty_rate_cluster)[,1] +
      scale(employment_rate_cluster)[,1]
    ) / 3,
    
    # Education opportunity
    edu_score = scale(educational_attainment_cluster)[,1],
    
    # Housing affordability (inverse - lower costs = more opportunity)
    housing_score = -housing_cost_cluster,
    
    # Family and access scores
    family_score = (
      scale(avg_household_size_cluster)[,1] +
      scale(children_household_share_cluster)[,1]
    ) / 2,
    access_score = (
      scale(log_transit_jobs_45min_cluster)[,1] +
      scale(no_vehicle_share_cluster)[,1]
    ) / 2,
    
    # Overall opportunity index (average of components)
    opportunity_index = (econ_score + edu_score + housing_score + family_score + access_score) / 5
  )

# Prepare data for k-means clustering
# Extract only the numeric variables for clustering
cluster_vars <- c(
  "median_income_cluster", "poverty_rate_cluster", "employment_rate_cluster",
  "educational_attainment_cluster", "housing_cost_cluster",
  "avg_household_size_cluster", "children_household_share_cluster",
  "no_vehicle_share_cluster", "log_transit_jobs_45min_cluster"
)

census_data_normalized <- census_data_normalized %>%
  mutate(cluster_complete = complete.cases(across(all_of(cluster_vars))))

cluster_data <- census_data_normalized %>%
  filter(cluster_complete) %>%
  st_drop_geometry() %>%
  select(all_of(cluster_vars))

# Scale the data for k-means
cluster_data_scaled <- scale(cluster_data)

# Determine optimal number of clusters using elbow method
cat("Determining optimal number of clusters...\n")

set.seed(123)
wss <- sapply(1:10, function(k) {
  kmeans(cluster_data_scaled, centers = k, nstart = 25)$tot.withinss
})

# Perform k-means clustering with 5 clusters
cat("Performing k-means clustering...\n")

set.seed(123)
kmeans_result <- kmeans(cluster_data_scaled, centers = 5, nstart = 25)

# Plausible descriptive labels for the 5-cluster solution. These are based on
# the observed tract proof-of-concept profiles and preserve the numeric IDs.
cluster_labels <- c(
  "1" = "High-Income Family Enclaves",
  "2" = "Large-Household Lower-Cost Areas",
  "3" = "Transit-Rich Lower-Income Corridors",
  "4" = "Transit-Rich Educated Core",
  "5" = "Middle-Income Mixed Neighborhoods"
)

cluster_palette <- c(
  "High-Income Family Enclaves" = "#1b9e77",
  "Transit-Rich Lower-Income Corridors" = "#d95f02",
  "Transit-Rich Educated Core" = "#7570b3",
  "Middle-Income Mixed Neighborhoods" = "#e7298a",
  "Large-Household Lower-Cost Areas" = "#66a61e",
  "Not clustered / missing ACS estimate" = "#d9d9d9"
)

cluster_assignments <- rep(NA_character_, nrow(census_data_normalized))
cluster_assignments[census_data_normalized$cluster_complete] <- as.character(kmeans_result$cluster)

# Add cluster assignments back to the spatial data
census_data_clustered <- census_data_normalized %>%
  mutate(
    cluster = factor(cluster_assignments, levels = names(cluster_labels)),
    cluster_label = factor(
      if_else(
        is.na(cluster),
        "Not clustered / missing ACS estimate",
        cluster_labels[as.character(cluster)]
      ),
      levels = names(cluster_palette)
    )
  )

# Create visualizations
cat("Creating visualizations...\n")

# 1. Elbow plot for cluster selection
elbow_plot <- ggplot(data.frame(k = 1:10, wss = wss), aes(x = k, y = wss)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue", size = 3) +
  labs(
    title = "Elbow Method for Optimal K",
    x = "Number of Clusters",
    y = "Within-Cluster Sum of Squares"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14)
  )

# 2. Opportunity Index Map
opportunity_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = opportunity_index), color = NA) +
  scale_fill_gradient2(
    low = "#d73027",
    mid = "#ffffbf",
    high = "#1a9850",
    midpoint = 0,
    name = "Opportunity\nIndex",
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Austin Opportunity Index by Census Tract",
    subtitle = "Based on economic, educational, housing, family, and transit access indicators",
    caption = paste0(
      "Data: ACS ", acs_year, " 5-Year Estimates; ",
      access_jobs_year, " LODES jobs; CapMetro ", access_snapshot_label
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 3. K-means Cluster Map
cluster_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = cluster_label), color = "white", linewidth = 0.1) +
  scale_fill_manual(
    values = cluster_palette,
    name = "Cluster Profile"
  ) +
  labs(
    title = "Austin Census Tract Opportunity Profiles",
    subtitle = "Five-cluster solution based on income, education, housing, family, vehicle, and transit indicators",
    caption = paste0(
      "Data: ACS ", acs_year, " 5-Year Estimates; ",
      access_jobs_year, " LODES jobs; CapMetro ", access_snapshot_label
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank(),
    legend.position = c(0.04, 0.08),
    legend.justification = c(0, 0),
    legend.background = element_rect(fill = "white", color = NA)
  )

# 4. Median Income Map
income_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = median_income), color = NA) +
  scale_fill_viridis_c(
    option = "plasma",
    name = "Median\nIncome ($)",
    labels = scales::comma,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Median Household Income by Census Tract",
    subtitle = "City of Austin, Texas",
    caption = paste0("Data: ACS ", acs_year, " 5-Year Estimates")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 5. Transit Access Map
transit_access_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = transit_jobs_45min), color = NA) +
  scale_fill_viridis_c(
    option = "mako",
    name = paste0("Jobs by Transit\nwithin ", transit_threshold_minutes, " min"),
    labels = scales::comma,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Transit Access to Jobs by Census Tract",
    subtitle = paste0(
      "H8 access aggregated primarily with resident-worker weights; ",
      transit_threshold_minutes, "-minute walk-plus-transit threshold"
    ),
    caption = paste0(
      "Data: ", access_jobs_year,
      " LODES jobs; CapMetro ", access_snapshot_label
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 6. Households with Children Map
family_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = children_household_share), color = NA) +
  scale_fill_viridis_c(
    option = "viridis",
    name = "Households\nwith Children",
    labels = scales::percent,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Households with Children by Census Tract",
    subtitle = "Share of households with people under 18",
    caption = paste0("Data: ACS ", acs_year, " 5-Year Estimates")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# Save plots
cat("Saving plots...\n")

ggsave(file.path(output_dir, "elbow_plot.png"), elbow_plot, width = 10, height = 6, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "opportunity_index_map.png"), opportunity_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "cluster_map.png"), cluster_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "income_map.png"), income_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "transit_access_map.png"), transit_access_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "family_map.png"), family_map, width = 12, height = 10, dpi = 300, bg = "white")

# Print cluster statistics
cat("\n=== Cluster Statistics ===\n")
cluster_stats <- census_data_clustered %>%
  st_drop_geometry() %>%
  filter(!is.na(cluster)) %>%
  group_by(cluster, cluster_label) %>%
  summarise(
    n_tracts = n(),
    avg_income = mean(median_income, na.rm = TRUE),
    avg_poverty_rate = mean(poverty_rate, na.rm = TRUE),
    avg_education = mean(educational_attainment, na.rm = TRUE),
    avg_home_value = mean(median_home_value, na.rm = TRUE),
    avg_household_size = mean(avg_household_size, na.rm = TRUE),
    avg_children_household_share = mean(children_household_share, na.rm = TRUE),
    avg_no_vehicle_share = mean(no_vehicle_share, na.rm = TRUE),
    avg_transit_jobs_45min = mean(transit_jobs_45min, na.rm = TRUE),
    avg_opportunity = mean(opportunity_index, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(avg_opportunity))

print(cluster_stats)

# Save data
cat("\nSaving processed data...\n")
saveRDS(census_data_clustered, file.path(output_dir, "austin_opportunity_data.rds"))
write_csv(
  census_data_clustered %>% st_drop_geometry(), 
  file.path(output_dir, "austin_opportunity_data.csv")
)

cat("\n=== Analysis Complete ===\n")
cat("Output files created:\n")
cat("  - output/elbow_plot.png\n")
cat("  - output/opportunity_index_map.png\n")
cat("  - output/cluster_map.png\n")
cat("  - output/income_map.png\n")
cat("  - output/transit_access_map.png\n")
cat("  - output/family_map.png\n")
cat("  - output/austin_opportunity_data.rds\n")
cat("  - output/austin_opportunity_data.csv\n")
