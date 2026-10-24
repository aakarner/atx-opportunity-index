# Proposed local cleanup

This manifest records generated or superseded material that can be removed
after explicit approval. Required raw sources, final destination layers,
manual decisions, central workflow code, caches requested by the project
owner, and final accessibility results are excluded from deletion.

| Local material | Approximate size | Reason |
| --- | ---: | --- |
| 30 `travel_matrix_subset.csv` files in final run folders | 1.86 GB | Diagnostic copies; source matrices remain and the runner regenerates them |
| Old block/H8 test-output folders | 61 MB | Superseded by the 34 validated scenario-runner outputs |
| Destination comparison scratch products | 21 MB | Decisions are already reflected in final layers and retained QA/manual files |
| Superseded destination `interim/` files | 4.7 MB | Reproducible from raw sources and numbered scripts |
| `data/_backup/` | 7.8 MB | Obsolete duplicate backup inside the working tree |
| Earlier destination-only dashboard | 9.4 MB | Replaced by the accessibility dashboard |
| Unused DataAxle community-organization working set | 2.0 MB | Final workflow uses screened public community and senior centers |
| GeoPackage lock files, `.DS_Store`, and RStudio session state | <1 MB | Temporary application files |
| Five one-off accessibility scripts copied during migration | <0.1 MB | Replaced by the scenario registry and shared runner |

Files explicitly retained include `rosm.cache/`, `accessibility/.venv/`, the H8
matrices, `accessibility/data/`, source downloads, final processed destination
layers, manual decision tables, QA summaries, `accessibility/output/working/`
results/manifests, and the new dashboard.
