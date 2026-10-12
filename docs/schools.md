# AISD school opportunity: preparation and methods

Run the preparation scripts from the repository root after package setup:

```sh
Rscript scripts/prepare/pull_school_indicators.R
Rscript scripts/prepare/pull_school_boundaries.R 2025-26
Rscript scripts/prepare/pull_school_boundaries.R 2026-27
Rscript scripts/prepare/build_school_assignments.R
```

These scripts prepare **Austin ISD (district 227901)** records independently of
tract and routing data. The component pipeline reads the saved 2025–26 scored
attendance zones. Schools in other districts and independent charter districts
are outside this initial coverage, even if located in Austin. Published zones
do not establish access to selective or specialized programs.

The TEA preparation script acquires statewide campus accountability summaries,
normalizes only AISD records, and writes source, coverage, and exception audits.
It keeps the existing campus-panel schema; comparative analyses and their plots
are no longer part of preparation. Their methods and substantive findings are
retained below as historical evidence.

Downloads are cached under `data/raw/tea_accountability/`. Use
`REFRESH_TEA_ACCOUNTABILITY=true Rscript scripts/prepare/pull_school_indicators.R`
to replace them with newly retrieved releases. Source URLs, cache modification
times, SHA-256 checksums, and per-year field dictionaries identify the actual
download used. TEA can revise annual files after appeals.

## Measures

| Analysis field | TEA field | Interpretation |
|---|---|---|
| `achievement` | `CD1A` | Raw STAAR Student Achievement component score; not adjusted for economic disadvantage. This combines achievement thresholds and is not simply the percentage meeting grade level. |
| `growth` | `CD2A` | Raw Part A Academic Growth component score, including accelerated-learning credit. It uses prior/current performance transitions, not demographic regression adjustment. |
| `relative_performance` | `CD2BS` | **Scaled** Part B Relative Performance score, comparing achievement against economic-disadvantage benchmarks. For high/combined schools it may incorporate college, career, and military readiness (CCMR) as well as STAAR. |
| `econ_disadv_pct` | `CPETECOP` | TEA-reported percentage of economically disadvantaged students. This is a campus student characteristic, not a neighborhood poverty estimate. |

The raw fields `CD2B_STAAR` and `CD2B_CCMR` in TEA's separate Part B export
are inputs to adjustment, not adjusted scores. `CD2B` is an alternative-campus
retest-growth component and must not be substituted for `CD2BS`. The combined
School Progress domain chooses the better of Parts A and B, so it is not used.
Raw/scaled growth, raw/scaled achievement, and raw CCMR are retained in the
normalized panel for inspection. Equal numerical values across these measures
do not mean equal educational outcomes.

## Normalization and eligibility

All AISD campus-year records remain in the normalized panel. Eligibility excludes
alternative accountability, disciplinary/juvenile justice/residential treatment
settings, unknown school types, invalid enrollment, unrated campuses, and any
flagged accountability pairing. Pairing exclusions include donor/recipient flags;
inherited or shared ratings are not treated as independent campus observations.

Original score tokens are preserved. Blanks, negative sentinels, suppression
marks, and nonnumeric values become missing, never zero. Preparation stops on
invalid schemas, duplicate campus IDs, unexpected flags, and out-of-range
percentages. The downstream growth join requires an eligible campus with a
usable growth score; it does not require achievement, relative performance, or
economic-disadvantage values. The panel's `complete_metrics` and `primary_sample`
fields are retained for compatibility and interpretation of historical work.

## Prepared outputs

The normalized panel is `data/processed/school_indicators/aisd_campus_year.csv`.
The following files are written to `data/qaqc/school_indicators/`:

| File | Purpose |
|---|---|
| `coverage.csv` | Campus counts, eligible counts, and measure availability by year/type |
| `exclusions_and_missingness.csv` | Excluded or incomplete records with flags and source tokens |
| `source_manifest.csv` | Source URLs, cache timestamps, and checksums |
| `source_field_dictionary.csv` | Original TEA field names and labels |
| `session_info.txt` | R environment used for preparation |

Boundary and assignment products and their audits are described below. Running
the preparation scripts does not regenerate the former exploratory comparison
CSV files or plots.

## Historical indicator comparison: 2023–2026

The original comparison evaluated candidate indicators; it did not establish
causal school effectiveness or produce an access/tract score. Lower correlation
with poverty was one diagnostic, not proof of validity. Part B is deliberately
adjusted, so some reduction in that association is mechanical. For high schools,
the comparison also changes outcome content because Part B can include CCMR.
Achievement, learning growth, school resources, and the experience of attending
a school answer different questions.

The comparison separated elementary, middle, high, and combined campuses, with
equal campus weights. It compared all three measures on the same complete
sample within each year/type, including economic-disadvantage values, and used
metric-specific available samples to check missingness. Pearson and Spearman
correlations required at least five observations and variation in both values.
Combined-school results had only one complete campus per year and could not
support correlations. Raw/scaled growth sensitivity checked ties and ceilings.

Ranks used average ranks for ties and 0–100 within-year/type percentiles. Annual
stability matched campus IDs and school types with complete data in both years,
then recomputed ranks on each matched panel so entries/exits alone did not
change them. Grade-span changes were flagged. These ranks were descriptive,
not proposed housing-award cutoffs; a stable campus ID cannot establish unchanged
programs, admission policies, or student composition.

The first 2023–2026 run found that growth and relative performance reduced, but
did not remove, the negative association with student economic disadvantage.
For 2026 elementary schools (76 common-sample campuses), Spearman correlations
were approximately -0.89 for achievement, -0.76 for growth, and -0.67 for relative
performance. In the matched 2025–2026 elementary panel, rank stability was about
0.96, 0.81, and 0.90, respectively. These are retained findings from the original
download, not parameters or statistics recomputed by the current preparation
scripts. Refreshes can change the underlying records.

Campus inclusion does not establish that a nearby household may enroll there.
Selective/magnet and specialized programs remain included unless excluded by
the flags above. Published attendance zones now link locations to campus scores;
program-specific access, school transportation, and tract aggregation still need
further work before a final housing-siting measure.

## Official sources and time comparability

- [TEA accountability downloads](https://rptsvr1.tea.texas.gov/perfreport/account/acct_download?year=2026): campus-level Accountability Summary export, with rating, domain, student, school-type, flag, and pairing categories.
- [2025 School Progress methodology](https://tea2.tea.texas.gov/school-and-district-leaders/accountability/academic-accountability/performance-reporting/chapter-3-2025-school-progress-domain-0.pdf): Parts A/B, scoring, and alternative-accountability distinctions.
- [2023 accountability refresh](https://tea.texas.gov/taa-letters/2023-accountability-manual): the series starts with the refreshed system, avoiding a pre/post-2023 comparison.
- [2024 final manual notice](https://legacycms.tea.texas.gov/about-tea/news-and-multimedia/correspondence/taa-letters/final-2024-accountability-manual): continuation of the refreshed system.
- [2026 accountability framework](https://tea.texas.gov/texas-schools/accountability/academic-accountability/performance-reporting/2026-academic-accountability-system-framework.pdf): no changes to Academic Growth or Relative Performance components; CCMR qualification details can still change.

Accountability years are the years named by TEA, not the dates the files were
released. Annual stability combines real changes, measurement noise, student
composition, and any assessment/accountability changes. It should not be read
as a pure measure of changes in educational effectiveness.

## Assignment boundaries and snapshot direction

Working direction agreed October 2, 2026: use academic growth as the primary
candidate, with a single latest-year score rather than a historical average,
and keep transportation outside the first school component. The pipeline uses
the aligned 2025–26 baseline below. The historical multi-year comparison informs
this choice; it is not a final weighted school-access indicator.

Run `Rscript scripts/prepare/pull_school_boundaries.R` to retrieve a fresh snapshot of
the layers used in AISD's [2026–27 assignment application](https://aisd.maps.arcgis.com/apps/instant/lookup/index.html?appid=5f909a8aff0c42148e389ee49e7847ce).
AISD links this application under "Review school assignments" on its
[consolidation page](https://www.austinisd.org/consolidate). The application
configuration identifies it as "SY 26-27 Existing Boundaries & School
Reassignments (July 30, 2026)." This establishes its advertised school year;
individual layers have different edit dates. The district's separate static
GIS download page still labels its shapefiles 2022–23 and is not our source.

The source is the public `Reassignments/FeatureServer` service in AISD's ArcGIS
organization (`5HXFPHsCivNoDso0`), referenced by web map
`0b14b8e1f73945a6832d9df3b5b52e5b`:

| GeoPackage layer | Service layer | Assignment attribute | Downloaded polygons |
|---|---:|---|---:|
| `elementary` | 9 | `Campus` | 81 |
| `middle` | 3 | `Campus` | 21 |
| `high` | 1 | `HIGH_DESC` | 11 |

These are source polygon counts, not counts of distinct currently operating
schools. The elementary and middle layers contain 13 and 8 explicitly labeled
reassignment polygons, respectively. The GeoPackage adds `assigned_school_label`,
`reassignment_flag`, `school_level`, and `assignment_school_year` and preserves
the original fields. It does not dissolve polygons or reinterpret reassignment
labels as TEA campus identifiers.

Files:

- `data/processed/school_indicators/aisd_assignments_2026_27.gpkg`: three layers,
  WGS84 / EPSG:4326, ready to open in QGIS or R.
- `data/raw/aisd_boundaries/2026_27/`: source GeoJSON, layer metadata, object-ID
  lists, app metadata/configuration, and web-map configuration.
- `data/qaqc/aisd_boundaries/2026_27/`: source manifest with URLs, edit/retrieval
  times and checksums, geometry checks, and full assignment attributes.

All 113 polygons passed validity/empty-geometry checks on download. The source
has small within-level overlaps: approximately 65 square meters elementary,
29,184 square meters middle, and negligible high-school overlap (computed in
EPSG:5070). Resolve ambiguous point/area assignments before tract aggregation;
valid geometry alone does not establish a gap-free, non-overlapping partition.

**Use receiving-school labels, not legacy zone codes, for campus matching.**
For example, the Reilly reassignment polygon retains `ELEM_=133`, while the
existing Reilly zone has `ELEM_=132`. AISD's
[Reilly transition letter](https://www.austinisd.org/sites/default/files/dept/consolidation/docs/FotF_Consolidation%20Letters_Reilly_ENG.pdf)
confirms that Reilly receives students from Ridgetop, which closes after
2025–26. Blindly prefixing every legacy zone code with the district ID would
attach the wrong campus's score. The assignment builder matches receiving-campus names and
isolates ambiguous overlaps. Program/grade exceptions still require review
before using these campus-wide scores for housing siting.

For a current-access indicator, the pairing is **2026–27 assignments with
2025–26 growth (TEA 2026)**.
Even the latest score predates fall-2026 consolidations and program changes.
Use the receiving campus's latest available score as a provisional proxy and
flag changed campuses; a single-year snapshot cannot describe post-change
performance that has not yet been observed. Closed campuses' old scores should
not continue to score the locations reassigned to other schools.

### Aligned 2025–26 baseline

Run `Rscript scripts/prepare/pull_school_boundaries.R 2025-26` to download the separate
[AISD 2025–26 locator](https://aisd.maps.arcgis.com/apps/instant/lookup/index.html?appid=e1ba75fe20044ef38cb2b75909332298).
Its title and introduction explicitly identify 2025–26 assignments. Web map
`f7e36f4653ca4e43b8cb21147e1884bc` references the public
`SY_25_26_School_Locator_App_WFL1/FeatureServer` service in the same AISD
organization. Its elementary, middle, and high-school layers are 0, 2, and 1,
with label fields `ELEM_DESC`, `MID_DESC`, and `HIGH_DESC`, respectively.

The October 2, 2026 download contains **77 elementary, 16 middle, and 11 high
school polygons**. All 104 are valid and nonempty; within-level overlap excess
is below one square meter at each level. Each level covers approximately
601.44 square kilometers. The elementary layer retains Ridgetop and Winn,
and the middle layer retains Paredes. Layer metadata reports last edits on
December 1, 2025; this is a snapshot of the published locator, not an assertion
that no assignments changed within the school year.

The resulting file is
`data/processed/school_indicators/aisd_assignments_2025_26.gpkg`, with the same
three layer names as the current-year file. Source downloads and audit files
are under `data/raw/aisd_boundaries/2025_26/` and
`data/qaqc/aisd_boundaries/2025_26/`. Both years are retained independently.

Pairing **2025–26 boundaries with 2025–26 growth (TEA 2026)** provides an aligned
historical baseline for developing the indicator. It does not describe current
2026–27 enrollment access where schools closed or assignments changed. Retain
the newer boundaries for a subsequent change comparison and current-access
version. The assignment builder implements campus matching and score joins for
both snapshots.

## Attendance-zone growth joins and boundary-change audit

Run `Rscript scripts/prepare/build_school_assignments.R` after preparing the
boundaries for both school years and the TEA campus panel. This runs offline against the saved inputs and records their
SHA-256 checksums. It uses TEA **2026 raw Academic Growth (`CD2A`)**, representing
2025–26, in both boundary snapshots. The 2025–26 output is the aligned baseline;
the 2026–27 output is a provisional receiving-campus proxy whose performance
predates the new assignment year.

### Matching and score treatment

Matching requires a unique normalized campus name within school level. The
script removes bilingual reassignment prefixes, folds Spanish accents, and
standardizes school-type suffixes. Three explicit name aliases reconcile
`Travis Heights` / `TRAVIS HTS`, the GIS spelling `Wooldrige` / `WOOLDRIDGE`, and
`Marshall` / `GENERAL MARSHALL`. No fuzzy matches are accepted. All labels matched in the October 2, 2026 snapshot; unmatched or ambiguous
names cause a failure rather than a guessed score.

Zone-code-derived IDs are retained as an independent audit. They must agree
with name matches for ordinary polygons. For labeled reassignment polygons,
the receiving name controls; the old code may be missing or refer to another
campus. For example, both current Reilly polygons receive Reilly's score of 78,
not Ridgetop's 82. Full source attributes and object IDs remain in the outputs.

`reported_growth` preserves the published numeric score; `growth_token` retains
its original token. `usable_growth` is missing for excluded or missing-score
records, never replaced by zero. Eligibility follows the conservative
campus exclusions described above, but the growth join does **not** require achievement, relative
performance, or economic-disadvantage data to be complete. `score_status`
explains exclusions. Blazier's reported 71 is retained for review but its
`usable_growth` is missing because its accountability record is paired.

| Assignment year | Level | Source polygons | Matched campuses | Campuses with usable growth |
|---|---|---:|---:|---:|
| 2025–26 | Elementary | 77 | 77 | 76 |
| 2025–26 | Middle | 16 | 16 | 16 |
| 2025–26 | High | 11 | 11 | 11 |
| 2026–27 | Elementary | 81 | 68 | 67 |
| 2026–27 | Middle | 21 | 14 | 14 |
| 2026–27 | High | 11 | 11 | 11 |

Campus-wide growth may include selective programs. A residential zone establishes
the published campus assignment, not access to every program or the growth
experienced by a particular student. Grade-span and paired-accountability fields
are retained for further review. No within-level normalization or weighting is
imposed at this stage.

### Spatial comparison

The comparison dissolves same-campus polygons separately within each year,
projects to equal-area EPSG:5070, and identifies positive-area overlaps between
different assigned campuses. The union of those ambiguous areas is removed
from both years before intersection; no arbitrary campus takes precedence.
Areas covered by only one snapshot are reported separately. Every output piece
has a status and area, and the categories must sum to the combined footprint.

Changed assignments cover approximately **28.3 km² (4.7%)** at elementary level
and **121.1 km² (20.1%)** at middle level. Percentages use the union of each
level's two footprints, approximately 601.44 km². High-school changes are
numerical fragments only. These are geographic area shares, not population or
student shares, and areas across levels must not be added together.

There are 13 elementary and 8 middle old/new campus pairs with at least one
square meter of changed area. Examples include Ridgetop to Reilly, Widen to
Rodriguez, and parts of Paredes to Bailey or Mendez. The current layer's
reassignment labels and old zone codes are not used to infer the former school;
the former assignment comes from spatial intersection with the 2025–26 layer.

Numerical fragments remain in the full geometry and audit, with
`sub_square_meter_piece` and `reviewable_assignment_change` flags. The compact
pair-review CSV filters aggregate changed areas below 1 m². This is a review
tolerance, not a claim that every larger discrepancy is a policy change.
Different-campus ambiguity totals about 64 m² elementary and 3,776 m² middle;
same-campus overlaps are harmless after dissolving. Middle-school coverage
differences include approximately 0.086 km² present only in the older layer and
0.015 km² present only in the newer layer. These source discrepancies remain
flagged for any later point or tract assignment.

`growth_difference` subtracts the former assigned campus's 2025–26 score from
the receiving campus's **same-vintage** score. It is not an observed improvement
after reassignment or an estimate of a closure's effect.

### Outputs and validation

Under `data/processed/school_indicators/`:

- `aisd_growth_assignments_2025_26.gpkg`: baseline scored zones, EPSG:4326.
- `aisd_growth_assignments_2026_27.gpkg`: current receiving-campus proxies,
  EPSG:4326, with `score_predates_assignment_year` set to true.
- `aisd_assignment_changes_2025_26_to_2026_27.gpkg`: comparison pieces,
  EPSG:5070, with former/current campus IDs, scores, change flags, and areas.

All three files contain `elementary`, `middle`, and `high` layers. Review files
in `data/qaqc/school_assignments/` include the two campus crosswalks,
`score_coverage.csv`, `score_exceptions.csv`, `assignment_change_area.csv`,
`changed_campus_pairs.csv` (review threshold), `changed_campus_pairs_all.csv`
(all numerical fragments), `assignment_changes.png`, `access_summary.txt`,
`input_manifest.csv`, and `session_info.txt`.

Focused checks in `tests/test_aisd_school_access.R` exercise stale-code receiving
matches, accent/name variants, excluded-score preservation, rejected unmatched
names, conflicting overlaps, same-campus overlap dissolution, missing coverage,
unchanged assignments, and area conservation. The production run also validates
boundary year, unique source IDs, geometry, campus uniqueness, and area balance.
This completes the campus/zone join and change audit, not the final weighted
school-access indicator or its tract aggregation.
