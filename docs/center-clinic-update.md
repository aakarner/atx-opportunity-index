# Center and clinic update — 2026-11-17

Consumes the new dated DAM snapshot (61 series, 804,529 records) from the shared
project folder `index-development/data/dam-accessibility/2026-11-17`.
DAM code revision: 7a0506c. The prior 55 series remain historical.

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
These mappings are proposed for team review in this integration branch.

Validation: all six new regional series (13,189 origins each) independently agree
with OD minima. The team importer checks release hashes/schema; direct calculation
passed for all 1,029 Austin origins, new threshold columns and profile counts.
Historical eight-type export checks continue against historical component series,
not against the revised destination set.

Run with DAM_DATA_DIR pointing to the new snapshot:
    Rscript tests/test_center_clinic_update.R
    Rscript scripts/run_pipeline.R review_report web_mockup_data

The direct test produces review tables in output/components/center-clinic-update.
Full pipeline attempted locally but blocked by missing pinned heat inputs and
school inputs (elementary_growth_assignments_2026_27.gpkg,
expanded_subgroup_comparison_2026.csv and elementary-boundary source manifest).
Published dashboard assets have NOT been regenerated or deployed by this PR.
The collaborator with those inputs must finish the complete rebuild before publishing.

Source-inventory caveats: Northeast Central Health temporary service changes;
Clinical Education Center included in community category by project decision;
Lockhart operation and other senior operator/partnership review notes preserved.
Transit uses the archived July 2026 AM settings and retains the GTFS warning; this
is an inventory update, not a new service-date or regional-feed release.
