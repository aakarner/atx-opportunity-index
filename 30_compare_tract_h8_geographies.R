# Compare Austin census tract and H3 H8 geographies
#
# This standalone demonstration script compares the current ACS tract geography
# used by the proof-of-concept with the H3 resolution 8 geography under
# consideration. The tract side uses 2024 ACS 5-year geometry, based on 2020
# Census tract definitions.
# This supplemental geography comparison informs future development but is not
# a result of the submitted Methods and Data Report.

source("00_setup_packages.R")
setup_project_packages(c(
  "tidyverse", "h3jsr", "patchwork", "scales", "sf",
  "tidycensus", "tigris"
))

options(tigris_use_cache = TRUE)
sf_use_s2(FALSE)

extract_polygons <- function(x) {
  suppressWarnings(st_collection_extract(x, "POLYGON"))
}

drop_empty_positive_area <- function(x) {
  x <- x[!st_is_empty(x), ]
  x[as.numeric(st_area(x)) > 0, ]
}

h8_access_path <- "accessibility/output/h8_job_accessibility.csv"
output_dir <- "output"
equal_area_crs <- 5070
acs_year <- 2024
city_boundary_year <- 2024
analysis_counties <- c("Travis", "Williamson", "Hays")
acs_geometry_variable <- "B01003_001"

figure_path <- file.path(output_dir, "tract_h8_geography_comparison.png")
stats_path <- file.path(output_dir, "tract_h8_geography_comparison_stats.csv")

if (!file.exists(h8_access_path)) {
  stop(
    "Missing ", h8_access_path,
    ". Run the accessibility pipeline first."
  )
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message(
  "Pulling ",
  acs_year,
  " ACS tract geometry for ",
  paste(analysis_counties, collapse = ", "),
  " counties..."
)

county_tracts <- lapply(
  analysis_counties,
  function(county_name) {
    get_acs(
      geography = "tract",
      variables = acs_geometry_variable,
      state = "TX",
      county = county_name,
      year = acs_year,
      survey = "acs5",
      geometry = TRUE,
      output = "wide"
    )
  }
) %>%
  bind_rows() %>%
  select(GEOID, NAME, geometry) %>%
  st_transform(4326) %>%
  st_make_valid()

message("Pulling ", city_boundary_year, " City of Austin boundary...")

austin_outline <- places(
  state = "TX",
  year = city_boundary_year,
  class = "sf"
) %>%
  filter(NAME == "Austin") %>%
  st_transform(4326) %>%
  st_make_valid() %>%
  extract_polygons()

austin_outline_equal_area <- austin_outline %>%
  st_transform(equal_area_crs)

if (nrow(austin_outline_equal_area) != 1) {
  stop(
    "Expected exactly one City of Austin boundary; found ",
    nrow(austin_outline_equal_area),
    "."
  )
}

county_tracts_equal_area <- county_tracts %>%
  st_transform(equal_area_crs)

tracts_equal_area <- suppressWarnings(
  county_tracts_equal_area %>%
    st_filter(austin_outline_equal_area, .predicate = st_intersects) %>%
    st_intersection(st_geometry(austin_outline_equal_area))
) %>%
  st_make_valid() %>%
  drop_empty_positive_area() %>%
  group_by(GEOID, NAME) %>%
  summarise(.groups = "drop")

tracts <- tracts_equal_area %>%
  st_transform(4326)

h8_access <- read_csv(h8_access_path, show_col_types = FALSE)

h8_cells <- st_sf(
  h3_id = unique(h8_access$h3_id),
  geometry = cell_to_polygon(unique(h8_access$h3_id)),
  crs = 4326
) %>%
  st_make_valid() %>%
  extract_polygons()

h8_cells_display <- suppressWarnings(
  st_intersection(
    st_transform(h8_cells, equal_area_crs),
    st_geometry(austin_outline_equal_area)
  )
) %>%
  st_make_valid() %>%
  extract_polygons() %>%
  st_transform(4326)

summarise_units <- function(data, label, area_column_name = "unit_area_sq_km") {
  areas_sq_km <- data %>%
    st_transform(equal_area_crs) %>%
    st_area() %>%
    as.numeric() / 1e6

  tibble(
    geography = label,
    units = nrow(data),
    total_area_sq_km = sum(areas_sq_km),
    mean_area_sq_km = mean(areas_sq_km),
    median_area_sq_km = median(areas_sq_km),
    min_area_sq_km = min(areas_sq_km),
    max_area_sq_km = max(areas_sq_km),
    mean_area_acres = mean(areas_sq_km) * 247.105,
    median_area_acres = median(areas_sq_km) * 247.105,
    area_measure = area_column_name
  )
}

geography_stats <- bind_rows(
  summarise_units(
    tracts,
    paste0(acs_year, " ACS census tracts clipped to City of Austin"),
    "City-intersection tract area; 2024 ACS tract geography"
  ),
  summarise_units(
    h8_cells,
    "H3 resolution 8 cells with centers in Austin",
    "Full H8 cell area"
  ),
  summarise_units(
    h8_cells_display,
    "H3 resolution 8 cells clipped to City of Austin",
    "City-intersection H8 area"
  )
) %>%
  mutate(
    across(
      c(
        total_area_sq_km, mean_area_sq_km, median_area_sq_km,
        min_area_sq_km, max_area_sq_km, mean_area_acres,
        median_area_acres
      ),
      ~ round(.x, 3)
    )
  )

write_csv(geography_stats, stats_path)

summary_label <- geography_stats %>%
  filter(geography != "H3 resolution 8 cells clipped to City of Austin") %>%
  transmute(
    geography,
    label = paste0(
      comma(units), " units; mean area ",
      number(mean_area_sq_km, accuracy = 0.01), " km² / ",
      number(mean_area_acres, accuracy = 1), " acres"
    )
  )

tract_subtitle <- summary_label$label[
  summary_label$geography == paste0(acs_year, " ACS census tracts clipped to City of Austin")
]
h8_subtitle <- summary_label$label[
  summary_label$geography == "H3 resolution 8 cells with centers in Austin"
]

base_map_theme <- theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
    plot.subtitle = element_text(size = 10, hjust = 0.5),
    plot.caption = element_text(size = 8, hjust = 0),
    plot.margin = margin(5, 5, 5, 5)
  )

tract_plot <- ggplot() +
  geom_sf(data = tracts, fill = "#d8e6f3", color = "#315f85", linewidth = 0.12) +
  geom_sf(data = austin_outline, fill = NA, color = "#111111", linewidth = 0.45) +
  coord_sf(datum = NA) +
  labs(
    title = paste0(acs_year, " ACS census tracts"),
    subtitle = tract_subtitle
  ) +
  base_map_theme

h8_plot <- ggplot() +
  geom_sf(data = h8_cells, fill = "#e8dcc8", color = "#8a5f1f", linewidth = 0.08) +
  geom_sf(data = austin_outline, fill = NA, color = "#111111", linewidth = 0.45) +
  coord_sf(datum = NA) +
  labs(
    title = "H3 resolution 8 cells",
    subtitle = h8_subtitle,
    caption = "H8 cells are shown as full cells; the supplemental stats also report their city-intersection area."
  ) +
  base_map_theme

comparison_plot <- tract_plot + h8_plot +
  plot_annotation(
    title = "Census Tracts vs. H3 H8 Geography for Austin Opportunity Analysis",
    subtitle = paste0(
      "Same 2024 Austin outline, different spatial units: ",
      "2024 ACS tract geography compared with regular hexagonal cells."
    ),
    caption = paste0(
      "Source: ACS ", acs_year,
      " 5-Year tract geometry, TIGER/Line ", city_boundary_year,
      " Austin place boundary, and H8 accessibility output. ",
      "Areas calculated in EPSG:", equal_area_crs, "."
    ),
    theme = theme(
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 11, hjust = 0.5),
      plot.caption = element_text(size = 8)
    )
  )

ggsave(
  figure_path,
  comparison_plot,
  width = 13,
  height = 8,
  dpi = 300,
  bg = "white"
)

print(geography_stats)
message("Saved figure to ", figure_path)
message("Saved statistics to ", stats_path)
