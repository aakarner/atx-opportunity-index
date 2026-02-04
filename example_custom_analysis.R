# Example: Custom Analysis using Configuration File
# This example shows how to use the config.R file for customization

# Load configuration
source("config.R")

# Load required libraries
library(tidycensus)
library(tidyverse)
library(tigris)
library(sf)

# Set options
options(tigris_use_cache = TRUE)

# Set Census API key if defined in config
# Uncomment and set in config.R:
# census_api_key(CENSUS_API_KEY, install = TRUE)

# Example 1: Pull data using configuration settings
cat("Example: Pulling census data with custom configuration...\n")

# Use configuration variables
census_data <- get_acs(
  geography = "tract",
  variables = CENSUS_VARIABLES,
  state = STATE,
  county = COUNTIES,
  year = YEAR,
  survey = SURVEY,
  geometry = TRUE,
  output = "wide"
)

cat("Successfully pulled data for", nrow(census_data), "census tracts\n")

# Example 2: Custom opportunity index with weights
cat("\nExample: Calculating weighted opportunity index...\n")

# Clean data
census_data_clean <- census_data %>%
  select(-ends_with("M")) %>%
  rename_with(~str_remove(., "E$"), ends_with("E"))

# Calculate weighted opportunity scores
census_data_weighted <- census_data_clean %>%
  mutate(
    # Normalize each component
    econ_norm = scale(median_income)[,1],
    edu_norm = scale(bachelors_or_higher + graduate_degree)[,1],
    housing_norm = -scale(median_home_value + median_rent)[,1],
    access_norm = scale(vehicle_access + health_insurance)[,1],
    
    # Apply weights from config
    opportunity_index = (
      econ_norm * WEIGHT_ECONOMIC +
      edu_norm * WEIGHT_EDUCATION +
      housing_norm * WEIGHT_HOUSING +
      access_norm * WEIGHT_ACCESS
    )
  )

cat("Opportunity index calculated using weights:\n")
cat("  Economic:", WEIGHT_ECONOMIC, "\n")
cat("  Education:", WEIGHT_EDUCATION, "\n")
cat("  Housing:", WEIGHT_HOUSING, "\n")
cat("  Access:", WEIGHT_ACCESS, "\n")

# Example 3: K-means with custom cluster number
cat("\nExample: K-means clustering with", NUM_CLUSTERS, "clusters...\n")

cluster_data <- census_data_weighted %>%
  st_drop_geometry() %>%
  select(median_income, bachelors_or_higher, graduate_degree,
         median_home_value, median_rent, vehicle_access, health_insurance) %>%
  na.omit()

cluster_data_scaled <- scale(cluster_data)

set.seed(RANDOM_SEED)
kmeans_result <- kmeans(cluster_data_scaled, 
                       centers = NUM_CLUSTERS, 
                       nstart = NSTART)

cat("Clustering complete. Cluster sizes:\n")
print(table(kmeans_result$cluster))

# Example 4: Custom map with configuration colors
cat("\nExample: Creating map with custom colors...\n")

census_data_final <- census_data_weighted %>%
  filter(!is.na(median_income) & !is.na(opportunity_index)) %>%
  mutate(cluster = as.factor(kmeans_result$cluster))

custom_map <- ggplot(census_data_final) +
  geom_sf(aes(fill = opportunity_index), color = NA) +
  scale_fill_gradient2(
    low = COLOR_LOW,
    mid = COLOR_MID,
    high = COLOR_HIGH,
    midpoint = 0,
    name = "Opportunity\nIndex"
  ) +
  labs(
    title = paste("Opportunity Index -", paste(COUNTIES, collapse = ", "), "County"),
    subtitle = paste("ACS", YEAR, SURVEY, "estimates")
  ) +
  theme_minimal()

# Save with configuration settings
if (SAVE_PLOTS) {
  ggsave(
    "example_custom_map.png", 
    custom_map, 
    width = MAP_WIDTH, 
    height = MAP_HEIGHT, 
    dpi = MAP_DPI
  )
  cat("Map saved to example_custom_map.png\n")
}

cat("\n=== Example Complete ===\n")
cat("See config.R to customize analysis parameters\n")
