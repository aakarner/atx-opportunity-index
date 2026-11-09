# Destination benefits for affordable housing siting

The November 3, 2026 DAM release supplies 55 morning accessibility series for 13,189 H3 resolution 8 origins. The input target verifies SHA-256 hashes against the team manifest and checks its source commit, units, status, record keys and completeness. Of the 1,029 origins in the opportunity map, 887 have the DAM full-purpose Austin flag. All 1,029 match the metro results. The opportunity map uses its pinned full- and limited-purpose boundary and exact H8 IDs.

## Rebuild and review

Set `DAM_DATA_DIR` to the synced dated snapshot. From the repository root run:

```sh
Rscript scripts/run_pipeline.R review_report web_mockup_data
python3 -m http.server 8765 --bind 127.0.0.1 --directory site
```

Open the local map at http://127.0.0.1:8765 and the review in `output/components/benefits/review.html`. That directory contains a two-layer GeoPackage, the source measure dictionary, scores at three example addresses, population comparisons and sensitivity tables. See `config/benefits.yml` for trial settings. Use the team snapshot and review derived fields before a public release. The web assets contain results and school zones. Facility inventories and household-level locations are excluded.

## Measures and geography

Each selected type contributes one point if the modeled nearest destination is reachable within the budget, inclusive. A modeled non-reach contributes zero under the 60-minute driving and 90-minute transit model limits. An unknown input makes the corresponding score unknown. A modeled zero-minute trip can occur within the origin cell. The release's complete-basket mean and all eight-type threshold counts at 15, 30 and 60 minutes are reconstructed from the component times and checked on every included H8. The sum describes separate trips. A secondary mean gives the average of the nearest trip times within a profile only when every selected type has a modeled time. Jobs, alternative destination choices, and park acres retain their units. The older-adult and single-adult preliminary baskets currently coincide. The permanent supportive housing basket is partial. Services in the building itself require a project-specific assessment.

For city-clipped tracts, residents from the DAM H8 demographic estimates are apportioned by tract overlap as a fraction of full H8 area. Each score is averaged over the positive, known resident weight in the overlap. This assumes uniform distribution within each H8 cell. Zero-population and unknown-population cells still receive site scores. The tract layer reports the represented resident weight, geometric coverage and area with known weights. Zero represented residents leaves the score unavailable. Per-type tract values are resident-weighted shares meeting the budget. DAM job counts use the existing H8 resident-worker weights with overlap-area fallback where the worker denominator is zero. The earlier 45-minute transit job benchmark retains its original fallback rules.

A map address uses the containing H8. Family school profiles query the current published neighborhood elementary assignment at the point itself, across Austin, Round Rock, Pflugerville, Del Valle and Manor ISDs. Middle and high school assignments are excluded. Campus scores and exclusion reasons come from the existing assigned-school growth pipeline. Overlaps and areas outside available zones are flagged. A tract has no single assigned campus. Travel time to the assigned campus is unmeasured.

The GeoPackage H8 layer retains the source series values named in the dictionary. Columns such as `walk_transit_30_families` count reachable types at H8 and give their resident-weighted mean at tract level. `walk_transit_30_grocery` is a 0/1 at H8 and a 0–1 share at tract level. Nearest-destination status columns preserve the distinction between modeled, unreachable and missing. In the sensitivity table, zero and full count H8 origins. Population-context percentages use the covered full cells, with separate weights for persons, households or families. These are descriptive comparisons for the prototype footprint rather than city population totals.

## Transit coverage and trial standards

The local CapMetro source ZIP matches the upstream network configuration SHA-256 (9d0ef3a61f1a7aa7b675a0f6849803043f4fedafb89365df01c8a19c9585a3cb). Applying the weekday calendar and July 13, 2026 exceptions to trips gives 4 active service IDs, 4,585 trips and 67 routes for the full day. This checks the archived input calendar. The snapshot omits the actual routing cache, so matching feed ingestion for each run and July coverage of connecting agencies still need verification. The AM results represent the July 13 07:00 departure window of 120 minutes. Transit includes access, egress and walking, with a configured 20-minute walking limit.

CARTS operates interurban connections and Texas State publishes a GTFS feed. Review dated July feeds and transfers against the DAM network before using non-reach for a funding decision. [CARTS routes](https://www.ridecarts.com/routes-schedules/) · [Texas State GTFS](https://www.shuttle.txst.edu/about/gtfs.html).

The trial defaults are 10 minutes driving and 30 minutes by transit and walking. Compare the results at 5 and 15 minutes driving and at 45 and 60 minutes by transit. Establish local expectations by mode and trip purpose with resident and City input. The published regional survey reports observed durations and does not validate the trial cutoffs. [CAMPO household travel survey](https://ftp.txdot.gov/pub/txdot-info/tpp/survey/austin-2017-household.pdf).

## Comparing education and employment scoring choices

Run `Rscript scripts/run_pipeline.R scoring_comparison` with the same `DAM_DATA_DIR` to produce `output/components/benefit-scoring-review/review.html`. The settings are in `config/benefit-scoring-review.yml`. This analysis reads current 2026–27 school assignment zones directly and pairs them with 2025–26 growth. It compares overall and economically disadvantaged pooled growth at the assigned elementary school only, across Austin, Round Rock, Pflugerville, Del Valle and Manor. A score requires a recognized elementary assignment and available growth measure. The H8 summaries use routing origins, while the three example sites use their actual coordinates.

Rounded subgroup growth is compared with the published whole-point overall measure. Raw values and fixed elementary-campus percentile sensitivities are exported. The reference pools zoned elementary campuses across all five districts with both measures available, one vote per campus. School sample sensitivity uses the minimum of the reading and math growth denominators at the assigned elementary school. It does not depend on achievement-test samples. The comparison reports coverage separately and requires both growth measures when comparing rankings. H8 origin counts are not population counts or independent campus observations.

Employment points follow `min(reachable_jobs / full_credit_target, 1)`. Full transit credit occurs at 50,000 total jobs in 45 minutes. Unlike the earlier binary map flag, the linear rule includes exactly 50,000. Candidate driving targets are tested at 15 and 30 minutes. Floors of 50%, 60% and 70% are sensitivity scenarios. A final education target and the rule for handling a failed minimum are still open.

Confirmed weights are equal thirds for families, 75% destinations and 25% jobs for older adults, and 40% destinations and 60% jobs for single adults. PSH 75/25 and 50/50 are proposed comparisons. Education has zero weight for the adult-only presets. Adjustable weights should be normalized to 100% with a visible custom label and reset control. The applicable domains for minimum requirements should be defined by housing profile separately from their adjustable weights. Missing required education must leave the overall assessment incomplete.

Coverage exports now include total residents and children under 18, using the same ACS 2020–2024 block-group estimates and census-block-to-H8 weights. Reconstructed total population must match the existing DAM allocation before child counts are used. Both the `austin` and `metro` crosswalk partitions are required. Missing population is retained as unknown. Geographic assignment, usable overall growth, and subgroup sample thresholds have separate coverage numerators; these are origin-classified whole-hex estimates, not exact boundary-clipped counts. See `docs/schools.md` for current boundary source labels and preparation.
