# Austin H8 Job Accessibility

This pipeline calculates walk-plus-transit access to jobs for H3 resolution 8
cells whose centers fall inside the City of Austin boundary.

For the submitted Methods and Data Report, this pipeline is an upstream data
source rather than the reported cluster analysis itself. Step 20 aggregates
the H8 results to the shared tract file, and
`22_policy_typology_proof_of_concept.R` uses the resulting 45-minute job-access
measure in the report's five-cluster demonstration. The additional
accessibility outputs and tract functional-role experiment remain available for
broader method development.

## Data bundle

The pipeline uses the newest mutually defensible data available as of June
2026. The result should be described as **current-network access to the latest
available employment distribution**, because source release schedules differ.

- Demographic integration target: 2020–2024 ACS 5-year estimates
- Jobs and resident workers: 2023 LODES WAC and RAC
- City boundary: 2024 TIGER/Line place boundary
- Transit: CapMetro GTFS snapshot fetched June 25, 2026
- Streets: Geofabrik/OpenStreetMap snapshot dated June 25, 2026
- Analysis date: Monday, July 13, 2026
- Departure window: 7:00–8:59 a.m.
- Accessibility threshold: 45 minutes
- Origins: City of Austin H8 cell centers
- Destinations: 2023 job blocks aggregated to H8 across the five-county
  Austin–Round Rock metro (Bastrop, Caldwell, Hays, Travis, and Williamson)

Source URLs, dates, checksums, and model parameters live in
[`accessibility/config.R`](config.R). Large downloaded and intermediate files
are reproducible and intentionally excluded from Git.

## Requirements

- R 4.6 or compatible
- JDK 21 (required by `r5r`)
- `osmium` command-line tool
- R packages: `r5r`, `lehdr`, `h3jsr`, `tidyverse`, `sf`, `tigris`,
  `digest`, `patchwork`, and `zip`

Install and validate the complete project R dependency set from the repository
root:

```sh
Rscript 00_setup_packages.R
```

Accessibility scripts also source the central setup file and load their own
package subsets automatically.

Install project-local JDK 21:

```r
options(rJavaEnv.valid = TRUE)
rJavaEnv::java_quick_install(
  version = 21,
  project_path = "accessibility/data/java"
)
```

## Run order

Run from the repository root:

```sh
Rscript accessibility/01-setup/01_pull_capmetro_gtfs.R
Rscript accessibility/01-setup/02_pull_osm_network.R
Rscript accessibility/02-data-processing/01_pull_lodes_wac_jobs.R
Rscript accessibility/03-analysis/01_unweighted_job_accessibility.R
Rscript accessibility/03-analysis/02_weighted_job_accessibility.R
```

The directory prefixes identify the accessibility phase; filename prefixes
give the order within each phase. Unnumbered files such as `config.R`,
`r5r_setup.R`, and `utilities.R` are sourced helpers and should not be run as
pipeline steps.

The LODES processing script writes three products: H8 job destinations, H8
resident-worker weights, and
`austin_tract_functional_role_2023.csv`. The tract file directly aggregates
2023 block-level WAC jobs and RAC resident workers to 2020-vintage tracts for
the opportunity-index functional-role experiment; it is not derived by
allocating H8 values back to tracts.

The first routing run builds and caches the R5 network. Later runs reuse it
unless the GTFS, OSM, or `r5r` version recorded in the input manifest changes.

## Outputs

- `h8_job_accessibility.csv`: H8 access to all, low-, middle-, and high-wage
  jobs, plus resident-worker weights for downstream aggregation
- `h8_job_accessibility_summary.csv`: resident-worker-weighted and unweighted
  summaries
- `h8_job_accessibility_map.png`: four-panel accessibility map
- `austin_tract_functional_role_2023.csv`: tract jobs, resident workers,
  job-worker balance, and total local activity for the experimental clustering
  analysis

## Validation notes

- The output contains 1,021 unique City of Austin H8 cells with no missing
  accessibility values.
- Five-county WAC totals reconcile exactly: 1,303,090 total jobs equals the
  sum of the three wage groups.
- Three-county RAC totals reconcile exactly: 1,116,869 workers equals the sum
  of the three wage groups.
- The source GTFS contains 9,426 transfer rows with blank `transfer_type` and
  populated `min_transfer_time`. The setup script creates a documented
  R5-compatible derivative by assigning transfer type 2 to those rows while
  preserving and checksumming the untouched archive.
- `r5r` warns that fewer than 20% of service IDs operate on the analysis date.
  The feed uses date-specific service IDs: the selected Monday contains 4,585
  scheduled trips, versus a feed maximum of 4,609, so the warning does not
  indicate materially reduced weekday service.

The tract-based `20_austin_opportunity_index.R` aggregates H8 access to clipped
tracts with area-apportioned resident-worker weights and combines it with 2024
ACS, environmental-hazard, and KSI crash inputs. Step 22 then reads that tract
file and independently fits the cluster solution reported in the Methods and
Data Report. Step 20 separately tests direct tract LODES activity and
job-worker-balance measures alongside development pressure and detailed ACS
built form; those experiments are not report findings. A later implementation
can allocate the relevant ACS indicators to H8 so every component shares the
same target geography.
