# Script hierarchy and run order

Run all commands from the repository root. Numeric prefixes identify runnable
scripts and their intended sequence. Gaps between phases are deliberate so new
steps can be inserted without renaming the entire pipeline.

Unnumbered R files are configuration or helper files sourced by numbered
scripts. They are not independent pipeline steps.

## Current reproducible pipeline

### 00 — Environment

```sh
Rscript 00_setup_packages.R
```

This installs missing R dependencies and validates external requirements. All
later scripts also source this file and request their own dependency subsets.

### Accessibility — Phases 01 through 03

```sh
Rscript accessibility/01-setup/01_pull_capmetro_gtfs.R
Rscript accessibility/01-setup/02_pull_osm_network.R
Rscript accessibility/02-data-processing/01_pull_lodes_wac_jobs.R
Rscript accessibility/03-analysis/01_unweighted_job_accessibility.R
Rscript accessibility/03-analysis/02_weighted_job_accessibility.R
```

The two `01-setup` downloads are independent, but their numbering provides a
consistent order. Both must finish before the routing analysis. The LODES step
must precede both accessibility-analysis steps, and the weighted summary must
follow the unweighted routing calculation.

### 10–15 — Place, exposure, and candidate inputs

```sh
Rscript 10_pull_epa_frs_environmental_hazards.R
Rscript 11_pull_austin_open_data_crash_injuries.R
Rscript 12_pull_austin_open_data_development_pressure.R
Rscript 13_pull_austin_open_data_land_use.R
Rscript 14_pull_austin_open_data_displacement_risk.R
Rscript 15_pull_austin_flood_hazard.R
```

Steps 10 and 11 are required by the current primary model. Step 12 supplies an
active experimental specification. Steps 13 and 14 prepare the land-use and
City-updated displacement-risk categories for the mixed-data experiments.
Step 13 downloads the large parcel inventory in checksum-tracked pages and
reuses valid cached pages unless `REFRESH_AUSTIN_LAND_USE=true` is set.
Step 15 prepares probability-based physical flood-hazard polygons for the
focused post-analysis experiment in step 31.

### 20 — Main analysis

```sh
Rscript 20_austin_opportunity_index.R
```

Run this after the accessibility pipeline and required input scripts. Existing
processed inputs may be reused when their vintages and QA/QC remain suitable.

### 21–22 and 30–31 — Post-analysis and demonstration

```sh
Rscript 21_example_custom_analysis.R
Rscript 22_policy_typology_proof_of_concept.R
Rscript 30_compare_tract_h8_geographies.R
Rscript 31_test_flood_hazard_kmeans.R
```

Step 21 requires the output from step 20 and demonstrates an alternative
cluster count. Step 22 is the mostly stand-alone, submission-ready proof of
concept: it reads the tract inputs produced by step 20, independently estimates
the prespecified five-cluster policy typology, and writes a compact output
folder with poverty and race/ethnicity as its only demonstration equity
overlays. The primary specification uses observed one-unit-housing,
recent-construction, and disability shares; transformed built form and
age-standardized disability remain sensitivity models. Estimated residents
with disabilities are exported separately for service-planning review.
Step 30 is a stand-alone tract-versus-H8 geography comparison; it requires step
00 but does not require the main analysis output.
Step 31 requires outputs from steps 15 and 20 and compares the compact
five-input model with an otherwise identical model that adds physical flood
hazard. It does not replace the primary cluster assignment.

## Optional and exploratory workflows

These scripts do not feed the current primary analysis. Their high numeric
prefixes keep them visibly separate from the reproducible core.

### 80 — Candidate social infrastructure

```sh
Rscript 80_pull_austin_open_data_social_infrastructure.R
```

This earlier candidate input is retained for possible future work but is not
part of the active specifications.

### 81–83 — Eviction-data preparation

```sh
Rscript 81_process_jp_eviction_filings.R
Rscript 82_pull_austin_open_data_address_points.R
Rscript 83_geocode_jp_eviction_filings.R
```

This is a self-contained optional sequence. Eviction data remain outside the
current clustering analysis.

### 90–92 — Accessibility explorations

```sh
Rscript accessibility/02-data-processing/90_create_hex_exploratory.R
Rscript accessibility/02-data-processing/91_pull_school_quality_exploratory.R
Rscript accessibility/02-data-processing/92_pull_311_calls_exploratory.R
```

These are exploratory notebooks-in-script-form, not production pipeline steps.
Some include local or provisional assumptions and should be reviewed before
reuse.

### 94 — TxDOT CRIS backup workflow

```sh
Rscript 94_pull_txdot_cris_public_extract.R
```

This is retained for future validation or regional expansion. The active crash
input comes from step 11 using the City of Austin Open Data extract derived from
CRIS.

## Sourced support files

- `config.R`: settings for `21_example_custom_analysis.R`
- `accessibility/config.R`: accessibility source vintages, parameters, and paths
- `accessibility/01-setup/r5r_setup.R`: R5 network builder used by the routing
  script
- `accessibility/02-data-processing/utilities.R`: shared exploratory spatial
  helpers

Because these files are sourced rather than run, they intentionally have no
numeric prefix.
