# Setup script for Austin Opportunity Index
# This script installs required R packages

cat("Installing required packages...\n")

# List of required packages
packages <- c(
  "tidycensus",
  "tidyverse",
  "tigris",
  "sf",
  "scales"
)

# Install packages that are not already installed
new_packages <- packages[!(packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) {
  install.packages(new_packages)
  cat("Installed packages:", paste(new_packages, collapse = ", "), "\n")
} else {
  cat("All required packages are already installed.\n")
}

# Check for Census API key
cat("\n=== Census API Key ===\n")
if(Sys.getenv("CENSUS_API_KEY") == "") {
  cat("WARNING: No Census API key found.\n")
  cat("Get a free API key at: https://api.census.gov/data/key_signup.html\n")
  cat("Then set it in R using:\n")
  cat("  census_api_key('YOUR_API_KEY_HERE', install = TRUE)\n")
} else {
  cat("Census API key is set.\n")
}

cat("\nSetup complete! You can now run austin_opportunity_index.R\n")
