# Austin Opportunity Index

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
geometry and ACS context, computes tract crash density, acquires EPA RSEI industrial-air microdata, and joins published
displacement categories. Job access, schools, flood polygons, and crash points
currently use prepared input files. Initial source downloads need network
access; Census acquisition also requires a configured API key. Later runs reuse
cached sources. See
[`PIPELINE.md`](PIPELINE.md) for source preparation, configuration, and limits.

## Current scope

- **Benefits:** transit job access, including wage groups, and AISD assigned-school
  academic growth. Other destinations and driving access are pending.
- **Burdens:** mapped FEMA floodplain overlap, recorded severe-crash density, and
  EPA RSEI modeled industrial air-toxic concentration. Heat, traffic pollution, and improved City flood measures
  are pending.
- **Context:** selected tract demographic, housing, and displacement attributes.
- **Outputs:** tract component maps and three editable site examples. Site
  profiles query the underlying spatial data where available and report the
  limits of approximating access with existing H8 origins.

For candidate benefit/burden flags, open `output/components/classification-review/review.html`.
This separate analysis compares provisional rules without adopting screening thresholds;
see [RSEI methods and classification review](docs/rsei.md).

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

## Interactive map prototype

[Open the benefit and burden map](https://aakarner.github.io/atx-opportunity-index/).
Tract maps and address-to-H8 profiles use strong job access **>50,000** and
elevated RSEI burden **≥100**, with independent flags.
See [website rebuild and publishing instructions](docs/web-mockup.md).
