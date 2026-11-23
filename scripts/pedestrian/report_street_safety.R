# Compare the crash and sidewalk gap indicators at the two study radii.
.libPaths(c(".R-library", .libPaths()))
suppressPackageStartupMessages({library(sf); library(ggplot2); library(patchwork)})
source("R/pipeline_reports.R")
root <- "output/components/street-safety"
analysis <- readRDS(file.path(root, "analysis.rds"))
policy <- analysis$policy$scoring
components <- c(crash_score = "Fatal and serious-injury crashes", major_frontage_score = "Sidewalk gaps on major streets")
flags <- c(crash_score = "crash_high", major_frontage_score = "major_frontage_high")

component_map <- function(geometry, field) {
  ggplot(geometry) + geom_sf(aes(fill = .data[[field]]), color = NA) +
    scale_fill_viridis_c(option = "magma", direction = -1, limits = c(0, 100),
      na.value = "#b5bdc1", name = "Burden score") +
    labs(title = components[[field]]) + theme_void() + theme(legend.position = "bottom")
}

summary_rows <- list()
for (scenario in names(analysis$results)) {
  rows <- analysis$results[[scenario]]
  geometry <- merge(analysis$geometry, rows, by = "h3_id", sort = FALSE)
  maps <- lapply(names(components), function(field) component_map(geometry, field))
  radius <- unique(rows$radius_miles)
  plot <- wrap_plots(maps, guides = "collect") +
    plot_annotation(title = paste(radius, "mile neighborhoods"),
      caption = "Gray indicates missing observations. Each component contributes one sixth of the overall burden score.")
  basename <- if (scenario == "primary") "primary_map" else "sensitivity_maps"
  ggsave(file.path(root, paste0(basename, ".png")), plot, width = 12, height = 8, dpi = 160)
  if (scenario == "primary") ggsave(file.path(root, "primary_map.pdf"), plot, width = 12, height = 8)
  for (field in names(components)) {
    observed <- is.finite(rows[[field]])
    summary_rows[[length(summary_rows) + 1L]] <- data.frame(
      component = components[[field]], radius_miles = radius, available = sum(observed),
      unavailable = sum(!observed), median_score = median(rows[[field]], na.rm = TRUE),
      high = sum(rows[[flags[[field]]]], na.rm = TRUE),
      known_residents_covered_percent = 100 * sum(rows$total_population[observed], na.rm = TRUE) /
        sum(rows$total_population, na.rm = TRUE))
  }
}
summary <- do.call(rbind, summary_rows)
write.csv(summary, file.path(root, "summary.csv"), row.names = FALSE)
html <- paste0('<!doctype html><html lang="en"><meta charset="utf-8"><title>Crashes and sidewalk gaps on major streets</title>',
  '<style>body{font:17px/1.5 system-ui;max-width:1100px;margin:36px auto;padding:0 20px}img{width:100%}th,td{padding:8px;text-align:left}</style>',
  '<h1>Crashes and sidewalk gaps on major streets</h1><p>Both indicators use circles around hexagon centers clipped to Austin. ',
  'Crash scores reach 100 at ', round(policy$crash_full_burden_density, 3),
  ' fatal or serious-injury crashes per year per observed square mile. The high flag starts at ',
  round(policy$crash_high_burden_density, 3), '. The sidewalk gap score is the percentage of major-street length without a mapped sidewalk or parallel path, counting each side separately. ',
  'The high flag starts at ', policy$major_frontage_high_burden_score, '%. Each high component counts toward the overall threshold of two.</p>',
  '<h2>Half-mile neighborhoods</h2><img src="primary_map.png" alt="Half-mile crash and sidewalk gap scores">',
  '<h2>Quarter-mile sensitivity</h2><img src="sensitivity_maps.png" alt="Quarter-mile crash and sidewalk gap scores">',
  '<h2>Coverage and flags</h2>', report_html_table(summary),
  '<p><a href="primary.csv">Half-mile data</a> · <a href="sensitivity.csv">Quarter-mile data</a> · ',
  '<a href="summary.csv">Summary</a> · <a href="primary_map.pdf">Half-mile maps (PDF)</a></p></html>')
writeLines(html, file.path(root, "review.html"))
