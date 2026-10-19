# Job-access source preparation

These scripts prepare the H8 job-access snapshot consumed by the repository's
`{targets}` pipeline. Routine component analysis uses the existing snapshot;
source preparation is a separate, explicit operation. Maps, tract aggregation,
and site profiles are produced by [the main pipeline](../PIPELINE.md).

## Pinned specification

- **Jobs:** 2023 LODES WAC, across the five-county Austin–Round Rock metro
  (Bastrop, Caldwell, Hays, Travis, and Williamson).
- **Resident-worker weights:** 2023 LODES RAC, across Travis, Williamson, and
  Hays counties, aggregated to H8.
- **Origins:** H3 resolution 8 cell centers inside the pinned City of Austin municipal boundary (full- and limited-purpose limits, including Dog’s Head; ETJ excluded). The snapshot is configured in `config/pipeline.yml` and documented in `docs/municipal-boundary.md`.
- **Network:** CapMetro GTFS and OpenStreetMap snapshots dated June 25, 2026.
- **Travel:** walk plus transit; departures July 13, 2026, from 7:00–8:59 a.m.;
  50th-percentile travel times and a 45-minute accessibility threshold.

This describes access on a pinned summer network, not current-day service.
Source URLs, checksums, routing parameters, and paths are in
[`config.R`](config.R). Keep its source metadata consistent with
[`config/pipeline.yml`](../config/pipeline.yml) when adopting a new snapshot.

## Rebuild the source snapshot

Run from the **repository root**. Source preparation requires network access,
JDK 21 for R5, and the `osmium` command-line tool for the OSM extract. A
project-local JDK under `accessibility/data/java/rjavaenv/` is used when present.

```sh
Rscript scripts/setup_pipeline.R --sources
Rscript accessibility/01-setup/01_pull_capmetro_gtfs.R
Rscript accessibility/01-setup/02_pull_osm_network.R
Rscript accessibility/02-data-processing/01_pull_lodes_wac_jobs.R
Rscript accessibility/03-analysis/01_unweighted_job_accessibility.R
Rscript accessibility/03-analysis/02_weighted_job_accessibility.R
Rscript scripts/run_pipeline.R
```

The setup command installs dependencies explicitly. Preparation scripts load
their dependencies through `scripts/prepare/packages.R`; they do not install
packages during analysis. The routing packages are `digest`, `dplyr`, `h3jsr`,
`lehdr`, `purrr`, `readr`, `r5r`, `sf`, `tidyr`, `tigris`, and `zip`.

`01-setup/r5r_setup.R` is a helper sourced by the routing script, not a separate
pipeline step. It rebuilds the cached R5 network when the GTFS checksum, OSM
checksum, or recorded `r5r` version changes. The weighted preparation step is
required: it attaches resident-worker counts to the routing output.

## Files and checks

- `data/processed/lehd/`: H8 job destinations and resident-worker counts.
- `data/processed/accessibility/`: cached H8 origins.
- `data/r5_setup/`: prepared GTFS, OSM extract, network cache, and input manifests.
- `output/h8_job_accessibility.csv`: pipeline input containing all/low-/middle-/
  high-wage job access, resident-worker counts, coordinates, and source metadata.
- `output/h8_job_accessibility_summary.csv`: compact source QA table. Each
  wage-specific summary uses its corresponding resident-worker group; downstream
  tract summaries use all resident workers for every job-access component.

The H8 preparation checks identifiers, finite nonnegative counts, and agreement
between total counts and wage groups. A missing count in a present RAC record
is an error; an origin absent from the complete RAC aggregation receives zero
workers. The pipeline separately checks input metadata and tract/site behavior.

GTFS preparation preserves the original archive and records the derivative
that fills blank `transfer_type` with type 2 where `min_transfer_time` is given.
The pinned feed has date-specific service IDs, so R5's service-ID coverage
warning alone is not a measure of service frequency. Inspect scheduled trips
when selecting a new analysis date. Large downloads and routing caches remain
under `accessibility/data/` and are excluded from Git.
