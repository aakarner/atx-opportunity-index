# Environmental and safety burdens: current scope

User decisions, November 9, 2026: remove recurring power outages and combine
crash density with pedestrian gaps in one street-safety/pedestrian-environment
domain, with provisional internal weights of **50% each**. The four domains
are industrial air pollution, traffic-related pollution, heat, and the combined
street-safety/pedestrian-environment domain. All four domains now have adopted
component scoring rules. On November 10, 2026, the user adopted **equal thirds
across heat, air, and street safety**. Air is split equally between industrial
air and traffic: the four input weights are 1/3 heat, 1/3 street safety,
1/6 industrial air, and 1/6 traffic. Equal four-domain weighting is not retained
as a sensitivity in the public map. The street-safety score retains its internal
50/50 crash/gap split.

All four inputs must be present; missingness withholds the composite without
redistributing weights. Any primary component warning remains visible regardless
of the average. Known high burden plus missing data is labeled high/incomplete;
missing data without a known high component is incomplete, not unflagged.
Secondary industrial review and limited heat observations remain separate badges.
The public map includes the approved quarter-mile street and 25% traffic-flag
sensitivities. Flood eligibility stays independent and overrides score colors.
The exported snapshot has 880 complete scores, 480 high/complete, 38
high/incomplete, 400 without a primary high flag, and 111 incomplete without a
known high flag. The 149 incomplete scores lack pedestrian-gap inputs.

Implementation: `R/combined_burdens.R`, `combined_burden_assets` target,
`site/assets/combined-burdens.json`, and `site/combined-burdens.mjs`. The browser
recomputes every assessment and checks its agreement with the R export before
drawing the map. Run `Rscript tests/test_combined_burdens.R` and
`node tests/test_combined_burdens.mjs`. Component review sections below record the
analysis sequence; their earlier publication and open-decision notes are historical.

Tree canopy is protective context rather than
an additional independent heat burden. Noise has not been adopted separately.

Flooding is a **hard development-eligibility constraint**, not a scored burden.
It has no weight and cannot be compensated by benefits or low values elsewhere.
The policy is recorded in `config/burdens.yml`. No existing benefit inputs,
profile weights, minima, or descriptive scores change when flood status changes.

## Pedestrian-gap readiness review, November 9, 2026

The September 15 technical meeting proposed sidewalk-network coverage. The
September 28 meeting broadened “pedestrian barriers” to missing sidewalks,
high speeds, and conditions discouraging walking. October 12 notes explicitly
said this indicator remained under development; the accompanying slides listed
sidewalk gaps, unsafe crossings, and highway/arterial barriers. These are design
records, not evidence of a completed indicator. A search of the working checkout,
current GitHub main tree, and shared project files found no prepared pedestrian
gap layer, extraction script, or H8 score. The registry still marks it as not
integrated and its source as to be selected.

Public sources identified for preparation:

- [City pedestrian-facility inventory](https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/Sidewalks_%28Public%29/FeatureServer/0):
  existing sidewalks, driveways, shared-use/protected paths, completed shared
  streets, planned shared streets, planned sidewalks, and potential sidewalks.
  The service describes daily maintenance; freeze and validate a dated snapshot.
- [2023 Sidewalks, Crossings and Shared Streets Plan](https://www.austintexas.gov/transportation-public-works/sidewalks-crossings-and-shared-streets-plan):
  a documented crossing-suitability and spacing-gap analysis already exists.
  Obtain and verify the underlying GIS outputs and their vintage/completion
  status before integrating. Its prioritized crossing analysis excludes frontage
  roads, so it cannot represent every highway barrier. Project-priority scores
  include equity considerations and should not substitute for physical gaps.

Recommended first measure (not yet adopted): length of inventoried unbuilt
facilities in the City's planned pedestrian network divided by the corresponding
existing-plus-planned network length. “Required network” was conversational
shorthand, not a verified City GIS classification or a parcel-level legal finding.
The 2023 plan's sections 2.1 and 2.3.1 describe sidewalks on both sides of
arterial/collector streets and one side of some existing residential streets;
new residential streets are described separately as requiring both sides.
Suitable shared streets can substitute for sidewalks on some local streets.
The plan combines universal pedestrian access with context-sensitive retrofit
choices and funding/time constraints; project priority is a separate decision.
The GIS encoding of these rules, particularly potential facilities and one-sided
residential coverage, still needs validation before fixing a denominator.
Establish a consistent street-side/frontage denominator; audit
driveways, potential facilities, shared streets, alternative paths, duplicates,
and missing coverage. Completed shared streets need not have conventional
sidewalks; planned shared streets remain unbuilt. Missing inventories or an
empty denominator remain unavailable, not zero gaps. Compare the measure over
the same one-mile origin neighborhoods as crashes and within full hexes before
selecting its geography. Retain crossing gaps as separately visible diagnostics
until their data and integration rules are validated. This initial measure would
describe network completion, not full ADA compliance or walking-route quality.

## Pedestrian-gap implementation

The inventory-based measure is now prepared for all 1,029 current origins, with
explicit unavailable results where appropriate. The main score is 100 times
planned length divided by completed-plus-planned length; potential sidewalks are
a sensitivity. Both City-clipped hex and one-mile neighborhood versions are
provided. See [the reproducible workflow and findings](../scripts/pedestrian/README.md).
The preceding readiness discussion records the earlier design stage. The current
implementation uses inventoried line length, rather than claiming independently
verified required frontage or a universal two-sided sidewalk denominator.
That initial inventory build preceded selection of the spatial scale and flags.

Following review, the user adopted **half a mile for both crashes and pedestrian
gaps**, keeping **quarter mile as a sensitivity**. `scripts/pedestrian/compare_radii.R` compares matched quarter-
and half-mile windows against the original one-mile baseline, retaining the
2020–2024 crash period. It checks sparse counts, ranking sensitivity, network
denominators and City observation areas. The original one-mile inventory build
configuration remains a historical baseline; the adopted radius is recorded in
the combined-domain spatial policy. Matching half- and quarter-mile data are
already available in the comparison outputs. The combined-domain implementation
below now scores both adopted radii; public-map publication remains separate.

## Adopted street-safety scoring

The primary radius is half a mile, with quarter mile as a sensitivity. Both
components use the same City-clipped origin windows. The crash component is
`min(100, 100 * annual_KSI_density / 6.1118601065110614)`, using unique fatal or
suspected serious-injury crashes across all road users, 2020–2024, per year per
observed square mile. The anchor is the frozen 95th percentile across the original
1,029 half-mile origins (unweighted R type-7 quantile), not a safety standard.
The gap component retains its raw missing-network percentage. The combined
score is 50% of each; higher is greater burden.

Independently retain high-component flags at crash density
`>= 4.2772765182635766` (frozen original 90th percentile) or gaps `>= 50`.
The quarter-mile sensitivity uses the **same** anchors and flags. Missing either
component makes the combined score unavailable; a known high component still
produces a warning, while missing information without a known high component
produces an incomplete assessment. Neither a zero crash count nor falling below
the flags establishes safety. Counts, actual observation areas, network lengths
and inventory completion-date review flags are retained.

`R/street_safety.R` implements spatial aggregation, scoring and exports;
`street_safety` / `street_safety_assets` add it to the targets graph. The standalone
runner is `Rscript scripts/pedestrian/build_street_safety.R`, followed by
`Rscript scripts/pedestrian/report_street_safety.R`. Results are in
`output/components/street-safety/`, including maps, a review report, both radii's
per-origin scores, GIS layers and frozen policy/provenance metadata. Tests are
`tests/test_street_safety.R` and `tests/test_street_safety_snapshot.R`.

The half-mile result covers 880 of 1,029 origins and 98.53% of known estimated
residents. Median score is 32.36, with 363 origins triggering at least one flag
and 18 triggering both. One high-crash warning is retained despite an unavailable
gap score. The 149 unavailable scores consist of 145 empty main-network
denominators and four unknown-inventory cases. Among 798 origins scored at both
radii, median absolute score change is 6.98 points and Spearman correlation is
0.794. These are local burden scores, separate from benefits and flood eligibility;
this analytical implementation does not publish the public map.

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
The report is `output/components/heat-burden/review.html`. Overall burden weights
remain open, and the public map is unchanged by this analysis.

## Industrial-air review, November 10, 2026

An analysis-only comparison now evaluates a linear score capped at the current
95th-percentile RSEI ToxConc (622.7302) and a flag at the 90th percentile (351.1041)
against the existing mockup flag of 100. The proposed flag identifies 103 origins
containing 3.87% of known estimated residents, versus 334 origins and 30.78% under
the existing threshold. The 231 origins losing their flag contain approximately
259,352 known residents. The continuous candidate score has median 8.39.
See [industrial-air methods and reproduction](rsei.md) and the local report at
`output/components/industrial-air-review/review.html`. These remain discussion
candidates in that historical review report; the subsequent adoption is below.

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
for reproduction and tests. Overall domain weights remain open. The public
prototype remains at its prior deployment pending publication.

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
All four burden domains now have adopted component scoring rules. Overall
weights, overall burden status and public-map publication remain to be settled.

## Historical overall weight comparison, November 10, 2026

The user requested a comparison of equal thirds by broad theme (heat 1/3, street
safety 1/3, industrial air 1/6, traffic 1/6) against equal quarters across the four
domains. No default preset has been selected. Both require every weighted domain;
missing data do not cause weights to be redistributed. Component high-burden
flags, industrial-air secondary review and heat observation flags remain fixed.

Both produce 880 complete scores representing 98.53% of known estimated residents;
149 composites are unavailable because pedestrian-gap scores are missing. The
median score is 33.07 under equal themes versus 28.15 under equal domains. Spearman
rank correlation is 0.9839. Median absolute score change is 4.62 points, and median
absolute rank change is 1.93 percentile points. The highest-scoring deciles share
77 of 88 origins (87.5%); upper quartiles share 196 of 220 (89.1%). These tails are
diagnostics, not proposed overall high-burden flags.

Equal themes raises scores in 806 complete origins and lowers them in 74. The
score difference is exactly `(heat + street safety - industrial air - traffic)/12`.
Mean contributions among the complete origins are 17.60 heat, 10.67 street safety,
3.10 industrial air and 2.22 traffic points under equal themes, versus 13.20, 8.00,
4.65 and 3.32 under equal domains. This reflects different score distributions,
not equivalent health effects or a causal influence decomposition.

Under the proposed weight-independent warning rule, 480 origins have known high
burden with complete assessments, 38 have high burden with incomplete assessments,
400 have no high flags and complete assessments, and 111 have incomplete
assessments without a known high flag. The same warnings apply to both presets;
the secondary industrial band and traffic sensitivity do not trigger primary
warnings. The four-domain warning count treats the street-safety domain once,
while retaining its separate crash and pedestrian warnings in the output.

Reproduce with `Rscript scripts/air/compare_burden_weights.R`, then run
`Rscript tests/test_burden_weight_review.R`. Candidate weights are isolated in
`config/burden-weight-review.yml`. The report and all per-origin scores, rank
changes, contribution tables, maps and source hashes are under
`output/components/burden-weight-review/`. The public map is unchanged.

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
