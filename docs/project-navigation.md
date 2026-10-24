# Destination and accessibility workflow navigation

## Start here

The repository has one source-to-output path:

1. `destinations/` prepares final destination inventories.
2. `config/destination_accessibility.yml` declares inventories, modes,
   periods, measures, and thresholds.
3. `accessibility/scripts/run_accessibility.R` runs one declared scenario.
4. `accessibility/output/working/` stores local analytical results and QA.
5. `dashboard/` contains compact, browser-ready outputs for GitHub Pages.

Large downloads, routing matrices, caches, and generated analytical outputs
are intentionally local. They are described by manifests and configuration
rather than committed to ordinary Git history.

## Repository map

| Path | Purpose | Versioned in Git? |
| --- | --- | --- |
| `destinations/` | Download, clean, screen, geocode, and finalize destination layers | Yes |
| `config/destination_accessibility.yml` | Single registry for analysis scenarios | Yes |
| `accessibility/R/` | Reusable accessibility measures and matrix readers | Yes |
| `accessibility/scripts/` | Scenario runner and result summaries | Yes |
| `accessibility/01-setup/` | GTFS, OSM, and R5 preparation | Yes |
| `data/destinations/raw/` | Immutable source snapshots | Local only |
| `data/destinations/processed/` | Final destination layers used by analysis | Local only |
| `data/destinations/manual/` | Human review and override decisions | Local; preserve and back up |
| `data/destinations/qaqc/` | Compact validation tables | Local only |
| `accessibility/data/` | GTFS, OSM, LODES, and routing inputs | Local only |
| `accessibility/output/working/` | Final scenario results, manifests, and QA | Local only |
| `dashboard/` | Compact static map distributed through GitHub Pages | Yes |
| `tests/` | Tests for runner behavior and parity | Yes |

## Reproduce destination inventories

Read `destinations/README.md`. Each destination subfolder uses numbered scripts
in execution order. Final files referenced by the accessibility registry are
the authoritative products; `interim/` files are reproducible working data.

## Run accessibility scenarios

Read `docs/destination-accessibility.md` and `accessibility/README.md`, then run:

```sh
Rscript accessibility/scripts/run_accessibility.R \
  --scenario grocery_third_nearest \
  --mode drive \
  --period am_peak
```

Change only the scenario, mode, and period. Do not create a new one-off script
for a destination that can be represented in the central YAML registry.

## Required local data

The analysis requires the H8 origin grid and prepared automobile matrices,
the CapMetro GTFS and OSM network for transit, final destination layers, and
LODES job opportunities. See `data/README.md` for the local directory contract.

## Outputs to retain

For each completed scenario retain `accessibility.csv`, `qa_summary.csv`, and
`run_manifest.json`. The copied `travel_matrix_subset.csv` files are temporary
diagnostics and can be regenerated. The dashboard retains only compact values
needed by the browser.
