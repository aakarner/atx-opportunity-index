#!/usr/bin/env python3
"""Package validated accessibility outputs for the static dashboard."""

import csv
import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITE = Path(__file__).resolve().parents[1]
OUT = SITE / "data"
RESULTS = ROOT / "accessibility" / "output" / "working"
GRID = ROOT / "data" / "Karner, Alex - austin_msa_h3_r8_share_2026-10-02" / "input" / "austin_msa_h3_r8_cells.geojson"
CITY = OUT / "austin-full-purpose.geojson"

SCENARIOS = {
    "jobs_cumulative": {
        "destination": "Jobs", "short": "Jobs", "measure": "cumulative",
        "description": "Jobs reachable within the selected travel-time threshold",
        "source": "LEHD/LODES employment opportunities",
    },
    "grocery_third_nearest": {
        "destination": "Grocery stores", "short": "Grocery", "measure": "time",
        "description": "Travel time to the third-nearest grocery store",
        "source": "USDA SNAP retailers with reviewed DataAxle additions",
    },
    "childcare_fifth_nearest": {
        "destination": "Childcare facilities", "short": "Childcare", "measure": "time",
        "description": "Travel time to the fifth-nearest childcare facility",
        "source": "Texas HHSC licensed and registered operations",
    },
    "park_reachable_supply": {
        "destination": "Parks and open space", "short": "Parks", "measure": "cumulative",
        "description": "Number or acreage of eligible parks reachable within the selected threshold",
        "source": "ParkServe with City of Austin attributes",
    },
    "library_nearest": {
        "destination": "Public libraries", "short": "Libraries", "measure": "time",
        "description": "Travel time to the nearest public library",
        "source": "City and regional public-library sources",
    },
    "pharmacy_nearest": {
        "destination": "Pharmacies", "short": "Pharmacy", "measure": "time",
        "description": "Travel time to the nearest community pharmacy",
        "source": "Texas State Board of Pharmacy with DataAxle checks",
    },
    "hospital_second_nearest": {
        "destination": "Hospitals", "short": "Hospitals", "measure": "time",
        "description": "Travel time to the second-nearest hospital",
        "source": "CMS NPPES facility records",
    },
    "urgent_care_third_nearest": {
        "destination": "Urgent care", "short": "Urgent care", "measure": "time",
        "description": "Travel time to the third-nearest urgent-care facility",
        "source": "CMS NPPES and reviewed DataAxle locations",
    },
    "public_center_nearest": {
        "destination": "Public community and senior centers", "short": "Public centers", "measure": "time",
        "description": "Travel time to the nearest public community or senior center",
        "source": "City and regional government facility sources",
    },
}

FIELD_LABELS = {
    "total_jobs": "All jobs", "low_wage_jobs": "Low-wage jobs",
    "middle_wage_jobs": "Middle-wage jobs", "high_wage_jobs": "High-wage jobs",
    "park_count": "Number of parks", "acreage": "Park acreage",
    "facility_count": "Travel time",
}

def number(value):
    if value in (None, "", "NA", "NaN"):
        return None
    x = float(value)
    return x if math.isfinite(x) else None

def point_in_ring(x, y, ring):
    inside = False
    j = len(ring) - 1
    for i, point in enumerate(ring):
        xi, yi = point[0], point[1]
        xj, yj = ring[j][0], ring[j][1]
        if ((yi > y) != (yj > y)) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-20) + xi:
            inside = not inside
        j = i
    return inside

def point_in_polygon(x, y, polygon):
    return bool(polygon and point_in_ring(x, y, polygon[0]) and not any(point_in_ring(x, y, hole) for hole in polygon[1:]))

def city_shapes():
    if not CITY.exists(): return []
    shapes = []
    for feature in json.load(CITY.open()).get("features", []):
        geom = feature.get("geometry") or {}
        polygons = geom.get("coordinates", []) if geom.get("type") == "MultiPolygon" else [geom.get("coordinates", [])]
        for polygon in polygons:
            if not polygon or not polygon[0]: continue
            xs = [p[0] for p in polygon[0]]; ys = [p[1] for p in polygon[0]]
            shapes.append(((min(xs), min(ys), max(xs), max(ys)), polygon))
    return shapes

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "results").mkdir(parents=True, exist_ok=True)

    with GRID.open() as f:
        grid = json.load(f)
    ids = [f["properties"]["h3_id"] for f in grid["features"]]
    grid_index = {v: i for i, v in enumerate(ids)}
    shapes = city_shapes()
    for feature in grid["features"]:
        props = feature["properties"]
        x, y = props["center_longitude"], props["center_latitude"]
        in_austin = any(b[0] <= x <= b[2] and b[1] <= y <= b[3] and point_in_polygon(x, y, poly) for b, poly in shapes)
        feature["properties"] = {"h3_id": props["h3_id"], "region": "austin" if in_austin else "metro"}
    with (OUT / "h8-grid.geojson").open("w") as f:
        json.dump(grid, f, separators=(",", ":"))

    catalog = {"generated_from": "validated scenario-runner outputs", "cell_count": len(ids), "scenarios": []}
    for scenario, meta in SCENARIOS.items():
        item = {"id": scenario, **meta, "modes": [], "periods": [], "files": {}}
        for csv_path in sorted((RESULTS / scenario).glob("*/*/accessibility.csv")):
            mode, period = csv_path.parts[-3], csv_path.parts[-2]
            rows = list(csv.DictReader(csv_path.open()))
            groups = {}
            for row in rows:
                pval = row["parameter_value"]
                key = f'{row["opportunity_field"]}__{pval}'
                groups.setdefault(key, {"field": row["opportunity_field"], "parameter": row["parameter_name"], "value": pval, "values": [None] * len(ids)})
                idx = grid_index.get(row["geography_id"])
                if idx is not None:
                    groups[key]["values"][idx] = number(row["access_value"])
            series = []
            for key, group in groups.items():
                field, pval = group["field"], group["value"]
                if meta["measure"] == "time":
                    label, unit, direction = meta["description"], "minutes", "lower"
                else:
                    threshold = str(int(float(pval))) if pval not in ("", "NA") else ""
                    label = f'{FIELD_LABELS.get(field, field.replace("_", " ").title())} within {threshold} minutes'
                    unit = "acres" if field == "acreage" else ("parks" if field == "park_count" else "jobs")
                    direction = "higher"
                series.append({"id": key, "label": label, "unit": unit, "direction": direction, "values": group["values"]})
            name = f"{scenario}__{mode}__{period}.json"
            with (OUT / "results" / name).open("w") as f:
                json.dump({"scenario": scenario, "mode": mode, "period": period, "series": series}, f, separators=(",", ":"), allow_nan=False)
            item["files"][f"{mode}:{period}"] = f"data/results/{name}"
            if mode not in item["modes"]: item["modes"].append(mode)
            if period not in item["periods"]: item["periods"].append(period)
        catalog["scenarios"].append(item)
    with (OUT / "catalog.json").open("w") as f:
        json.dump(catalog, f, indent=2)

    print(f"Packaged {len(catalog['scenarios'])} scenarios and {len(ids):,} H8 cells")

if __name__ == "__main__":
    main()
