# Austin Opportunity Index

The [interactive map](https://aakarner.github.io/atx-opportunity-index/) describes
access to opportunities, environmental burdens, and flood eligibility for housing
locations in Austin. It covers 1,029 H3 resolution 8 hexagons and includes tract
summaries of benefits. Demographic, housing, and displacement measures provide context.

The repository has one analytical entrypoint: [`_targets.R`](_targets.R).

## Run

Set `DAM_DATA_DIR` to the local, dated DAM team snapshot (2026-11-17). From the repository root:

```sh
Rscript scripts/setup_pipeline.R
Rscript scripts/run_pipeline.R
```

Open [`output/components/review.html`](output/components/review.html) for the
maps, site profiles, indicator registry, source manifest, and quality checks.
The same directory contains CSV tables and a tract GeoPackage.

The pipeline acquires Census and City displacement sources, rebuilds tract
geometry and ACS context, computes tract crash density, acquires EPA RSEI industrial-air microdata, and joins published
displacement categories. Job access, schools, flood polygons, and crash points
currently use prepared input files. Initial source downloads need network
access; Census acquisition also requires a configured API key. Later runs reuse
cached sources. See
[`PIPELINE.md`](PIPELINE.md) for source preparation, configuration, and limits.

## Current scope

- **Benefits.** Housing profiles combine destination access, jobs, and assigned elementary-school growth for families. The map shows the weighted score and minimum status for each travel mode. [Benefit methods](docs/benefits.md)
- **Burdens.** Heat contributes one third of the score. Industrial air, near-road traffic, fatal and serious-injury crashes, and sidewalk gaps on major streets each contribute one sixth. At least two high components flag a hexagon for overall high burden. [Burden methods](docs/burdens.md)
- **Eligibility.** The City of Austin fully developed floodplain determines flood eligibility. Partial overlap with a hexagon requires a check at the selected address.
- **Context.** The tract component report includes demographics, housing, displacement, and three editable example sites. The examples illustrate how to interpret the data.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`_targets.R`](_targets.R) | Analytical dependencies and tracked outputs |
| [`config/`](config/) | Source settings, parameters, and example coordinates |
| [`R/`](R/) | Input validation, spatial calculations, site profiles, and reporting |
| [`scripts/`](scripts/) | Explicit dependency setup, pipeline runner, and source preparation helpers |
| [`accessibility/`](accessibility/) | Retained network, employment, and H8 routing preparation |
| [`data/`](data/) | Tracked source caches and prepared spatial inputs |
| [`tests/`](tests/) | Spatial checks and isolated pipeline integration checks |
| [`docs/`](docs/) | School methods and project terminology |
| `output/components/` | Generated review page, maps, tables, and spatial exports |

Change [`config/example_sites.csv`](config/example_sites.csv) to evaluate other
illustrative locations. Change [`config/pipeline.yml`](config/pipeline.yml) to
select compatible input snapshots or report settings. `{targets}` rebuilds the
work affected by those changes and reuses unchanged calculations.

See [`PIPELINE.md`](PIPELINE.md) for the complete run guide,
[`docs/schools.md`](docs/schools.md) for the school measures, and
[`docs/glossary.md`](docs/glossary.md) for project terminology.

## Map preview and publication

Serve the checked-in map locally with `python3 -m http.server 8765 --directory site`.
See the [map guide](docs/web-mockup.md) for rebuild, validation, and publication commands.
