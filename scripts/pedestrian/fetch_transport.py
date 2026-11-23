"""Archive Austin roadway and existing urban trail layers. Run from the repository root."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
import argparse
import hashlib
import json
import subprocess

ROOT = Path("data/raw/pedestrian_alternatives/2026-11-23")
BASE = "https://services.arcgis.com/0L95CJ0VTaxqcmED/arcgis/rest/services/"
SOURCES = {
    "trails": ("Urban_Trails_Network_Public_view", "BUILD_STATUS='EXISTING'", "OBJECTID_1,SEGMENT_NAME,TRAIL_STRUCTURES"),
    "roads": ("Comprehensive_Transportation_Network_Maint_Non_Edit_View", "FACILITY_TYPE='Roadway' AND LINE_TYPE='On-Street' AND ROAD_CLASS IN (1,2,4,5,6,8,10,14,15,16)", "OBJECTID,SEGMENT_ID,CTN_SEGMENT_ID,FULL_STREET_NAME,ROAD_CLASS,STREET_LEVEL,CTM_BUILT_STATUS,BUILT_STATUS,MAINTENANCE_AGENCY,THRU_LANE_COUNT,ONE_WAY,PAVEMENT_WIDTH,BIKE_MAP_GRADE"),
    "crossings": ("Markings_Short_Line_Read_Only", "SHORT_LINE_TYPE='CROSSWALK'", "OBJECTID,SEGMENT_ID,LOCATION_STATUS,SIGNAL_INTERSECTION,SUBTYPE"),
    "signals": ("TRANSPORTATION_signals2", "1=1", "OBJECTID,SIGNAL_TYPE,SIGNAL_STATUS,PRIMARY_ST,CROSS_ST"),
}
road_service, _, road_fields = SOURCES["roads"]
SOURCES["other_roads"] = (road_service, "FACILITY_TYPE='Roadway' AND LINE_TYPE='On-Street' AND (ROAD_CLASS IS NULL OR ROAD_CLASS NOT IN (1,2,4,5,6,8,10,14,15,16))", road_fields)
STUDY = "https://services.austintexas.gov/edims/document.cfm?id=342423"


def get(url, params=None):
    query = url + ("?" + urlencode(params) if params else "")
    return subprocess.check_output(["curl", "-fgLsS", "--retry", "3", "--max-time", "120", query])


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main(include_review=False):
    sources = SOURCES if include_review else {k: SOURCES[k] for k in ("roads", "other_roads", "trails")}
    ROOT.mkdir(parents=True, exist_ok=True)
    manifest = ROOT / "manifest.json"
    meta = {}
    if manifest.exists():
        for name, checksum in json.loads(manifest.read_text())["files"].items():
            assert sha(ROOT / name) == checksum, name
        meta = json.loads(manifest.read_text())["sources"]
        if set(sources).issubset(meta) and (not include_review or "speed_study" in meta):
            return
    for key, (service, where, fields) in sources.items():
        if key in meta:
            continue
        url = BASE + service + "/FeatureServer/0"
        info = json.loads(get(url, {"f":"json"}))
        (ROOT / (key+"_layer.json")).write_text(json.dumps(info))
        # Keep a margin around the full project area to evaluate boundary routes.
        filt = dict(where=where, geometry="-98.08,30.00,-97.44,30.58", inSR=4326,
                    geometryType="esriGeometryEnvelope", spatialRel="esriSpatialRelIntersects")
        def ids():
            return sorted(json.loads(get(url+"/query", dict(filt, returnIdsOnly="true", f="json")))["objectIds"])
        initial = ids()
        oid = info["objectIdField"]
        fields = ",".join(dict.fromkeys([oid, *fields.split(",")]))
        batches = [initial[i:i+400] for i in range(0, len(initial), 400)]
        def page(item):
            i, batch = item
            p = ROOT / f"{key}_{i:04}.geojson"
            raw = get(url+"/query", dict(filt,where=f"({where}) AND {oid} >= {batch[0]} AND {oid} <= {batch[-1]}",outFields=fields,outSR=4326,f="geojson"))
            features = json.loads(raw)["features"]
            assert sorted(x["properties"][oid] for x in features) == batch
            p.write_bytes(raw)
        with ThreadPoolExecutor(5) as pool:
            for _ in pool.map(page, enumerate(batches)):
                pass
        assert ids() == initial
        end = json.loads(get(url, {"f":"json"}))
        assert end.get("editingInfo") == info.get("editingInfo")
        meta[key] = dict(url=url, where=where, fields=fields, count=len(initial), extent=filt["geometry"],
                         edit=info.get("editingInfo"))
        print(key, len(initial), flush=True)
    if include_review and "speed_study" not in meta:
        (ROOT/"speed_study.pdf").write_bytes(get(STUDY))
        meta["speed_study"] = dict(url=STUDY, title="Austin speed modification report, 2020, Appendix A")
    manifest.write_text(json.dumps(dict(retrieved=datetime.now(timezone.utc).isoformat(), sources=meta,
        files={p.name:sha(p) for p in sorted(ROOT.iterdir()) if p.is_file() and p!=manifest}), indent=2))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--include-review", action="store_true", help="Also fetch crossings, signals and traffic studies for the alternatives comparison.")
    main(parser.parse_args().include_review)
