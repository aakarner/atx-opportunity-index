"""Extract map classes and georeferencing from LTISD's currently linked GeoPDF.

Requires pypdf, numpy and Pillow. This is a raster-derived approximation, not
district GIS polygons. The seven colors are matched to the PDF legend; gray
cartographic marks are filled only when surrounded by a single class. Marks
touching multiple zones or the exterior remain unassigned. No proximity-based
school assignment is used. Run build_lake_travis_pdf.R after this script.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from pypdf import PdfReader

ROOT = Path("data/raw/elementary_boundaries/2026_27")
source = ROOT / "lake_travis_elementary.pdf"
assert hashlib.sha256(source.read_bytes()).hexdigest() == "edfc6e960bbd1166e9151439a4b71c0357ca175cd450c0a8368b885c3f61a91d", "LTISD map changed; review colors, controls, and effective year before extracting"
page = PdfReader(source).pages[0]
viewport = page["/VP"][0]
measure = viewport["/Measure"].get_object()
assert measure["/Subtype"] == "/GEO"
names = ["Bee Cave", "Lake Pointe", "Lake Travis", "Lakeway", "Rough Hollow",
         "Serene Hills", "West Cypress Hills"]
palette = np.array([[114, 137, 68], [214, 157, 188], [224, 90, 85],
                    [74, 177, 212], [88, 232, 84], [112, 68, 137], [232, 169, 81]])


def hue(rgb):
    rgb = rgb.astype(float)
    rgb -= rgb.min(axis=-1, keepdims=True)
    return rgb / np.maximum(1, rgb.max(axis=-1, keepdims=True))


# The PDF paints its geographic image in horizontal strips with one overlapping
# pixel row. Recover placement from each image matrix, never concatenate blindly.
strips = []
ops = page.get_contents().operations
for i, (args, op) in enumerate(ops):
    if op != b"Do":
        continue
    obj = page["/Resources"]["/XObject"][args[0]].get_object()
    if obj.get("/Subtype") != "/Image" or obj.get("/Width") != 9750:
        continue
    assert ops[i - 1][1] == b"cm"
    a, b, c, d, e, f = map(float, ops[i - 1][0])
    assert b == c == 0 and a > 0 and d < 0 and obj["/ColorSpace"] == "/DeviceRGB"
    strips.append((a, d, e, f, obj))
assert len(strips) == 225
width = 9750
pixel = strips[0][0] / width
pixel_y = -strips[0][1] / int(strips[0][4]["/Height"])
left, top = strips[0][2:4]
height = round((top - strips[-1][3] - strips[-1][1]) / pixel_y)
classes = np.zeros((height, width), dtype=np.uint8)
seen_rows = set()
max_color_error = 0.0
overlap_repainted_pixels = 0
for a, d, e, f, obj in strips:
    assert abs(a / width - pixel) < 1e-8 and abs(e - left) < 1e-6
    rows = int(obj["/Height"])
    assert abs(-d / rows - pixel_y) < 1e-7
    offset = round((top - f) / pixel_y)
    assert abs(top - f - offset * pixel_y) < 0.002
    rgb = np.frombuffer(obj.get_data(), dtype=np.uint8).reshape(rows, width, 3)
    packed = rgb.astype(np.uint32)
    codes, inverse = np.unique(packed[:, :, 0] * 65536 + packed[:, :, 1] * 256 + packed[:, :, 2], return_inverse=True)
    colors = np.column_stack((codes // 65536, codes // 256 % 256, codes % 256))
    labels = np.zeros(len(colors), dtype=np.uint8)
    chromatic = np.ptp(colors.astype(int), axis=1) > 0
    distances = np.linalg.norm(hue(colors[chromatic])[:, None, :] - hue(palette)[None, :, :], axis=2)
    if len(distances):
        max_color_error = max(max_color_error, float(distances.min(axis=1).max()))
        assert max_color_error < 0.05, "Unexpected map color; review legend"
        labels[chromatic] = distances.argmin(axis=1) + 1
    labels[~chromatic & (colors[:, 0] < 255)] = 255
    # PDF image samples start at image-space y=1. The negative-y paint matrix
    # reverses each strip; converting to a north-up raster must reverse it too.
    block = np.flipud(labels[inverse].reshape(rows, width))
    if offset in seen_rows:
        # ArcMap repaints one shared row; follow PDF painting order and audit it.
        overlap_repainted_pixels += int(np.sum(classes[offset] != block[0]))
    classes[offset:offset + rows] = block
    seen_rows.update(range(offset, offset + rows))
assert len(seen_rows) == height

# Fill only enclosed gray/black cartographic marks with unanimous colored
# neighbors. Preserve all white exterior pixels and all ambiguous marks.
flat = classes.reshape(-1)
remaining = set(np.flatnonzero(flat == 255).tolist())
filled = unresolved = 0
while remaining:
    seed = remaining.pop()
    component, todo, neighbors = [seed], [seed], set()
    while todo:
        i = todo.pop()
        for j in (i - width, i + width, i - 1, i + 1):
            if j < 0 or j >= len(flat) or (abs(j - i) == 1 and i // width != j // width):
                neighbors.add(0)
            elif flat[j] == 255:
                if j in remaining:
                    remaining.remove(j)
                    component.append(j)
                    todo.append(j)
            else:
                neighbors.add(int(flat[j]))
    label = next(iter(neighbors)) if len(neighbors) == 1 and 0 not in neighbors else 0
    flat[component] = label
    if label:
        filled += len(component)
    else:
        unresolved += len(component)

Image.fromarray(classes).save(ROOT / "lake_travis_classes.tif", compression="tiff_lzw")
# Explicit world file prevents image readers from treating unreferenced TIFF
# rows as south-up. These are PDF page coordinates, georeferenced in the R step.
(ROOT / "lake_travis_classes.tfw").write_text("\n".join(map(str,
    [pixel, 0, 0, -pixel_y, left + pixel / 2, top - pixel_y / 2])) + "\n")
metadata = dict(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    method="Georeferenced PDF raster colors; approximate attendance boundaries",
    source_effective_year="2023-24", current_use_checked="2026-11-10", names=names,
    pdf_bbox=list(map(float, viewport["/BBox"])), gpts=list(map(float, measure["/GPTS"])),
    lpts=list(map(float, measure["/LPTS"])), crs_wkt=str(measure["/GCS"]["/WKT"]),
    raster_extent=[left, left + width * pixel, top - height * pixel_y, top],
    width=width, height=height, pixel_points=pixel, pixel_y_points=pixel_y, maximum_hue_error=max_color_error,
    cartographic_pixels_filled=filled, ambiguous_cartographic_pixels_unassigned=unresolved,
    overlap_repainted_pixels=overlap_repainted_pixels,
    class_pixels=[int(np.sum(classes == i)) for i in range(1, 8)])
(ROOT / "lake_travis_pdf_georeferencing.json").write_text(json.dumps(metadata, indent=2))
print(json.dumps({k: metadata[k] for k in ("width", "height", "maximum_hue_error",
    "cartographic_pixels_filled", "ambiguous_cartographic_pixels_unassigned", "class_pixels")}, indent=2))
