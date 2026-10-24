# Diagnostic maps for the childcare destination layer
#
# Purpose is inspection, not presentation. Geocoding artifacts are far easier
# to see than to summarise: interpolated points stacked along a single street
# segment, records landing in the wrong county, or coverage holes that align
# with neighbourhood boundaries all show up immediately on a map and not at all
# in a match-rate table.
#
#   Rscript destinations/childcare/05_map_texas_hhsc_childcare.R

source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "h3jsr", "ggplot2"))
source("destinations/R/destination_paths.R")

processed_dir <- destination_dir("childcare", "processed")
figures_dir   <- "figures/childcare"

dir.create(figures_dir, showWarnings = FALSE, recursive = TRUE)

metro_boundary_path <- file.path(
  "data", "Karner, Alex - austin_msa_h3_r8_share_2026-10-02", "input",
  "austin_msa_cbsa_12420_boundary.geojson"
)

# ---- Load --------------------------------------------------------------------

childcare_points <- st_read(
  file.path(processed_dir, "childcare_texas_hhsc.gpkg"),
  layer = "childcare_destinations",
  quiet = TRUE
)

h8_childcare <- read_csv(
  file.path(processed_dir, "childcare_texas_hhsc_h8_opportunities.csv"),
  show_col_types = FALSE
)

cat("Points: ", nrow(childcare_points), "\n", sep = "")
cat("H8 cells: ", nrow(h8_childcare), "\n", sep = "")

# ---- Reference geography -----------------------------------------------------

catchment <- st_read(metro_boundary_path, quiet = TRUE) %>%
  st_transform(4326) %>%
  st_make_valid()

# ---- H8 cell geometry --------------------------------------------------------

h8_polygons <- h3jsr::cell_to_polygon(
  h8_childcare$h3_address,
  simple = FALSE
) %>%
  st_as_sf() %>%
  bind_cols(select(h8_childcare, -h3_address)) %>%
  mutate(h3_address = h8_childcare$h3_address) %>%
  st_transform(4326)

map_theme <- theme_void(base_size = 11) +
  theme(
    legend.position  = "right",
    plot.title       = element_text(face = "bold", hjust = 0),
    plot.subtitle    = element_text(colour = "grey30"),
    plot.caption     = element_text(colour = "grey45", hjust = 0, size = 8)
  )

# ---- 1. Points by coordinate provenance --------------------------------------
#
# The single most useful diagnostic. Census-geocoded points sit on street
# centrelines; if a cluster sits somewhere implausible, or if one provenance
# class occupies a distinct part of the map, that is visible here and nowhere
# in the summary statistics.

provenance_map <- ggplot() +
  geom_sf(data = catchment, fill = "grey96", colour = NA) +
  geom_sf(
    data = childcare_points,
    aes(colour = coordinate_source),
    size = 0.7, alpha = 0.75
  ) +
  scale_colour_brewer(palette = "Dark2", name = "Coordinate source") +
  labs(
    title    = "Childcare operations by coordinate provenance",
    subtitle = paste0(nrow(childcare_points), " operations within the catchment"),
    caption  = "Census points are interpolated onto street segments, not parcels."
  ) +
  map_theme

ggsave(
  file.path(figures_dir, "childcare_provenance.png"),
  provenance_map, width = 8, height = 9, dpi = 200
)

# ---- 2. Points by operation type ---------------------------------------------
#
# Home-based operations should be dispersed through residential areas while
# centers cluster along commercial corridors. If both classes trace the same
# lines, geocoding is collapsing them onto shared street segments.

type_map <- ggplot() +
  geom_sf(data = catchment, fill = "grey96", colour = NA) +
  geom_sf(
    data = childcare_points,
    aes(colour = operation_type),
    size = 0.7, alpha = 0.75
  ) +
  scale_colour_brewer(palette = "Set2", name = "Operation type") +
  labs(
    title    = "Childcare operations by type",
    subtitle = "Centers cluster on commercial corridors; homes disperse into residential areas"
  ) +
  map_theme

ggsave(
  file.path(figures_dir, "childcare_operation_type.png"),
  type_map, width = 8, height = 9, dpi = 200
)

# ---- 3. H8 licensed slots ----------------------------------------------------
#
# Square-root scale rather than linear: a handful of large centers otherwise
# flatten the entire distribution into one colour.

slots_map <- ggplot() +
  geom_sf(data = catchment, fill = "grey96", colour = NA) +
  geom_sf(
    data = h8_polygons,
    aes(fill = childcare_slots),
    colour = NA
  ) +
  scale_fill_viridis_c(
    option = "magma", direction = -1, trans = "sqrt",
    name = "Licensed slots"
  ) +
  labs(
    title    = "Licensed childcare slots by H3 cell (resolution 8)",
    subtitle = paste0(
      format(sum(h8_childcare$childcare_slots), big.mark = ","),
      " slots across ", nrow(h8_childcare), " cells"
    ),
    caption  = "Square-root colour scale. Cells with no operations are unshaded."
  ) +
  map_theme

ggsave(
  file.path(figures_dir, "childcare_slots_h8.png"),
  slots_map, width = 8, height = 9, dpi = 200
)

# ---- 4. Subsidized share -----------------------------------------------------
#
# Access conditioned on affordability. Cells with fewer than 20 slots are
# dropped: a share computed on a handful of slots is noise, and mapping it
# invites reading pattern into sampling variation.

subsidy_map_data <- h8_polygons %>%
  filter(childcare_slots >= 20) %>%
  mutate(subsidized_share = childcare_slots_subsidized / childcare_slots)

subsidy_map <- ggplot() +
  geom_sf(data = catchment, fill = "grey96", colour = NA) +
  geom_sf(
    data = subsidy_map_data,
    aes(fill = subsidized_share),
    colour = NA
  ) +
  scale_fill_viridis_c(
    option = "viridis", labels = scales::percent,
    name = "Subsidy-accepting\nshare of slots"
  ) +
  labs(
    title    = "Share of childcare slots accepting subsidies",
    subtitle = "Cells with fewer than 20 slots excluded",
    caption  = "Subsidy acceptance is self-reported to HHSC and may lag actual practice."
  ) +
  map_theme

ggsave(
  file.path(figures_dir, "childcare_subsidized_share.png"),
  subsidy_map, width = 8, height = 9, dpi = 200
)

# ---- Stacking check ----------------------------------------------------------
#
# Address-range interpolation places every match on a street centreline, so
# distinct addresses on the same segment can collapse to identical coordinates.
# Harmless at H8 unless it is widespread, but worth quantifying rather than
# assuming.

duplicate_coordinates <- childcare_points %>%
  st_drop_geometry() %>%
  count(latitude, longitude, name = "operations_at_point") %>%
  filter(operations_at_point > 1) %>%
  arrange(desc(operations_at_point))

cat("\nCoordinate pairs shared by more than one operation: ",
    nrow(duplicate_coordinates), "\n", sep = "")

if (nrow(duplicate_coordinates) > 0) {
  cat("Largest stacks:\n")
  print(head(duplicate_coordinates, 10))
}

cat("\nMaps written to ", figures_dir, "\n", sep = "")
