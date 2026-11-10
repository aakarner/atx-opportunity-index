# Industrial air-toxic burden and candidate classifications

## Adopted industrial-air score, November 10, 2026

The user adopted the recommended continuous score, high-burden flag and secondary
review band. Production policy is in `config/burdens.yml` under `industrial_air`:

- Score: `min(100, 100 * ToxConc / 622.73023119285699)`.
- High burden: `ToxConc >=351.10409694733289`.
- Secondary review: `100 <= ToxConc <351.10409694733289`.
- Below 100: below the review band, not a safe-air finding.
- Missing concentrations or incomplete modeled-grid coverage: unavailable.

The anchors remain fixed to the reviewed baseline rather than recalculating with
each run. The secondary band is exclusive of high burden, adds no score points,
and does not set the high-burden flag. A separate review-or-high field preserves
the broader >=100 screen. Raw concentrations remain available above the score cap.
All 1,029 origins are scored: 103 are high burden, 231 are secondary review and
695 are below the review band. Median score is 8.39. The high and review bands
contain 3.87% and 26.91% of known estimated residents, respectively.

`R/industrial_air_burden.R` provides scoring, aggregation and exports. Reproduce
with the existing `DAM_DATA_DIR` environment pointing to the November 3 snapshot:

```sh
Rscript scripts/run_pipeline.R industrial_air_burden_assets
Rscript scripts/air/report_industrial_burden.R
Rscript tests/test_industrial_air_burden.R
Rscript tests/test_industrial_air_burden_snapshot.R
```

The `industrial_air_burden` and `industrial_air_burden_assets` targets were built
successfully. Results in `output/components/industrial-air-burden/` include
`review.html`, maps, scores and separate flags, population summaries, GIS data,
and frozen policy/source metadata. The comparison below and the earlier mockup
remain historical review artifacts. Public-map deployment is separate and has
not been changed by this analytical implementation. Traffic scoring was adopted
subsequently; overall burden weights remain open.

## November 10, 2026 score and flag review

The user requested a comparison before adopting industrial-air scoring. This
review does not change the existing mockup or public map. The candidate score
is `min(100, 100 * ToxConc / 622.73023119285699)`, with an inclusive candidate
high-burden flag at `351.10409694733289`. These are the unweighted type-7 95th
and 90th percentiles, respectively, across the current 1,029 H8 origins. The
existing mockup flag is `ToxConc >=100`. Source data are RSEI v2.3.12, year 2022.
All inputs have complete modeled-grid coverage; neither flag is a health standard.

| Rule | Flagged origins | Known residents | Share of known residents | Known children | Share of known children |
|---|---:|---:|---:|---:|---:|
| Existing >=100 | 334 | 296,621 | 30.78% | 59,942 | 34.81% |
| Candidate >=351.1041 | 103 | 37,269 | 3.87% | 8,991 | 5.22% |
| Flag removed by higher cutoff | 231 | 259,352 | 26.91% | 50,951 | 29.59% |

The candidate score has median 8.39 and 75th percentile 24.00. Fifty-two origins
reach the 100-point cap; raw concentrations remain available above it. The old
flag corresponds to 16.06 score points and the candidate flag to 56.38 points.
The continuous score and flag are separate decisions. A possible secondary
review band from 100 to 351.1041 is discussed, not adopted. None of the removed
flags indicates improvement in air quality. The reference is not weighted by
population; these population summaries use whole-hex estimates and exclude 71
origins with unknown population.

Reproduce from the existing prepared RSEI/H8 and population targets:

```sh
Rscript scripts/air/compare_industrial.R
Rscript tests/test_industrial_air_review.R
```

Candidate parameters are isolated in `config/industrial-air-review.yml`.
`R/industrial_air_review.R` implements review-only score/flag fields. The
script checks the current quantiles against the pinned candidate reference;
a changed reference must be explicitly reviewed. Outputs in
`output/components/industrial-air-review/` include `review.html`, score and
classification maps, distribution plots, per-origin results with coordinates,
removed flags, population summaries, GIS data and provenance. No production
burden configuration or overall weights are changed.

## Source and scope

The pipeline now acquires EPA's **2022 aggregated air geographic microdata**, RSEI
**v2.3.12** (2022 reporting-year freeze), and extracts the grid cells intersecting
Austin and the full H8 access cells. Configuration is in `config/pipeline.yml`.
This vintage is the latest in EPA's public Current_Version directory verified on
October 14, 2026; it is not a 2026 emissions estimate.

- [EPA download directory](https://gaftp.epa.gov/rsei/Current_Version/V2312_RY2022/Aggregated_Grid_Cell/)
- [Aggregated grid dictionary](https://www.epa.gov/rsei/rsei-data-dictionary-aggregated-grid-cell-geographic-microdata)
- [Geographic microdata documentation](https://www.epa.gov/rsei/documentation-risk-screening-environmental-indicators-rsei-geographic-microdata-rsei-gm)
- [Methodology v2.3.12, section 5.1 and Exhibit 5.1](https://www.epa.gov/rsei/risk-screening-environmental-indicators-rsei-methodology-0)
- [Interpretation](https://www.epa.gov/rsei/understanding-rsei-results)

The source is a national gzip CSV of approximately 239 MB (228 MiB). Acquisition
validates gzip integrity and the exact column schema, retains the archive, and
records URL, version, reporting year, acquisition timestamp and SHA-256 in a JSON
sidecar. Cached files must agree with that provenance. `refresh: true` explicitly
reacquires the source on a target rebuild; reset it afterwards. Missing archives
trigger acquisition. Failed downloads do not replace a valid cached archive.
Chunked extraction limits memory use and retains only the local subset. Facilities
outside Austin are not excluded: the receptor cells incorporate modeled contributions
from all sources included by EPA.

## Measurement and spatial contracts

`ToxConc` is modeled air concentration multiplied by relative inhalation toxicity
weights and summed over contributing chemicals. It does **not** include a population
multiplier. `CTConc` and `NCTConc` are retained separately for cancer and noncancer
toxicity weighting; they are not additive components of `ToxConc`. EPA's `Score`
and `Pop` are retained in the native-grid extract for provenance, but neither enters
our burden measure.

CONUS grid code 14 uses NAD83 / Conus Albers, EPSG:5070. The standard parallels
are 29.5 and 45.5 degrees north, central meridian -96 degrees, and latitude of
origin 23 degrees. Each cell center is `(810 * X, 810 * Y)` meters in that CRS;
its square extends 405 meters in each direction. X/Y are signed center indices,
not array offsets from the southwest corner. The extracted template covers the
union of the shared Austin municipal boundary and full available H8 polygons.

- H8 means use **full-cell area weights**, matching the full-cell job-access origins.
- Tract means use **City-clipped tract area weights**, independently of worker counts.
- Site profiles query the **containing native EPA cell**, using half-open boundaries
  for deterministic assignment. No nearest-cell fallback is used for RSEI.
- The comparison's existing site examples use **H8 means**, explicitly labeled,
  so they can be compared against the H8 classification maps. They can differ from
  the native-grid point result in the production site table.
- Less than complete overlap (tolerance 1e-6) yields a missing mean, with coverage
  reported. Overcoverage fails. Crosswalks are cached separately from summaries.
- EPA's geographic documentation, coverage section, states that the national file
  omits cells unaffected by modeled releases. An absent record after a validated
  complete scan is a **zero modeled contribution**, explicitly flagged; it does
  not imply clean air. Missing or invalid values in an existing record fail rather
  than becoming zero. Population is not inferred for absent records.

RSEI is a screening model of TRI-related industrial air releases. It is not a
measurement of actual exposure, an estimate of total air pollution, or a safe/unsafe
threshold. Mapping it to H8 does not improve its native 810 m resolution. The
aggregated source cannot attribute hotspots to facilities or chemicals; attribution
would require disaggregated microdata. No nearby facility should be assumed to
cause a hotspot based solely on proximity.

## Rebuild and outputs

```sh
Rscript scripts/run_pipeline.R
# Just the discussion report and its dependencies:
Rscript scripts/run_pipeline.R classification_report
# Just reusable industrial-burden products:
Rscript scripts/run_pipeline.R rsei_files tract_rsei
```

The first run needs internet access; subsequent runs reuse the raw source and
`targets` cache. Normal outputs include:

- `output/components/rsei_and_h8.gpkg`: native EPA cells and H8 component polygons.
- `rsei_native_grid.csv`, `h8_components.csv`: corresponding measurements.
- `tract_components.csv` / `.gpkg`: existing components plus industrial burden.
- `site_profiles.csv`: native EPA cell IDs and concentrations for configured sites.
- Updated registry, source manifest, QA, and an industrial-burden component map.

`R/rsei.R` owns source acquisition, grid construction, extraction, aggregation,
site lookup, QA and exports. `_targets.R` integrates these with the shared geography.
No candidate classifications enter the production component fields.

## Candidate-rule comparison

`config/classification-review.yml` specifies exploratory fixed thresholds.
`R/classification_review.R` adds a tertile comparator and generates the analysis
branch. **All thresholds are discussion scenarios, not adopted standards.**

| Dimension | Candidate | Rationale for comparison |
|---|---|---|
| Total transit jobs in 45 minutes | Baseline tertiles | Reproduce the proposed relative binning approach |
| Total transit jobs in 45 minutes | Limited below 10,000; strong at least 50,000 | Illustrative fixed job-count criterion |
| Total transit jobs in 45 minutes | Limited below 25,000; strong at least 100,000 | More demanding fixed job-count criterion |
| Air ToxConc | Upper baseline tertile | Relative broad burden flag |
| Air ToxConc | At least 100 | Round threshold close to the current upper-tertile cutoff |
| Air ToxConc | At least 500 | More selective flag for the high-concentration tail |

The job-count thresholds have not been validated as adequate access. The RSEI
thresholds have no health-standard interpretation. Their purpose is to reveal how
much and which geography changes as the rule changes, before choosing policy rules.
The fixed RSEI thresholds were selected after inspecting the local distribution;
this is a sensitivity analysis, not an independently validated classification.

The baseline includes **all available H8 origins centered in the pinned Austin municipal boundary**, including
zero-worker cells, equally weighted. Tertiles use R's type-7 quantiles; ties remain
together. Limited means strictly below the lower cutoff; strong/elevated means at
least the upper cutoff. Unknown remains a distinct class. The same numeric
cutoffs apply to H8 values and tract averages; tracts are not reranked separately.
Tract job access retains the main pipeline's worker weighting and fallback flags.
Low-/middle-/high-wage access remains available in the detailed location tables;
only total access is classified here to avoid double counting wage components.

The review branch currently recomputes tertile cutoffs if its baseline changes.
`candidate_thresholds.csv` records their exact values. Once a rule is adopted,
freeze its numerical thresholds and baseline version in configuration so that
improvement can reduce the flagged area instead of recreating a fixed fraction.

Open `output/components/classification-review/review.html` beside its assets:

- Maps of all three access rules and all three burden rules at both scales.
- Counts, City-clipped area shares, and H8 resident-worker shares for each class.
  The report calculates H8 coverage from the pinned municipal boundary; uncovered areas are shown separately.
  H8 area shares use only covered City area, not the full City denominator.
  H8 worker counts include the full source cells at the city edge; they are not
  an exact count of City residents. Whole-tract ACS totals are not used as Austin
  population denominators.
- All nine benefit/burden rule combinations and pairwise classification switches.
- Native-grid area above each pollution cutoff within each tract, identifying
  hotspots obscured by the tract average. The 10% highlight is only a review aid.
- Every H8 and tract, its values and classifications, in CSV and GeoPackage form;
  H8 center coordinates and containing tract IDs support location inspection.
- Existing demonstration origins and a continuous access-versus-burden plot.

## Validation

```sh
Rscript tests/test_rsei.R
Rscript tests/test_classification_review.R
Rscript tests/test_pipeline.R
Rscript tests/test_pipeline_integration.R
```

Fixtures test cell alignment, exact boundaries, unequal overlap weights, incomplete
coverage, source absence versus missing values, duplicate rows, malformed archives,
classification cutoffs, and ties. The isolated integration test uses the acquired
source read-only, checks the existing pipeline behavior, and verifies that changing
classification rules does not rebuild the underlying RSEI or access measurements.

## Selected mockup rules

The mockup uses **strong access >50,000 total jobs reachable in 45 minutes** and
**elevated burden at RSEI ToxConc >=100**, configured under `mockup` in
`config/classification-review.yml`. The access comparison is strict: exactly
50,000 does not qualify. No lower access cutoff was selected; other observed
values are simply not flagged as strong, and missing values remain unknown.
These are mockup choices, not adopted policy or health standards.

The review report highlights this selection. `mockup_thresholds.csv` records the
operators and cutoffs; `mockup_summary.csv` records counts at both scales. Detailed
H8/tract CSVs, GeoPackage layers, and example-location tables contain `mockup_`
fields. The original sensitivity scenarios remain available, including their
inclusive 50,000-job comparator. Raw component measurements remain unchanged.
