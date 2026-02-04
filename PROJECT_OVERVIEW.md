# Project Files Overview

This document provides a comprehensive overview of all files in the Austin Opportunity Index project.

## Core Analysis Scripts

### austin_opportunity_index.R
**Purpose**: Main analysis script that performs the complete opportunity index workflow.

**What it does**:
1. Pulls census data for Travis County using tidycensus API
2. Calculates opportunity index from 9 census variables across 4 domains:
   - Economic opportunity (income, poverty, employment)
   - Educational opportunity (bachelor's and graduate degrees)
   - Housing opportunity (home values, rental costs)
   - Access opportunity (vehicle access, health insurance)
3. Performs k-means clustering to identify 5 neighborhood types
4. Creates 4 visualizations:
   - Elbow plot (cluster optimization)
   - Opportunity index map (diverging color scale)
   - Cluster map (categorical display)
   - Median income map (continuous scale)
5. Saves results to RDS and CSV files

**Dependencies**: tidycensus, tidyverse, tigris, sf

**Runtime**: 2-5 minutes depending on internet speed and data caching

**Outputs**:
- `elbow_plot.png` - Shows optimal number of clusters
- `opportunity_index_map.png` - Main opportunity index visualization
- `cluster_map.png` - Neighborhood type classifications
- `income_map.png` - Income distribution map
- `austin_opportunity_data.rds` - R data object with spatial features
- `austin_opportunity_data.csv` - Tabular data export

---

## Setup and Configuration

### setup.R
**Purpose**: Installation helper for required R packages.

**What it does**:
1. Checks for installed packages
2. Installs missing packages from CRAN
3. Verifies Census API key is configured
4. Provides instructions if API key is missing

**Usage**: Run once before first analysis
```r
source("setup.R")
```

### config.R
**Purpose**: Centralized configuration file for customizing the analysis.

**Configurable parameters**:
- Geographic scope (year, survey type, counties)
- Clustering parameters (number of clusters, random seed)
- Census variables to include in analysis
- Opportunity index component weights
- Map visualization settings (colors, dimensions, DPI)
- Output preferences (file formats, directories)

**Usage**: Modify values in this file, then use with example_custom_analysis.R

---

## Examples and Documentation

### example_custom_analysis.R
**Purpose**: Demonstrates how to use config.R for customized analyses.

**Examples included**:
1. Pull data with custom configuration
2. Calculate weighted opportunity index
3. Perform k-means with custom cluster count
4. Create maps with custom color schemes

**Usage**: 
```r
# First, modify config.R with your settings
source("example_custom_analysis.R")
```

### README.md
**Purpose**: Primary project documentation.

**Contents**:
- Project overview and goals
- Required packages and dependencies
- Basic usage instructions
- Output file descriptions
- Data source information

**Audience**: General users, GitHub visitors

### QUICKSTART.md
**Purpose**: Detailed step-by-step guide for new users.

**Contents**:
- Installation prerequisites (R, RStudio, Census API key)
- Detailed setup instructions
- Running the analysis
- Understanding outputs
- Troubleshooting common issues
- Links to external resources

**Audience**: First-time users, beginners

---

## Project Metadata

### .gitignore
**Purpose**: Specifies files that should not be committed to version control.

**Excludes**:
- R history and session files (.Rhistory, .RData)
- RStudio user files (.Rproj.user)
- Generated outputs (PNG, RDS, CSV files)
- Cache directories
- OAuth tokens

### LICENSE
**Purpose**: Legal terms for using and distributing the code.

---

## Data and Analysis Details

### Census Variables Used

The analysis uses American Community Survey (ACS) 5-year estimates from the following tables:

| Variable Code | Description | Domain |
|--------------|-------------|---------|
| B19013_001 | Median household income | Economic |
| B17001_002 | Population below poverty level | Economic |
| B23025_004 | Employed population | Economic |
| B15003_022 | Bachelor's degree holders | Education |
| B15003_023 | Graduate degree holders | Education |
| B25077_001 | Median home value | Housing |
| B25064_001 | Median gross rent | Housing |
| B08201_002 | Households with vehicle(s) | Access |
| B27001_004 | Population with health insurance | Access |

### K-means Clustering Method

The script uses standard k-means clustering with:
- **Input**: Scaled (standardized) census variables
- **Algorithm**: Lloyd's algorithm with multiple random starts
- **Default clusters**: 5 (can be customized)
- **Random seed**: 123 (for reproducibility)
- **Iterations**: Up to 25 random starts to find optimal solution

### Opportunity Index Formula

```
opportunity_index = mean(economic_score, education_score, housing_score, access_score)
```

Where each component score is standardized (z-score normalized) and housing is inverted (lower costs = higher opportunity).

---

## Expected Output Examples

### Terminal Output
```
Pulling census data for Travis County, TX...
Cleaning and preparing data...
Calculating opportunity index components...
Determining optimal number of clusters...
Performing k-means clustering...
Creating visualizations...
Saving plots...

=== Cluster Statistics ===
# A tibble: 5 × 6
  cluster n_tracts avg_income avg_education avg_home_value avg_opportunity
  <fct>      <int>      <dbl>         <dbl>          <dbl>           <dbl>
1 3             45     95234.        356.5         425000.           0.856
2 1             38     125000.       512.3         550000.           1.234
...

=== Analysis Complete ===
Output files created:
  - elbow_plot.png
  - opportunity_index_map.png
  - cluster_map.png
  - income_map.png
  - austin_opportunity_data.rds
  - austin_opportunity_data.csv
```

---

## Common Use Cases

1. **Basic Analysis**: Run `austin_opportunity_index.R` for standard Austin analysis
2. **Custom Geography**: Modify `config.R` to add Williamson and Hays counties
3. **Different Variables**: Edit census_vars in main script or CENSUS_VARIABLES in config
4. **Custom Weights**: Adjust opportunity index weights in config.R
5. **Time Series**: Run for multiple years and compare changes

---

## Technical Requirements

- **R Version**: 4.0.0 or higher recommended
- **RAM**: 2GB minimum (4GB+ recommended for larger analyses)
- **Disk Space**: ~500MB for cache and outputs
- **Internet**: Required for initial data download
- **Census API Key**: Free registration required

---

## Extending the Analysis

### Adding Counties
```r
# In config.R or main script
COUNTIES <- c("Travis", "Williamson", "Hays")
```

### Adding Variables
```r
# Add to census_vars definition
"internet_access" = "B28002_004"
```

### Changing Cluster Count
```r
# In config.R
NUM_CLUSTERS <- 7
```

### Custom Color Schemes
Available color schemes:
- Continuous: "viridis", "plasma", "inferno", "magma", "cividis"
- Diverging: Custom with COLOR_LOW, COLOR_MID, COLOR_HIGH
- Categorical: "Set1", "Set2", "Set3", "Paired"

---

## Support and Resources

- **tidycensus documentation**: https://walker-data.com/tidycensus/
- **Census variables**: https://api.census.gov/data/2021/acs/acs5/variables.html
- **tigris package**: https://github.com/walkerke/tigris
- **sf package**: https://r-spatial.github.io/sf/

---

*Last updated: February 2026*
