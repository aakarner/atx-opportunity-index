# Austin Opportunity Index

This project develops a proof-of-concept opportunity framework for Austin,
Texas. It uses k-means clustering to describe different combinations of
people/service-fit, place, exposure, and access conditions across census
tracts, then applies social and economic indicators as post-clustering overlays.

## Overview

The submission-ready policy typology produced by step 22 uses:

- **Housing-market context**: Median home value and rent
- **People/service fit**: Household size and households with children
- **Resident service needs**: Older-adult share and observed disability
  prevalence
- **Built form**: Share of housing units in one-unit structures and share built
  since 2010
- **Access**: Transit access to jobs
- **Environmental exposure**: Proximity to EPA hazard-candidate facilities
- **Traffic-safety exposure**: Fatal and suspected-serious-injury crash density

The five-cluster count is prespecified as a policy-relevant resolution. The
inputs are balanced across seven conceptual domains, and the proof-of-concept
script reports separation, gap-statistic, cluster-size, and subsample-stability
diagnostics transparently. The earlier five-input model remains a reference in
step 20, which also compares experimental specifications that add
residential development pressure, ACS built form, and 2023 LODES functional
role. These experiments are exported separately and do not replace the
step-22 policy typology. Social infrastructure is not part of the active
pipeline.

Step 22 retains the immediately preceding compositional/logit built-form and
age-standardized disability formulation as a sensitivity. It also isolates the
two changes so readers can distinguish the effect of simplifying built form
from the effect of using observed disability prevalence.

The workflow now also tests a clearly labeled unified
"neighborhood context and resident needs" family. It adds share age 65 or
older, age-standardized disability prevalence, and—in three bounded-weight
specifications—poverty. Resident context is prespecified to account for 20%,
25%, or 33% of total squared clustering distance. These models are diagnostic
experiments, not replacements for the primary map.

A separate mixed-data family evaluates the City parcel land-use inventory and
the City-updated displacement-risk categories using Gower distance and
partitioning around medoids (PAM). It compares nominal land-use categories
with continuous tract land-use shares, varies categorical influence, and
reports when an apparent multi-cluster solution primarily reproduces a source
category. These results remain experimental.

The submission-ready demonstration uses only poverty and race/ethnicity as
post-clustering overlays and cross-tabs. Neither enters clustering or cluster
names. Additional social and economic measures remain in the broader step-20
exploratory outputs but are not included in the compact proof-of-concept
folder. Estimated residents with disabilities are exported separately as a
service-planning overlay; the count does not enter clustering. Cluster profiles
are descriptive and are not assigned a single
higher/lower opportunity direction.

## Requirements

Install and validate all R package dependencies from the repository root:

```sh
Rscript 00_setup_packages.R
```

Each runnable R script also sources `00_setup_packages.R`, installs any missing
packages in its own dependency subset, and loads them in the current session.

You'll also need a Census API key. Get one for free at: https://api.census.gov/data/key_signup.html

Set your API key in R:
```r
census_api_key("YOUR_API_KEY_HERE", install = TRUE)
```

## Usage

Runnable scripts are numbered by phase. Configuration and helper files are
intentionally unnumbered because they are sourced by other scripts rather than
run directly. See [`RUN_ORDER.md`](RUN_ORDER.md) for the complete hierarchy,
including optional and exploratory workflows.

For a complete first-time reproduction of the current analysis, run:

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

The Austin Open Data crash pull requires `AUSTIN_OPEN_DATA_APP_TOKEN` in the
process environment. The LODES processing step creates both the H8 job/worker
inputs and the 2023 tract functional-role file. Previously generated inputs can
be reused when their source vintages and checksums remain appropriate.

Steps 13 and 14 prepare the land-use and displacement-risk inputs used only by
the mixed-data experiments. The main analysis keeps low-coverage and unknown
records distinct rather than treating them as substantive categories.
Step 15 prepares probability-based FEMA flood-hazard polygons. Step 31 uses
them in a focused comparison of the five-input baseline with an otherwise
identical six-input model; it does not replace the primary cluster map.
Step 22 independently estimates the submission-ready five-cluster typology
from the tract analytical inputs. It writes poverty and race/ethnicity
demonstration overlays, a disability service-planning cross-tab, and controlled
input-form sensitivity comparisons under `output/proof_of_concept/`.

## Output

Principal outputs include:

- **output/proof_of_concept/**: Compact submission-ready five-cluster maps,
  profiles, diagnostics, assignments, QA/QC, poverty and race/ethnicity
  cross-tabs, a disability service-planning cross-tab, and specification
  sensitivities produced by step 22

- **cluster_map.png**: K-means place profiles
- **place_access_conditions_map.png**: Directional access/exposure index
- **environmental_hazard_map.png** and **crash_injury_map.png**: New place exposures
- **flood_hazard_exposure_map.png**, **flood_hazard_kmeans_map_comparison.png**,
  and **flood_hazard_kmeans_diagnostics.png**: Physical flood exposure and the
  focused five- versus six-input k-means comparison
- **development_pressure_experiment_map.png**, **built_form_experiment_map.png**,
  and **functional_role_experiment_map.png**: Candidate-input maps
- **experimental_cluster_diagnostics.png** and
  **experimental_cluster_stability.png**: Separation and 80% subsample
  stability comparisons across specifications
- **resident_context_cluster_diagnostics.png** and
  **resident_context_cluster_stability.png**: Separate diagnostics for the
  demographic-inclusive experimental family
- **mixed_model_diagnostics.png**, **mixed_model_stability.png**, and
  **mixed_categorical_weight_sensitivity.png**: Gower/PAM diagnostics and
  sensitivity to categorical influence
- **mixed_cluster_comparison_map.png**, **land_use_category_map.png**, and
  **displacement_risk_category_map.png**: Mixed-model and source-category maps
- **income_overlay_map.png**, **poverty_overlay_map.png**, and
  **no_vehicle_overlay_map.png**: Post-clustering context
- **cluster_input_summary.csv** and **cluster_centers_scaled.csv**: Cluster profiles
- **indicator_roles.csv** and **overlay_filter_thresholds.csv**: Reproducible
  definitions of model roles and relative screening thresholds
- **cluster_diagnostics.csv**, **cluster_input_correlations.csv**,
  **cluster_input_missingness.csv**, and **analysis_qaqc_summary.csv**: Model
  selection and QA/QC
- **experimental_model_summary.csv**, **experimental_model_diagnostics.csv**,
  **experimental_model_input_weights.csv**, and
  **experimental_cluster_assignments.csv**: Alternative-specification results
- **resident_context_model_summary.csv**,
  **resident_context_candidate_cluster_profiles.csv**,
  **resident_context_candidate_cluster_assignments.csv**, and
  **resident_context_reliability_sensitivity.csv**: Unified-model results,
  profiles for k = 2–6, and ACS precision sensitivities
- **experimental_race_ethnicity_audit.csv** and
  **experimental_poverty_concentration_guardrail.csv**: Post-clustering equity
  and concentration diagnostics; neither is a pass/fail screen
- **experimental_overlay_sorting.csv** and
  **built_form_reliability_sensitivity.csv**: Socioeconomic sorting and ACS
  reliability checks
- **mixed_model_summary.csv**, **mixed_cluster_profiles.csv**,
  **mixed_categorical_profiles.csv**, and
  **mixed_categorical_weight_sensitivity.csv**: Mixed-data model results,
  policy profiles, and category-dominance checks
- **austin_opportunity_data.rds** and **austin_opportunity_data.csv**: Complete
  tract-level analytical outputs

## Data Source

The tract proof of concept pulls Travis, Williamson, and Hays County ACS data
and clips intersecting tract geometry to the City of Austin boundary. It now
uses 2024 ACS 5-year estimates with 2024 ACS tract geography, based on 2020
Census tract definitions.

Clipping changes geometry only: ACS attributes remain published whole-tract
estimates for every tract intersecting Austin. Consequently, aggregated ACS
counts in the race/ethnicity audit describe the analytical tract universe and
must not be read as an Austin city population estimate.

The replacement accessibility pipeline calculates job access directly at H3
resolution 8 using 2023 LODES jobs and pinned 2026 CapMetro/OSM network data.
See [`accessibility/README.md`](accessibility/README.md) for methodology,
requirements, and reproduction steps. The tract proof of concept now aggregates
those H8 results using area-apportioned resident-worker weights, with an
area-weighted or nearest-H8 fallback where necessary. A later implementation
will move the relevant demographic and accessibility inputs onto the common H8
geography.

Environmental exposure uses unique EPA Facility Registry Service hazard
candidates within one mile of an internal tract representative point. Crash
exposure uses 2020–2024 City of Austin crash-level records derived from TxDOT
CRIS and is expressed as average annual KSI crashes per square mile within the
City-observed portion of the same one-mile window. These tract calculations are
an interim proof of concept designed to translate directly to an H8 workflow.

The step-22 built-form domain uses two transparent 2024 ACS shares: housing
units in one-unit detached or attached structures, and housing units built in
2010 or later. The primary model uses the observed shares directly before
standardization. Resident service needs use observed disability prevalence and
older-adult share; estimated residents with disabilities are retained as a
post-clustering planning overlay. The former log-ratio/logit built-form inputs
and age-standardized disability rate remain in controlled sensitivity models.

The experimental development measure combines 2020–2024 new-housing units and
residential-demolition permits, normalized by the existing housing stock. The
built-form experiment uses 2024 ACS units-in-structure and construction-era
estimates, screens broad shares using their ACS margins of error, and reports a
reliability-restricted sensitivity. The functional-role experiment uses 2023
LODES job and resident-worker counts to describe local activity intensity and
employment-center versus residential orientation. Experimental variables are
standardized first; where a domain contains multiple variables, its weights are
then adjusted so it does not gain influence merely by having more measures.

Land use comes from the City of Austin detailed parcel inventory. Parcel
polygons are intersected with City-clipped 2024 tracts and converted to broad
area shares. Water, streets/roads, and unknown inventory codes are excluded
from the compositional denominator; tracts with less than 50% usable inventory
coverage remain in the analytical file but do not enter land-use clustering.
The displacement input is the City's updated implementation of the Uprooted
framework. Because that classification embeds vulnerability indicators,
including income, race/ethnicity, education, and renter status, it is labeled
as policy context and audited rather than treated as a neutral place measure.

The unified resident-context experiment uses 2024 ACS age, disability, and
poverty estimates. Disability prevalence is directly age-standardized using
fixed Austin city age weights for the civilian noninstitutionalized
population. Age, disability, and poverty estimates must have a universe of at
least 100 and a 90% margin of error no greater than 10 percentage points before
their transformed values enter clustering; unreliable values receive a neutral
median substitution and remain flagged. Five- and 15-percentage-point screens
are exported as sensitivities. Race/ethnicity composition is aggregated from
published counts after clustering and is never imputed into the audit.

## License

See LICENSE file for details.
