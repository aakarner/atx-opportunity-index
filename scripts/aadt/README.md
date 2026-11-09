# Traffic proximity on the shared Austin H8 grid

Run from the repository root with `Rscript scripts/aadt/aadt_read.R`.
Required R packages are sf, h3jsr, units, httr2, jsonlite, digest, and yaml.
The first run downloads the public TxDOT AADT features. Later runs use the
checksummed snapshot in `source/` and can run offline.

The corrected deliverables are `aadt_metrics.csv` and
`aadt_metrics_hex8.gpkg`. Both have one row per H3 resolution 8 cell used by
the current municipal-boundary/accessibility workflow. `h3_id` is the stable
join key. `name` retains the same H3 ID for compatibility with the earlier
CSV, and `id` is a sequential row number.

| Field | Meaning |
| --- | --- |
| `distance_to_high_vol_ft` | Distance from the canonical H3 cell center to the nearest road with AADT_CUR greater than 50,000, in international feet |
| `fraction_overlap` | Fraction of the full hexagon area within 300 meters of any qualifying road, from 0 to 1 |

## Spatial method

The script uses the shared October 19, 2026 City of Austin full- and
limited-purpose boundary, including Dog's Head. `municipal_h8_ids()` selects
the same cell centers as the accessibility workflow. It retains complete
hexagons and verifies the IDs against the accessibility input. The grid and
boundary are exported as `hex_8_full.gpkg` and `austin_city_limits.gpkg`.

Distances and buffer/area operations use NAD83 / UTM zone 14N (EPSG:26914).
Distances originate at canonical H3 centers. Buffers have rounded ends and
are dissolved before intersecting cells, so overlapping corridors are counted
once. A 300-meter buffer is approximately 984 feet. This preserves Peter's
300-meter parameter. Zero overlap is retained, and distance is never truncated
at the buffer radius.

The road query covers the grid's bounding box plus 20 kilometers on all sides.
Features are selected by intersection with that envelope and downloaded whole,
including portions outside Austin. For every cell, the script verifies that
the nearest qualifying road is closer than the query boundary and that the
entire cell plus its buffer lies inside the query envelope. These checks ensure
roads omitted by the spatial query cannot alter either metric.

## Provenance and checks

`source/manifest.json` records the service URL, retrieval time, query extent,
threshold, feature count, and source-file hashes. Each download page must match
its requested object IDs. The source edit timestamp must remain stable during
acquisition. Cached inputs are verified before every run. A changed grid or
query requires a new source directory/snapshot.

`aadt_metrics.metadata.json` records the source extraction dates, municipal
boundary checksum, parameters, output ranges, and output checksums. TxDOT's
`EXT_DATE` records extraction from its roadway inventory. The layer does not
provide an observation year for each `AADT_CUR` value. Query completeness does
not establish that every road has a current traffic observation.

Run `Rscript tests/test_aadt.R` after rebuilding. The checks cover projection
units, rounded endpoints, dissolved overlaps, retained zeros, adequate road
search extent, exact agreement with the map's cell IDs, Dog's Head, matching
CSV/GeoPackage values, and input/output hashes.

The historical `aadt_sum_hex8.gpkg` from upstream is superseded and is not
produced by this workflow. Allocating each segment's AADT as an extensive
quantity makes the result depend on how roads are segmented. Use the two
metrics above for integration. This preparation step supplies the corrected
traffic data consumed by the targets pipeline and interactive map.

## Pipeline and map integration

`config/pipeline.yml` selects the CSV. Targets tracks it and its metadata as
files, validates the checksum, boundary and H8 IDs, and joins the measurements
to `h8_components`. Integration fields are `traffic_distance_ft` and
`traffic_buffer_share`. Site profiles use the containing H8 without a nearest
cell fallback. Tracts average the H8 measurements using intersection areas in
EPSG:5070 as weights. The denominator is covered area with both measurements.
`traffic_coverage_share` reports that area as a fraction of the city-clipped
tract. An uncovered tract has missing measurements and zero coverage.

The tract buffer measure is an area-weighted mean of full-H8 fractions. It
assumes those fractions represent intersecting parts of each cell. It is an
approximate summary of the H8 surface. No population weighting is applied.

The map includes both layers under Burdens and both values in hexagon and
tract profiles. Tract profiles show represented area. Colors display measurement
ranges; the combined access/industrial-air flags retain their existing rules.
The pipeline exports the fields in its H8, tract, and site tables, component
maps, source manifest, registry, QA, and public map assets.
