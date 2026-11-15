"""Hays year selection, future move-in policy, and KML holes."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/prepare"))
from elementary_boundary_formats import hays_elementary


class HaysFormats(unittest.TestCase):
    def fixture(self):
        outer = "-98,30,0 -97,30,0 -97,31,0 -98,31,0 -98,30,0"
        inner = "-97.8,30.2,0 -97.8,30.3,0 -97.7,30.3,0 -97.7,30.2,0 -97.8,30.2,0"
        shape = (f"<Polygon><outerBoundaryIs><LinearRing><coordinates>{outer}</coordinates>"
                 "</LinearRing></outerBoundaryIs><innerBoundaryIs><LinearRing>"
                 f"<coordinates>{inner}</coordinates></LinearRing></innerBoundaryIs></Polygon>")
        labels = [f"School {i} Elementary Attendance Zone" for i in range(16)]
        labels += ["Sunfield Elementary Attendance Zone",
                   "Tom Green Elementary Zone (For Move-Ins After January 1, 2027)"]
        marks = "".join(f"<Placemark><name>{name}</name><description>This zone goes to Sunfield Elementary</description>{shape}</Placemark>" for name in labels)
        return ('<kml xmlns="http://www.opengis.net/kml/2.2"><Document><Folder>'
                '<name>Elementary School Zones 2026-2027</name>' + marks +
                '</Folder><Folder><name>Middle School Zones 2026-2027</name>' + marks +
                '</Folder></Document></kml>')

    def test_year_and_future_assignment(self):
        features = hays_elementary(self.fixture())["features"]
        self.assertEqual(len(features), 18)
        self.assertEqual(features[-1]["properties"]["name"], "Sunfield")
        self.assertTrue(features[-1]["properties"]["future_move_in_exception"])
        self.assertEqual(len(features[0]["geometry"]["coordinates"][0]), 2)
        self.assertEqual(features[0]["geometry"]["coordinates"][0][0][0], [-98, 30])

    def test_changed_source_rejected(self):
        for changed in (self.fixture().replace("2026-2027", "2027-2028"),
                        self.fixture().replace("This zone goes to Sunfield Elementary", "Changed policy")):
            with self.assertRaises(ValueError):
                hays_elementary(changed)


if __name__ == "__main__":
    unittest.main()
