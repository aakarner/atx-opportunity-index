# Quick Start Guide - Austin Opportunity Index

## Prerequisites

1. **Install R**: Download from https://cran.r-project.org/
2. **Install RStudio** (recommended): Download from https://posit.co/download/rstudio-desktop/
3. **Get Census API Key**: Sign up at https://api.census.gov/data/key_signup.html

## Installation Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/aakarner/atx-opportunity-index.git
   cd atx-opportunity-index
   ```

2. Open R or RStudio and set your working directory to the project folder.

3. Install required packages:
   ```r
   source("setup.R")
   ```

4. Set your Census API key:
   ```r
   library(tidycensus)
   census_api_key("YOUR_API_KEY_HERE", install = TRUE)
   ```

## Running the Analysis

Simply run:
```r
source("austin_opportunity_index.R")
```

The script will:
1. Pull census data for Travis County (Austin area)
2. Calculate opportunity index scores
3. Perform k-means clustering analysis
4. Generate maps and visualizations
5. Save output files

## Understanding the Output

### Maps Generated

1. **opportunity_index_map.png**: Shows overall opportunity scores
   - Green areas: Higher opportunity
   - Yellow areas: Moderate opportunity
   - Red areas: Lower opportunity

2. **cluster_map.png**: Shows 5 distinct neighborhood types based on clustering
   - Different colors represent different cluster groups
   - Tracts in the same cluster share similar characteristics

3. **income_map.png**: Shows median household income distribution
   - Darker purple: Higher income areas
   - Lighter yellow: Lower income areas

4. **elbow_plot.png**: Technical plot showing clustering optimization

### Data Files

- **austin_opportunity_data.rds**: R data file for further analysis
- **austin_opportunity_data.csv**: Spreadsheet-compatible data export

## Customization

You can modify the script to:
- Add different census variables
- Change the number of clusters
- Include additional counties (e.g., Williamson, Hays)
- Adjust the opportunity index formula

## Troubleshooting

**Error: "Your API key is not valid"**
- Make sure you've requested and activated your Census API key
- Check that you've set it correctly using `census_api_key()`

**Error: Package installation fails**
- You may need to install system dependencies for spatial packages
- On Ubuntu/Debian: `sudo apt-get install libudunits2-dev libgdal-dev libgeos-dev libproj-dev`
- On macOS: `brew install udunits gdal geos proj`

**Script runs slowly**
- Census data downloads can take several minutes
- The tigris package caches shapefiles to speed up future runs
- Clustering computation may take time with many census tracts

## Support

For questions about:
- Census variables: https://api.census.gov/data/2021/acs/acs5/variables.html
- tidycensus package: https://walker-data.com/tidycensus/
- tigris package: https://github.com/walkerke/tigris
