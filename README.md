# Austin Opportunity Index

This project creates an opportunity index for Austin, Texas using census data. The analysis uses k-means clustering to identify patterns in opportunity indicators across census tracts.

## Overview

The opportunity index combines multiple indicators:
- **Economic Opportunity**: Median household income, employment rates
- **Educational Opportunity**: Bachelor's and graduate degree attainment
- **Housing Opportunity**: Home values and rental costs
- **Access**: Vehicle access and health insurance coverage

## Requirements

This script requires R and the following packages:

```r
install.packages(c("tidycensus", "tidyverse", "tigris", "sf"))
```

You'll also need a Census API key. Get one for free at: https://api.census.gov/data/key_signup.html

Set your API key in R:
```r
census_api_key("YOUR_API_KEY_HERE", install = TRUE)
```

## Usage

Run the main analysis script:

```r
source("austin_opportunity_index.R")
```

## Output

The script generates:
- **elbow_plot.png**: Visualization showing optimal number of clusters
- **opportunity_index_map.png**: Map showing the composite opportunity index
- **cluster_map.png**: Map showing k-means cluster assignments
- **income_map.png**: Map showing median household income
- **austin_opportunity_data.rds**: R data file with all results
- **austin_opportunity_data.csv**: CSV export of the data (without geometry)

## Data Source

Data is pulled from the U.S. Census Bureau's American Community Survey (ACS) 5-year estimates using the tidycensus package. The analysis focuses on Travis County, Texas, which contains Austin.

## License

See LICENSE file for details.
