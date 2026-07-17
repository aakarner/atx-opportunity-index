# Optional configuration for 21_example_custom_analysis.R.
# This file controls only the optional step-21 reanalysis of the step-20
# reference model. The submitted proof of concept is configured directly in
# 22_policy_typology_proof_of_concept.R.

# Census API Configuration
# Get your API key from: https://api.census.gov/data/key_signup.html
# CENSUS_API_KEY <- "YOUR_API_KEY_HERE"

# Geographic Scope
YEAR <- 2024              # ACS release used by the optional step-21 example
SURVEY <- "acs5"          # "acs1" (1-year) or "acs5" (5-year estimates)
STATE <- "TX"             # State abbreviation
COUNTIES <- c("Travis", "Williamson", "Hays")

# Clustering Parameters
NUM_CLUSTERS <- 5         # Number of k-means clusters
RANDOM_SEED <- 123        # Random seed for reproducibility
NSTART <- 25             # Number of random starts for k-means

# Census variables shown here support the optional step-21 example; this is not
# the complete registry used by step 20 or the submitted step-22 analysis. In
# step 20, poverty remains an overlay for the reference model but also enters a
# separately labeled unified resident-context sensitivity family.
# Find variables at: https://api.census.gov/data/2024/acs/acs5/variables.html

CENSUS_VARIABLES <- c(
  # Step-20 reference-model social and economic overlays
  "median_income" = "B19013_001",        # Median household income
  "poverty_total" = "B17001_001",         # Poverty universe
  "poverty_below" = "B17001_002",         # Below poverty level
  "labor_force" = "B23025_002",           # Civilian labor force
  "employed" = "B23025_004",              # Employed population
  "education_total" = "B15003_001",       # Population age 25+
  "bachelors" = "B15003_022",             # Bachelor's degree
  "masters" = "B15003_023",               # Master's degree
  "professional" = "B15003_024",          # Professional degree
  "doctorate" = "B15003_025",             # Doctorate degree
  "no_vehicle_households" = "B08201_002", # No vehicle available

  # Cluster-defining housing and family/service-fit indicators
  "median_home_value" = "B25077_001",    # Median home value
  "median_rent" = "B25064_001",          # Median gross rent
  "households_total" = "B11005_001",     # Total households
  "households_with_children" = "B11005_002", # Households with children
  "avg_household_size" = "B25010_001"    # Average household size
)

# Relative overlay/filter threshold. A value of 0.25 flags the lower quartile
# for income, employment, and education and the upper quartile for poverty and
# households without a vehicle.
OVERLAY_TAIL_PROBABILITY <- 0.25

# Map Visualization Settings
MAP_WIDTH <- 12           # Plot width in inches
MAP_HEIGHT <- 10          # Plot height in inches
MAP_DPI <- 300           # Resolution for saved maps

# Color schemes for maps
# Options: "viridis", "plasma", "inferno", "magma", "cividis"
COLOR_SCHEME_CONTINUOUS <- "plasma"

# Diverging color scheme for the directional place-and-access conditions index
COLOR_LOW <- "#d73027"    # Lower access / higher exposure
COLOR_MID <- "#ffffbf"    # Yellow for medium
COLOR_HIGH <- "#1a9850"   # Higher access / lower exposure

# Output Settings
OUTPUT_DIR <- "output"    # Directory for output files
SAVE_RDS <- TRUE         # Save R data file
SAVE_CSV <- TRUE         # Save CSV export
SAVE_PLOTS <- TRUE       # Save PNG maps

# Print cluster statistics
PRINT_STATS <- TRUE
VERBOSE <- TRUE          # Print progress messages
