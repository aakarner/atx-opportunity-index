# Project Files Overview

This document provides a comprehensive overview of all files in the Austin Opportunity Index project.

## Core Analysis Scripts

### 20_austin_opportunity_index.R
**Purpose**: Main proof-of-concept workflow for tract place profiles,
place-and-access conditions, and post-clustering overlays.

**What it does**:

1. Pulls 2024 ACS data for Travis, Williamson, and Hays Counties and clips
   intersecting tracts to the 2024 City of Austin boundary
2. Aggregates the H8 job-accessibility results to the tract proof-of-concept
3. Adds one-mile EPA environmental-hazard proximity and KSI crash-density inputs
4. Performs five-cluster k-means using housing-market, family/service-fit,
   transit-access, environmental-exposure, and traffic-safety dimensions
5. Separately tests development pressure, ACS built form, and 2023 LODES
   functional role as experimental additions
6. Tests a separate unified resident-context family with older-adult share,
   age-standardized disability prevalence, and bounded poverty influence
7. Tests land-use and displacement-risk inputs using Gower distance and PAM,
   including continuous-share and categorical-weight sensitivities
8. Keeps income, employment, education, and no-vehicle indicators as overlays;
   poverty remains an overlay in the primary model, while race/ethnicity is
   reserved for a post-clustering audit
9. Saves maps, tract-level data, cluster profiles, overlay cross-tabs,
   correlations, model comparisons, stability tests, and QA/QC tables

The original five-input baseline remains the primary proof-of-concept model
pending review. Experimental assignments are exported separately. Social
infrastructure is not part of the active pipeline.

**Dependencies**: Managed centrally by `00_setup_packages.R`

**Runtime**: 2-5 minutes depending on internet speed and data caching

**Outputs**:

- `cluster_map.png` - Place-profile classifications
- `place_access_conditions_map.png` - Directional access/exposure summary
- Environmental, crash, transit, family, and overlay maps
- Development-pressure, built-form, and functional-role experiment maps
- Experimental separation and 80% subsample-stability plots
- `cluster_input_summary.csv` and `cluster_overlay_summary.csv`
- `cluster_overlay_crosstab.csv` and `overlay_filter_thresholds.csv`
- `cluster_input_correlations.csv`, `cluster_input_missingness.csv`, and
  `analysis_qaqc_summary.csv`
- `cluster_diagnostics.csv` - Elbow, silhouette, Calinski-Harabasz, and gap
  statistics for candidate cluster counts
- `experimental_model_summary.csv` and `experimental_model_diagnostics.csv`
- `experimental_cluster_profiles.csv`, `experimental_cluster_assignments.csv`,
  and `experimental_cluster_centers_scaled.csv`
- `experimental_candidate_correlations.csv` and
  `experimental_overlay_sorting.csv`
- `built_form_reliability_sensitivity.csv`
- `resident_context_model_summary.csv`,
  `resident_context_model_diagnostics.csv`, and
  `resident_context_candidate_cluster_profiles.csv`
- `resident_context_candidate_cluster_assignments.csv`
- `resident_context_reliability_sensitivity.csv`
- `experimental_race_ethnicity_audit.csv` and
  `experimental_poverty_concentration_guardrail.csv`
- `experimental_model_input_weights.csv` and
  `disability_standardization_reference.csv`
- Mixed-data maps, diagnostics, medoids, profiles, assignments,
  categorical-weight sensitivity, and post-clustering audits
- `austin_opportunity_data.rds` and `austin_opportunity_data.csv`

---

## Setup and Configuration

### 00_setup_packages.R
**Purpose**: Central installation and loading helper for required R packages.

**What it does**:

1. Defines the complete package requirements for all current R workflows
2. Installs missing packages from CRAN
3. Loads either the complete set or a script-specific subset
4. Reports external Census API, Java, and osmium requirements

**Usage**: Run from the repository root before the first analysis
```sh
Rscript 00_setup_packages.R
```

Runnable R scripts source this file automatically and request their own package
subsets in the active session.

### Required Run Order

For a complete first-time reproduction, run from the repository root:

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

The LODES step now creates both the H8 job/resident-worker inputs and the direct
2020-tract aggregation used by the functional-role experiment. Existing
processed inputs can be reused when their source vintages remain appropriate.
The full required, candidate, and exploratory hierarchy is documented in
[`RUN_ORDER.md`](RUN_ORDER.md).

### Stand-alone Place and Change Inputs

- `10_pull_epa_frs_environmental_hazards.R` prepares the EPA hazard-candidate
  facility input.
- `11_pull_austin_open_data_crash_injuries.R` prepares 2020–2024 fatal and
  suspected-serious-injury crashes from Austin Open Data.
- `12_pull_austin_open_data_development_pressure.R` prepares 2020–2024 new-housing
  and residential-demolition permits for the development experiment.
- `13_pull_austin_open_data_land_use.R` intersects the current City parcel
  inventory with analytical tracts, preserves continuous area shares, and
  constructs broad nominal categories with explicit coverage QA.
- `14_pull_austin_open_data_displacement_risk.R` prepares the City-updated
  displacement-risk categories derived from the Uprooted framework. The main
  analysis treats this as policy context because it embeds vulnerability
  indicators.
- `15_pull_austin_flood_hazard.R` downloads and validates the official Greater
  Austin FEMA Floodplain polygons, preserves the 1% and 0.2% annual-chance
  classes, and clips them to the City boundary.

### 31_test_flood_hazard_kmeans.R
**Purpose**: Focused post-analysis comparison of the current five-input
k-means model with an otherwise identical model that adds the tract share in
FEMA's 1%-annual-chance floodplain.

The script evaluates candidate values of k, five-cluster stability and
membership changes, correlations with the socioeconomic overlays, and mapped
cluster differences. Its results are diagnostic and do not replace the primary
proof-of-concept assignment.

### 22_policy_typology_proof_of_concept.R
**Purpose**: Mostly stand-alone, submission-ready proof of concept.

The script reads the tract analytical file created by step 20 but independently
estimates its own five-cluster k-means solution. Its transparent built-form
domain uses the observed shares of housing units in one-unit structures and
built since 2010. Its resident-service-needs domain uses older-adult share and
observed disability prevalence. Domain balancing prevents either two-input
domain from gaining influence simply because it contains more coordinates.

The script treats five clusters as a prespecified policy resolution and exports
separation and stability diagnostics. It retains age-standardized disability,
the preceding transformed built-form measures, and the complete preceding
proof-of-concept formulation as controlled sensitivity specifications. Poverty
and race/ethnicity remain the only demonstration equity overlays and neither
enters clustering or cluster labels. Estimated residents with disabilities are
exported separately as a service-planning cross-tab and do not enter k-means.
All deliverables are isolated under `output/proof_of_concept/`.

### config.R
**Purpose**: Optional settings for `21_example_custom_analysis.R`. The main
proof-of-concept workflow currently defines its settings in
`20_austin_opportunity_index.R`.

**Configurable parameters**:

- Geographic scope (year, survey type, counties)
- Clustering parameters (number of clusters, random seed)
- Census variables and their overlay/cluster roles
- Relative overlay threshold
- Map visualization settings (colors, dimensions, DPI)
- Output preferences (file formats, directories)

**Usage**: Modify values in this file, then use with
`21_example_custom_analysis.R`.

---

## Examples and Documentation

### 21_example_custom_analysis.R
**Purpose**: Re-estimates the current five-input model with an alternative
cluster count after the main workflow has run.

**Examples included**:

1. Reads the complete tract output from the main workflow
2. Performs k-means with a custom cluster count using the same five inputs
3. Summarizes social and economic overlays after clustering
4. Creates an alternative cluster map

**Usage**: 
```r
# First run the main workflow, then modify NUM_CLUSTERS in config.R
Rscript 21_example_custom_analysis.R
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

### RUN_ORDER.md

**Purpose**: Authoritative numbered execution hierarchy for the required,
candidate, optional, and exploratory R workflows.

**Audience**: Anyone reproducing or extending the pipeline

---

## Project Metadata

### .gitignore
**Purpose**: Specifies files that should not be committed to version control.

**Excludes**:

- R history and session files (.Rhistory, .RData)
- RStudio user files (.Rproj.user)
- Generated outputs (PNG, RDS, CSV files)
- Downloaded and processed local data (`data/` and `accessibility/data/`)
- Cache directories
- OAuth tokens

### LICENSE
**Purpose**: Legal terms for using and distributing the code.

---

## Data and Analysis Details

### ACS Variables Used

The analysis uses 2024 American Community Survey 5-year estimates. Housing and
family/service-fit variables help define the primary clusters. A separate
unified experiment adds resident-needs and economic-constraint variables;
race/ethnicity remains audit-only.

ACS attributes remain whole-tract estimates after intersecting tract geometry
is clipped to Austin. Aggregated demographic counts therefore describe the
analytical tract universe, not the population contained exactly within the
municipal boundary.

| Variable code(s) | Description | Analysis role |
|------------------|-------------|---------------|
| B25077_001, B25064_001 | Median home value and rent | Cluster input: housing-market profile |
| B25010_001, B11005_001–002 | Household size and households with children | Cluster input: family/service fit |
| B25024 series | Units in broad structure-size categories | Experimental input: built form |
| B25034 series | Housing units built in 2010 or later | Experimental input: built form |
| B25001_001 | Total housing units | Development-rate denominator |
| B19013_001 | Median household income | Overlay/filter |
| B01001_001, B01001_020–025, B01001_044–049 | Population age 65 or older | Unified experimental input: resident needs |
| B18101 series | Age-specific disability counts | Unified experimental input: age-standardized resident needs |
| B17001_001–002 | Poverty rate numerator and denominator | Primary overlay; bounded unified experimental input |
| B23025_002, B23025_004 | Employment rate numerator and denominator | Overlay/filter |
| B15003_001, B15003_022–025 | Bachelor's degree or higher | Overlay/filter |
| B08201_002 | Households without a vehicle | Overlay/filter |
| B03002 series | Race and Hispanic/Latino origin | Post-clustering audit only |

Transit job access, EPA hazard-facility proximity, and KSI crash density are
additional cluster inputs produced by the project's stand-alone data pipelines.
The development-permit, built-form, and LODES functional-role measures are
experimental inputs only.

### K-means Clustering Method

The script uses standard k-means clustering with:

- **Input**: Five scaled housing-market, family/service-fit, transit-access,
  environmental-exposure, and traffic-safety measures
- **Algorithm**: R's default Hartigan–Wong algorithm with multiple random starts
- **Proof-of-concept clusters**: 5
- **Random seed**: 123 (for reproducibility)
- **Iterations**: 25 random starts

Candidate values from 1 to 10 are evaluated using within-cluster variation;
values from 2 to 10 are also evaluated using silhouette and
Calinski-Harabasz statistics. A 100-simulation gap statistic provides a fourth
check. For k = 2 through 6, 100 repeated 80% subsamples assess assignment
stability using the adjusted Rand index. The current baseline diagnostics favor
a two-cluster statistical solution, while five is retained as a transparent
substantive choice to provide a more useful policy-facing typology.

### Experimental Specifications

The main workflow compares eleven specifications without changing the primary
baseline map. Six test place-based candidates:

1. Baseline five inputs
2. Baseline plus development pressure
3. Baseline plus ACS built form
4. Baseline plus LODES functional role
5. Baseline plus all three candidate domains
6. An all-candidate model balancing exposure, built form, and functional role

Five additional specifications test a unified "neighborhood context and
resident needs" typology:

1. An exposure-balanced reference with the existing family/service-fit profile
2. The reference plus older-adult share and age-standardized disability
3. The same resident-needs measures plus poverty, with all resident-context
   variables together contributing 20% of total squared clustering distance
4. The same model with a 25% resident-context contribution
5. The same model with a 33% resident-context contribution

In the three mixed models, resident-context squared weight is split equally
between a service-needs block and the poverty coordinate; service-needs weight
is then divided equally among family, age, and disability. EPA and KSI measures
jointly receive one exposure-domain unit. These are sensitivity tests, not a
mechanism for forcing a preferred number of clusters.

### Mixed-Data Land-Use and Displacement Experiments

Eight Gower/PAM specifications compare land-use and displacement policy
context with the existing continuous inputs. Two use continuous land-use area
shares; the others use broad nominal land-use categories, displacement-risk
categories, or both. The resident-context variants test age and disability,
with bounded poverty included in a separate family. Candidate values from two
through six clusters are evaluated using silhouette width, cluster size,
adjacent-tract agreement, and 100 paired 80% subsample stability tests.

Each conceptual domain receives equal total Gower weight in the reference
comparison. Because a full-weight nominal category can mechanically become the
partition, the workflow also varies categorical-domain weight from 0.10 to
1.00 and reports adjusted-Rand agreement between the five-cluster assignment
and each source category. Continuous-share models provide a second check on
whether land use adds multidimensional structure without a discrete category
jump. The primary k-means map is not replaced by these experiments.

The land-use processor excludes water, streets/roads, and unknown codes from
the share denominator. Tracts with less than 50% usable inventory coverage are
retained in outputs but excluded from land-use clustering. Unknown
displacement coverage is likewise distinct from the published “no
designation” category and is not imputed.

Development pressure combines standardized log rates of permitted new housing
units and residential demolitions per 1,000 existing housing units. Built form
uses broad structure-size composition and recent-construction measures from the
2024 ACS. Component and share margins of error are propagated; estimates must
pass minimum-denominator, reconciliation, and 20-percentage-point MOE screens
before entering the primary transformation. Unavailable or unreliable values
are median-imputed for the full comparison, and a separate sensitivity refits
the built-form models only on tracts passing the reliability screens. The QA
table also reports counts under a 15-percentage-point screen.

Functional role uses direct 2023 LODES block-to-tract aggregation to measure
total local job/resident-worker activity per square mile and a signed balance
from residential orientation to employment-center orientation. Full-tract land
area is used so City-boundary clipping does not inflate activity intensity.

Every model input is standardized before any experimental domain weight is
applied. A domain represented by multiple variables receives per-variable
weight `1 / sqrt(n)`, so its total squared-distance contribution is comparable
to a one-variable domain rather than growing mechanically with its variable
count.

Model review includes silhouette, Calinski-Harabasz, gap, cluster-size, first-PC
variance, 80% subsample stability, and adjusted-Rand comparisons with the
baseline. Post-clustering diagnostics also measure how strongly each candidate
solution sorts the income, poverty, employment, education, and vehicle-access
overlays.

Older-adult share and poverty are empirical-logit transformed, while
age-standardized disability is converted with a bounded logit; each is
winsorized at the 1st and 99th percentiles before standardization. Disability
uses fixed 2024 Austin place-level age weights and the civilian
noninstitutionalized population. The primary ACS reliability screen requires a
universe of at least 100 and a 90% MOE no greater than 10 percentage points.
Unreliable coordinates are neutral median-imputed and flagged; complete-case
sensitivities use 5-, 10-, and 15-point screens.

Race and ethnicity never enter clustering. The audit aggregates published
counts by model and k, reports population-weighted cluster composition,
representation ratios, group-assignment shares, and group-versus-rest
dissimilarity, and propagates tract MOEs to cluster aggregates. A parallel
poverty guardrail makes socioeconomic concentration visible whether poverty is
an overlay or a direct experimental input.

### Directional Place-and-Access Conditions Index

```
place_access_index = mean(transit_access_score,
                          environmental_safety_score,
                          traffic_safety_score)
```

The three components are standardized. Environmental-hazard and KSI-crash
exposure are inverted so higher values consistently mean higher access and/or
lower exposure. Housing, family, age, disability, and poverty profiles are not
given a higher/lower direction. None enters this directional index. Income,
employment, education, vehicle availability, and race/ethnicity do not enter
any clustering routine; poverty enters only the bounded unified experimental
family.

---

## Expected Output Examples

### Terminal Output
```
Pulling ACS data for Travis, Williamson, Hays counties, TX...
Reading H8 job accessibility results...
Reading place, exposure, and development inputs...
Evaluating baseline and experimental cluster specifications...
Retaining baseline k = 5 for primary maps.
Creating visualizations...
Saving plots...

=== Analysis Complete ===
Output files created:
  - elbow_plot.png
  - place_access_conditions_map.png
  - cluster_map.png
  - income_overlay_map.png
  - poverty_overlay_map.png
  - environmental_hazard_map.png
  - crash_injury_map.png
  - development_pressure_experiment_map.png
  - built_form_experiment_map.png
  - functional_role_experiment_map.png
  - experimental_cluster_diagnostics.png
  - experimental_cluster_stability.png
  - austin_opportunity_data.rds
  - austin_opportunity_data.csv
  - cluster_diagnostics.csv
  - experimental_model_summary.csv
  - experimental_model_diagnostics.csv
  - experimental_overlay_sorting.csv
  - built_form_reliability_sensitivity.csv
```

---

## Common Use Cases

1. **Basic Analysis**: Run `20_austin_opportunity_index.R` for the standard
   Austin analysis
2. **Alternative Cluster Count**: Change `NUM_CLUSTERS` in `config.R` and run
   `21_example_custom_analysis.R`
3. **Overlay Screening**: Use the overlay flags in the RDS/CSV output to assess
   project concentration and displacement concerns after identifying a place
   profile
4. **Different Variables or Geography**: Edit the explicitly labeled settings
   and role definitions in the main script
5. **Time Series**: Regenerate date-stamped input datasets before comparing
   results across periods

---

## Technical Requirements

- **R Version**: 4.0.0 or higher recommended
- **RAM**: 2GB minimum (4GB+ recommended for larger analyses)
- **Disk Space**: ~500MB for cache and outputs
- **Internet**: Required for initial data download
- **Census API Key**: Free registration required

---

## Extending the Analysis

### Adding Variables
```r
# Add the ACS code to census_vars, then explicitly assign the derived measure
# to cluster_vars or the overlay/filter definitions—not both by default.
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
- **Census variables**: https://api.census.gov/data/2024/acs/acs5/variables.html
- **tigris package**: https://github.com/walkerke/tigris
- **sf package**: https://r-spatial.github.io/sf/

---

*Last updated: July 2026*
