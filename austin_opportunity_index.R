# Austin Opportunity Index Analysis
# This script pulls census data for Austin, TX, performs k-means clustering,
# and creates visualizations using ggplot and tigris

# Load required libraries
library(tidycensus)
library(tidyverse)
library(tigris)
library(sf)

# Set options
options(tigris_use_cache = TRUE)

acs_year <- 2019
transit_year <- 2021
transit_threshold_seconds <- 2700
transit_threshold_minutes <- transit_threshold_seconds / 60
transit_file <- "data/Texas_transit_2021.zip"
transit_member <- "Texas_transit_2021/Texas_48_transit_census_tract_2021.csv"
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

# Pull census data for Travis County (Austin's primary county).
# The 2021 Observatory file uses 2010-vintage tract GEOIDs; 2019 ACS 5-year
# estimates are the most recent ACS release here that align to that geography.
cat("Pulling ACS data for Travis County, TX...\n")

census_data <- get_acs(
  geography = "tract",
  variables = census_vars,
  state = "TX",
  county = "Travis",
  year = acs_year,
  survey = "acs5",
  geometry = TRUE,
  output = "wide"
)

cat("Reading University of Minnesota Accessibility Observatory transit data...\n")

transit_access <- read_csv(
  unz(transit_file, transit_member),
  col_types = cols(geoid = col_character(), .default = col_guess())
) %>%
  filter(threshold == transit_threshold_seconds) %>%
  transmute(
    GEOID = str_pad(geoid, 11, pad = "0"),
    transit_jobs_45min = weighted_average
  )

# Clean column names and prepare data
cat("Cleaning and preparing data...\n")

census_data_clean <- census_data %>%
  select(-ends_with("M")) %>%  # Remove margin of error columns
  rename_with(~str_remove(., "E$"), ends_with("E") & !all_of("NAME")) %>%
  st_transform(4326) %>%  # Transform to WGS84 for mapping
  left_join(transit_access, by = "GEOID")

cat(
  "Transit access matched ",
  sum(!is.na(census_data_clean$transit_jobs_45min)),
  " of ",
  nrow(census_data_clean),
  " ACS tracts.\n",
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
# the observed 2021 ACS cluster profiles and preserve the numeric cluster IDs.
cluster_labels <- c(
  "1" = "High-Income Family Enclaves",
  "2" = "Transit-Rich Lower-Income Corridors",
  "3" = "Transit-Rich Educated Core",
  "4" = "Middle-Income Mixed Neighborhoods",
  "5" = "Large-Household Lower-Cost Areas"
)

cluster_palette <- c(
  "High-Income Family Enclaves" = "#66c2a5",
  "Transit-Rich Lower-Income Corridors" = "#fc8d62",
  "Transit-Rich Educated Core" = "#8da0cb",
  "Middle-Income Mixed Neighborhoods" = "#e78ac3",
  "Large-Household Lower-Cost Areas" = "#a6d854",
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
      "University of Minnesota Accessibility Observatory ", transit_year,
      " transit access, ", transit_threshold_minutes, "-minute threshold"
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
      "University of Minnesota Accessibility Observatory ", transit_year,
      " transit access, ", transit_threshold_minutes, "-minute threshold"
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
    subtitle = "Travis County, Texas",
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
    subtitle = paste0("Worker-weighted reachable jobs within ", transit_threshold_minutes, " minutes by transit"),
    caption = paste0(
      "Data: University of Minnesota Accessibility Observatory ",
      transit_year,
      " transit access"
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
