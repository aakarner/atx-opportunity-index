# Sidewalk gaps on major streets

For each H3 resolution 8 center, the pipeline draws a half-mile circle and clips it to Austin's full- and limited-purpose boundary. The quarter-mile sensitivity repeats the calculation in a smaller circle. Each map hexagon displays its center's result.

The score is 100 × (eligible frontage − served frontage) / eligible frontage. Each eligible street side contributes its length. The outside edges of paired divided roads count once each. An ordinary two-sided street with a continuous sidewalk on one side scores 50. The high-burden flag starts at 50 and the component carries one sixth of the combined score.

## What counts

- **Eligible streets.** The City Comprehensive Transportation Network supplies existing or passable on-street roadways. Public eligibility uses road classes 2, 4, 5, 6, 8 and 14, street levels where class is missing or zero, and identified public service roads. The major subset includes levels 2–4 (also recorded as 102–104), road classes 2, 4, 5 and 8, and eligible service roads named SVRD. Level 5, private and unbuilt roads are excluded. Ordinary local residential streets contribute no frontage.
- **Served frontage.** The City sidewalk inventory supplies existing sidewalks, protected street paths and shared-use paths. Driveway crossings count when both ends meet existing pedestrian facilities within 2.5 m. The existing urban trails layer supplies additional parallel paths. Planned facilities have no served length. [Street network](https://services.arcgis.com/0L95CJ0VTaxqcmED/arcgis/rest/services/Comprehensive_Transportation_Network_Maint_Non_Edit_View/FeatureServer/0) · [Sidewalks](https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/Sidewalks_(Public)/FeatureServer/0) · [Urban trails](https://services.arcgis.com/0L95CJ0VTaxqcmED/arcgis/rest/services/Urban_Trails_Network_Public_view/FeatureServer/0)
- **Matching.** Projected road segments in NAD83 / UTM 14N are sampled in intervals of up to 8 m. Each midpoint contributes its interval length to the windows that contain it. Candidate facilities must have a compatible direction, side, and street name or close parallel alignment. The major-street search distance is half the recorded pavement width plus 7 m, with a 22 m floor and 35 m cap. Duplicate facilities on the same side earn a single credit. Nearby parallel one-way carriageways with the same normalized name contribute only their outer frontage.
- **Missing data.** A window with no eligible frontage has no score. A window with eligible frontage but neither pedestrian inventory nor mapped service has unknown coverage. An observed window with zero matched service scores 100. Incomplete mapping can still affect observed windows. The measure describes mapped infrastructure and does not establish walking activity, pedestrian accessibility or sidewalk condition.

## Build and verify

Use the archived November 9 sidewalk and November 23 street and trail snapshots identified in `config/burdens.yml`. The pipeline verifies each source page against its acquisition manifest. Source acquisition scripts are `fetch_inventory.py` and `fetch_transport.py`. For an updated source vintage, archive it in a new directory and update the configured path. Production uses the local archives and the model's geometry directly.

Set `DAM_DATA_DIR` as described in the project pipeline guide. Set `FRONTAGE_PYTHON` to a Python interpreter with GeoPandas 1.x, Shapely 2.1, NumPy, pandas and a GeoPackage-capable GDAL installation. The default is `python3`.

```sh
Rscript scripts/run_pipeline.R street_safety_assets combined_burden_assets web_mockup_data
Rscript scripts/pedestrian/report_street_safety.R
"$FRONTAGE_PYTHON" tests/test_major_frontage.py
Rscript tests/test_street_safety.R
Rscript tests/test_street_safety_snapshot.R
Rscript tests/test_combined_burdens.R
node tests/test_combined_burdens.mjs
```

The two CSVs and the hex and window layers under `output/components/street-safety/` contain eligible and served meters, coverage, burden, availability reason and crash observations. Metadata records source dates, checksums and policy. The public map uses the versioned combined-burdens JSON export.
