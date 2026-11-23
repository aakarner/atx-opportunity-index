# Center and clinic update — 2026-11-17

Consumes the new dated DAM snapshot (61 series, 804,529 records) from the shared
project folder `index-development/data/dam-accessibility/2026-11-17`.
DAM code revision: 7a0506c. The release retains the 55 November 3 series alongside the six additions.

Three new AM measures, each for drive and transit plus walking:
- community_social_recreation_nearest: 39 destinations; excludes Luling, separates seniors.
- senior_center_nearest: 8 records; existing review caveats retained.
- urgent_care_clinic_nearest: 72 records; broader clinical scope, not urgent-care-only.

Explicit scenario mappings replace old measure selections. Older adults use senior
centers in the existing center slot (six-type basket unchanged); single adults use
community/social/recreation centers (four-type basket unchanged). Urgent care is
relabeled urgent care/clinics. General comparison includes both center categories;
this is a nine-type comparison, not the historical eight-type aggregate.
Families' destination basket, domain weights and profile minimum counts are unchanged.

Validation: all six new regional series (13,189 origins each) independently agree
with OD minima. The team importer checks release hashes/schema; direct calculation
passed for all 1,029 Austin origins, new threshold columns and profile counts.
Historical eight-type export checks continue against historical component series,
not against the revised destination set.

The rebuild covers 1,029 map origins and 270 tracts. The table counts origins
whose combined benefit score changed from the November 3 baseline under the
default weights. Each column uses the destination and job budgets for that mode.

| Housing profile | 15-minute drive | 45-minute transit and walk |
| --- | ---: | ---: |
| Families with children | 0 | 0 |
| Older adults | 328 | 194 |
| Single adults | 175 | 140 |
| Adult permanent supportive housing | 157 | 127 |

For older adults using transit, 14 origins moved below the combined minimums
and three newly met them. The map uses the revised travel times for both the
counts and the per-destination trip details.

Set `DAM_DATA_DIR` to the November 17 snapshot and run from the repository root.

```sh
Rscript tests/test_center_clinic_update.R
Rscript scripts/run_pipeline.R review_report web_mockup_data scoring_comparison
Rscript scripts/compare_destination_minimums.R
node tests/test_web_mockup.mjs
node tests/test_combined_benefits.mjs
```

The pipeline writes the location and tract scores to `site/assets/benefits.json`
and the combined benefit inputs and reference scores to
`site/assets/combined-benefits.json`. The local benefit review is in
`output/components/benefits/review.html`.

Source-inventory caveats: Northeast Central Health temporary service changes;
Clinical Education Center included in community category by project decision;
Lockhart operation and other senior operator/partnership review notes preserved.
Transit uses the archived July 2026 AM settings and retains the GTFS warning; this
is an inventory update, not a new service-date or regional-feed release.
