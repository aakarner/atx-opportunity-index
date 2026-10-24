#!/usr/bin/env python3
"""Check dashboard series labels, units, value domains, and transit coverage."""
import csv, json
from pathlib import Path

SITE = Path(__file__).resolve().parents[1]
DATA = SITE / "data"
grid = json.load((DATA / "h8-grid.geojson").open())["features"]
city = [i for i, f in enumerate(grid) if f["properties"].get("region") == "austin"]
catalog = json.load((DATA / "catalog.json").open())
rows = []
for scenario in catalog["scenarios"]:
    for key, filename in scenario["files"].items():
        mode, period = key.split(":")
        result = json.load((SITE / filename).open())
        for series in result["series"]:
            values = series["values"]
            assert len(values) == len(grid), (scenario["id"], key, len(values))
            observed = [v for v in values if v is not None]
            assert all(v >= 0 for v in observed)
            if series["unit"] == "minutes": assert max(observed, default=0) <= 90
            if "acreage" in series["id"]: assert series["unit"] == "acres"
            if "park_count" in series["id"]: assert series["unit"] == "parks"
            if mode == "walk_transit":
                good = lambda v: v is not None and (v > 0 if series["direction"] == "higher" else True)
                rows.append({"scenario": scenario["id"], "period": period, "series": series["id"],
                             "metro_accessible_pct": round(100 * sum(good(v) for v in values) / len(values), 1),
                             "austin_accessible_pct": round(100 * sum(good(values[i]) for i in city) / len(city), 1)})
with (DATA / "transit-coverage-qa.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=rows[0]); w.writeheader(); w.writerows(rows)
print(f"Validated {len(rows)} transit series; {len(grid):,} metro cells and {len(city):,} Austin cells")
