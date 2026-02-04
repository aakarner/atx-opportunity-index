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

# Define variables for opportunity index
# Using American Community Survey 5-year estimates
census_vars <- c(
  # Economic opportunity indicators
  median_income = "B19013_001",      # Median household income
  poverty_rate = "B17001_002",       # Population below poverty level
  employment_rate = "B23025_004",    # Employed population
  
  # Educational opportunity indicators
  bachelors_or_higher = "B15003_022", # Bachelor's degree
  graduate_degree = "B15003_023",     # Graduate or professional degree
  
  # Housing opportunity indicators
  median_home_value = "B25077_001",   # Median home value
  median_rent = "B25064_001",         # Median gross rent
  
  # Transportation access
  vehicle_access = "B08201_002",      # Households with 1+ vehicles
  
  # Health insurance coverage
  health_insurance = "B27001_004"     # Population with health insurance
)

# Pull census data for Travis County (Austin's primary county)
# Using tract-level data for detailed spatial analysis
cat("Pulling census data for Travis County, TX...\n")

census_data <- get_acs(
  geography = "tract",
  variables = census_vars,
  state = "TX",
  county = "Travis",
  year = 2021,
  survey = "acs5",
  geometry = TRUE,
  output = "wide"
)

# Clean column names and prepare data
cat("Cleaning and preparing data...\n")

census_data_clean <- census_data %>%
  select(-ends_with("M")) %>%  # Remove margin of error columns
  rename_with(~str_remove(., "E$"), ends_with("E")) %>%  # Remove E suffix
  st_transform(4326)  # Transform to WGS84 for mapping

# Calculate opportunity index components
# Normalize variables (higher values = more opportunity)
cat("Calculating opportunity index components...\n")

census_data_normalized <- census_data_clean %>%
  mutate(
    # Economic opportunity (normalize to 0-1 scale)
    econ_score = scale(median_income)[,1],
    
    # Education opportunity
    edu_score = scale(bachelors_or_higher + graduate_degree)[,1],
    
    # Housing affordability (inverse - lower costs = more opportunity)
    housing_score = -scale(median_home_value + median_rent)[,1],
    
    # Access score
    access_score = scale(vehicle_access + health_insurance)[,1],
    
    # Overall opportunity index (average of components)
    opportunity_index = (econ_score + edu_score + housing_score + access_score) / 4
  )

# Prepare data for k-means clustering
# Extract only the numeric variables for clustering
cluster_data <- census_data_normalized %>%
  st_drop_geometry() %>%
  select(median_income, bachelors_or_higher, graduate_degree, 
         median_home_value, median_rent, vehicle_access, health_insurance) %>%
  na.omit()

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

# Add cluster assignments back to the spatial data
census_data_clustered <- census_data_normalized %>%
  filter(!is.na(median_income) & !is.na(bachelors_or_higher) & 
         !is.na(graduate_degree) & !is.na(median_home_value) & 
         !is.na(median_rent) & !is.na(vehicle_access) & 
         !is.na(health_insurance)) %>%
  mutate(cluster = as.factor(kmeans_result$cluster))

# Create visualizations
cat("Creating visualizations...\n")

# 1. Elbow plot for cluster selection
elbow_plot <- ggplot(data.frame(k = 1:10, wss = wss), aes(x = k, y = wss)) +
  geom_line(color = "steelblue", size = 1) +
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
    name = "Opportunity\nIndex"
  ) +
  labs(
    title = "Austin Opportunity Index by Census Tract",
    subtitle = "Based on Economic, Educational, Housing, and Access Indicators",
    caption = "Data: American Community Survey 2021 5-Year Estimates"
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
  geom_sf(aes(fill = cluster), color = "white", size = 0.1) +
  scale_fill_brewer(
    palette = "Set2",
    name = "Cluster"
  ) +
  labs(
    title = "K-Means Clusters of Austin Census Tracts",
    subtitle = "5 Clusters Based on Opportunity Indicators",
    caption = "Data: American Community Survey 2021 5-Year Estimates"
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
    labels = scales::comma
  ) +
  labs(
    title = "Median Household Income by Census Tract",
    subtitle = "Travis County, Texas",
    caption = "Data: American Community Survey 2021 5-Year Estimates"
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

ggsave("elbow_plot.png", elbow_plot, width = 10, height = 6, dpi = 300)
ggsave("opportunity_index_map.png", opportunity_map, width = 12, height = 10, dpi = 300)
ggsave("cluster_map.png", cluster_map, width = 12, height = 10, dpi = 300)
ggsave("income_map.png", income_map, width = 12, height = 10, dpi = 300)

# Print cluster statistics
cat("\n=== Cluster Statistics ===\n")
cluster_stats <- census_data_clustered %>%
  st_drop_geometry() %>%
  group_by(cluster) %>%
  summarise(
    n_tracts = n(),
    avg_income = mean(median_income, na.rm = TRUE),
    avg_education = mean(bachelors_or_higher + graduate_degree, na.rm = TRUE),
    avg_home_value = mean(median_home_value, na.rm = TRUE),
    avg_opportunity = mean(opportunity_index, na.rm = TRUE)
  ) %>%
  arrange(desc(avg_opportunity))

print(cluster_stats)

# Save data
cat("\nSaving processed data...\n")
saveRDS(census_data_clustered, "austin_opportunity_data.rds")
write_csv(
  census_data_clustered %>% st_drop_geometry(), 
  "austin_opportunity_data.csv"
)

cat("\n=== Analysis Complete ===\n")
cat("Output files created:\n")
cat("  - elbow_plot.png\n")
cat("  - opportunity_index_map.png\n")
cat("  - cluster_map.png\n")
cat("  - income_map.png\n")
cat("  - austin_opportunity_data.rds\n")
cat("  - austin_opportunity_data.csv\n")
