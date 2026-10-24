# Accessibility dashboard

This folder is the static GitHub Pages build of the Austin Metro Accessibility
Explorer. Open `index.html` through a local web server for review; browsers
cannot load the data files correctly from a `file://` URL.

The dashboard reads compact files under `data/` that were exported from the
validated scenario results. To refresh it:

1. Run all required scenarios with `accessibility/scripts/run_accessibility.R`.
2. Run `dashboard/scripts/export_dashboard_data.py` from the repository root.
3. Validate the export with `validate_dashboard_data.py`.
4. Review the changed compact data files before committing them.

GitHub Actions publishes this directory through
`.github/workflows/dashboard-pages.yml`. The dashboard contains derived,
compact outputs; raw downloads and routing matrices stay outside Git.
