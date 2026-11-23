# Benefit and burden website

The static client in `site/` is designed for GitHub Pages at
https://aakarner.github.io/atx-opportunity-index/ . It uses Leaflet 1.9.4,
H3-js 4.2.1, CARTO Positron, and the public City of Austin address locator.
Vendored browser library licenses are in `site/vendor/`.

## Map views

**Benefits** opens on families, using 45 minutes by transit and walking. The
combined score and minimum status use the selected housing profile. Other views
show destination counts or compare a profile with all eight destination types.
Elementary assignments use the selected point for address profiles and the
routing origin for map scores. See [benefit methods](benefits.md).

**Burdens** opens directly at `/#burdens`. The selector includes the combined
score, overall classification, five component scores, heat observation quality,
and industrial-air screening bands. Heat contributes one third. Crashes,
unserved major-street frontage, industrial air, and near-road traffic contribute one sixth each.
An unavailable component withholds the combined score. Two known high components
are sufficient to flag a hexagon, even when another observation is missing.
The default crash and major-street frontage radius is half a mile. The quarter-mile
radius and 25% traffic-overlap flag are available as sensitivities. See
[burden methods](burdens.md).

**Eligibility** shows the city’s fully developed floodplain over hex outlines.
Entirely covered hexagons are excluded. For partial overlap, the address profile
tests the selected coordinate. The floodplain overlay is available in every view.

## Rebuild and preview

From the repository root:

```sh
# Set DAM_DATA_DIR to the 2026-11-03 snapshot before rebuilding.
Rscript scripts/run_pipeline.R web_mockup_data
Rscript scripts/site/configure_basemap.R /path/to/.Renviron
for test in tests/*.mjs; do node "$test" || exit 1; done
Rscript tests/test_web_mockup.R
python3 -m http.server 8765 --bind 127.0.0.1 --directory site
```

Open http://127.0.0.1:8765/ . ES modules and data fetches require an HTTP
server, not a `file://` URL. There is no Node package install or frontend build.
The R export test uses the existing targets store; the Node checks operate on
the committed public snapshot and run in GitHub Actions on PRs and main pushes.

`web_mockup_data` builds all map assets, including benefits, combined burdens,
and flood eligibility. Its geography export supplies the city boundary, hexagon
and tract source values, observation metadata, and coverage. The browser checks
the combined assessments against the exported component values and flags. Commit
regenerated snapshots with their corresponding method or configuration changes.

## Address lookup and geography

Searches go directly from the browser to the City of Austin locator, only on
submission. The user chooses among returned matches; geocoder text is escaped
before display. Requests time out, and stale responses/selections are discarded.
The site does not persist searches or use an analytics service.

`latLngToCell(latitude, longitude, 8)` identifies the actual containing hexagon.
The exact H3 ID joins the exported source rows. A point must also lie within the
pinned Austin municipal polygon (full- and limited-purpose limits, including
Dog’s Head; ETJ excluded). No nearest-hex or tract fallback fabricates an address
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
