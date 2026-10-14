# Running the opportunity component pipeline

`_targets.R` builds tract component maps and finer-scale example profiles with
explicit source tracking and quality checks. Census and City displacement
acquisition, tract geometry, ACS context, crash calculations, and displacement
joins run inside the dependency graph. Job access, school assignments, flood
polygons, and crash points currently enter as prepared files. The pipeline has no dependency on a
previous tract analytical output.

## Setup and execution

Run from the repository root:

```sh
Rscript scripts/setup_pipeline.R
Rscript scripts/run_pipeline.R
```

Setup explicitly installs missing dependencies in `.R-library/`. Analytical
runs load packages and fail if a dependency is missing; they never install
packages. Source-preparation helpers require the additional setup option:

```sh
Rscript scripts/setup_pipeline.R --sources
```

Census API requests require a configured `CENSUS_API_KEY`. Keep the key in the
R environment, not in `config/pipeline.yml`; source provenance excludes it.
Initial Census acquisition requires network access. Available genuine Tigris
cache files can supply boundary sources; otherwise the pipeline downloads them
from Census. The retained prepared files listed below must also be available.

Build selected targets and their dependencies by passing target names:

```sh
Rscript scripts/run_pipeline.R review_report
```

`{targets}` stores its cache in `_targets/`. An unchanged run skips up-to-date
work. Changes to tracked source files, configuration, or functions rebuild
affected descendants. Site-coordinate changes reuse shared spatial calculations.
Generated output files are tracked too and are rebuilt if removed or modified.
There is no environment lockfile yet; `runtime.txt` records the actual R/package
environment.

## Sources and configuration

`config/pipeline.yml` defines source paths and vintages, spatial parameters, map
dimensions, and the output directory.

| Source | Current input and treatment |
| --- | --- |
| Census ACS | 2024 five-year tract estimates and margins of error for Travis, Williamson, and Hays counties; county JSON responses and manifests cached under `data/raw/census/`. |
| Census geography | 2024 1:500,000 cartographic tract boundaries and full TIGER/Line place boundaries; Austin place GEOID `4805000`. Source shapefile components and manifests are tracked files. |
| City displacement | Downloads or reuses raw `data/raw/austin_open_data_displacement_risk/city_of_austin_displacement_risk_areas_2022.geojson`; published categories join by tract GEOID. |
| EPA industrial air | National RSEI v2.3.12 2022 aggregated air microdata; cached in `data/raw/epa_rsei/`, extracted and area-averaged inside the graph. |
| H8 job access | `accessibility/output/h8_job_accessibility.csv`, including resident-worker weights and employment/routing metadata. |
| AISD schools | `data/processed/school_indicators/aisd_growth_assignments_2025_26.gpkg`, with attendance zones, matched growth scores, and availability flags. |
| FEMA flood | `data/processed/flood_hazard/austin_fema_floodplain.gpkg`. |
| Crash points | `data/processed/crash_injuries/austin_open_data_ksi_crashes.gpkg`, containing fatal and suspected-serious-injury crashes. |
| Example sites | `config/example_sites.csv`, containing WGS84 coordinates, labels, and selection notes. |

The `census` configuration specifies `acs_year`, `boundary_year`, `state_fips`,
`county_fips`, `place_geoid`, `raw_dir`, and `refresh`. The defaults select 2024,
Texas (`48`), counties `453`, `491`, and `209`, and Austin (`4805000`). Valid cached
source files are reused when `refresh: false`. To request reacquisition, set
`refresh: true`, run the pipeline, then reset it to `false`. Leaving it true does
not force downloads on every unchanged run: targets still caches completed work.
Review vintages and QA when replacing a source.

The `displacement` section independently specifies `source_year`, `url`, `path`,
and `refresh`. Its tracked acquisition target downloads the raw City GeoJSON
when absent or deliberately refreshed, validates categories and identifiers,
and otherwise reuses the existing file. Its refresh flag follows the same
target-caching behavior as Census acquisition.

Input validation checks identifiers, geometry, metadata, and the supported
measurement settings. The current access fields represent 45 minutes and H3
resolution 8; area calculations use EPSG:5070. Source contracts currently require
Austin and the Travis/Williamson/Hays county set, 2024 ACS and boundaries,
2022 displacement categories, and 2020–2024 crash points. Changing those settings
requires reviewing the related source contracts and measurement definitions.
Source SHA-256 checksums identify
the exact files used. A missing prepared input produces an error rather than
triggering an unrequested source-preparation script.

The three initial site examples are occupied AISD H8 origins spanning low-wage
job-access levels. They are demonstrations, not housing proposals, and have not
been screened for parcel availability or development feasibility. Edit
`config/example_sites.csv` to replace or add locations.

## Outputs

Open `output/components/review.html` for the maps, site profiles, indicator
registry, source manifest, and QA. Keep the page beside its `maps/` folder so
relative image links work. The same directory contains:

- `tract_components.csv` and `tract_components.gpkg`: tract measurements,
  source context, and coverage/aggregation flags.
- `site_profiles.csv`: example-site profiles and tract identifiers.
- `maps/`: low-wage transit-job access, FEMA floodplain area share, annual tract
  KSI crash density, AISD growth by school level, and an example-location map.
- `indicator_registry.csv`: roles, units, vintages, readiness, and limitations.
- `source_manifest.csv`: input paths, file sizes, and SHA-256 checksums.
- `qa_summary.csv` and `runtime.txt`: analytical checks and runtime information.

Outputs and the targets cache can be rebuilt from source files, prepared inputs,
configuration, and code. Retain the prepared inputs until their full preparation
has moved into the graph.

## Measurement and interpretation

**Geography and ACS.** Reporting tracts have positive area overlap with the Austin
place boundary. The cartographic tract shapes are clipped to the full place
boundary; their generalized edges are not parcel boundaries. ACS attributes
remain published whole-tract estimates after clipping. Summing those attributes
does not produce an Austin city population total.

The four contextual measures use these Census variables:

| Context | Calculation |
| --- | --- |
| Poverty | `B17001_002 / B17001_001` |
| People of color | `1 - B03002_003 / B03002_001` |
| Households without a vehicle | `B08201_002 / B11005_001` |
| Median gross rent | `B25064_001` |

The three proportions are stored on a 0–1 scale; rent is in dollars. Source
estimates and 90% margins of error are retained, with proportion margins of error
calculated using the ACS subset formula and ratio fallback. Missing or zero
denominators produce missing proportions. Original missing-value codes remain
in raw JSON and become missing analytical values; there is no imputation. These
attributes are context, not inputs to a benefit score or an adopted eligibility
rule. ACS updates do not rebuild unchanged reporting geometry.

**Job access.** Tract values aggregate H8 access with area-apportioned
resident-worker weights. Total and all three wage-group measures use the same
`workers_all` weights, rather than separate origin weights for each wage group.
Area-weighted and nearest-origin fallbacks remain flagged. Current inputs use
2023 jobs and a pinned summer 2026 network. Site profiles use the containing H8
cell or a nearest-origin fallback, report its distance, and apply a maximum
distance. This approximates access without fresh routing from the site.

**Schools.** Site assignments query attendance-zone polygons and retain score
availability and assignment ambiguity. The current baseline matches 2025–26
assignments and growth from TEA's 2026 accountability release. Coverage is AISD
only; there is no tract school composite yet. Campus-wide growth is descriptive,
not a causal measure of school effectiveness. Missing scores remain missing.
See `docs/schools.md` for matching and exclusions.

**Flood.** Tracts report the fraction of City-clipped area intersecting the FEMA
1%-annual-chance floodplain snapshot. Sites report point overlap. No mapped
overlap does not establish absence of flood risk. Improved City flood measures
remain pending.

**Street safety.** Tract crash measures are recomputed from crash points. Each
tract receives an internal representative point after projection to EPSG:5070.
Its configured buffer is intersected with the actual Austin place boundary.
Unique crash IDs within that window are divided by the configured number of
years, including zero-crash years, and by the City-observed window area in square
miles. Site profiles use the same observation boundary around their coordinates.
The current default is a one-mile radius and 2020–2024. Updating points or
parameters rebuilds the affected measures. These are recorded-crash densities,
not exposure-adjusted risks or individual safety estimates.

**Displacement.** The City's published 2022 categories join to reporting tracts
by exact GEOID, without a spatial crosswalk. Source `N/A` means no published
risk designation. It remains distinct from missing or unrecognized categories
and tracts outside published coverage. This is policy context rather than a
neutral environmental measure or an eligibility screen.

**Industrial pollution.** EPA RSEI 2022 v2.3.12 air geographic microdata are acquired
and extracted inside the graph. Native 810 m cells supply area-weighted H8/tract
concentrations and containing-cell site profiles. No population multiplier or
health threshold is applied. Source integrity, provenance, and spatial coverage
are checked. See [docs/rsei.md](docs/rsei.md) for the source contract, interpretation,
outputs, and the separate candidate-classification review.

**Incomplete components.** Heat, traffic pollution,
pedestrian barriers, improved City flood measures, other destinations, and
driving access remain incomplete. Missing components never count as zero burden
or a passed screen. The pipeline does not create composite scores, clusters,
policy thresholds, or site exclusions.

## Preparing the remaining inputs

The following helpers remain outside the targets graph. Run them deliberately
to refresh the prepared inputs, review their QA, and update configuration before
rebuilding. Install their dependencies with
`Rscript scripts/setup_pipeline.R --sources`. `scripts/prepare/packages.R` is
the shared dependency loader, not an analysis step.

Network and employment preparation precede routing, and the weighted-summary
step attaches the resident-worker information needed by tract aggregation:

```sh
Rscript accessibility/01-setup/01_pull_capmetro_gtfs.R
Rscript accessibility/01-setup/02_pull_osm_network.R
Rscript accessibility/02-data-processing/01_pull_lodes_wac_jobs.R
Rscript accessibility/03-analysis/01_unweighted_job_accessibility.R
Rscript accessibility/03-analysis/02_weighted_job_accessibility.R
```

`accessibility/config.R` specifies vintages and routing settings. Routing needs
the external Java/R5 environment used by `accessibility/01-setup/r5r_setup.R`.
The output metadata must agree with `config/pipeline.yml`.

Crash and flood preparation remain independent:

```sh
Rscript scripts/prepare/pull_crashes.R
Rscript scripts/prepare/pull_flood.R
```

The crash pull requires `AUSTIN_OPEN_DATA_APP_TOKEN`.

Prepare school boundaries and accountability data before matching assignments:

```sh
Rscript scripts/prepare/pull_school_boundaries.R 2025-26
Rscript scripts/prepare/pull_school_boundaries.R 2026-27
Rscript scripts/prepare/pull_school_indicators.R
Rscript scripts/prepare/build_school_assignments.R
```

The assignment builder reads prepared files offline and preserves separate
vintages. See `docs/schools.md` for source details and QA requirements.

## Code and validation

`R/tract_sources.R` handles Census acquisition, source validation, and reporting
geography/context; `R/tract_measures.R` handles tract crash windows and City
displacement categories. The `R/pipeline_*.R` modules handle other inputs,
aggregation, site queries, exports, and reports. `_targets.R` connects them.

Run focused checks and the isolated integration checks with:

```sh
Rscript tests/test_pipeline.R
Rscript tests/test_pipeline_integration.R
```

Integration checks use temporary outputs and test dependency behavior, including
an unchanged run and a site edit. They do not depend on a saved tract analytical
reference or alter production configuration, cache, or outputs.

Remaining migrations include prepared job/school/flood/crash inputs and
environment locking. New access and burden components can join the same tract
and site reporting interfaces. Keep expensive
preparation and routing upstream of aggregation and policy comparisons.

The `web_mockup_data` file target exports the selected access/RSEI components,
city and tract geometry, and thresholds to `site/assets/` for the GitHub Pages
client. Rebuild with `Rscript scripts/run_pipeline.R web_mockup_data`; see
[website instructions](docs/web-mockup.md) for preview, checks, and publication.
