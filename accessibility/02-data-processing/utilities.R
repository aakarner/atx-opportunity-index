#
# add this function to cut out water from geos
# st - GIS function in sf package
#
cut_polygons_rmapshaper <- function(polygons, cutters) {
  if (!requireNamespace("rmapshaper", quietly = TRUE)) {
    stop("rmapshaper is required; run Rscript 00_setup_packages.R first.")
  }
  
  # 1. Align Coordinate Reference Systems (CRS)
  if (st_crs(polygons) != st_crs(cutters)) {
    cutters <- st_transform(cutters, st_crs(polygons))
  }
  
  # 2. Fix invalid geometries 
  polygons <- st_make_valid(polygons)
  cutters <- st_make_valid(cutters)
  
  # 3. Combine the water polygons into a single mask [st_union is a big bottleneck!]
  cutters_combined <- rmapshaper::ms_dissolve(cutters)
  
  # 4. Use ms_erase to punch out the water
  result <- rmapshaper::ms_erase(target = polygons, erase = cutters_combined)
  
  # 5. Fix invalid geometries that result from the cutting
  result <- st_make_valid(result)
  
  return(result)
}
#
# This function makes a simple choropleth
#
choropleth <- function(polygon,theme,theme_name,map_title,map_subtitle,bin_mins){
ggplot(polygon) +
  geom_sf(aes(fill = theme), linewidth = 0, alpha = 0.9) +
  theme_void() +
  scale_fill_viridis_c(
    trans = "log", breaks = bin_mins,
    name = theme_name,
    guide = guide_legend(
      keyheight = unit(3, units = "mm"),
      keywidth = unit(12, units = "mm"),
      label.position = "bottom",
      title.position = "top",
      nrow = 1
    )
  ) +
  labs(
    title = map_title,
    subtitle = map_subtitle,
    caption = ""
  ) +
  theme(
    text = element_text(color = "#22211d"),
    plot.background = element_rect(fill = "#f5f5f2", color = NA),
    panel.background = element_rect(fill = "#f5f5f2", color = NA),
    legend.background = element_rect(fill = "#f5f5f2", color = NA),
    plot.title = element_text(
      size = 20, hjust = 0.01, color = "#4e4d47",
      margin = margin(
        b = -0.1, t = 0.4, l = 2,
        unit = "cm"
      )
    ),
    plot.subtitle = element_text(
      size = 15, hjust = 0.01,
      color = "#4e4d47",
      margin = margin(
        b = -0.1, t = 0.43, l = 2,
        unit = "cm"
      )
    ),
    plot.caption = element_text(
      size = 10,
      color = "#4e4d47",
      margin = margin(
        b = 0.3, r = -99, t = 0.3,
        unit = "cm"
      )
    ),
    legend.position = c(0.7, 0.09)
  )
}
