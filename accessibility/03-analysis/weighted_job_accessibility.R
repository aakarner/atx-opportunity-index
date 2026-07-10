# Summarize and map H8 accessibility using 2023 LODES resident workers.

source("accessibility/config.R")

source("setup_packages.R")
setup_project_packages(c(
  "dplyr", "ggplot2", "h3jsr", "patchwork", "purrr", "readr",
  "scales", "sf", "tidyr"
))

if (!file.exists(accessibility_output_path) || !file.exists(lodes_workers_path)) {
  stop("Run the LODES preparation and unweighted accessibility scripts first.")
}

access <- read_csv(accessibility_output_path, show_col_types = FALSE)
workers <- read_csv(lodes_workers_path, show_col_types = FALSE)

worker_columns <- c(
  "workers_all", "workers_low", "workers_middle", "workers_high"
)

access_workers <- access %>%
  select(-any_of(worker_columns)) %>%
  left_join(workers, by = "h3_id") %>%
  mutate(across(starts_with("workers_"), ~ replace_na(.x, 0)))

# Keep the resident-worker weights with the committed H8 results so downstream
# tract validation does not depend on an ignored intermediate file.
write_csv(access_workers, accessibility_output_path)

measure_config <- tibble(
  access_column = c(
    "access_total_jobs", "access_low_wage_jobs",
    "access_middle_wage_jobs", "access_high_wage_jobs"
  ),
  worker_column = c(
    "workers_all", "workers_low", "workers_middle", "workers_high"
  ),
  job_type = c("All jobs", "Low-wage jobs", "Middle-wage jobs", "High-wage jobs")
)

summary_table <- purrr::pmap_dfr(
  measure_config,
  function(access_column, worker_column, job_type) {
    values <- access_workers[[access_column]]
    weights <- access_workers[[worker_column]]
    valid <- !is.na(values) & weights > 0

    tibble(
      job_type = job_type,
      weighted_mean = weighted.mean(values[valid], weights[valid]),
      unweighted_mean = mean(values, na.rm = TRUE),
      median = median(values, na.rm = TRUE),
      minimum = min(values, na.rm = TRUE),
      maximum = max(values, na.rm = TRUE),
      worker_count = sum(weights, na.rm = TRUE)
    )
  }
)

summary_path <- file.path(output_dir, paste0("h", h3_resolution, "_job_accessibility_summary.csv"))
write_csv(summary_table, summary_path)

map_data <- st_sf(
  access_workers,
  geometry = cell_to_polygon(access_workers$h3_id),
  crs = 4326
) %>%
  pivot_longer(
    cols = starts_with("access_"),
    names_to = "measure",
    values_to = "jobs_accessible"
  ) %>%
  mutate(
    measure = recode(
      measure,
      access_total_jobs = "All jobs",
      access_low_wage_jobs = "Low-wage jobs",
      access_middle_wage_jobs = "Middle-wage jobs",
      access_high_wage_jobs = "High-wage jobs"
    )
  )

map_plots <- lapply(measure_config$job_type, function(measure_name) {
    data <- filter(map_data, measure == measure_name)
    legend_max <- max(data$jobs_accessible, na.rm = TRUE)
    legend_breaks <- c(0, legend_max / 2, legend_max)

    ggplot(data) +
      geom_sf(aes(fill = jobs_accessible), color = NA) +
      scale_fill_viridis_c(
        labels = scales::label_number(scale_cut = scales::cut_short_scale()),
        breaks = legend_breaks,
        option = "mako",
        guide = guide_colorbar(
          title.position = "top",
          barwidth = grid::unit(3, "cm"),
          barheight = grid::unit(0.3, "cm")
        )
      ) +
      labs(title = unique(data$measure), fill = "Jobs") +
      theme_void() +
      theme(
        plot.title = element_text(face = "bold"),
        legend.position = "bottom"
      )
  })

access_map <- wrap_plots(map_plots, ncol = 2) +
  plot_annotation(
    title = paste0("City of Austin H", h3_resolution, " Transit Access to Jobs"),
    subtitle = paste0(
      "Jobs reachable within ", access_cutoff_minutes,
      " minutes; 2023 LODES jobs on the pinned 2026 transit network"
    ),
    caption = paste0(
      "Median travel times for departures from 7:00–8:59 a.m. on July 13, 2026; ",
      "GTFS and OSM snapshots: June 25, 2026"
    ),
    theme = theme(plot.title = element_text(face = "bold"))
  )

map_path <- file.path(output_dir, paste0("h", h3_resolution, "_job_accessibility_map.png"))
ggsave(map_path, access_map, width = 13, height = 10, dpi = 300, bg = "white")

print(summary_table)
message("Updated H8 accessibility output with resident-worker weights at ", accessibility_output_path)
message("Saved summary to ", summary_path)
message("Saved map to ", map_path)
