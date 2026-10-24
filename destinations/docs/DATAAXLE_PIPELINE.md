# Data Axle destination pipeline

## Run as new batches arrive

Data Axle exports are licensed, so they live under the git-ignored `data/`
folder, one folder per destination:

```
data/destinations/<destination>/raw/dataaxle/*.csv
```

Destinations with Data Axle exports: `groceries`, `healthy_foods`,
`healthcare`, `libraries`, `museums`, `parks`, `pharmacies`,
`community_organizations` (listed in `destinations/R/dataaxle_config.R`).
Custom, Summary, and Detail exports may be mixed. Add batches, then run the
two scripts for that destination from the project root, for example:

```sh
Rscript destinations/groceries/02_clean_dataaxle_groceries.R
Rscript destinations/groceries/04_build_dataaxle_groceries_gpkg.R
```

Step 02 reads every CSV directly inside `raw/dataaxle/`. Nested subfolders are
not scanned. All batches are treated as one cumulative inventory: a newer
download does not remove a business from an older batch. Archive superseded
batches outside the input folder when replacing a vintage. To add a new
destination, create its `raw/dataaxle/` folder, add it to
`dataaxle_destinations` and `dataaxle_rules`, and copy the two scripts.

Raw files are never modified. No network requests or geocoding submissions are
made. Nothing is committed or pushed by this workflow.

## What is retained

The standardized record keeps business name, parent name, full street address,
city/state/ZIP, county, Data Axle ID where supplied, website, phone, primary
NAICS and SIC codes/descriptions, location type, source record type, and
coordinates. Eight-digit Data Axle NAICS extensions are preserved; `naics6`
provides the first six digits separately. Identifiers and ZIPs remain text.
Executive names, financial/property estimates, and other unrelated export
columns are omitted from the standardized layer. The original exports retain
all attributes for later inspection.

Each record also carries a stable destination ID, source filenames/count,
classification reason, review state, coordinate status, and H7/H8 cell IDs.
The source-row audit links each selected input row to its consolidated ID.
The input manifest records SHA-256 checksums, paths, and row counts.

## Duplicate handling

Exact normalized business name plus full address/city/state/ZIP identifies
repeat records across batches and Summary/Detail exports. Missing fields are
filled from the other matching rows. Latitude and longitude are always taken
as a pair from one row. Conflicting codes, IDs, or coordinates trigger review.
When an address is incomplete, matching source IDs can consolidate otherwise
identical records; records without that evidence remain separate and flagged.
Changing the identity fields creates a new ID. Old unmatched reviews are
reported for reconciliation rather than transferred by guesswork.

Different businesses sharing an address are flagged, not automatically merged.
Data Axle IDs occurring at multiple identities also trigger review. By default
these two checks compare against the exports of every destination, so a grocery
and its in-store pharmacy are both flagged; set `dataaxle_duplicate_scope` in
`dataaxle_config.R` to `"within_destination"` to compare within one destination. No fuzzy
name matching is used. This conservative approach can leave duplicate listings
for human review. Resolve service-location duplicates before final counting.
A destination appearing in multiple types is counted once within each type;
do not sum type counts as a count of unique destinations.

## Map first, review later

Open `data/destinations/<destination>/processed/<destination>_dataaxle.gpkg` in QGIS or another GIS.
It contains a `candidates_<type>` point layer for each type with plausible
coordinates. Review/excluded records are retained for inspection and carry
`screen_decision` and `analysis_ready` flags. Classification uncertainty does
not stop a point from appearing on the map.

Data Axle coordinates are reused with `coordinate_source=dataaxle_unverified`.
The numeric and regional bounding-box checks do not verify the address,
entrance, service location, or public accessibility. Candidates are not clipped
to Austin or a five-mile buffer. The initial regional screen is longitude
-99 to -96 and latitude 29 to 32; revise `dataaxle_bbox` for a different region.
Points outside that screen are kept in the master and geocoding queue.

`data/destinations/<destination>/qaqc/dataaxle/geocoding_queue.csv` identifies missing/invalid coordinates
and conflicting pairs. Correct locations using verified evidence and enter
`destination_id`, `record_fingerprint`, latitude, longitude, coordinate source,
reviewer, date, and evidence in `data/destinations/manual/dataaxle_coordinate_corrections.csv`.
The script creates an empty input template once and never overwrites it.
Corrections with invalid coordinates or stale fingerprints are reported and
cannot make a record analysis-ready. Coordinate correction and service
classification are separate decisions.

## Screening rules and human decisions

The rules are initial operational screens based on the codes in these exports,
not an advisor-approved definition of opportunity. Grocery retailer, public
library, and museum codes receive provisional inclusion unless another flag
requires review. Parks, healthcare, healthy-food subtypes, community
organizations, and unknown codes remain review candidates. Hospitals are
split into proposed service types; surgical centers are not automatically
classified as urgent care. Juice retailers stay distinct from produce markets.

For community organizations, later map/site review should establish:

1. What service operates at the listed location?
2. Who can use it, and are there membership, referral, eligibility, or other
   access restrictions?
3. Is this a service site, administrative office, residential facility,
   commercial listing, or duplicate of another service location?
4. Which destination type should it count toward, and what evidence supports
   that decision?

Use an organization website, service directory, or documented location check;
record the URL/reference and a short rationale. Business name or nonprofit
status alone does not establish an eligible community service.

Review candidates are in `data/destinations/<destination>/qaqc/dataaxle/review_queue.csv`.
Copy completed rows into the shared `data/destinations/manual/dataaxle_reviews.csv`,
retaining these columns:

- `collection`, `destination_id`, `record_fingerprint`: copy unchanged.
- `review_decision`: `include`, `exclude`, or `review`.
- `reviewed_type`: final type using lowercase letters/digits/underscores.
- `reviewer`, `reviewed_on`, `evidence`, `notes`: document the decision.

Rerun the destination's step 02 and 04 to apply decisions. Input files are never overwritten. A changed
record fingerprint holds the decision for rereview. An identical duplicate
batch does not invalidate it. Rule changes should update `dataaxle_rule_version`.
The queue is regenerated; do not use it as the only saved copy of your edits.

## Outputs for analysis

Per destination, under `data/destinations/<destination>/`:

- `interim/dataaxle/dataaxle_standardized.{csv,rds}`: all consolidated records and flags.
- `processed/<destination>_dataaxle.gpkg`: map candidates, one `candidates_<type>` layer per proposed/final type.
- `processed/<destination>_dataaxle_analysis_ready.csv`: included records with plausible coordinates,
  no unresolved coordinate conflict, and complete identity/address fields.
  `classification_basis` distinguishes provisional rules from manual review.
- `processed/<destination>_dataaxle_h7_counts.csv`, `_h8_counts.csv`: unique included
  business-location counts by type and cell, for a later OD join.
- `qaqc/dataaxle/`: source rows, input manifest, summary, duplicate review,
  review queue, geocoding queue, orphaned reviews, and unapplied corrections.

These are counts of business listings after the stated cleaning rules, not
service capacity. No category with only pending records is silently treated as
zero opportunities: it is absent from the counts and visible in the QA summary.
Before automobile accessibility analysis, settle the eligible service universe,
review coverage against the OD destination geography, and select the required
classification basis. These scripts do not run accessibility or replace the
separate HHSC childcare workflow.

## Validation

```sh
Rscript destinations/tests/test_dataaxle.R
Rscript destinations/tests/test_dataaxle_pipeline.R
```

Tests cover duplicate batches, Summary/Detail enrichment, coordinate-pair
integrity, conflicting attributes, shared addresses, repeatable reruns, saved
inclusion/exclusion, stale review decisions, coordinate corrections, and the
cross-destination shared-address check. The end-to-end test runs in a
disposable project and leaves real exports and review inputs alone.

## Descriptive statistics before classification decisions

After refreshing each destination's step 02, run:

```sh
Rscript destinations/comparisons/90_describe_dataaxle_destinations.R
```

Outputs under `data/destinations/comparisons/dataaxle_descriptive/` include a readable
`classification_review.md`, full NAICS and NAICS–SIC tables, six-digit NAICS
groupings, location-type and city/county frequencies, attribute completeness,
and a record listing with websites and screening reasons. Counts include all
cleaned candidates, not just provisionally included records. Percentages use
the full cleaned collection as denominator. Each summary reconciles to that
denominator; missing codes/descriptions appear as Unknown.

`data/destinations/manual/dataaxle_category_decisions.csv` is a separate, never-overwritten
notes template for proposed retain/exclude/reclassify/needs_review decisions.
These notes are not applied automatically. The record review file
(`dataaxle_reviews.csv`) remains the mechanism for final record decisions.

## Compare Data Axle parks with the City inventory

```sh
Rscript destinations/parks/01_pull_austin_open_data_parks.R   # if not yet saved
Rscript destinations/comparisons/91_compare_dataaxle_austin_open_data_parks.R
```

Uses saved `data/destinations/parks/raw/austin_open_data/parks.geojson`, the
cached 2024 Austin boundary, and all current park CSV batches. Writes a
source-assessment report, map/GeoPackage, 0/100/250/500-metre coverage
sensitivity tables, park-type summaries, all-record name candidates, and
individual match-review tables under
`data/destinations/comparisons/parks_dataaxle_austin_open_data/`. City asset IDs
are dissolved before counting. Full and open/developed reference inventories
are reported separately. Spatial matches are candidates, not confirmed
identities; coordinates and classification require review before interpreting
a definitive source error rate.

## Compare SNAP food retailers with Data Axle

```sh
Rscript destinations/groceries/01_pull_usda_snap_groceries.R
Rscript destinations/comparisons/92_compare_usda_snap_dataaxle_groceries.R
```

The pull script downloads the official current SNAP locator layer for the five
metro counties, checks pagination and source-edit consistency, and saves a
dated/hash manifest under `data/destinations/groceries/raw/usda_snap/`.
Rerunning replaces that cache with the latest snapshot, so preserve it
separately for a frozen research vintage. The comparison uses all groceries
and healthy_foods Data Axle batches against that cached snapshot.

Results under `data/destinations/comparisons/groceries_usda_snap_dataaxle/`
include an assessment report, source point map/GeoPackage, county/type tables,
category crosswalk, candidate pairs, unmatched SNAP grocery candidates, and
coordinate-discrepancy review. Only the SNAP Supermarket, Super Store and
Grocery Store categories define the primary count comparison; matching searches
all types to expose classification differences. No candidate is automatically
accepted as a verified match and no source coordinates or opportunity
definitions are overwritten. These generated review tables are overwritten by
reruns; copy them before recording decisions.
