# Austin H8 Job Accessibility

This pipeline calculates walk-plus-transit access to jobs for H3 resolution 8
cells whose centers fall inside the City of Austin boundary.

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
Rscript setup_packages.R
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
Rscript accessibility/01-setup/pull_capmetro_gtfs.R
Rscript accessibility/01-setup/pull_osm_network.R
Rscript accessibility/02-data-processing/pull_lodes_wac_jobs.R
Rscript accessibility/03-analysis/unweighted_job_accessibility.R
Rscript accessibility/03-analysis/weighted_job_accessibility.R
```

The first routing run builds and caches the R5 network. Later runs reuse it
unless the GTFS, OSM, or `r5r` version recorded in the input manifest changes.

## Outputs

- `h8_job_accessibility.csv`: H8 access to all, low-, middle-, and high-wage
  jobs, plus resident-worker weights for downstream aggregation
- `h8_job_accessibility_summary.csv`: resident-worker-weighted and unweighted
  summaries
- `h8_job_accessibility_map.png`: four-panel accessibility map

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

The tract-based `austin_opportunity_index.R` uses this H8 output for an interim
validation. It aggregates H8 access to clipped tracts with area-apportioned
resident-worker weights and retains the 2019 ACS inputs so the accessibility
change can be evaluated in isolation. The final integration will allocate 2024
ACS demographics to H8 so every component shares the same target geography.
