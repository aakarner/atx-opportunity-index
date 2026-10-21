# Reporting for the first component-pipeline migration. These functions write
# only to the dedicated output directory; they do not modify source snapshots.

write_component_outputs <- function(tract_components, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(csv = file.path(output_dir, "tract_components.csv"),
             gpkg = file.path(output_dir, "tract_components.gpkg"))
  readr::write_csv(sf::st_drop_geometry(tract_components), paths[["csv"]], na = "")
  sf::st_write(tract_components, paths[["gpkg"]], layer = "tract_components",
               delete_dsn = TRUE, quiet = TRUE)
  unname(paths)
}

component_map_theme <- function() {
  ggplot2::theme_void(base_size = 12) +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      plot.title = ggplot2::element_text(face = "bold", size = 17, margin = ggplot2::margin(b = 7)),
      plot.subtitle = ggplot2::element_text(colour = "#404040", size = 11, margin = ggplot2::margin(b = 12)),
      plot.caption = ggplot2::element_text(hjust = 0, colour = "#555555", size = 9,
                                         margin = ggplot2::margin(t = 10)),
      plot.title.position = "plot", plot.caption.position = "plot",
      plot.margin = ggplot2::margin(16, 18, 16, 18),
      legend.position = "bottom", legend.title = ggplot2::element_text(size = 10),
      legend.text = ggplot2::element_text(size = 9),
      strip.text = ggplot2::element_text(face = "bold", size = 12),
      panel.spacing = grid::unit(1, "lines")
    )
}

map_number_labels <- function(x) {
  format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
}

write_component_maps <- function(tract_components, school_zones, sites, output_dir, map_spec,
                                 job_spec, school_spec, crash_spec) {
  map_dir <- file.path(output_dir, "maps")
  dir.create(map_dir, recursive = TRUE, showWarnings = FALSE)
  width <- if (is.null(map_spec$width)) 9 else map_spec$width
  height <- if (is.null(map_spec$height)) 8 else map_spec$height
  dpi <- if (is.null(map_spec$dpi)) 160 else map_spec$dpi
  tracts <- sf::st_transform(tract_components, 5070)
  boundary <- sf::st_union(sf::st_geometry(tracts))
  city <- sf::st_sf(geometry = boundary)
  missing_colour <- "#cecece"
  base <- ggplot2::ggplot() + component_map_theme()
  specs <- list(
    low_wage_jobs = list(field = "transit_low_wage_jobs_45min", scale = 1,
      title = "Transit access to low-wage jobs",
      subtitle = paste0("Jobs reachable within ", job_spec$cutoff_minutes, " minutes · ",
                         job_spec$employment_year, " LODES jobs · network snapshot ", job_spec$network_snapshot),
      legend = "Reachable low-wage jobs",
      caption = paste("City-clipped tracts; resident-worker-weighted H8 aggregation with flagged fallbacks.",
                      "Provisional component; no combined opportunity score. Grey = missing.", sep = "\n")),
    fema_floodplain = list(field = "fema_one_percent_area_share", scale = 100,
      title = "Mapped 1%-annual-chance floodplain",
      subtitle = "Share of each City-clipped tract within the existing FEMA flood snapshot",
      legend = "Mapped overlap (% of tract area)",
      caption = paste("Physical area overlap, not population exposure. FEMA snapshot; City flood data remain pending.",
                      "Zero mapped overlap does not establish absence of flood risk. Grey = missing.", sep = "\n")),
    ksi_crashes = list(field = "annual_ksi_crash_density", scale = 1,
      title = "Fatal and serious-injury crash density",
      subtitle = paste0("Tract neighborhood measure · City-observed crashes, ", crash_spec$first_year,
                         "–", crash_spec$last_year),
      legend = "Annual KSI crashes / square mile",
      caption = paste(paste0("Average annual crashes within ",
                      format(crash_spec$buffer_meters / 1000, digits = 5, trim = TRUE),
                      " km of an internal tract point, normalized to City-observed area."),
                      "Describes nearby recorded crashes; not an individual risk estimate. Grey = missing.", sep = "\n"))
  )
  paths <- character()
  for (name in names(specs)) {
    spec <- specs[[name]]
    if (!spec$field %in% names(tracts)) stop("Missing map component: ", spec$field)
    map_data <- tracts
    map_data$map_value <- map_data[[spec$field]] * spec$scale
    p <- base +
      ggplot2::geom_sf(data = map_data, ggplot2::aes(fill = map_value), colour = "white", linewidth = 0.06) +
      ggplot2::geom_sf(data = city, fill = NA, colour = "#444444", linewidth = 0.22) +
      ggplot2::scale_fill_viridis_c(option = "C", na.value = missing_colour,
                                   labels = map_number_labels, name = spec$legend) +
      ggplot2::guides(fill = ggplot2::guide_colourbar(barwidth = grid::unit(11, "cm"),
                                                    barheight = grid::unit(0.35, "cm"),
                                                    title.position = "top")) +
      ggplot2::labs(title = spec$title,
                    subtitle = paste(strwrap(spec$subtitle, width = max(50, floor(width * 11))), collapse = "\n"),
                    caption = spec$caption)
    path <- file.path(map_dir, paste0(name, ".png"))
    ggplot2::ggsave(path, p, width = width, height = height, dpi = dpi, bg = "white")
    paths <- c(paths, stats::setNames(path, name))
  }

  school_panels <- lapply(names(school_zones), function(level) {
    zone <- sf::st_transform(school_zones[[level]], sf::st_crs(tracts))
    zone <- zone[, c("campus_name", "usable_growth")]
    zone <- suppressWarnings(sf::st_intersection(zone, boundary))
    zone$level <- tools::toTitleCase(level)
    zone
  })
  schools <- do.call(rbind, school_panels)
  schools$level <- factor(schools$level, levels = c("Elementary", "Middle", "High"))
  outlines <- do.call(rbind, lapply(levels(schools$level), function(level) {
    sf::st_sf(level = factor(level, levels = levels(schools$level)), geometry = boundary)
  }))
  p <- base +
    ggplot2::geom_sf(data = outlines, fill = "#f8f8f8", colour = NA) +
    ggplot2::geom_sf(data = schools, ggplot2::aes(fill = usable_growth), colour = "white", linewidth = 0.06) +
    ggplot2::geom_sf(data = outlines, fill = NA, colour = "#444444", linewidth = 0.2) +
    ggplot2::facet_wrap(~level, nrow = 1, drop = FALSE) +
    ggplot2::scale_fill_viridis_c(option = "C", limits = c(0, 100), na.value = missing_colour,
                                 name = "Campus academic growth score (0–100)") +
    ggplot2::guides(fill = ggplot2::guide_colourbar(barwidth = grid::unit(11, "cm"),
                                                  title.position = "top")) +
    ggplot2::labs(title = "Assigned-school academic growth · AISD only",
      subtitle = paste0("Attendance zones: ", school_spec$assignment_year, " · growth: ", school_spec$growth_year,
                         " · TEA ", school_spec$accountability_year, " accountability release · clipped to Austin"),
      caption = paste("Campus-wide descriptive growth scores; not causal estimates of school effectiveness. Other districts are not yet integrated.",
                      "Grey = unavailable or excluded score. Near-white = outside the mapped AISD assignment coverage; outline = Austin.", sep = "\n"))
  school_path <- file.path(map_dir, "aisd_school_growth.png")
  ggplot2::ggsave(school_path, p, width = max(width, 12), height = height, dpi = dpi, bg = "white")
  paths <- c(paths, aisd_school_growth = school_path)

  if (!is.null(sites) && nrow(sites)) {
    points <- sf::st_transform(sites, sf::st_crs(tracts))
    points$map_label <- seq_len(nrow(points))
    site_key <- paste(strwrap(paste(paste0(points$map_label, ": ", points$label), collapse = "   ·   "),
                              width = 100), collapse = "\n")
    p <- base +
      ggplot2::geom_sf(data = tracts, fill = "#eeeeee", colour = "white", linewidth = 0.08) +
      ggplot2::geom_sf(data = city, fill = NA, colour = "#555555", linewidth = 0.25) +
      ggplot2::geom_sf(data = points, colour = "#163f55", size = 5.5) +
      ggplot2::geom_sf_text(data = points, ggplot2::aes(label = map_label), colour = "white", size = 3) +
      ggplot2::labs(title = "Illustrative screening locations", subtitle = site_key,
                    caption = "Configured demonstration origins, not housing proposals. Site reports retain the resolution and limits of each source.")
    site_path <- file.path(map_dir, "example_locations.png")
    ggplot2::ggsave(site_path, p, width = width, height = height, dpi = dpi, bg = "white")
    paths <- c(paths, example_locations = site_path)
  }
  unname(paths)
}

report_html_escape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- "Unknown / unavailable"
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

report_html_table <- function(x) {
  if (inherits(x, "sf")) x <- sf::st_drop_geometry(x)
  x <- as.data.frame(x)
  if (!nrow(x)) return("<p>No records available.</p>")
  header <- paste0("<th scope=\"col\">", report_html_escape(names(x)), "</th>", collapse = "")
  rows <- vapply(seq_len(nrow(x)), function(i) {
    cells <- vapply(x, function(column) {
      value <- column[i]
      if (is.list(value)) value <- paste(unlist(value), collapse = ", ")
      if (is.numeric(value) && !is.na(value)) value <- format(signif(value, 7), trim = TRUE, scientific = FALSE)
      paste0("<td>", report_html_escape(value), "</td>")
    }, character(1))
    paste0("<tr>", paste(cells, collapse = ""), "</tr>")
  }, character(1))
  paste0("<div class=\"table-scroll\"><table><thead><tr>", header,
         "</tr></thead><tbody>", paste(rows, collapse = "\n"), "</tbody></table></div>")
}

site_report_labels <- function(fields, job_spec, crash_spec) {
  labels <- c(site_id = "Example ID", label = "Location", longitude = "Longitude", latitude = "Latitude",
    selection_note = "Selection note", tract_GEOID = "Containing tract GEOID",
    tract_assignment_status = "Tract assignment", access_origin_h3 = "H8 access origin",
    access_origin_distance_m = "Distance to access origin (m)", access_status = "Access coverage / method",
    transit_jobs_45min = paste("Jobs reachable by transit in", job_spec$cutoff_minutes, "minutes"),
    transit_low_wage_jobs_45min = paste("Low-wage jobs reachable by transit in", job_spec$cutoff_minutes, "minutes"),
    fema_point_intersects = "Point intersects mapped FEMA floodplain",
    flood_screen = "Flood interpretation", ksi_crashes_in_window = paste0("KSI crashes, ", crash_spec$first_year,
                                                                          "–", crash_spec$last_year),
    crash_observed_area_sqmi = "City-observed buffer area (square miles)",
    crash_buffer_meters = "Crash buffer radius (m)", crash_observation_years = "Crash observation period (years)",
    crash_observed_window_share = "Share of crash buffer within City observation area",
    annual_ksi_crash_density = "Annual KSI crashes per square mile", overall_screen = "Screening completeness")
  for (level in c("elementary", "middle", "high")) {
    prefix <- paste0("school_", level, "_")
    labels[paste0(prefix, c("campus_id", "campus_name", "growth", "status"))] <-
      paste(tools::toTitleCase(level), c("campus ID", "assigned campus", "growth score (0–100)", "assignment / score status"))
  }
  result <- gsub("_", " ", fields)
  known <- fields %in% names(labels)
  result[known] <- unname(labels[fields[known]])
  result
}

write_review_report <- function(site_profiles, registry, manifest, qa, maps, output_dir,
                                job_spec, school_spec, crash_spec) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  map_titles <- c(low_wage_jobs = "Transit access to low-wage jobs", fema_floodplain = "FEMA floodplain overlap",
                  ksi_crashes = "Recorded fatal and serious-injury crashes", aisd_school_growth = "AISD assigned-school growth",
                  example_locations = "Illustrative screening locations")
  map_html <- vapply(maps, function(path) {
    # All current maps are generated inside this report's maps/ directory.
    if (!identical(normalizePath(dirname(path)), normalizePath(file.path(output_dir, "maps")))) {
      stop("Review map must be in the report's maps directory: ", path)
    }
    stem <- tools::file_path_sans_ext(basename(path))
    title <- if (stem %in% names(map_titles)) map_titles[[stem]] else gsub("_", " ", stem)
    wide <- if (stem == "aisd_school_growth") ' class="wide"' else ""
    paste0("<figure", wide, "><a href=\"maps/", report_html_escape(basename(path)), "\"><img src=\"maps/",
           report_html_escape(basename(path)), "\" alt=\"", report_html_escape(title),
           "\" loading=\"lazy\"></a><figcaption>", report_html_escape(title), "</figcaption></figure>")
  }, character(1))
  site_profiles <- as.data.frame(site_profiles)
  site_html <- vapply(seq_len(nrow(site_profiles)), function(i) {
    title <- if ("label" %in% names(site_profiles)) site_profiles$label[i] else paste("Example", i)
    values <- vapply(site_profiles, function(column) {
      value <- column[i]
      if (is.list(value)) value <- paste(unlist(value), collapse = ", ")
      if (is.numeric(value) && !is.na(value)) value <- format(signif(value, 7), trim = TRUE, scientific = FALSE)
      as.character(value)
    }, character(1))
    table <- data.frame(measure = site_report_labels(names(values), job_spec, crash_spec),
                        value = unname(values), stringsAsFactors = FALSE)
    paste0("<article class=\"site\"><h3>", report_html_escape(title), "</h3>", report_html_table(table), "</article>")
  }, character(1))
  html <- paste0('<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Austin opportunity components — provisional review</title>
<style>
:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f5f5f2;color:#202d33;font:16px/1.55 system-ui,-apple-system,sans-serif}
main{max-width:1240px;margin:auto;padding:36px 28px 72px}h1{font-size:2.1rem;line-height:1.15;max-width:900px}h2{margin-top:2.2rem;border-bottom:1px solid #c8cfce;padding-bottom:.4rem}h3{margin-top:0}
a{color:#075a75}p{max-width:960px}.kicker{font-size:.85rem;letter-spacing:.09em;text-transform:uppercase;color:#526369;font-weight:700}.notice{border-left:5px solid #c68521;background:#fff6e5;padding:18px 22px;margin:24px 0}.notice p{margin:0 0 .65rem}.notice p:last-child{margin-bottom:0}
.maps{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.maps .wide{grid-column:1/-1}figure{margin:0;background:white;border:1px solid #d9dfdd;padding:10px}figure img{display:block;width:100%;height:auto}figcaption{padding:8px 6px;font-size:.9rem;color:#4d5d63}
.sites{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:16px}.site{background:white;border:1px solid #d9dfdd;padding:18px;min-width:0}.table-scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:.83rem;background:white}th,td{text-align:left;vertical-align:top;border-bottom:1px solid #dfe5e2;padding:8px 10px;overflow-wrap:anywhere}th{background:#e9efec;font-weight:650}.site td:first-child{width:48%;font-family:ui-monospace,monospace;font-size:.76rem}footer{margin-top:36px;font-size:.85rem;color:#57686d}
@media(max-width:760px){main{padding:24px 16px}.maps{grid-template-columns:1fr}h1{font-size:1.7rem}}@media print{body{background:white}main{padding:0}.maps{display:block}figure,.site{break-inside:avoid;margin-bottom:20px}.table-scroll{overflow:visible}}
</style></head><body><main>
<p class="kicker">Austin Opportunity Index · component pipeline</p>
<h1>Benefits, burdens, and illustrative site profiles</h1>
<div class="notice"><p><strong>Provisional component review.</strong> Tract geography and ACS context are rebuilt from Census sources, crash measures from recorded crash points, and displacement context from the City source. Job access, schools, flood, and crash points use prepared snapshots. These products do not constitute a completed opportunity index, adopted screening rules, or recommendations about housing locations.</p>
<p>No composite score, clustering, or site exclusion is applied. Heat, RSEI pollution, traffic pollution, City flood data, and additional destination access remain pending; missing components are unknown, never evidence of zero burden.</p></div>
<p>The same evidence supports tract summaries and finer-scale demonstration profiles. See the indicator registry, source checksums, and QA below for the current scope.</p>
<p><a href="tract_components.csv">Tract component table (CSV)</a> · <a href="tract_components.gpkg">Tract geometries and components (GeoPackage)</a> · <a href="site_profiles.csv">Site profiles (CSV)</a></p>
<h2>Component maps</h2><p>Each map retains its own units. Grey represents missing or unusable values. The school map also distinguishes areas outside the current AISD assignment coverage. Click any map to open its full-size image.</p>
<div class="maps">', paste(map_html, collapse = "\n"), '</div>
<h2>Illustrative site profiles</h2>
<p>These configured origins are examples, not actual housing proposals. Job access uses the containing H8 cell or a nearest-origin fallback and is approximate; no new routing is performed. Review the reported origin distance and coverage flags. Tract context remains distinct from measurements made at a point or around it. The access measure counts jobs reachable in ',
report_html_escape(job_spec$cutoff_minutes), ' minutes, using ', report_html_escape(job_spec$employment_year),
' jobs and network snapshot ', report_html_escape(job_spec$network_snapshot), '.</p>
<p>A point outside the mapped FEMA floodplain has no mapped overlap in that snapshot; this does not establish absence of flood risk. School growth is a campus-wide descriptive score, not a causal estimate of effectiveness. The school baseline uses ',
report_html_escape(school_spec$assignment_year), ' assignments and ', report_html_escape(school_spec$growth_year),
' growth, from the TEA ', report_html_escape(school_spec$accountability_year), ' accountability release. Coverage is currently AISD only.</p>
<p>Site crash density describes the City-observed portion of a ',
report_html_escape(format(crash_spec$buffer_meters / 1000, digits = 5, trim = TRUE)), '-kilometer buffer, using crashes from ',
report_html_escape(crash_spec$first_year), '–', report_html_escape(crash_spec$last_year),
'. It is not an exposure-adjusted crash rate.</p>
<div class="sites">', paste(site_html, collapse = "\n"), '</div>
<h2>Indicator registry</h2>', report_html_table(registry), '
<h2>Quality checks</h2>', report_html_table(qa), '
<h2>Source manifest</h2><p>SHA-256 identifies the exact local file contents used in this run. Source dates and analytical roles are recorded in configuration and the registry.</p>', report_html_table(manifest), '
<footer>Generated from the local targets workflow. Rebuild with <code>Rscript scripts/run_pipeline.R</code> from the repository root. See <code>PIPELINE.md</code> for the migration boundary and interpretation.</footer>
</main></body></html>')
  path <- file.path(output_dir, "review.html")
  writeLines(html, path, useBytes = TRUE)
  path
}
