# Independent Dog's Head regression geometry

`dogs-head-annexation-2026.geojson` was retrieved October 19, 2026 from the
[City of Austin annexation polygons service](https://maps.austintexas.gov/arcgis/rest/services/Shared/BoundariesGrids_3/MapServer/5).
Query: `JURISDICTION_CASE_NUMBER = 'C7a-2026-0003'`, all fields, output EPSG:4326,
GeoJSON. Object IDs: 3959, 3642, 3643, 3644.

[Council annexation record](https://www.austintexas.gov/planning/annexation):
May 21, 2026, ordinance 20260521-060, approximately 2,614 acres. The regression
test checks the complete union against the separately acquired current municipal
jurisdiction layer, allowing less than 0.001% missing area and checking that all edge slivers lie
within 25 cm of the municipal outline after projected/spherical validity repair.
