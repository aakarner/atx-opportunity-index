# Local data contract

The `data/` directory is intentionally excluded from ordinary Git commits.
Keep the following local hierarchy so configuration paths remain portable:

```text
data/
├── Karner, Alex - austin_msa_h3_r8_share_2026-10-02/
│   ├── input/                       # H8 grid and metro boundary
│   └── outputs/long/                # prepared auto matrices
└── destinations/
    ├── manual/                      # human decisions and coordinate overrides
    ├── groceries/{raw,processed,qaqc}/
    ├── childcare/{raw,processed,qaqc}/
    ├── pharmacies/{raw,processed,qaqc}/
    ├── healthcare/{raw,processed,qaqc}/
    ├── parks/{raw,processed,qaqc}/
    ├── libraries/{raw,processed,qaqc}/
    └── recreation_centers/{raw,processed,qaqc}/
```

### Retention rules

- `raw/`: immutable source snapshots needed to rebuild a destination.
- `processed/`: only authoritative final layers and compact analysis inputs.
- `manual/`: preserve every team-reviewed inclusion, classification, and
  coordinate decision; back these files up separately.
- `qaqc/`: retain compact summaries and unresolved-review tables.
- `interim/`: reproducible working files; remove after the final layer passes
  QA unless a script cannot reconstruct them.

The 1.1 GB NPPES monthly archive is intentionally local. Do not place licensed
DataAxle exports or other restricted source files in a public repository.
Record source dates, URLs, checksums, and access restrictions in manifests or
methods notes instead.

Accessibility-specific inputs such as GTFS, OSM, LODES, and the R5 network are
stored under `accessibility/data/`, following `accessibility/README.md`.
