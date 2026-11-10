# Heat validation and scoring comparison

The November 9 validation below preceded scoring adoption. On **November 10,
2026**, the user adopted the reconstructed relative percentile as the heat score,
a **score >=90** high-heat flag, and retention of the limited-observation flags.
The main score uses dates with at least **50% of hex land observed**; fewer than
**eight eligible dates** flags the score without excluding or reranking it. No
eligible observations means unavailable. Hot-pixel share is context only.

## Adopted score and reproduction

`config/burdens.yml` pins the validated indicator and daily extraction hashes,
the source manifest, the 2026 reference and the scoring rules.
`R/heat_burden.R` independently reconstructs daily/final ranks and pooled hot
shares from the daily extraction before accepting the prepared indicator input.
It joins current population for reporting only. The pipeline targets are
`heat_source_files`, `heat_inputs`, `heat_burden`, and `heat_burden_assets`.

```sh
Rscript scripts/run_pipeline.R heat_burden_assets
Rscript scripts/heat/report_heat_burden.R
Rscript tests/test_heat_burden.R
Rscript tests/test_heat_burden_snapshot.R
python3 tests/test_heat_validation.py
```

An equivalent standalone build using existing geometry/population targets is
`Rscript scripts/heat/build_heat_burden.R`. Prepared inputs come from the source
validation workflow below. A changed input hash requires review and an explicit
reference-version update; display filters and observation flags cannot silently
change rankings.

The targets route requires `DAM_DATA_DIR` to point to the existing dated benefits
snapshot (`index-development/data/dam-accessibility/2026-11-03`) for the shared
population inputs. The heat targets were successfully built against that snapshot.

Results in `output/components/heat-burden/` include the review report, maps,
per-origin scores and context, daily reference, population summaries, GeoPackage
and policy/provenance metadata. All 1,029 origins are scored. There are 103
high-heat origins, 257 with limited observations, and 21 in both groups.
High-heat hexes contain approximately 141,711 known estimated residents
(14.70%) and 27,082 children (15.73%). Limited-observation hexes contain
approximately 222,402 known residents (23.08%); 71 origins have unknown population
and are omitted from population denominators. These are whole-hex population
estimates, not counts of people exposed to the measured surface temperature.

The percentile median is 50.05 by construction; it is not an absolute thermal
severity measure. Scores describe daytime land-surface heat in one season, not
air temperature, nighttime heat or health risk. No air score, overall burden
weights, or public-map publication is adopted by this implementation.

## Source and reproduction

Peter Haas's [October 27 contribution](https://github.com/aakarner/atx-opportunity-index/commit/735b0213ee0a9f1e28a90a1c03350cb78acbfc56)
is read from [pinned main commit d90d74f38a](https://github.com/aakarner/atx-opportunity-index/tree/d90d74f38a70472418e59666ac86e9d5736efab5/scripts/prepare/surface_temp).
The download script verifies Git blob hashes and records SHA-256 hashes. It also
fetches checksum-pinned Census 2024 area-water polygons for Travis, Williamson,
and Hays counties. Source scripts are inspected, never executed or overwritten.

After building the existing `h8_geometry` and `dam_inputs` targets, run from the
repository root:

```sh
python3 scripts/heat/fetch_peter_snapshot.py
Rscript scripts/heat/validate_heat.R
Rscript scripts/heat/report_heat.R
python3 tests/test_heat_validation.py
```

The first step requires network access. Later steps use local sources and the
existing targets store. The fractional raster/polygon crosswalk is cached against
geometry and source hashes. Results, PNG/PDF figures, CSVs, and `review.html` are
in `output/components/heat-validation/`. Raw downloads and analysis outputs are
gitignored; scripts and this decision record are tracked source files.

## What validates and what needed correction

- Peter's grid matches 1,022 of the current 1,029 H3 resolution 8 origins. The seven
  missing cells contain about 46 known residents and 14 children; four have
  unknown population. Their observations can be extracted from the saved rasters,
  so the reconstructed heat indicators cover all 1,029 current cells.
- The comparison uses stable H3 identifiers, not sequential source row IDs.
  After removing Census water, the maximum matched land-geometry difference is
  6.04 square meters. Differences from full H3 polygons mostly reflect water removal.
- `hex_8_temps.gpkg` has 12,890 records: 1,372 named nonempty geometries and
  11,518 nameless empty rows. The hot-pixel layer has unique valid geometries.
- Independent `terra` extraction reproduces source daily means within 0.000014°F
  and pooled hot-pixel shares within 0.0000012 percentage points. Fractional
  pixel counts agree within 0.000031 pixel-equivalents.
- The saved final ranks reproduce exactly when dates through August require
  **more than 45 valid pixel-equivalents**, but September requires **more than one**.
  The committed hex script uses more than one throughout. The comparison
  reconstructs both indicators with a single area-coverage rule instead of
  importing that inconsistent saved ranking.
- There are 17 saved 30 m raster grids for May–September 2026. Fourteen have valid
  observations within our footprint. Two May rasters are wholly empty and
  September 4 has no valid observations in the current hexes.

The supplied raster values are already Kelvin: convert using
`(K - 273.15) * 9/5 + 32`. The acquisition script uses `rsi` with band rescaling.
Do not apply the [USGS digital-number scaling](https://www.usgs.gov/landsat-missions/landsat-collection-2-surface-temperature)
again. This validates extraction from the supplied rasters; original QA bands,
STAC acquisition records, and the original `rsi` version are not supplied, so
upstream cloud masking and completeness of scene selection are not independently
recreated. A 30 m stored grid does not itself establish independent 30 m thermal
measurement resolution.

## Consistent comparison definitions

Count a date for a hex only when at least **50% of its land area** has valid pixels.
This is a provisional comparison rule, not an adopted scoring requirement.

**Relative heat** ranks the eligible date's mean surface temperature across
current hexagons, averages those daily percentiles equally, then ranks those
averages. Empirical CDF ranks keep ties together. The reference is fixed to
current hexes with an eligible observation; filtering low-coverage cells later
does not rerank the survivors. The daily reference still varies with observation
availability. Rank is relative to this geography and season, not an absolute
measure of thermal exposure or year-to-year change.

**Hot-pixel share** pools observed pixel-area fractions at or above **120°F** and
divides by all observed pixel-area fractions on the same eligible dates. Dates
with more observed land contribute more weight. This is a share of observed
pixel-date area, not a share of days, residents, or fixed land area. The threshold
is exploratory land-surface temperature, not air temperature, heat index, a
health standard, or a validated conversion to 100°F air temperature.

Both summarize one season of daytime satellite snapshots. Neither measures
nighttime heat, indoor conditions, personal exposure, or a long-term normal.
Clear-pixel availability and different observed dates can affect both metrics.

## Results

The main comparison retains all cells and flags fewer than eight eligible dates.
Cells have 4–13 eligible dates (median 8); 257 cells receive that flag.
The two indicators have Spearman correlation **0.848** (0.838 without the
half-land rule; 0.850 after restricting to at least eight eligible dates).

The hot-share median is **2.70%** across hexes, its 75th percentile is **7.95%**,
its 90th percentile is **15.22%**, and its maximum is **39.21%**. The
resident-weighted median is **4.65%**. Population weights describe residents in
classified hexes, not residents actually exposed to the indicated temperature.

Both upper quartiles contain 258 cells; 193 are shared (75%). Both upper deciles
contain 103 cells; only 61 are shared (59%). The difference matters for high-burden
flags even though the overall correlation is strong. A relatively warm cell can
have few observations above a fixed extreme threshold, and a cell with a lower
average relative temperature can contain very hot pixels.

| Candidate flag | Cells | Known residents in flagged cells |
|---|---:|---:|
| Relative percentile ≥75 | 258 | 38.7% |
| Relative percentile ≥90 | 103 | 14.7% |
| Hot-pixel share ≥5% | 367 | 48.9% |
| Hot-pixel share ≥10% | 205 | 27.9% |
| Hot-pixel share ≥15% | 106 | 14.0% |
| Hot-pixel share ≥20% | 50 | 6.0% |

Denominator: about 963,741 known residents across current whole-hex population
weights. Seventy-one hexes have unknown population, excluded from population
denominators but retained in geographic comparisons. These are not exact
city-boundary-clipped resident counts. Child-weighted tables use about 172,174
known residents under 18, not school enrollment.

### Observation coverage sensitivity

| Minimum eligible dates | Cells retained | Known residents covered | Known children covered |
|---|---:|---:|---:|
| Retain available observations | 1,029 | 100% | 100% |
| 5 | 1,027 | 99.91% | 99.97% |
| 8 | 772 | 76.92% | 76.97% |
| 10 | 183 | 21.02% | 22.83% |

Excluding cells with fewer than eight dates would remove locations containing
about 222,402 known residents. Flagging them is preferable for an initial
prototype, pending agreement on a hard coverage minimum.

Restricting to the four dates with at least 80% of the full study land observed
(July 26, August 19, September 20, September 28) gives rank correlations with the
main comparison of **0.959 for relative heat** and **0.916 for hot share**. The
median absolute changes are 4.86 percentile points and 1.32 percentage points,
respectively; these have different units and should not be directly compared.
Cells retain two to four eligible dates in this sensitivity, so it is not a
complete common-date panel. It supports the broad pattern while showing that
individual classifications depend on observation timing.

## Historical scoring options considered November 9

Recommended prototype: use the consistently reconstructed relative percentile
as a **0–100 heat-burden score, higher = greater burden**; display hot-pixel share
and observation counts alongside it. Flag thin observation coverage. A candidate
high-heat status is percentile ≥90, with ≥75 as a broader sensitivity. If the
eventual combined index uses higher = better, invert at the combination step.

An absolute alternative is `100 * min(hot_share_percent / 20, 1)`, with a
separate candidate flag at 10% or 15%. The benchmark 20%, flag thresholds, and
120°F temperature cutoff require a policy rationale; the distribution alone
does not establish them as adequate or safe levels.

Do not count both as independent burden components without explicitly accepting
the extra weight given to heat. Next decisions are the score measure, high-burden
flag, and treatment of thin coverage. Environmental-domain weights and
noncompensatory status rules remain separate decisions.
