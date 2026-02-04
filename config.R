# Configuration File for Austin Opportunity Index
# Modify these parameters to customize your analysis

# Census API Configuration
# Get your API key from: https://api.census.gov/data/key_signup.html
# CENSUS_API_KEY <- "YOUR_API_KEY_HERE"

# Geographic Scope
YEAR <- 2021              # Year of ACS data (check tidycensus for available years)
SURVEY <- "acs5"          # "acs1" (1-year) or "acs5" (5-year estimates)
STATE <- "TX"             # State abbreviation
COUNTIES <- c("Travis")   # County or counties to analyze
                         # For greater Austin: c("Travis", "Williamson", "Hays")

# Clustering Parameters
NUM_CLUSTERS <- 5         # Number of k-means clusters
RANDOM_SEED <- 123        # Random seed for reproducibility
NSTART <- 25             # Number of random starts for k-means

# Census Variables
# Modify this list to include different opportunity indicators
# Find variables at: https://api.census.gov/data/2021/acs/acs5/variables.html

CENSUS_VARIABLES <- c(
  # Economic Indicators
  "median_income" = "B19013_001",        # Median household income
  "poverty_rate" = "B17001_002",         # Below poverty level
  "employment_rate" = "B23025_004",      # Employed population
  "unemployment_rate" = "B23025_005",    # Unemployed population
  
  # Education Indicators
  "bachelors_or_higher" = "B15003_022",  # Bachelor's degree
  "graduate_degree" = "B15003_023",      # Graduate degree
  "high_school" = "B15003_017",          # High school graduate
  
  # Housing Indicators
  "median_home_value" = "B25077_001",    # Median home value
  "median_rent" = "B25064_001",          # Median gross rent
  "owner_occupied" = "B25003_002",       # Owner-occupied units
  
  # Access/Mobility Indicators
  "vehicle_access" = "B08201_002",       # Households with vehicle
  "health_insurance" = "B27001_004",     # With health insurance
  "internet_access" = "B28002_004"       # With internet subscription
)

# Opportunity Index Weights
# Adjust weights to emphasize different components (should sum to 1.0)
WEIGHT_ECONOMIC <- 0.30
WEIGHT_EDUCATION <- 0.25
WEIGHT_HOUSING <- 0.25
WEIGHT_ACCESS <- 0.20

# Map Visualization Settings
MAP_WIDTH <- 12           # Plot width in inches
MAP_HEIGHT <- 10          # Plot height in inches
MAP_DPI <- 300           # Resolution for saved maps

# Color schemes for maps
# Options: "viridis", "plasma", "inferno", "magma", "cividis"
COLOR_SCHEME_CONTINUOUS <- "plasma"

# Diverging color scheme for opportunity index
COLOR_LOW <- "#d73027"    # Red for low opportunity
COLOR_MID <- "#ffffbf"    # Yellow for medium
COLOR_HIGH <- "#1a9850"   # Green for high opportunity

# Output Settings
OUTPUT_DIR <- "."         # Directory for output files
SAVE_RDS <- TRUE         # Save R data file
SAVE_CSV <- TRUE         # Save CSV export
SAVE_PLOTS <- TRUE       # Save PNG maps

# Print cluster statistics
PRINT_STATS <- TRUE
VERBOSE <- TRUE          # Print progress messages
