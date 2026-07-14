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

3. Install and validate required packages:
   ```sh
   Rscript 00_setup_packages.R
   ```

   Individual analysis scripts also source this package setup automatically.

4. Set your Census API key:
   ```r
   library(tidycensus)
   census_api_key("YOUR_API_KEY_HERE", install = TRUE)
   ```

## Running the Analysis

From the repository root, generate the accessibility, place/exposure, and
development inputs and then run the main analysis:

```sh
Rscript 00_setup_packages.R
Rscript accessibility/01-setup/01_pull_capmetro_gtfs.R
Rscript accessibility/01-setup/02_pull_osm_network.R
Rscript accessibility/02-data-processing/01_pull_lodes_wac_jobs.R
Rscript accessibility/03-analysis/01_unweighted_job_accessibility.R
Rscript accessibility/03-analysis/02_weighted_job_accessibility.R
Rscript 10_pull_epa_frs_environmental_hazards.R
Rscript 11_pull_austin_open_data_crash_injuries.R
Rscript 12_pull_austin_open_data_development_pressure.R
Rscript 13_pull_austin_open_data_land_use.R
Rscript 14_pull_austin_open_data_displacement_risk.R
Rscript 15_pull_austin_flood_hazard.R
Rscript 20_austin_opportunity_index.R
Rscript 22_policy_typology_proof_of_concept.R
Rscript 31_test_flood_hazard_kmeans.R
```

The numeric prefixes encode the intended execution sequence. See
[`RUN_ORDER.md`](RUN_ORDER.md) for exploratory scripts and optional
subworkflows. Steps 13 and 14 supply the land-use and City-updated Uprooted
inputs used by the mixed-data experiments. Step 15 supplies physical FEMA
flood-hazard polygons for the focused post-analysis comparison in step 31.
Step 22 independently estimates the submission-ready five-cluster typology
from the step-20 tract inputs using simplified one-unit-housing,
recent-construction, and observed-disability shares. It isolates the primary
results and controlled input-form sensitivities under `output/proof_of_concept/`.

The Austin Open Data crash script reads its API token from
`AUSTIN_OPEN_DATA_APP_TOKEN`. The LODES step also writes the 2023 tract-level
job/resident-worker file required by the experimental functional-role model.

The script will:

1. Pull 2024 ACS data for the three counties containing Austin
2. Aggregate H8 job access and add EPA-hazard and KSI-crash exposures
3. Perform the primary k-means clustering without income, poverty, education,
   employment, or vehicle availability defining the solution
4. Retain that five-input baseline as the step-20 reference model
5. Compare experimental additions for development pressure, ACS built form,
   and 2023 LODES functional role
6. Separately test unified resident-context models that add age-standardized
   disability, older-adult share, and bounded poverty influence
7. Test land-use and displacement-risk specifications using Gower distance and
   PAM, including continuous-share and categorical-weight sensitivities
8. Keep race/ethnicity out of clustering and evaluate it after clustering
9. Apply remaining social and economic indicators as overlays and filters
10. Generate maps, profiles, cross-tabs, diagnostics, and QA/QC outputs

The step-22 proof of concept uses poverty and race/ethnicity as its only
demonstration equity overlays; neither enters clustering or cluster names.
Estimated residents with disabilities are exported separately as a
service-planning cross-tab and do not enter clustering.

Social infrastructure is not included in the active specifications.

## Understanding the Output

### Maps Generated

1. **place_access_conditions_map.png**: Directional summary of transit access,
   environmental exposure, and KSI crash exposure

2. **cluster_map.png**: Shows five descriptive place profiles
   - Different colors represent different cluster groups
   - Tracts in the same cluster share similar characteristics

3. **income_overlay_map.png**, **poverty_overlay_map.png**, and
   **no_vehicle_overlay_map.png**: Social and transportation context that does
   not define the clusters

4. **environmental_hazard_map.png** and **crash_injury_map.png**: Place-based
   exposure inputs used in clustering

5. **elbow_plot.png**: Technical plot showing clustering optimization

6. **development_pressure_experiment_map.png**,
   **built_form_experiment_map.png**, and
   **functional_role_experiment_map.png**: Candidate measures tested without
   changing the primary baseline map

7. **experimental_cluster_diagnostics.png** and
   **experimental_cluster_stability.png**: Separation and reproducibility
   comparisons across candidate specifications

8. **resident_context_cluster_diagnostics.png** and
   **resident_context_cluster_stability.png**: The same checks for the unified
   demographic-inclusive experiments, kept separate from the primary model

9. **mixed_model_diagnostics.png**, **mixed_model_stability.png**, and
   **mixed_categorical_weight_sensitivity.png**: Separation, stability, and
   category-dominance checks for the Gower/PAM experiments

10. **mixed_cluster_comparison_map.png**, **land_use_category_map.png**, and
    **displacement_risk_category_map.png**: Mixed-model and categorical-input
    maps

11. **flood_hazard_exposure_map.png**,
    **flood_hazard_kmeans_map_comparison.png**, and
    **flood_hazard_kmeans_diagnostics.png**: Physical flood exposure and its
    effect on the compact k-means specification

### Data Files

- **austin_opportunity_data.rds**: R data file for further analysis
- **austin_opportunity_data.csv**: Spreadsheet-compatible data export
- **cluster_input_summary.csv** and **cluster_overlay_summary.csv**: Separate
  summaries of cluster-defining indicators and post-clustering overlays
- **cluster_diagnostics.csv**: Elbow, silhouette, Calinski-Harabasz, and gap
  statistics for candidate cluster counts. Five clusters are retained for
  policy-facing detail even though the separation metrics favor two.
- **experimental_model_summary.csv** and
  **experimental_model_diagnostics.csv**: Side-by-side model and cluster-count
  diagnostics, including silhouette, Calinski-Harabasz, gap, and 80% subsample
  stability
- **experimental_overlay_sorting.csv**: Checks whether candidate clusters
  reproduce income, poverty, employment, education, or vehicle-availability
  patterns; it identifies when poverty is a direct experimental input
- **built_form_reliability_sensitivity.csv**: Re-estimates built-form models on
  tracts passing the ACS sample-size and margin-of-error screens
- **resident_context_model_summary.csv** and
  **resident_context_candidate_cluster_profiles.csv**: Unified-model
  diagnostics and profiles for k = 2–6; the corresponding long-form tract
  assignments are in **resident_context_candidate_cluster_assignments.csv**
- **resident_context_reliability_sensitivity.csv**: Re-estimates the unified
  models under 5-, 10-, and 15-percentage-point ACS MOE screens
- **experimental_race_ethnicity_audit.csv**: Population-weighted composition,
  representation, and sorting diagnostics; race/ethnicity is never a cluster
  input
- **experimental_poverty_concentration_guardrail.csv**: Makes direct and
  indirect poverty concentration visible for every candidate k

## Customization

You can modify the script to:

- Add different census variables
- Change the number of clusters
- Change the county scope and align the supporting spatial inputs
- Adjust the directional place-and-access conditions formula

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

- Census variables: https://api.census.gov/data/2024/acs/acs5/variables.html
- tidycensus package: https://walker-data.com/tidycensus/
- tigris package: https://github.com/walkerke/tigris
