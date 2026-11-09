# Environmental and safety burdens: current scope

User decision, November 9, 2026: remove recurring power outages. The five domains
to score are industrial air pollution, traffic-related pollution, heat, street
safety, and pedestrian barriers. Their scoring transformations, benchmarks, and
weights remain under discussion. Tree canopy is protective context rather than
an additional independent heat burden. Noise has not been adopted separately.

Flooding is a **hard development-eligibility constraint**, not a scored burden.
It has no weight and cannot be compensated by benefits or low values elsewhere.
The policy is recorded in `config/burdens.yml`. No existing benefit inputs,
profile weights, minima, or descriptive scores change when flood status changes.

## Flood eligibility rule

Use the City's published **Fully Developed Floodplain**, FloodPro MapServer layer
9, rather than the earlier standalone FEMA 1%-annual-chance layer:

- [Official GIS layer](https://maps.austintexas.gov/gis/rest/FloodPro/FloodPro/MapServer/9)
- [City explanation of the regulatory mapping](https://www.austintexas.gov/watershed-protection/programs/floodplain-management)

The City layer combines its studies with interim regulatory categories. Use the
whole published regulatory layer, including nested 25-year and mapped shallow
flood areas; dissolve overlaps once. Do not filter solely for a category named
“Fully Developed 100-Year” and thereby omit the City's other regulatory polygons.
Recognized zone values are checked on acquisition/read; unexpected categories
require review. This snapshot does not substitute a generic FEMA layer or a TWDB
social-vulnerability measure for the City layer.

| Geography / result | Status |
|---|---|
| Entire **full H3 hexagon** covered by the dissolved floodplain | Ineligible for development |
| Positive area overlap but some hexagon area remains outside | Partial overlap; actual address check required |
| No mapped floodplain area in the hexagon | Not excluded by this flood rule |
| Selected address/map point inside or on the floodplain boundary | Ineligible for development |
| Selected address/map point outside the floodplain | Not excluded by this flood rule |
| Unknown coordinates, unavailable data, or unsupported geography | Unknown; never counted as passing |

Hex eligibility uses geometric `covered_by`, not the centroid and not a rounded
area percentage. A cell that is 99.999% flooded is still partial if any area lies
outside. Full cells include water and portions beyond the municipal boundary;
source polygons are not prematurely clipped to the City. An ineligible address
does **not** make its entire partially flooded hexagon ineligible. Point checks
respect polygon holes and include floodplain boundaries.

Tract profiles report overlap as context and direct the user to an actual address.
No tract-average percentage is used to declare every address ineligible. A
geocoded address is a point screen, not a proposed building footprint or parcel
survey. The UI labels this as the project's eligibility rule, not a permit
determination. “Not excluded” only addresses this constraint, not general site
approval or the absence of all flooding.

## Implementation and reproducibility

```sh
python3 scripts/prepare/pull_fully_developed_floodplain.py
Rscript scripts/run_pipeline.R flood_constraint_assets site_profile_file registry_file manifest_file
Rscript tests/test_flood_eligibility.R
# Run the JavaScript tests with an available Node runtime:
node tests/test_flood_eligibility.mjs
```

The acquisition script obtains all features intersecting the bounding envelope of
the complete hexes and City geometry. It verifies exact object IDs on every page,
rechecks the ID set at completion, retains source modification fields and metadata,
and writes SHA-256 checksums. The service supplies no global editing timestamp;
this is not a guaranteed transactional snapshot of concurrent attribute edits.
The dated cache is immutable: a changed source or study envelope requires a new
snapshot. Reads verify every cached source file. Missing or mismatched inputs
stop the build rather than substituting zero overlap.

`R/flood_eligibility.R` implements union, area and point screens, provenance, and
exports. The targets graph builds the constraint separately from legacy FEMA
context. Existing site profiles receive `flood_ineligible` and
`flood_eligibility_status`; a positive exclusion overrides `overall_screen`.
The indicator registry identifies the City layer as `eligibility_constraint` and
the old FEMA measure as `legacy_context`.

Outputs:

- `site/assets/flood-eligibility.json`: all current hex statuses, tract area
  shares, source metadata and policy. `flood-geometry.geojson` carries the
  unsimplified per-hex flood geometry separately.
- `output/components/flood-eligibility/`: hex, tract, and example-site CSVs plus
  point fixtures for independent browser-versus-sf verification.
- Public-client source: separate Eligibility view; persistent dark flags for
  fully excluded hexes across map modes; actual-point status at the top of each
  address profile. The browser uses unsimplified per-hex flood polygons, exported
  at ten decimal places. Benefits remain visible as descriptive information.

Publication uses the repository’s `scripts/site/publish.sh` workflow. It validates
the flood snapshot and versions its geometry, metadata, and client module together.
Independent point fixtures are committed under `tests/fixtures/` so release and
CI checks do not require the local targets store.

## Overlap gut-check, November 9, 2026

An independent intersection of the 1,029 full hexes with the **original,
undissolved City polygons** reproduces all 801 touched hexes. There are 800
partial cells, one entirely covered cell, and 228 with no overlap. Dissolving
the source before area calculation prevents overlapping categories from being
counted twice. This is a count of cells touched, not a percentage of flooded area.

| Share of full hex in the mapped floodplain | Hexes |
|---|---:|
| No overlap | 228 |
| Positive, under 1% | 100 |
| 1% to under 5% | 165 |
| 5% to under 10% | 128 |
| 10% to under 25% | 239 |
| 25% to under 50% | 110 |
| 50% to under 100% | 58 |
| Entirely covered | 1 |

The mapped floodplain covers 112.505 km² of 865.355 km² of full hex area
(13.001%). The median partial cell is 10.226% covered. There are 28 positive
overlaps below 0.1%; the smallest is about 5.11 m². Tiny intersections do occur,
but they do not account for most of the 800 partial cells. No minimum overlap
cutoff is applied to eligibility.

The denominator includes water and full cells extending beyond city limits;
this is not an estimate of developable land or the exact City land percentage.
The City's general statement that about 10% of Austin land is floodplain is a
rough plausibility check, not a matching denominator or independent validation.
Source renderer labels confirm that A/AE/AO polygons are City interim 25-year
categories and “Shallow” is fully developed 100-year shallow flooding. These
remain part of the published layer; no additional generic FEMA layer is added.

`Rscript scripts/flood/audit_overlap.R` reproduces the count and area audit in
`output/components/flood-eligibility/overlap-audit.json` using cached targets.
The Eligibility view now defaults to the actual floodplain footprint over
lightly outlined hexes. “Show actual floodplain” can be toggled in every view.
The drawing uses the same unsimplified geometry as point classification, clipped
to the study hexes; Leaflet simplifies screen rendering at each zoom. No geometry
or eligibility thresholds were changed for this display update.
