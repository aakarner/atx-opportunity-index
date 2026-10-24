# Descriptive statistics and retention screening for City of Austin parkland.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf"))
source("destinations/R/destination_paths.R")

out <- destination_comparison_dir("parks_austin_open_data_descriptive")
gpkg <- file.path(destination_dir("parks", "processed"), "parks_austin_open_data.gpkg")
sf_use_s2(FALSE)

source_rows <- st_read(gpkg, layer = "parks_polygons", quiet = TRUE) |>
  st_make_valid() |>
  mutate(
    analysis_acres = coalesce(suppressWarnings(as.numeric(acres)),
                              suppressWarnings(as.numeric(asset_size))),
    asset_key = coalesce(na_if(trimws(asset_mgmt_id), ""), paste0("objectid_", objectid))
  )

# The source has one asset represented by two polygon rows. Statistics use one
# record per asset so that the duplicate geometry does not inflate counts.
attrs <- setdiff(names(st_drop_geometry(source_rows)), "asset_key")
assets <- source_rows |>
  group_by(asset_key) |>
  summarise(
    across(all_of(attrs), ~ first(.x)),
    source_polygon_rows = n(),
    .groups = "drop"
  )

norm_text <- function(x) coalesce(na_if(trimws(as.character(x)), ""), "Missing")
developed_levels <- paste0("Level ", 1:4, " Developed")

assets <- assets |>
  mutate(
    park_type = norm_text(park_type),
    development_status = norm_text(development_status),
    asset_status = norm_text(asset_status),
    owner_type = norm_text(owner_type),
    owner_name = norm_text(owner_name),
    managing_type = norm_text(managing_type),
    managing_name = norm_text(managing_name),
    restrictions = norm_text(restrictions),
    development_group = case_when(
      development_status %in% developed_levels ~ "Developed (Level 1-4)",
      development_status == "Undeveloped" ~ "Undeveloped",
      TRUE ~ "Missing or other"
    ),
    screening_group = case_when(
      asset_status != "Open" ~ "exclude/hold - closed",
      park_type %in% c("Cemetery", "Golf Course", "Planting Strips/Triangles") ~
        "exclude from general park measure",
      park_type == "School" ~ "review - verify public access",
      park_type == "Nature Preserve" ~ "policy decision - nature preserve",
      park_type == "Special" ~ "review - special purpose",
      development_status == "Undeveloped" ~ "review - undeveloped/access uncertain",
      park_type %in% c("Metropolitan", "District", "Neighborhood", "Pocket",
                       "Pocket Park", "Button", "Button Park", "Bark Park", "Greenbelt") ~
        "retain candidate - general public park",
      TRUE ~ "review - other"
    ),
    screening_reason = case_when(
      asset_status != "Open" ~ "City asset status is not Open.",
      park_type == "Cemetery" ~ "Specialized land use; exclude from a general recreational-park opportunity measure unless the team decides otherwise.",
      park_type == "Golf Course" ~ "Specialized and potentially fee/access-limited facility; analyze separately if needed.",
      park_type == "Planting Strips/Triangles" ~ "Small transportation/landscape open space may not provide meaningful recreational access.",
      park_type == "School" ~ "Public recreational access outside school operations is not established by park type alone.",
      park_type == "Nature Preserve" ~ "Public value is clear, but conservation purpose and access restrictions differ from general parks.",
      park_type == "Special" ~ "Broad special-purpose category requires facility/function review.",
      development_status == "Undeveloped" ~ "Undeveloped parkland can have limited access; verify an entrance, trail, or other usable public access.",
      TRUE ~ "Open, developed City park type suitable as an initial general-park retain candidate."
    )
  )

summarise_group <- function(data, field) {
  st_drop_geometry(data) |>
    group_by(across(all_of(field))) |>
    summarise(
      assets = n(),
      open_assets = sum(asset_status == "Open"),
      developed_assets = sum(development_group == "Developed (Level 1-4)"),
      undeveloped_assets = sum(development_group == "Undeveloped"),
      total_acres = sum(analysis_acres, na.rm = TRUE),
      median_acres = median(analysis_acres, na.rm = TRUE),
      missing_acres = sum(is.na(analysis_acres)),
      .groups = "drop"
    ) |>
    mutate(share_percent = 100 * assets / nrow(data)) |>
    arrange(desc(assets))
}

park_type_summary <- summarise_group(assets, "park_type")
development_summary <- summarise_group(assets, "development_status")
owner_type_summary <- summarise_group(assets, "owner_type")
manager_type_summary <- summarise_group(assets, "managing_type")
restrictions_summary <- summarise_group(assets, "restrictions")
screening_summary <- summarise_group(assets, "screening_group")
n_assets <- nrow(assets)

owner_manager_summary <- assets |>
  st_drop_geometry() |>
  count(owner_name, managing_name, owner_type, managing_type, name = "assets") |>
  mutate(share_percent = 100 * assets / n_assets) |>
  arrange(desc(assets), owner_name, managing_name)

type_development_crosswalk <- assets |>
  st_drop_geometry() |>
  count(park_type, development_status, asset_status, name = "assets") |>
  arrange(park_type, development_status, asset_status)

outputs <- list(
  park_type_summary = park_type_summary,
  development_status_summary = development_summary,
  owner_type_summary = owner_type_summary,
  manager_type_summary = manager_type_summary,
  owner_manager_summary = owner_manager_summary,
  restrictions_summary = restrictions_summary,
  park_type_development_crosswalk = type_development_crosswalk,
  retention_screening_summary = screening_summary
)
iwalk(outputs, ~ write_csv(.x, file.path(out, paste0(.y, ".csv")), na = ""))

review_gpkg <- file.path(out, "austin_open_data_parks_screening.gpkg")
if (file.exists(review_gpkg)) file.remove(review_gpkg)
st_write(assets, review_gpkg, layer = "park_assets_screening", quiet = TRUE)

assessment <- c(
  "# City of Austin parkland descriptive statistics", "",
  paste0("The City layer contains ", nrow(source_rows), " polygon records representing ",
         nrow(assets), " distinct park assets. Statistics use distinct assets; the screening layer records source_polygon_rows so the duplicate remains traceable."), "",
  "## Interpretation", "",
  "Austin groups Metropolitan, District, Neighborhood, and Pocket parks as all-purpose parks. Greenbelts are retained as initial candidates because they commonly support passive recreation and trails, subject to usable public access. Button, Button Park, Bark Park, and Pocket Park are also initial candidates when open and developed.", "",
  "Nature Preserves should be a separate policy decision because their conservation purpose and access rules differ from general parks. School sites require confirmation of public access. Special parks require facility review because the label does not identify the specific function. Undeveloped land should be reviewed rather than automatically removed because Austin describes it as potentially having minimal access before Level I development.", "",
  "Cemeteries, golf courses, and planting strips/triangles are flagged for exclusion from the general park measure. Closed assets are held out. No source asset is deleted.", "",
  "The level_of_use field is not used for screening because the local layer does not provide a clear public-facing definition and nearly all records are coded Low.", "",
  "## Suggested review fields", "",
  "Use screening_group as the first pass. For review cases, inspect park_type, development_status, asset_status, restrictions, development_comment, location_name, managing_name, analysis_acres, and geometry. analysis_acres uses the City's asset_size field because acres is empty in this extract. Record the team's final decision in a later manual-review field rather than overwriting the City source fields."
)
writeLines(assessment, file.path(out, "descriptive_assessment.md"))

print(park_type_summary, n = Inf)
print(development_summary, n = Inf)
print(screening_summary, n = Inf)
