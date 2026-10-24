# Destination data

Scripts that download, clean, geocode, and package destination layers
(childcare, groceries, pharmacies, parks, and so on). Each destination has its
own folder, and each data source inside it has its own scripts, from download
to a finished GeoPackage. Run everything from the repository root.

## Layout

```
destinations/
  R/                 sourced helpers (not run directly)
  <destination>/     one folder per destination type
  comparisons/       cross-source comparisons (90-series)
  tests/             Data Axle tests
  docs/              source catalog and Data Axle method notes

data/destinations/   (git-ignored)
  <destination>/raw/<source>/       untouched downloads or exports
  <destination>/interim/<source>/   cleaned tables, geocoder files
  <destination>/qaqc/<source>/      checks and review queues
  <destination>/processed/          final layers: <destination>_<source>.gpkg/.csv
  manual/                           human review inputs (never overwritten)
  comparisons/<name>/               comparison outputs
```

## Script names

`<stage>_<verb>_<source>_<destination>.R`. The stage number means the same
thing in every folder; a source that does not need a stage has no script with
that number.

| Stage | Verb | Does |
|---|---|---|
| 01 | `pull` | Download from the source into `raw/<source>/` |
| 02 | `clean` | Standardize, filter, screen into `interim/<source>/` |
| 03 | `geocode` | Add coordinates when the source has none |
| 04 | `build` | Write `processed/<destination>_<source>.gpkg` |
| 05 | `map` | Diagnostic maps |

Source names: `texas_hhsc`, `usda_snap`, `tsbp` (Texas State Board of
Pharmacy), `cms_nppes`, `austin_open_data` (City of Austin Socrata), and
`dataaxle` (manual Data Axle exports).

## Destinations and sources

| Destination | Source | Scripts | Final output |
|---|---|---|---|
| childcare | texas_hhsc | 01 → 03 → (03b) → 04 → 05 | `childcare_texas_hhsc.gpkg`, `childcare_texas_hhsc_h8_opportunities.csv` |
| groceries | usda_snap | 01 → 02 → 04 | `groceries_usda_snap.gpkg` |
| groceries | dataaxle | 02 → 04 | `groceries_dataaxle.gpkg` |
| pharmacies | tsbp + dataaxle | 01 → 05 | `pharmacies_final.gpkg` |
| healthcare | cms_nppes | 01 → 04 | `healthcare_cms_nppes.gpkg` |
| healthcare | dataaxle | 02 → 04 | `healthcare_dataaxle.gpkg` |
| parks | austin_open_data | 01 → 04 | `parks_austin_open_data.gpkg` |
| parks | dataaxle | 02 → 04 | `parks_dataaxle.gpkg` |
| libraries | austin_open_data | 01 → 04 | `libraries_austin_open_data.gpkg` |
| libraries | dataaxle | 02 → 04 | `libraries_dataaxle.gpkg` |
| recreation_centers | austin_open_data | 01 → 04 | `recreation_centers_austin_open_data.gpkg` |
| community_organizations | dataaxle | 02 → 04 | `community_organizations_dataaxle.gpkg` |

Final outputs are in `data/destinations/<destination>/processed/`.
Candidate government sources not yet pulled are listed in
[`docs/GOVERNMENT_SOURCE_CATALOG.md`](docs/GOVERNMENT_SOURCE_CATALOG.md).

## Run commands

```sh
# Childcare (Texas HHSC licensing data)
Rscript destinations/childcare/01_pull_texas_hhsc_childcare.R
Rscript destinations/childcare/03_geocode_texas_hhsc_childcare.R
Rscript destinations/childcare/03b_retry_geocode_texas_hhsc_childcare.R   # optional
Rscript destinations/childcare/04_build_texas_hhsc_childcare_gpkg.R
Rscript destinations/childcare/05_map_texas_hhsc_childcare.R

# Groceries (USDA SNAP)
Rscript destinations/groceries/01_pull_usda_snap_groceries.R
Rscript destinations/groceries/02_clean_usda_snap_groceries.R
python3 destinations/groceries/03_audit_usda_snap_classification.py
Rscript destinations/groceries/04_build_usda_snap_groceries_gpkg.R
Rscript destinations/groceries/05_build_final_usda_snap_grocery_inventory.R

# Pharmacies (Texas State Board of Pharmacy)
Rscript destinations/pharmacies/01_pull_tsbp_pharmacies.R
Rscript destinations/pharmacies/02_clean_tsbp_pharmacies.R
Rscript destinations/pharmacies/03_geocode_tsbp_pharmacies.R
Rscript destinations/pharmacies/04_build_tsbp_pharmacies_gpkg.R
Rscript destinations/pharmacies/02_clean_dataaxle_pharmacies.R
Rscript destinations/pharmacies/04_build_dataaxle_pharmacies_gpkg.R
Rscript destinations/pharmacies/05_build_final_pharmacies_inventory.R

# Healthcare (CMS NPPES; four selected facility taxonomies)
Rscript destinations/healthcare/01_pull_cms_nppes_healthcare.R
Rscript destinations/healthcare/02_clean_cms_nppes_healthcare.R
Rscript destinations/healthcare/03_geocode_cms_nppes_healthcare.R
Rscript destinations/healthcare/04_build_cms_nppes_healthcare_gpkg.R

# City of Austin Open Data (same pattern for libraries and recreation_centers)
Rscript destinations/parks/01_pull_austin_open_data_parks.R

# Metro parks (Trust for Public Land ParkServe)
python3 destinations/parks/01_pull_parkserve_parks.py
Rscript destinations/parks/04_build_parkserve_parks_gpkg.R
Rscript destinations/comparisons/93_compare_parkserve_austin_open_data_parks.R
Rscript destinations/comparisons/94_describe_parkserve_open_access_parks.R
Rscript destinations/parks/04_build_austin_open_data_parks_gpkg.R
Rscript destinations/comparisons/95_describe_austin_open_data_parks.R
Rscript destinations/parks/05_build_final_parks_inventory.R
Rscript destinations/libraries/05_build_final_libraries_inventory.R
Rscript destinations/pharmacies/05_build_final_pharmacies_inventory.R

# Data Axle (same pattern for every destination with exports)
Rscript destinations/groceries/02_clean_dataaxle_groceries.R
Rscript destinations/groceries/04_build_dataaxle_groceries_gpkg.R
```

Saved downloads and geocoder responses are reused where a script says so
(`REFRESH_TSBP=true`, `REFRESH_TSBP_GEOCODE=true` force a new pull). Data Axle
batch handling, screening rules, and manual review are described in
[`docs/DATAAXLE_PIPELINE.md`](docs/DATAAXLE_PIPELINE.md).
The eligibility, source-integration, coordinate, and deduplication rules for
the final pharmacy inventory are documented in
[`pharmacies/METHODS.md`](pharmacies/METHODS.md).
The current NPPES selection, geocoding, counts, and unresolved methodological
issues are documented in [`healthcare/NPPES_METHODS.md`](healthcare/NPPES_METHODS.md).

## Comparisons

```sh
Rscript destinations/comparisons/90_describe_dataaxle_destinations.R
Rscript destinations/comparisons/91_compare_dataaxle_austin_open_data_parks.R
Rscript destinations/comparisons/92_compare_usda_snap_dataaxle_groceries.R
```

These describe or compare sources; they do not feed the final layers.

## Adding a new source

1. Pick the destination folder (create `destinations/<destination>/` if new).
2. Name the scripts `<stage>_<verb>_<source>_<destination>.R`, using the stage
   numbers above.
3. Source `destinations/R/destination_paths.R` and use `destination_dir()` and
   `destination_output_path()` so files land in the standard folders.
4. Add a row to the table above.

## Childcare notes

The childcare layer uses Texas HHSC Child Care Regulation licensing data
(dataset `bc5r-88dy`). Step 01 retrieves operations for Travis, Williamson,
Hays, Bastrop, and Caldwell counties and prepares Census batch geocoder input.
Step 03 submits addresses to the Census geocoder. Step 04 joins the saved
coordinates and creates H8 capacity and facility counts. Step 05 produces
destination diagnostics in `figures/childcare/`.
`accessibility/03-analysis/05_childcare_od_accessibility_test.R` then
aggregates opportunities to H7 and uses the advisor-provided AM-peak OD matrix;
see `accessibility/README.md`.

To retry unmatched addresses, run step 03b after step 03, then explicitly
select its combined output when rebuilding opportunities:

```sh
Rscript destinations/childcare/03b_retry_geocode_texas_hhsc_childcare.R
CHILDCARE_GEOCODE_PATH=data/destinations/childcare/interim/texas_hhsc/childcare_geocoded_combined.csv Rscript destinations/childcare/04_build_texas_hhsc_childcare_gpkg.R
```

Use the default step-03 file if there were no unmatched addresses. Selecting
the retry file explicitly avoids silently reusing an older retry result.
Inspect the geocoding and capacity summaries under
`data/destinations/childcare/qaqc/texas_hhsc/` before interpreting accessibility.

The destination catchment is the Austin-Round Rock-San Marcos five-county metro
boundary (CBSA 12420; January 1, 2025 vintage), matching the H8 automobile OD
matrix geography. The point layer retains all facilities inside that boundary
and includes `od_matrix_eligible`. The H8 opportunity table excludes any
boundary-edge facility whose H8 cell is absent from the supplied matrix grid;
those records are documented in `childcare_od_matrix_edge_exclusions.csv`.
Capacity means reported
capacity, not available vacancies. Missing capacity is omitted from slot sums;
facility counts still include those operations. Listed Family Homes are
included in the primary measures, with separate licensed-capacity fields.

Retain the source and geocoding snapshots for reproduction: the source download
and the `Public_AR_Current` geocoder benchmark can change. Individual
destination files include home-based operations at residential addresses and
remain local.

### Superseded checkpoint: 2026-09-10

Rebuilt step 04 from the saved normalized data and original geocode file:
892 facilities, 78,138 reported slots, and 559 H8 cells. Ran the AM-peak
accessibility script for 151 Austin H7 origins at four cutoffs (604 rows).
All results matched an independent join-and-sum calculation of opportunities
within each cutoff; uniqueness, missing-value, and monotonicity checks passed.
The script generated both maps, and the 30-minute map was visually inspected.
R syntax checks passed for all destination scripts. The source download and
external geocoding requests were not rerun.

Remaining data-quality review: 123 of 1,404 source operations had no
coordinates. Licensed-center geocoding matched 88.8%, and the HHSC-versus-Census
coordinate comparison contains large outliers despite a 67-metre overall
median. Inspect these discrepancies before treating this test as final
research evidence.

The September 10 checkpoint used an earlier Austin-plus-five-mile catchment.
The current build replaces that limited geography with the complete metro
boundary; use the current QA/QC files for counts.
