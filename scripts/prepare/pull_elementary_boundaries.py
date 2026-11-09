"""Snapshot district-published elementary zones used for 2026–27 enrollment.

Run from the repository root. Public locator layer labels are retained verbatim:
older labels do not establish the effective year. See source_manifest.json for
the current-use evidence. Del Valle proposals are explicitly excluded.
"""
import hashlib
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen
from datetime import datetime, timezone

ROOT = Path("data/raw/elementary_boundaries/2026_27")
ROOT.mkdir(parents=True, exist_ok=True)
MANIFEST = []


def fetch(name, url, sanitize=None):
    path = ROOT / name
    cached = path.exists()
    if cached:
        value = json.loads(path.read_text())
    else:
        with urlopen(url, timeout=120) as response:
            value = json.load(response)
        if isinstance(value, dict) and "error" in value:
            raise ValueError(value["error"])
        if sanitize:
            value = sanitize(value)
        path.write_text(json.dumps(value))
    MANIFEST.append(dict(path=str(path), url=url, reused_cache=cached,
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                         snapshot_utc=datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()))
    return value


def write(name, value):
    (ROOT / name).write_text(json.dumps(value))


def arcgis_layer(name, endpoint):
    meta = fetch(name + "_metadata.json", endpoint + "?f=json")
    ids = fetch(name + "_ids.json", endpoint + "/query?" + urlencode(dict(f="json", where="1=1", returnIdsOnly="true")))
    expected = sorted(ids["objectIds"])
    assert expected and len(expected) <= meta["maxRecordCount"]
    data = fetch(name + ".geojson", endpoint + "/query?" + urlencode(dict(f="geojson", where="1=1", outFields="*", outSR=4326, returnGeometry="true")))
    assert not data.get("exceededTransferLimit")
    assert sorted(f["properties"][ids["objectIdFieldName"]] for f in data["features"]) == expected
    return data


# Round Rock's official district page embeds this app and web map.
rr_portal = "https://portal.metrostudygis.com/arcgis/sharing/rest/content/items/"
rr_app = fetch("round_rock_app.json", rr_portal + "664b1d4bdb2448aa86307343b34ba9d0/data?f=json")
assert rr_app["map"]["itemId"] == "0842a9153b0249f4b45f1f742cf439f0"
rr_map = fetch("round_rock_webmap.json", rr_portal + rr_app["map"]["itemId"] + "/data?f=json")
rr_service = "https://server.metrostudygis.com/arcgis/rest/services/Round_Rock_ISD_2526/MapServer"
assert rr_service in [x.get("url") for x in rr_map["operationalLayers"]]
arcgis_layer("round_rock_elementary", rr_service + "/4")
arcgis_layer("round_rock_everett", rr_service + "/1")

# Pflugerville's replacement locator embeds the actual polygon feature set.
arcgis = "https://www.arcgis.com/sharing/rest/content/items/"
pf_app = fetch("pflugerville_app.json", arcgis + "0bc78994af534cd1a703c8959abeac9d/data?f=json")
pf_id = "bb587c1043a949cca04f1b1904c235e3"
assert any(x.get("itemId") == pf_id for x in pf_app["dataSources"].values())
pf_map = fetch("pflugerville_webmap.json", arcgis + pf_id + "/data?f=json")
pf_layers = [x for x in pf_map["operationalLayers"] if x["title"] == "Elementary Schools 2025-26"]
assert len(pf_layers) == 1
pf_features = pf_layers[0]["featureCollection"]["layers"]
assert len(pf_features) == 1
pf = pf_features[0]
assert pf["layerDefinition"]["geometryType"] == "esriGeometryPolygon"
pf_set = dict(pf["featureSet"], fields=pf["layerDefinition"]["fields"],
              spatialReference=pf["featureSet"]["features"][0]["geometry"]["spatialReference"])
write("pflugerville_elementary.esrijson", pf_set)

# The district's comparison app includes current and proposed 2027–28 zones.
dv_client = "34aa2918-73b2-4db1-87ac-70d916f96b62"
dv_api = "https://apps.myplanware.com/api/schoolsearch/data?"
dv_collections = fetch("del_valle_collections.json", dv_api + urlencode(dict(kind="collections", clientId=dv_client)))
dv = [x for c in dv_collections if c["name"] == "Proposed Elementary" for x in c["items"] if x["scenario_name"] == "Current"]
assert len(dv) == 1 and dv[0]["id"] == "8a931554-2f25-4e07-a9a2-b9d8b9381c5c"
dv_zones = fetch("del_valle_elementary.geojson", dv_api + urlencode(dict(kind="collection", clientId=dv_client, collectionItemId=dv[0]["id"])))
assert len(dv_zones["features"]) == len(dv[0]["zones"]) == 9

# Manor enrollment links this live 2026–27 locator. Boundaries took effect in
# fall 2024 and still carry 24–25 names. No bus-stop or individual records used.
mi_api = "https://www.infofinderi.com/ifi/ws/"
mi_client = fetch("manor_client.json", mi_api + "ClientRequest.asmx/GetClientData?clientId=MI3XYXKDFNS",
                  lambda d: {k: d[k] for k in ["id", "name", "bulletinEnglish", "lastUpdatedStr", "schools"]})
assert "2026-2027" in mi_client["bulletinEnglish"] and mi_client["name"] == "Manor ISD"
mi_layers = fetch("manor_layers.json", mi_api + "RedistrictRequest.asmx/GetRedistricts?clientId=MI3XYXKDFNS")
assert any(x["RedistrictId"] == 4 and x["RedistrictName"] == "24-25 Elementary Schools" for x in mi_layers)
mi = fetch("manor_elementary_encoded.json", mi_api + "RedistrictRequest.asmx/GetRedistrict?clientId=MI3XYXKDFNS&redistrictId=4")
assert mi["RedistrictName"] == "24-25 Elementary Schools" and len(mi["Schools"]) == 8


def decode_ring(encoded):
    # Exactly the public locator's signed-delta algorithm, precision 1e6.
    offset, lat, lon, result = 0, 0, 0, []
    while offset < len(encoded):
        values = []
        for _ in range(2):
            value = shift = 0
            while True:
                byte = ord(encoded[offset]) - 63
                offset += 1
                value |= (byte & 31) << shift
                shift += 5
                if byte < 32:
                    break
            values.append(~(value >> 1) if value & 1 else value >> 1)
        lat += values[0]
        lon += values[1]
        result.append([lon / 1e6, lat / 1e6])
    assert len(result) >= 3 and all(-98 < x < -97 and 29 < y < 31 for x, y in result)
    if result[0] != result[-1]:
        result.append(result[0])
    return result


names = {s["schoolId"]: s["schoolName"] for s in mi_client["schools"]}
features = []
for school in mi["Schools"]:
    polys = []
    for encoded in school["Polygons"]:
        rings = json.loads(encoded) if encoded.startswith('["') else [encoded]
        polys.append([decode_ring(ring) for ring in rings])
    features.append(dict(type="Feature", properties=dict(source_id=school["SchoolId"],
        name=names[school["SchoolId"]], campus_id="227907" + school["SchoolCode"].zfill(3)),
        geometry=dict(type="MultiPolygon", coordinates=polys)))
write("manor_elementary.geojson", dict(type="FeatureCollection", features=features))

evidence = [
    dict(district="Round Rock ISD", source_label="Round Rock ISD 2526", current_use="District's currently published school-boundary page embeds this service; legacy SCHL_YEAR attributes are not used as assignment years.", page="https://www.roundrockisd.org/o/rrisd/page/school-boundaries-and-maps"),
    dict(district="Pflugerville ISD", source_label="Elementary Schools 2025-26", current_use="Current Find My School locator; 2026–27 enrollment directs families to this map. Proposed closures/rezoning apply in 2027–28 and are excluded.", page="https://www.pfisd.net/registration-information/find-my-school-map"),
    dict(district="Del Valle ISD", source_label="Current", current_use="Current elementary scenario in district-published map; future Option A/B excluded.", page="https://www.dvisd.net/departments/communications/north-del-valle-hs-updates/attendance-zones"),
    dict(district="Manor ISD", source_label="24-25 Elementary Schools", current_use="Enrollment-linked locator explicitly announces 2026–27; official attendance page says elementary changes effective fall 2024. Live locator layer retained with original label.", page="https://www.manorisd.net/information-for-parents-and-scholars/enroll")]
write("source_manifest.json", dict(assignment_school_year="2026-27", current_use_basis="District-published live locators, checked 2026-11-09; not district-certified effective-year GIS exports", evidence=evidence, files=MANIFEST))
print("Saved elementary boundary snapshots for Round Rock, Pflugerville, Del Valle and Manor.")
