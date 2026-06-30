# Austin Opportunity Index

This project creates an opportunity index for Austin, Texas using census data. The analysis uses k-means clustering to identify patterns in opportunity indicators across census tracts.

## Overview

The opportunity index combines multiple indicators:

- **Economic opportunity**: Income, poverty, and employment
- **Educational opportunity**: Bachelor's and graduate degree attainment
- **Housing opportunity**: Home values and rental costs
- **Family context**: Household size and households with children
- **Access**: Transit access to jobs and households without a vehicle

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

The tract proof of concept pulls Travis, Williamson, and Hays County ACS data
and clips intersecting tract geometry to the City of Austin boundary. Its 2019
ACS vintage is retained temporarily because the original 2021 Accessibility
Observatory file uses 2010-vintage tract identifiers.

The replacement accessibility pipeline calculates job access directly at H3
resolution 8 using 2023 LODES jobs and pinned 2026 CapMetro/OSM network data.
See [`accessibility/README.md`](accessibility/README.md) for methodology,
requirements, and reproduction steps. The final opportunity-index integration
will move demographics and accessibility onto this common H8 geography.

## License

See LICENSE file for details.
