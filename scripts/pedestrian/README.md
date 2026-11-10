# Pedestrian-network gap measure

## Combined street-safety score

The adopted half-mile score and quarter-mile sensitivity combine crash and gap
scores at 50/50, with fixed anchors and independent component flags. Reproduce:

```sh
Rscript scripts/pedestrian/build_street_safety.R
Rscript scripts/pedestrian/report_street_safety.R
Rscript tests/test_street_safety.R
Rscript tests/test_street_safety_snapshot.R
```

The standalone runner consumes the validated inventory analysis and existing
source targets. For a source-tracked rebuild, use
`Rscript scripts/run_pipeline.R street_safety_assets`, then generate the report.
Results and review maps are in `output/components/street-safety/`. See
`docs/burdens.md` for adopted rules, missing-data treatment and current findings.
The remainder of this document records the original inventory and radius review.

## Original inventory workflow

Run from the repository root:

```sh
python3 scripts/pedestrian/fetch_inventory.py
Rscript scripts/run_pipeline.R pedestrian_assets
Rscript scripts/pedestrian/audit_examples.R
Rscript scripts/pedestrian/report.R
Rscript scripts/pedestrian/compare_radii.R
Rscript tests/test_pedestrian_gaps.R
Rscript tests/test_pedestrian_snapshot.R
```

`Rscript scripts/pedestrian/build.R` is an equivalent standalone analysis runner
using the existing `h8_geometry` and `city_boundary` targets. The targets route
tracks source hashes, policy, geometry and exports; it does not alter or deploy
the public map. The report adds whole-hex population coverage and a diagnostic
comparison with the prepared 2020–2024 crash points.

`compare_radii.R` reuses the validated inventory analysis and prepared crash
points to compare matching City-clipped quarter-, half- and one-mile windows.
It writes `radius-comparison/review.html`, maps, per-origin counts and densities,
network lengths, population diagnostics and ranking comparisons. Crash counts
cover the full five years. Zero and fewer-than-five counts describe sparsity;
they are not adopted safety or reliability thresholds. Crash percentile ranks
and logarithmic map colors are diagnostic only, not scoring decisions. The
script checks nested counts/areas and verifies sample counts independently by
point distance and City membership. The user supports smaller windows for both
components and subsequently adopted half a mile as primary and quarter mile as
the sensitivity. The original inventory build remains a historical baseline;
the comparison outputs contain the adopted geographies for scoring integration.

The matching-window comparison found:

| Radius | Zero KSI crashes, all origins | Median five-year KSI count | Gap scores available |
|---|---:|---:|---:|
| Quarter mile | 60.5% | 0 | 800 / 1,029 |
| Half mile | 32.9% | 2 | 880 / 1,029 |
| One mile | 16.1% | 13 | 945 / 1,029 |

Among the 833 origins with positive estimated population, zero-crash shares are
54.3%, 23.9% and 9.4%, respectively. At half a mile, available gap scores represent
98.53% of known estimated residents. Half-mile versus one-mile crash-density
rank correlation is 0.853; quarter-mile versus half-mile is 0.727. Half-mile
windows preserve more local variation than one mile, while quarter-mile counts
are particularly sparse. Half-mile counts are still sparse (62.4% have fewer
than five KSI crashes over five years); retain visible counts and observation
areas. These findings support recommending half a mile for both components,
with quarter mile as a sensitivity, without treating zero history as safe.

## Definition

The 0–100 gap score is `100 * planned / (completed + planned)` using unique
inventoried **line length**, measured in EPSG:26914. Completeness is its complement.

| Facility type | Main treatment |
|---|---|
| EXISTING_SIDEWALK | Completed |
| DRIVEWAY | Completed pedestrian-inventory crossing segment |
| SHARED_USE_PATH / PROTECTED_STREET_PATH | Completed |
| SHARED_STREET | Completed |
| PLANNED_SIDEWALK / PLANNED_SHARED_STREET | Missing/planned |
| POTENTIAL_SIDEWALK | Excluded; additional-missing-length sensitivity |
| Null/unrecognized | Unknown; unexpected new nonnull categories stop ingestion |

The denominator is the inventory-coded existing-plus-planned network, not all
street length and not a claim to reproduce an official City parcel-coverage
statistic. Parallel street sides remain separate; one-sided adequacy is inherited
from City category choices, not reconstructed from a street centerline layer.
Potential-sidewalk inclusion is a broader inventory sensitivity, **not** a
verified both-sides-of-every-road alternative. Example street plots document
parallel planned/completed shared-street lines and planned-versus-potential sides;
no extra factor of two is applied to shared streets. Driveways in this sidewalk
inventory represent interruptions/crossings along the pedestrian facility; this
classification does not certify accessibility, slope, or priority over vehicles.

Two exact spatial overlays are provided: each H8's City portion, and the City
portion of a 1,609.344 m radius around its canonical H3 center. Buffers use 90
segments per quadrant. City scope is the pinned full- and limited-purpose limits.
These are neighborhood summaries, not address-specific sidewalk determinations.
Outside-City area is excluded with its share reported; service availability does
not establish inventory completeness. No line snapping or buffering invents
coverage. A zero main denominator remains unavailable, including a potential-only
window. Such windows may have a value in the explicitly broader sensitivity.

## Source and QA

The source is the City's public `Sidewalks_(Public)/FeatureServer/0` inventory.
The 2026-11-09 snapshot contains 352,387 records. Acquisition checks all source IDs,
page completeness and SHA-256 hashes, plus a stable service edit timestamp before
and after download. Reads verify every cached file and ID. All source records are
retained in the immutable raw snapshot, including the empty geometry. The public
view does not expose usable sidewalk-condition fields despite legacy subtype
metadata mentioning them; no condition/ADA score is inferred.

Same-status duplicates and overlapping lines are dissolved, including reverse
line direction, before measuring. Point intersections between crossing lines do
not count as duplicated length. Completed/planned overlap becomes unknown rather
than being counted twice. There is one unlocatable empty record (OBJECTID 141233),
one located unclassified segment, and about 0.290 m of completed/planned conflict
within the City footprint. A window with positive unknown length has no main
score; known-inventory estimates and lower/upper bounds are supplied. The 1e-6 m
unknown tolerance is numerical, not an adopted materiality threshold.

Thirty-nine records carry a planned type and a past completion date. The main
version follows facility type; a review flag and alternative score treat the
corresponding planned length as complete. This is not an automatic source repair.
Past construction may describe work other than completion of the planned facility.
The largest change is 7.81 points at hex scale and 2.13 at neighborhood scale.

## Current results

| Geography | Available main scores | Median gap score | Known residents represented |
|---|---:|---:|---:|
| City portion of hex | 835 / 1,029 | 31.32 | 98.09% |
| City portion of one-mile neighborhood | 945 / 1,029 | 33.31 | 97.12% |

Hex results have 192 empty main denominators and 2 unknown-inventory cases.
Neighborhood results have 67 empty denominators and 17 unknown-inventory cases.
A wider neighborhood can include uncertain segments outside its central hex,
so more scored origins does not necessarily mean greater population coverage.
Population denominators exclude 71 origins with unknown population and retain
whole-hex estimates; they are not exact City-clipped resident counts.

The geography comparison has Spearman correlation 0.699 and a median absolute
change of 11.37 points. Including potential sidewalks in the neighborhood measure
has correlation 0.818 with the main version and raises it by a median 5.24 points
among paired available results. Extremes warrant reviewing denominator lengths,
particularly where the main network is sparse. These are consequential choices.

One-mile gap score and matching-window annual KSI crash density have Spearman
correlation about 0.009 among available pairs. They describe complementary
conditions rather than empirically redundant rankings in this snapshot. The
agreed 50/50 internal weights are recorded in `config/burdens.yml`; no combined
score is produced until the crash-score transformation is selected. No high-gap
cutoff, broader burden weights, or public deployment is adopted by this analysis.

Outputs in `output/components/pedestrian-gaps/` include `review.html`, PNG/PDF
maps, category/coverage/sensitivity tables, per-origin CSVs, a GeoPackage with
hex/window/type-line layers, source metadata and the analysis object. Gray map
cells are unavailable, not zero. A short missing link can disconnect a route
without adding much length: this score does not measure crossings, route
continuity, disability access, sidewalk condition, or walking exposure.
