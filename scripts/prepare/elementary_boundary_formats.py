"""Readers for public attendance-map formats; never infer a nearby school."""
import re
import xml.etree.ElementTree as ET


def hays_elementary(kml):
    """Read the published 2026–27 folder as of November 10, 2026.

    The future Tom Green move-in overlay explicitly says it belongs to Sunfield
    before January 2027. Preserve that exception in the source audit, assigning
    its geometry to Sunfield for this snapshot (same-campus pieces dissolve).
    """
    ns = {"k": "http://www.opengis.net/kml/2.2"}
    root = ET.fromstring(kml)
    folders = [f for f in root.findall(".//k:Folder", ns)
               if f.findtext("k:name", namespaces=ns) == "Elementary School Zones 2026-2027"]
    if len(folders) != 1:
        raise ValueError("Expected exactly one Hays 2026–27 elementary folder")
    features = []
    for p in folders[0].findall("k:Placemark", ns):
        label = p.findtext("k:name", namespaces=ns).strip()
        description = p.findtext("k:description", default="", namespaces=ns)
        future = label == "Tom Green Elementary Zone (For Move-Ins After January 1, 2027)"
        if future:
            if "This zone goes to Sunfield Elementary" not in description:
                raise ValueError("Hays future move-in exception changed")
            name = "Sunfield"
        else:
            match = re.fullmatch(r"(.+) Elementary Attendance Zone", label)
            if not match:
                raise ValueError("Unrecognized Hays assignment: " + label)
            name = match[1]
        polygons = []
        for polygon in p.findall(".//k:Polygon", ns):
            rings = []
            for tag in ("outerBoundaryIs", "innerBoundaryIs"):
                for boundary in polygon.findall("k:" + tag, ns):
                    coords = boundary.findtext("k:LinearRing/k:coordinates", namespaces=ns)
                    ring = [[float(x) for x in point.split(",")[:2]] for point in coords.split()]
                    if len(ring) < 4 or ring[0] != ring[-1]:
                        raise ValueError("Invalid KML ring")
                    rings.append(ring)
            if not rings:
                raise ValueError("Missing KML polygon rings")
            polygons.append(rings)
        if not polygons:
            raise ValueError("Attendance placemark has no polygons")
        features.append(dict(type="Feature", properties=dict(
            name=name, source_label=label, source_description=description,
            future_move_in_exception=future, snapshot_as_of="2026-11-10"),
            geometry=dict(type="MultiPolygon", coordinates=polygons)))
    if len(features) != 18 or len({f["properties"]["name"] for f in features}) != 17:
        raise ValueError("Unexpected Hays elementary coverage")
    return dict(type="FeatureCollection", features=features)
