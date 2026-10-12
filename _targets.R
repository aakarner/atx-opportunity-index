# Component pipeline: Census sources and tract construction are in the graph.
# Routing and other prepared spatial sources retain their tracked-file boundary.
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
library(targets)
tar_source("R")
tar_option_set(packages = c("sf", "dplyr", "readr", "h3jsr", "ggplot2", "yaml", "digest", "httr2", "jsonlite", "rappdirs"),
               seed = 20261012L, error = "stop")

list(
  tar_target(config_file, "config/pipeline.yml", format = "file"),
  tar_target(config, read_pipeline_config(config_file)),
  tar_target(input_locations, config$inputs),
  tar_target(output_directory, config$output_dir),
  tar_target(spatial_crs, config$geography$equal_area_crs),
  tar_target(census_spec, config$census),
  tar_target(displacement_spec, config$displacement),
  tar_target(job_spec, config$jobs),
  tar_target(school_spec, config$schools),
  tar_target(crash_spec, config$crashes),
  tar_target(crash_buffer_meters, crash_spec$buffer_meters),
  tar_target(site_spec, config$sites),
  tar_target(map_spec, config$maps),

  tar_target(acs_files, acquire_acs_sources(census_spec), format = "file"),
  tar_target(tract_boundary_files, acquire_census_boundary("tracts", census_spec), format = "file"),
  tar_target(city_boundary_files, acquire_census_boundary("city", census_spec), format = "file"),
  tar_target(displacement_file, acquire_displacement_source(displacement_spec), format = "file"),
  tar_target(job_file, input_path(input_locations$jobs, "Run the source workflow in accessibility/README.md."), format = "file"),
  tar_target(school_file, input_path(input_locations$schools, "Run the school preparation commands in docs/schools.md."), format = "file"),
  tar_target(flood_file, input_path(input_locations$flood, "Run scripts/prepare/pull_flood.R."), format = "file"),
  tar_target(crash_file, input_path(input_locations$crashes, "Run scripts/prepare/pull_crashes.R."), format = "file"),
  tar_target(site_file, input_path(input_locations$sites, "Provide site_id, label, longitude, latitude and selection_note."), format = "file"),

  tar_target(acs_context, read_acs_sources(acs_files, census_spec)),
  tar_target(census_tracts, read_census_tracts(tract_boundary_files, census_spec)),
  tar_target(city_boundary, read_census_city(city_boundary_files, census_spec)),
  tar_target(tract_geometry, build_reporting_tracts(census_tracts, city_boundary, spatial_crs)),
  tar_target(tract_acs, join_tract_acs(tract_geometry, acs_context)),
  tar_target(displacement_context, read_displacement_source(displacement_file)),
  tar_target(tract_context, join_tract_displacement(tract_acs, displacement_context)),
  tar_target(job_access, read_job_access(job_file, job_spec)),
  tar_target(school_zones, read_school_zones(school_file, school_spec)),
  tar_target(flood_polygons, read_flood_layer(flood_file)),
  tar_target(crash_points, read_crash_points(crash_file, crash_spec)),
  tar_target(sites, read_sites(site_file)),

  # Geometry depends on origin IDs, not accessibility magnitudes. Changing job
  # counts does not rebuild the tract/H8 intersection.
  tar_target(h8_ids, job_access$h3_id),
  tar_target(h8_geometry, make_job_geography(data.frame(h3_id = h8_ids), spatial_crs)),
  tar_target(h8_access, dplyr::left_join(h8_geometry, job_access, by = "h3_id", relationship = "one-to-one")),
  tar_target(tract_h8_crosswalk, build_tract_h8_crosswalk(tract_geometry, h8_geometry)),
  tar_target(tract_job_access, aggregate_job_access(tract_geometry, h8_access, tract_h8_crosswalk)),
  tar_target(flood_union, make_flood_union(flood_polygons, spatial_crs)),
  tar_target(tract_flood, summarize_flood_tracts(tract_geometry, flood_union)),
  tar_target(tract_crash_windows, prepare_tract_crash_windows(tract_geometry, city_boundary,
    list(buffer_meters = crash_buffer_meters), spatial_crs)),
  tar_target(tract_crashes, summarize_tract_crashes(tract_crash_windows, crash_points, crash_spec)),
  tar_target(tract_inputs, dplyr::left_join(tract_context, tract_crashes, by = "GEOID", relationship = "one-to-one")),
  tar_target(tract_components, assemble_tract_components(tract_inputs, tract_job_access, tract_flood)),

  tar_target(site_access, site_job_access(sites, h8_access, site_spec$max_origin_distance_meters)),
  tar_target(site_profiles, build_site_profiles(sites, tract_geometry, site_access, school_zones,
                                               flood_union, crash_points, crash_spec, city_boundary)),
  tar_target(registry, indicator_registry(job_spec, school_spec, crash_spec, census_spec, displacement_spec)),
  tar_target(manifest, source_manifest(c(configuration = config_file, acs = acs_files,
    tract_boundaries = tract_boundary_files, city_boundaries = city_boundary_files,
    displacement = displacement_file, jobs = job_file, schools = school_file,
    flood = flood_file, crashes = crash_file, sites = site_file))),
  tar_target(qa, pipeline_qa(tract_inputs, tract_job_access, school_zones, sites)),

  tar_target(component_files, write_component_outputs(tract_components, output_directory), format = "file"),
  tar_target(component_maps, write_component_maps(tract_components, school_zones, sites,
                                                  output_directory, map_spec, job_spec, school_spec, crash_spec), format = "file"),
  tar_target(site_profile_file, write_pipeline_csv(site_profiles, output_directory, "site_profiles.csv"), format = "file"),
  tar_target(registry_file, write_pipeline_csv(registry, output_directory, "indicator_registry.csv"), format = "file"),
  tar_target(manifest_file, write_pipeline_csv(manifest, output_directory, "source_manifest.csv"), format = "file"),
  tar_target(qa_file, write_pipeline_csv(qa, output_directory, "qa_summary.csv"), format = "file"),
  tar_target(runtime_file, write_runtime_info(output_directory), format = "file"),
  tar_target(review_report, {
    component_files; site_profile_file; registry_file; manifest_file; qa_file; runtime_file
    write_review_report(site_profiles, registry, manifest, qa, component_maps, output_directory,
                        job_spec, school_spec, crash_spec)
  }, format = "file")
)
