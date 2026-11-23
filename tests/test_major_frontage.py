"""Synthetic frontage checks independent of the City snapshot."""
from pathlib import Path
import sys

import geopandas as gpd
import numpy as np
from shapely.geometry import LineString

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "pedestrian"))
from major_frontage import CRS, frontage_samples


def lines(rows):
    return [LineString([(start, y), (end, y)]) for start, end, y in rows]


def roads(rows, one_way):
    return gpd.GeoDataFrame(
        {"name": ["MAIN ST"] * len(rows), "major": True, "PAVEMENT_WIDTH": 30, "ONE_WAY": one_way},
        geometry=lines(rows), crs=CRS,
    )


def facilities(rows):
    return gpd.GeoDataFrame(
        {"name": ["MAIN ST"] * len(rows), "kind": "EXISTING_SIDEWALK"}, geometry=lines(rows), crs=CRS,
    )


# A 39.9 m sidewalk on one side of an 80 m road covers five 8 m samples.
# Duplicate sidewalk records and a perpendicular crossing earn no extra credit.
street = roads([(0, 80, 0)], "N")
walks = facilities([(0, 39.9, 6), (0, 39.9, 6), (50, 51, -10)])
walks.loc[2, "geometry"] = LineString([(50, -10), (50, 10)])
_, total, served = frontage_samples(street, walks)
assert np.isclose(total.sum(), 160) and np.isclose(served.sum(), 40)

# Two carriageways together have two outside frontages. A median path adds no credit.
divided = roads([(0, 80, 0), (80, 0, 16)], "Y")
walks = facilities([(0, 80, -6), (0, 80, 8)])
walks.loc[1, "kind"] = "SHARED_USE_PATH"
_, total, served = frontage_samples(divided, walks)
assert np.isclose(total.sum(), 160) and np.isclose(served.sum(), 80)
walks.loc[1, "geometry"] = lines([(0, 80, 22)])[0]
_, _, served = frontage_samples(divided, walks)
assert np.isclose(served.sum(), 160)

street["major"] = False
_, total, served = frontage_samples(street, walks)
assert total.size == 0 and served.size == 0
print("Verified side-specific and divided-street measurements, path credit and local-street exclusion.")
