# Shared Austin municipal boundary

The study footprint uses the City of Austin GIS
[BOUNDARIES_jurisdictions layer](https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/BOUNDARIES_jurisdictions/FeatureServer/0),
not the 2024 Census place geometry. The October 19, 2026 snapshot includes
Dog’s Head. The City’s [annexation record](https://www.austintexas.gov/planning/annexation)
identifies case C7a-2026-0003, ordinance 20260521-060, approved May 21, 2026
(approximately 2,614 acres). An independent copy of the four annexation polygons
is retained as a regression fixture under `tests/fixtures/`.

## Scope and provenance

Select `CITY_NAME = 'CITY OF AUSTIN'` and
`JURISDICTION_TYPE IN ('FULL','LTD')`; exclude ETJ and other municipalities.
The previous Census footprint included most limited-purpose territory, so this
preserves that scope. Full-purpose only would incorrectly remove roughly
112 km² of limited-purpose land previously included in the study.

`config/pipeline.yml` pins the snapshot date, source URL, raw path, jurisdiction
classes, and SHA-256. The public raw GeoJSON, service metadata, and acquisition
manifest are intentionally versioned under `data/raw/municipal_boundary/2026-10-19/`.
The manifest records the query, source edit time, retrieval time, object IDs,
feature count, and checksum. Downloads check the complete object-ID set and
reject changed data that does not match the reviewed checksum. Cached data is
also checked; a live service edit cannot silently replace this dated snapshot.

`R/municipal_boundary.R` dissolves the selected polygons in EPSG:5070, repairs
validity, and returns a common WGS84 footprint with provenance. Area/distance
operations use EPSG:5070. Projected/spherical conversions introduce tiny edge
slivers; regression checks require over 99.999% coverage of the independent
annexation and limited-purpose polygons, with all remaining slivers within
25 cm of the outline. This is not a survey boundary.

## Propagation

The shared footprint controls:

- H8 origin selection and the routing snapshot; every row carries its boundary
  checksum/date, and the pipeline requires exactly the expected H8 IDs.
- Census tract clipping, tract/H8 crosswalks, and tract access aggregation.
- RSEI extraction extent and native-grid overlaps for both H8 and tract means.
- Flood clipping and crash-point filtering, including tract/site observation
  windows. Prepared GeoPackages have `.boundary.json` sidecars; stale or missing
  provenance stops the pipeline and requires source preparation to be rerun.
- Component maps, site profiles, classification comparisons, and review pages.
- Website city/tract outlines, address eligibility, hex profiles, counts, and
  measured coverage. Published data requests are content-versioned together.

Census tracts and ACS remain 2024, displacement context remains 2022, jobs
remain 2023, the routing snapshot remains June 2026, and RSEI remains 2022.
Changing the municipal footprint does not update these source vintages.
The crash source has its own City-defined coverage; clipping cannot create
unreported crashes or guarantee historical coverage of newly annexed land.

## October 19 migration results

| Measure | Previous Census footprint | City GIS footprint |
|---|---:|---:|
| Municipal area (km²) | 862.319 | 868.728 |
| H8 origins | 1,021 | 1,029 |
| City-clipped tract records | 275 | 270 |
| Strong-access H8 cells | 137 | 137 |
| Elevated-burden H8 cells | 321 | 334 |
| H8 cells with both flags | 48 | 48 |

There are 16 added and 8 removed H8 origins. All access and resident-worker
values are identical for the 1,013 retained origins. The updated outline adds
12.532 km² and removes 6.123 km² relative to the old outline; these changes
include boundary revisions beyond Dog’s Head. The five removed tract records
were clipped edge fragments, each smaller than 0.001 km², totaling 0.001738 km².
Tract flag totals remain 80 strong-access, 87 elevated-burden, and 29 with both.
The available H8 cells cover 92.069% of the updated municipal area.

The website’s Dog’s Head example at 30.249080, -97.662190 was outside the former
footprint. It now joins H8 `88489e30bbfffff` and tract `48453002310`; its access
is 115 jobs and its RSEI concentration rounds to 565 (elevated burden).
Detailed added/removed IDs and tract-fragment areas are in
[`municipal-boundary-audit.json`](municipal-boundary-audit.json).

## Rebuild or adopt a later boundary

For the checked-in snapshot, no municipal download is necessary. From the root:

```sh
Rscript accessibility/03-analysis/01_unweighted_job_accessibility.R
Rscript accessibility/03-analysis/02_weighted_job_accessibility.R
Rscript scripts/prepare/pull_flood.R
Rscript scripts/prepare/pull_crashes.R
Rscript scripts/run_pipeline.R
Rscript tests/test_municipal_boundary.R
Rscript tests/test_web_mockup.R
node tests/test_web_mockup.mjs
Rscript tests/test_pipeline_integration.R
```

The preparation scripts reuse existing complete flood/crash raw snapshots by
default, so re-clipping does not silently change source vintages. Use
`REFRESH_AUSTIN_FLOOD_HAZARD=true` or `REFRESH_AUSTIN_CRASHES=true` only to
intentionally refresh those sources (the latter requires the API app token).

To adopt a later municipal release, first inspect the current City service,
review the FULL/LTD geometry changes and complete object-ID set, then create a
new dated snapshot path and pin its reviewed checksum in configuration. Preserve
the earlier snapshot for comparison. Run all preparation and pipeline steps
above, inspect added/removed cells and flagged areas, commit the source and
regenerated website assets, and publish using `scripts/site/publish.sh`.
