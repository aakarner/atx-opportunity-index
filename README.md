# Austin Opportunity Index

## Destination accessibility extension

This branch adds reproducible destination preparation, automobile and
walk-plus-transit accessibility scenarios, and an interactive results
dashboard. Start with [`docs/project-navigation.md`](docs/project-navigation.md)
for the folder map and replication sequence. The central scenario registry is
[`config/destination_accessibility.yml`](config/destination_accessibility.yml);
new destination measures should be added there and run through the shared
runner rather than implemented as separate analysis scripts.

The browser-ready dashboard is under [`dashboard/`](dashboard/) and is
published with GitHub Pages. Large source downloads, routing matrices, and
generated analytical results remain local and follow the contract in
[`data/README.md`](data/README.md).

A reproducible framework for describing neighborhood benefits and burdens in
Austin, with tract-level maps and more detailed profiles of example sites.
Benefits focus on access to opportunities; burdens remain separate physical
conditions. Demographic, housing, and displacement measures provide context.

The repository has one analytical entrypoint: [`_targets.R`](_targets.R).

## Run

From the repository root:

```sh
Rscript scripts/setup_pipeline.R
Rscript scripts/run_pipeline.R
```

Open [`output/components/review.html`](output/components/review.html) for the
maps, site profiles, indicator registry, source manifest, and quality checks.
The same directory contains CSV tables and a tract GeoPackage.

The pipeline acquires Census and City displacement sources, rebuilds tract
geometry and ACS context, computes tract crash density, and joins published
displacement categories. Job access, schools, flood polygons, and crash points
currently use prepared input files. Initial source downloads need network
access; Census acquisition also requires a configured API key. Later runs reuse
cached sources. See
[`PIPELINE.md`](PIPELINE.md) for source preparation, configuration, and limits.

## Current scope

- **Benefits:** transit job access, including wage groups, and AISD assigned-school
  academic growth. Other destinations and driving access are pending.
- **Burdens:** mapped FEMA floodplain overlap and recorded severe-crash density.
  Heat, industrial pollution, traffic pollution, and improved City flood measures
  are pending.
- **Context:** selected tract demographic, housing, and displacement attributes.
- **Outputs:** tract component maps and three editable site examples. Site
  profiles query the underlying spatial data where available and report the
  limits of approximating access with existing H8 origins.

Components retain their own units. The pipeline does not yet assign composite
scores or apply site exclusions, and missing burdens remain unknown. Example
locations are demonstrations, not proposed housing developments.

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
