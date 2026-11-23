# Environmental and safety burdens: current scope

The combined burden score requires five components. Heat contributes one third.
Industrial air, near-road traffic, fatal and serious-injury crashes, and
sidewalk gaps on major streets each contribute one sixth. A missing component withholds
the score. Crashes and sidewalk gaps use the same observation windows and are scored and
mapped individually.

Overall high burden requires **at least two high components**, independent
of the weighted score. The classification rule was adopted November 15, 2026.
Each primary component warning remains visible regardless of the average or
overall classification. At least two known high components plus missing data is
labeled high/incomplete. Fewer than two known high components plus missing data
is incomplete, not unflagged. Complete assessments with zero or one high component
are labeled below the overall high-burden threshold, not free of component warnings.
Secondary industrial review and limited heat observations remain separate badges
and do not count toward the two-component threshold. Flood eligibility is separate.
The public map includes the approved quarter-mile street and 25% traffic-flag
sensitivities. Flood eligibility stays independent and overrides score colors.
Of the 1,029 half-mile windows, 874 have a complete score. Overall high burden applies to 185 hexagons, including one with an incomplete score. Another 690 have complete scores below the overall threshold, and 154 have incomplete assessments with fewer than two known high components. At least one component is high in 551 hexagons.

### Census tract estimates

Tracts use the same population weights as combined benefits. Each hexagon contributes its estimated residents multiplied by the share of its full area inside the city-clipped tract. Each component mean uses hexagons with that component observed. The combined mean uses hexagons with all five scores. The map reports the resident share covered by each mean and the tract area with known population weights. A zero denominator gives an unavailable estimate.

High-burden shares count residents in hexagons already classified as high and divide by all represented residents with known weights. A hexagon with two known high components counts as high even if its combined score is missing. The unknown classification share is reported separately. A tract with no classifiable resident weight has an unavailable high-burden share. Both street radii and both traffic-flag thresholds follow these rules. Flood eligibility remains a hexagon or address assessment.

The public JSON includes both radii under `tracts`. The pipeline also writes `tract_primary.csv` and `tract_sensitivity.csv` in `output/components/combined-burdens/`. Each row has the tract GEOID in `id`. Fields ending in `_pct` are percentages of represented residents. Area coverage fields are fractions of the clipped tract area.

Implementation: `R/combined_burdens.R`, `combined_burden_assets` target,
`site/assets/combined-burdens.json`, and `site/combined-burdens.mjs`. The browser
recomputes every assessment and checks its agreement with the R export before
drawing the map. Run `Rscript tests/test_combined_burdens.R` and
`node tests/test_combined_burdens.mjs`. Rebuild with
`Rscript scripts/run_pipeline.R combined_burden_assets`, or use
`Rscript scripts/build_combined_burdens.R` to rebuild just the combined export
from existing component analyses (their policies must match current configuration).
The version 5 export stores the five component scores and their weights directly. `overall_high` and `high_component_count`
describe the adopted classification, while `any_high` retains its individual-warning
meaning. `counts.high` counts overall high classifications; `counts.any_component_high`
counts cells with at least one warning. Both street radii and both traffic-flag
settings apply the same two-component rule. The quarter-mile setting identifies
163 overall high cells; the 25% traffic flag identifies 218 at half mile and 198
at quarter mile. Sensitivities change classification but not score weights.
The map classification layer, count, and profile badge use the overall rule;
dashed orange outlines on the combined-score map also require at least two high
components, including known overall high burden with an incomplete score.
Individual component maps retain their own high-component outlines, and profiles
retain all individual warnings.

Tree canopy is protective context rather than
an additional independent heat burden. Noise has not been adopted separately.

Flooding is a **hard development-eligibility constraint**, not a scored burden.
It has no weight and cannot be compensated by benefits or low values elsewhere.
The policy is recorded in `config/burdens.yml`. No existing benefit inputs,
profile weights, minima, or descriptive scores change when flood status changes.

## Crashes and sidewalk gaps on major streets

Both components use straight-line circles around each H3 center, clipped to Austin. The adopted radius is half a mile and the sensitivity radius is a quarter mile.

**Sidewalk gaps on major streets** measures the percentage of major-street length without a mapped sidewalk or parallel path, counting each side separately. Eligible streets include collectors, arterials and public service roads. A mile with a sidewalk along only one side has one of two frontage miles served and scores 50. Local residential streets are outside the denominator. The component is high at 50 or above. The map profile reports served and unserved percentages and the underlying frontage miles. The measure describes infrastructure along major roads. It does not estimate walking activity or the comfort of walking on a local street.

| City-clipped radius | Scored | High sidewalk gap burden | No eligible major street | Coverage unknown |
|---|---:|---:|---:|---:|
| Half mile | 874 | 358 | 125 | 30 |
| Quarter mile | 731 | 297 | 271 | 27 |

Coverage is unknown when a window has eligible frontage, no pedestrian inventory linework and no matched facility. Where the inventory is present, zero matched frontage gives a score of 100. Raw served and eligible lengths are available at both radii. [Source and geometry methods](../scripts/pedestrian/README.md)

**Crash density** counts unique fatal or suspected serious-injury crashes across all road users in 2020–2024, per year per observed square mile. The score is `min(100, 100 × annual_KSI_density / 6.1118601065110614)`. The high flag starts at 4.2772765182635766. These are the frozen 95th and 90th percentiles across the original 1,029 half-mile origins (unweighted R type-7 quantiles). Both radii use the same anchors.

## Adopted heat scoring, November 10, 2026

Use the validated reconstructed **relative heat percentile** as the 0–100 burden
score and flag **score >=90**. Keep scores with **fewer than eight eligible dates**
and show a separate limited-observation flag. An eligible date observes at least
half the hex's land area. An origin with no eligible observations is unavailable.
Hot-pixel share remains context and carries no additional score weight. The
reference is pinned; filtering thin observations never reranks the remaining cells.

All 1,029 origins are scored; 103 are high heat and 257 have limited observations,
including 21 that have both flags. High-heat cells contain 14.70% of known estimated
residents and 15.73% of known estimated children. See [the heat workflow](heat.md)
for the validation, pinned inputs and reproducible scoring/report commands.
The report is `output/components/heat-burden/review.html`.

## Adopted industrial-air scoring, November 10, 2026

The user adopted the linear score capped at 100 at ToxConc **622.73023119285699**,
the high-burden flag at **351.10409694733289**, and a separate secondary review
band **100 <= ToxConc <351.10409694733289**. Exact anchors are frozen in
`config/burdens.yml`. The review band does not trigger the high-burden flag or add
score points. Missing data or incomplete grid coverage remain unavailable.

All 1,029 origins are scored. There are 103 high-burden hexes (3.87% of known
estimated residents), 231 secondary-review hexes (26.91%), and 695 below the review
band. The median score is 8.39. `industrial_air_burden_assets` builds per-origin
scores/flags, GIS exports and provenance. The report is
`output/components/industrial-air-burden/review.html`; see [the RSEI workflow](rsei.md)
for reproduction and tests.

## Adopted near-road traffic score, November 10, 2026

Score the percentage of full hex area within **300 m** of roads carrying
**more than 50,000 vehicles/day** directly from 0–100. The primary high-burden
flag is **overlap >=50%**; **>=25%** is a broader flag sensitivity, with no change
to the underlying score. Nearest-road distance remains context only and is
measured from the canonical hex center. An address-specific distance is not
inferred from it. Missing overlaps remain unavailable and measured zeros remain
zero; neither zero nor falling below a flag establishes clean air.

All 1,029 origins are scored, including 717 with no qualifying corridor overlap.
There are 123 primary flags (12.17% of known estimated residents) and 201 flags
under the sensitivity (21.97%), adding 78 origins. The source observation year
for individual AADT values is unspecified; the November 2026 extraction date
is not an observation year. These are proximity screening parameters, not health
standards or pollutant concentrations.

`traffic_burden_assets` successfully builds scores/flags, distance context,
GIS exports and metadata. The report is
`output/components/near-road-traffic/review.html`; see
[the traffic workflow](../scripts/aadt/README.md) for reproduction and tests.

## Historical overall weight comparison, November 10, 2026

The user requested a comparison of equal thirds by broad theme (heat 1/3, street
safety 1/3, industrial air 1/6, traffic 1/6) against equal quarters across the four
domains. The equal-theme preset was adopted. Both require every weighted domain;
missing data do not cause weights to be redistributed. Component high-burden
flags, industrial-air secondary review and heat observation flags remain fixed.

Reproduce with `Rscript scripts/air/compare_burden_weights.R`, then run
`Rscript tests/test_burden_weight_review.R`. Candidate weights are isolated in
`config/burden-weight-review.yml`. The report and all per-origin scores, rank
changes, contribution tables, maps and source hashes are under
`output/components/burden-weight-review/`.

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
`flood_eligibility_status`; `overall_screen` describes the point’s flood status.
The indicator registry identifies the City layer as `eligibility_constraint` and
the old FEMA measure as `legacy_context`.

Outputs:

- `site/assets/flood-eligibility.json`: all current hex statuses, tract area
  shares, source metadata and policy. `flood-geometry.geojson` carries the
  unsimplified per-hex flood geometry separately.
- `output/components/flood-eligibility/`: hex, tract, and example-site CSVs plus
  point fixtures for independent browser-versus-sf verification.
- The public map marks fully excluded hexes in dark gray across map modes and
  gives the selected point’s flood status at the top of each address profile.
  The browser uses unsimplified per-hex flood polygons, exported
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
“Show actual floodplain” displays the floodplain footprint in every map view.
The drawing uses the same unsimplified geometry as point classification, clipped
to the study hexes; Leaflet simplifies screen rendering at each zoom. No geometry
or eligibility thresholds were changed for this display update.
