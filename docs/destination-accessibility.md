# Destination and multimodal accessibility integration

This branch carries the destination preparation and accessibility work into the
source-based pipeline introduced on `upstream/main` in October 2026. It does not
version raw downloads, licensed records, travel-time matrices, geocoder caches,
or generated maps. Those files remain in the ignored `data/`,
`accessibility/data/`, and `accessibility/output/` directories.

## Division of responsibility

- `destinations/` downloads, cleans, screens, geocodes, compares, and packages
  one reviewed inventory per destination type.
- `config/destination_accessibility.yml` records the prepared-layer contract and
  the current measure choices in one place.
- `accessibility/03-analysis/` consumes reviewed inventories and prepared travel
  time matrices. It writes reproducible tabular, spatial, QA, and map outputs.
- `_targets.R` remains the central opportunity-component pipeline. Destination
  outputs should enter it as prepared files only after their measures and QA
  rules have been accepted by the research team.

This boundary matches the upstream treatment of the prepared job-access file.
It also lets destination inventories be revised without placing restricted or
large source files in Git.

## Current measures

The current meeting-stage measures are travel time to the third-nearest grocery
and fifth-nearest childcare facility during the morning peak and midday; park
count and acreage reachable within 10, 15, and 30 minutes at midday; and travel
time to the nearest public library. Automobile measures use the supplied H8
travel-time matrix. The park workflow also has a walk-plus-transit version.

Measure names describe the calculation directly. Calculations use the R
`accessibility` package when it supplies the required method; project code
handles input contracts, scenarios, QA, and outputs around those functions.

Run one configured scenario, mode, and period from the repository root:

```sh
Rscript accessibility/scripts/run_accessibility.R \
  --scenario grocery_third_nearest --mode drive --period am_peak
```

The runner writes `accessibility.csv`, `qa_summary.csv`, and
`run_manifest.json` under
`accessibility/output/working/<scenario>/<mode>/<period>/`. Automobile runs
filter the large prepared Parquet matrix in origin batches before calculation,
so a full metro job run does not create another very large matrix file.
Walk-plus-transit runs build a travel-time matrix with R5. Unbatched runs also
retain `travel_matrix_subset.csv`. Both backends pass the standardized matrix
to the same package-based measure functions.

Large R5 scenarios, including regional job accessibility, also process origins
in batches. This produces the same origin-level measures while avoiding a
metro-wide origin-by-destination table in memory or on disk.

Walk-plus-transit paths use a 90-minute maximum total trip duration and up to
20 minutes of walking for access and egress. The total duration includes access
walking, waiting, transfers, in-vehicle time, and final walking. The longer
limit avoids treating potentially usable transit trips as unavailable merely
because their full door-to-door journey exceeds one hour; destinations that
remain unreachable within 90 minutes are retained explicitly in the output.

The Census-block product is a display transfer from H8 results, not block-level
routing. Its values inherit the H8 cell-center estimate and must be described
that way in maps and tables.

## Migration sequence

1. Rebuild or review a destination inventory using `destinations/README.md`.
2. Confirm the inventory path, layer, source, and measure in
   `config/destination_accessibility.yml`.
3. Run the relevant accessibility script and retain its run-details and QA
   outputs beside the analytical result.
4. Compare output geography, modes, periods, and source metadata with the
   registry before interpretation.
5. After the team accepts a measure, add its compact prepared output to
   `config/pipeline.yml` and a reader, validation target, manifest entry, and
   downstream component target to `_targets.R`.

The copied scripts are preserved migration inputs. Several predate the new
pipeline conventions and should be consolidated around the registry before
being treated as production targets. In particular, hard-coded matrix paths,
duplicated period definitions, and mixed experimental/final output folders
should be removed during that consolidation.
