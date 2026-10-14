# Benefit and burden website

The static client in `site/` is designed for GitHub Pages at
https://aakarner.github.io/atx-opportunity-index/ . It uses Leaflet 1.9.4,
H3-js 4.2.1, CARTO Positron, and the public City of Austin address locator.
Vendored browser library licenses are in `site/vendor/`.

## Rebuild and preview

From the repository root:

```sh
Rscript scripts/run_pipeline.R web_mockup_data
Rscript scripts/site/configure_basemap.R /path/to/.Renviron
node tests/test_web_mockup.mjs
Rscript tests/test_web_mockup.R
python3 -m http.server 8765 --bind 127.0.0.1 --directory site
```

Open http://127.0.0.1:8765/ . ES modules and data fetches require an HTTP
server, not a `file://` URL. There is no Node package install or frontend build.
The R export test uses the existing targets store; the Node checks operate on
the committed public snapshot and run in GitHub Actions on PRs and main pushes.

`web_mockup_data` depends on the pipeline's H8, tract, city-boundary, and
classification objects. It writes four compact public data files in
`site/assets/`. It does not duplicate source acquisition or spatial analysis.
Commit regenerated snapshots with any corresponding method/configuration change.
Thresholds come from `config/classification-review.yml`:

- Strong access: **strictly >50,000** jobs reachable by walk/transit in 45 minutes.
- Elevated burden: **RSEI air ToxConc >=100**.

The client checks every exported flag against its metadata before showing the
map. Missing values become JSON null and remain unknown. The current snapshot
has 1,021 H8 cells and 275 city-clipped tracts. Flags: 137 strong-access H8s,
321 elevated-burden H8s, 48 with both; 80 strong-access tracts and 87 elevated
tracts. These are prototype classifications, not adopted adequacy/health standards.

## Address lookup and geography

Searches go directly from the browser to the City of Austin locator, only on
submission. The user chooses among returned matches; geocoder text is escaped
before display. Requests time out, and stale responses/selections are discarded.
The site does not persist searches or use an analytics service.

`latLngToCell(latitude, longitude, 8)` identifies the actual containing hexagon.
The exact H3 ID joins the exported source rows. A point must also lie within the
2024 Austin study polygon. No nearest-hex or tract fallback fabricates an address
profile. Outside-city and uncovered cells show unavailable values and unknown
flags. City polygon holes and multipolygons are respected. Tract lookup uses
exported generalized Census geometry and is contextual, not a parcel assignment.

H8 access describes the routing origin; H8 RSEI is a full-cell area mean.
Tract access uses area-apportioned resident-worker weights (same weights for all
wage components), with area weighting or nearest-origin fallbacks identified in
the profile. Tract RSEI uses city-clipped area means. The profile keeps these
geographies separate. A tract click offers a separate hex profile at that point.
Selected source H8 outlines can extend beyond the study boundary.

Low/middle/high-wage access is a breakdown of total access. Cancer and noncancer
RSEI concentrations are diagnostics, not additive subcomponents of total ToxConc.
Benefits and burdens have separate flags; no net score is computed. See
`docs/rsei.md` and `accessibility/README.md` for provenance and interpretation.

## CARTO configuration

`scripts/site/configure_basemap.R` reads `CARTO_BASEMAP_API_KEY` from the environment
or an explicitly supplied environment file. The companion displacement repository
uses the same browser-basemap setup. It writes Git-ignored
`site/assets/basemap.json`, included in the public Pages artifact. The key is
necessarily visible in browser tile requests; use a basemap-only key restricted
to `aakarner.github.io` (and localhost if previewing), not a private API token.
Do not commit the source environment file. The script never prints the key.
Without this generated file, a source-only preview falls back to OpenStreetMap
standard tiles. No tile prefetching or offline download is implemented.

## Publish

Source changes can be reviewed on a feature branch while the mockup is deployed
independently. After committing the intended source and configuring CARTO:

```sh
bash scripts/site/publish.sh
```

Set `NODE_BIN` if Node is not on PATH. The script validates the snapshot, copies
only `site/` into a temporary checkout, and commits/pushes the `gh-pages` branch.
It preserves deployment history and never force-pushes. `deployment.json` records
the source commit. Repository Pages settings must serve **gh-pages / (root)**.
GitHub's branch deployment builds after the push; source PRs do not auto-publish.
The initial source work is in a review branch; future iterations use the same
script. For a larger public rollout, revisit basemap capacity, geocoder service
availability, keyboard tract navigation, and the draft thresholds.

## Combined map

The Combined tab cross-classifies the existing tract flags: both (purple, 29
tracts), strong access only (green, 51), elevated burden only (orange, 58), and
neither (light gray, 137). Missing either flag is unknown, never neither. Legend
counts are calculated from the displayed tract snapshot. The same categories
apply when inspecting hexagons. This is a combination of flags, not a net score;
thresholds and underlying component values are unchanged.

## Resident-group demonstration controls

Four presentation-only buttons preview future access measures for older adults,
families, permanent-supportive housing residents, and single adults. Clicking a
button changes its selected appearance and the demo notice only. It does not
filter data, change thresholds, recolor the map, or alter tract/hex profiles.
The current baseline access values remain the same for every selection.
