# Austin Opportunity Index Analysis
# This script pulls census data for Austin, TX, performs k-means clustering,
# and creates visualizations using ggplot and tigris

# Install missing packages and load this script's dependencies.
source("00_setup_packages.R")
setup_project_packages(c(
  "tidycensus", "tidyverse", "tigris", "sf", "h3jsr", "scales", "cluster"
))

# Set options
options(tigris_use_cache = TRUE)

acs_year <- 2024
city_boundary_year <- 2024
analysis_counties <- c("Travis", "Williamson", "Hays")
transit_threshold_minutes <- 45
accessibility_file <- "accessibility/output/h8_job_accessibility.csv"
tract_functional_role_file <- paste0(
  "accessibility/data/processed/lehd/",
  "austin_tract_functional_role_2023.csv"
)
environmental_hazard_file <- paste0(
  "data/processed/environmental_hazards/",
  "epa_frs_austin_hazard_candidate_facilities.gpkg"
)
crash_injury_file <- paste0(
  "data/processed/crash_injuries/",
  "austin_open_data_ksi_crashes.gpkg"
)
development_pressure_file <- paste0(
  "data/processed/development_pressure/",
  "austin_development_pressure_permits_2020_2024.gpkg"
)
land_use_file <- paste0(
  "data/processed/land_use/",
  "austin_land_use_by_tract.csv"
)
displacement_risk_file <- paste0(
  "data/processed/displacement_risk/",
  "austin_displacement_risk_by_tract.csv"
)
environmental_hazard_qaqc_file <- paste0(
  "data/qaqc/environmental_hazards/epa_frs_qaqc_summary.csv"
)
crash_injury_qaqc_file <- paste0(
  "data/qaqc/crash_injuries/austin_open_data_qaqc_summary.csv"
)
development_pressure_qaqc_file <- paste0(
  "data/qaqc/development_pressure/development_pressure_qaqc_summary.csv"
)
accessibility_equal_area_crs <- 5070
exposure_buffer_miles <- 1
meters_per_mile <- 1609.344
square_meters_per_square_mile <- 2589988.110336
overlay_tail_probability <- 0.25
selected_cluster_count <- 5
cluster_random_seed <- 123
cluster_nstart <- 25
experimental_gap_bootstraps <- 100
experimental_stability_bootstraps <- 100
experimental_stability_sample_share <- 0.80
demographic_min_universe <- 100
demographic_moe_threshold <- 0.10
demographic_moe_strict_threshold <- 0.05
demographic_moe_permissive_threshold <- 0.15
resident_context_weight_targets <- c(0.20, 0.25, 0.33)
output_dir <- "output"

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Define ACS inputs and their eventual cluster or overlay roles.
# Using American Community Survey 5-year estimates.
census_vars <- c(
  # Social and economic overlays
  median_income = "B19013_001",      # Median household income
  poverty_total = "B17001_001",      # Poverty universe
  poverty_below = "B17001_002",      # Population below poverty level
  labor_force = "B23025_002",        # Labor force
  employed = "B23025_004",           # Employed population

  # Resident-needs experimental inputs: age and disability are treated as
  # service-fit characteristics, not as directional measures of opportunity.
  age_population_total = "B01001_001",
  age_male_65_66 = "B01001_020",
  age_male_67_69 = "B01001_021",
  age_male_70_74 = "B01001_022",
  age_male_75_79 = "B01001_023",
  age_male_80_84 = "B01001_024",
  age_male_85_plus = "B01001_025",
  age_female_65_66 = "B01001_044",
  age_female_67_69 = "B01001_045",
  age_female_70_74 = "B01001_046",
  age_female_75_79 = "B01001_047",
  age_female_80_84 = "B01001_048",
  age_female_85_plus = "B01001_049",

  disability_population_total = "B18101_001",
  disability_male_under5_total = "B18101_003",
  disability_male_under5_with = "B18101_004",
  disability_male_5_17_total = "B18101_006",
  disability_male_5_17_with = "B18101_007",
  disability_male_18_34_total = "B18101_009",
  disability_male_18_34_with = "B18101_010",
  disability_male_35_64_total = "B18101_012",
  disability_male_35_64_with = "B18101_013",
  disability_male_65_74_total = "B18101_015",
  disability_male_65_74_with = "B18101_016",
  disability_male_75plus_total = "B18101_018",
  disability_male_75plus_with = "B18101_019",
  disability_female_under5_total = "B18101_022",
  disability_female_under5_with = "B18101_023",
  disability_female_5_17_total = "B18101_025",
  disability_female_5_17_with = "B18101_026",
  disability_female_18_34_total = "B18101_028",
  disability_female_18_34_with = "B18101_029",
  disability_female_35_64_total = "B18101_031",
  disability_female_35_64_with = "B18101_032",
  disability_female_65_74_total = "B18101_034",
  disability_female_65_74_with = "B18101_035",
  disability_female_75plus_total = "B18101_037",
  disability_female_75plus_with = "B18101_038",

  # Race and ethnicity are excluded from clustering and retained solely for a
  # post-clustering equity audit.
  race_ethnicity_total = "B03002_001",
  nh_white_alone = "B03002_003",
  nh_black_alone = "B03002_004",
  nh_aian_alone = "B03002_005",
  nh_asian_alone = "B03002_006",
  nh_nhpi_alone = "B03002_007",
  nh_other_race_alone = "B03002_008",
  nh_two_or_more_races = "B03002_009",
  hispanic_latino_any_race = "B03002_012",

  # Educational-attainment overlay
  education_total = "B15003_001",    # Population 25 years and over
  bachelors = "B15003_022",          # Bachelor's degree
  masters = "B15003_023",            # Master's degree
  professional = "B15003_024",       # Professional school degree
  doctorate = "B15003_025",          # Doctorate degree

  # Housing-market cluster inputs
  median_home_value = "B25077_001",   # Median home value
  median_rent = "B25064_001",         # Median gross rent
  housing_units_total = "B25001_001", # Existing housing-unit denominator
  renter_occupied_households = "B25003_003", # Future eviction-rate denominator

  # Built-form experimental inputs: broad structure and construction-era
  # categories are used to limit sampling noise and compositional redundancy.
  structure_units_total = "B25024_001",
  detached_units = "B25024_002",
  attached_units = "B25024_003",
  two_unit_units = "B25024_004",
  three_four_unit_units = "B25024_005",
  five_nine_unit_units = "B25024_006",
  ten_nineteen_unit_units = "B25024_007",
  twenty_fortynine_unit_units = "B25024_008",
  fifty_plus_unit_units = "B25024_009",
  mobile_other_units = "B25024_010",
  nonstandard_other_units = "B25024_011",
  structure_year_total = "B25034_001",
  built_2020_or_later = "B25034_002",
  built_2010_2019 = "B25034_003",

  # Family and household indicators
  households_total = "B11005_001",     # Total households
  households_with_children = "B11005_002", # Households with people under 18
  avg_household_size = "B25010_001",   # Average household size

  # Transportation-context overlay
  no_vehicle_households = "B08201_002" # Households with no vehicle available
)

# Pull census data for the three counties that contain the City of Austin.
# This tract-level proof of concept now uses the most recent ACS 5-year tract
# data supported by tidycensus so the demonstration reflects 2024 ACS tract
# geography, based on 2020 Census tract definitions, while the final H8
# integration is still being developed.
cat(
  "Pulling ACS data for ",
  str_c(analysis_counties, collapse = ", "),
  " counties, TX...\n",
  sep = ""
)

census_data <- map(
  analysis_counties,
  ~ get_acs(
    geography = "tract",
    variables = census_vars,
    state = "TX",
    county = .x,
    year = acs_year,
    survey = "acs5",
    geometry = TRUE,
    output = "wide"
  )
) %>%
  bind_rows()

# Fix the age-standardization weights to the published 2024 Austin place-level
# civilian noninstitutionalized population. This avoids allowing the selected
# tract sample or a later boundary change to redefine the disability measure.
disability_reference_vars <- census_vars[
  str_detect(names(census_vars), "^disability_")
]

austin_disability_reference_raw <- get_acs(
  geography = "place",
  variables = disability_reference_vars,
  state = "TX",
  year = acs_year,
  survey = "acs5",
  geometry = FALSE,
  output = "wide"
) %>%
  filter(str_detect(NAME, "^Austin city"))

if (nrow(austin_disability_reference_raw) != 1) {
  stop(
    "Expected one Austin city row for disability standardization; found ",
    nrow(austin_disability_reference_raw), "."
  )
}

disability_standardization_reference <- tibble(
  age_band = c("under_5", "age_5_17", "age_18_34", "age_35_64", "age_65_74", "age_75_plus"),
  reference_population = c(
    austin_disability_reference_raw$disability_male_under5_totalE +
      austin_disability_reference_raw$disability_female_under5_totalE,
    austin_disability_reference_raw$disability_male_5_17_totalE +
      austin_disability_reference_raw$disability_female_5_17_totalE,
    austin_disability_reference_raw$disability_male_18_34_totalE +
      austin_disability_reference_raw$disability_female_18_34_totalE,
    austin_disability_reference_raw$disability_male_35_64_totalE +
      austin_disability_reference_raw$disability_female_35_64_totalE,
    austin_disability_reference_raw$disability_male_65_74_totalE +
      austin_disability_reference_raw$disability_female_65_74_totalE,
    austin_disability_reference_raw$disability_male_75plus_totalE +
      austin_disability_reference_raw$disability_female_75plus_totalE
  ),
  reference_with_disability = c(
    austin_disability_reference_raw$disability_male_under5_withE +
      austin_disability_reference_raw$disability_female_under5_withE,
    austin_disability_reference_raw$disability_male_5_17_withE +
      austin_disability_reference_raw$disability_female_5_17_withE,
    austin_disability_reference_raw$disability_male_18_34_withE +
      austin_disability_reference_raw$disability_female_18_34_withE,
    austin_disability_reference_raw$disability_male_35_64_withE +
      austin_disability_reference_raw$disability_female_35_64_withE,
    austin_disability_reference_raw$disability_male_65_74_withE +
      austin_disability_reference_raw$disability_female_65_74_withE,
    austin_disability_reference_raw$disability_male_75plus_withE +
      austin_disability_reference_raw$disability_female_75plus_withE
  )
) %>%
  mutate(
    standard_weight = reference_population / sum(reference_population),
    reference_disability_rate = reference_with_disability / reference_population
  )

if (
  any(disability_standardization_reference$reference_population <= 0) ||
    any(!is.finite(disability_standardization_reference$standard_weight)) ||
    abs(sum(disability_standardization_reference$standard_weight) - 1) > 1e-10
) {
  stop("Invalid Austin age-standardization weights for disability prevalence.")
}

# LODES functional-role counts use whole 2020-vintage tracts. Retain TIGER
# land area before City clipping so activity intensity is not inflated for
# small municipal-boundary fragments.
tract_land_area <- map_dfr(
  analysis_counties,
  ~tigris::tracts(
    state = "TX",
    county = .x,
    year = city_boundary_year,
    class = "sf",
    progress_bar = FALSE
  ) %>%
    st_drop_geometry() %>%
    transmute(
      GEOID,
      full_tract_land_sqmi = ALAND / square_meters_per_square_mile
    )
)

census_data <- census_data %>%
  left_join(tract_land_area, by = "GEOID")

# Use a recent municipal boundary so the analysis covers the full City of
# Austin, including portions in Williamson and Hays counties.
cat("Pulling City of Austin boundary...\n")

austin_boundary <- places(
  state = "TX",
  year = city_boundary_year
) %>%
  filter(NAME == "Austin") %>%
  st_transform(4326) %>%
  st_make_valid()

if (nrow(austin_boundary) != 1) {
  stop("Expected exactly one City of Austin boundary; found ", nrow(austin_boundary), ".")
}

cat("Reading H8 job accessibility results...\n")

if (!file.exists(accessibility_file)) {
  stop(
    "Missing ", accessibility_file,
    paste0(
      ". Run the accessibility pipeline through accessibility/03-analysis/",
      "02_weighted_job_accessibility.R first."
    )
  )
}

if (!file.exists(tract_functional_role_file)) {
  stop(
    "Missing ", tract_functional_role_file,
    paste0(
      ". Run accessibility/02-data-processing/01_pull_lodes_wac_jobs.R first."
    )
  )
}

h8_access <- read_csv(accessibility_file, show_col_types = FALSE)
tract_functional_role <- read_csv(
  tract_functional_role_file,
  col_types = cols(GEOID = col_character()),
  show_col_types = FALSE
)

required_access_columns <- c(
  "h3_id", "access_total_jobs", "workers_all",
  "network_snapshot", "gtfs_snapshot", "jobs_year"
)
missing_access_columns <- setdiff(required_access_columns, names(h8_access))

if (length(missing_access_columns) > 0) {
  stop(
    "The H8 accessibility output is missing: ",
    str_c(missing_access_columns, collapse = ", "),
    ". Rerun accessibility/03-analysis/02_weighted_job_accessibility.R."
  )
}

required_functional_role_columns <- c(
  "GEOID", "total_jobs", "workers_all",
  "jobs_resident_worker_balance", "local_jobs_and_workers"
)
missing_functional_role_columns <- setdiff(
  required_functional_role_columns,
  names(tract_functional_role)
)

if (length(missing_functional_role_columns) > 0) {
  stop(
    "The tract functional-role file is missing: ",
    str_c(missing_functional_role_columns, collapse = ", ")
  )
}

if (
  anyDuplicated(h8_access$h3_id) > 0 ||
    anyDuplicated(tract_functional_role$GEOID) > 0
) {
  stop("H8 accessibility and tract functional-role identifiers must be unique.")
}

if (any(
  tract_functional_role$total_jobs < 0 |
    tract_functional_role$workers_all < 0
)) {
  stop("Tract jobs and resident-worker counts must be nonnegative.")
}

access_jobs_year <- unique(h8_access$jobs_year)
network_snapshot <- unique(h8_access$network_snapshot)
gtfs_snapshot <- unique(h8_access$gtfs_snapshot)

if (
  length(access_jobs_year) != 1 ||
  length(network_snapshot) != 1 ||
  length(gtfs_snapshot) != 1
) {
  stop("Expected one jobs year and one network/GTFS snapshot in the H8 output.")
}

access_snapshot_label <- if_else(
  network_snapshot == gtfs_snapshot,
  paste0("GTFS/OSM snapshot ", network_snapshot),
  paste0(
    "GTFS snapshot ", gtfs_snapshot,
    "; OSM snapshot ", network_snapshot
  )
)

# Read place-based exposure inputs. These are intentionally separate from the
# ACS overlays: EPA facilities and KSI crashes describe conditions of place,
# while income, poverty, education, employment, and vehicle availability are
# retained for post-clustering interpretation and project screening.
required_place_files <- c(
  environmental_hazard_file,
  crash_injury_file,
  development_pressure_file,
  land_use_file,
  displacement_risk_file
)
missing_place_files <- required_place_files[!file.exists(required_place_files)]

if (length(missing_place_files) > 0) {
  stop(
    "Missing place/exposure inputs: ",
    str_c(missing_place_files, collapse = ", "),
    ". Run numbered input steps 10 through 14 first."
  )
}

cat("Reading place, exposure, and development inputs...\n")

environmental_hazards <- st_read(environmental_hazard_file, quiet = TRUE) %>%
  st_make_valid()

ksi_crashes <- st_read(crash_injury_file, quiet = TRUE) %>%
  st_make_valid()

development_permits <- st_read(development_pressure_file, quiet = TRUE) %>%
  st_make_valid()

land_use_by_tract <- read_csv(
  land_use_file,
  col_types = cols(GEOID = col_character()),
  show_col_types = FALSE
)

displacement_risk_by_tract <- read_csv(
  displacement_risk_file,
  col_types = cols(GEOID = col_character()),
  show_col_types = FALSE
)

required_hazard_columns <- c(
  "registry_id", "has_brownfields", "has_tri", "has_rcra_lqg_tsd",
  "has_rmp", "has_superfund_sems", "has_npdes_major", "has_air_major"
)
required_crash_columns <- c(
  "crash_id", "crash_year", "fatal_crash",
  "vulnerable_road_user_ksi_crash"
)
required_development_columns <- c(
  "permit_id", "permit_year", "new_housing_permit",
  "residential_demolition_permit", "new_housing_units",
  "residential_units_demolished", "coordinate_source"
)
required_land_use_columns <- c(
  "GEOID", "land_use_category_detailed", "land_use_category",
  "land_use_category_cluster", "composition_coverage_ratio",
  "adequate_composition_coverage", "normalized_land_use_diversity",
  "share_residential", "share_mixed_use", "share_commercial_office",
  "share_industrial_logistics", "share_institutional_civic",
  "share_open_space", "share_transportation_utilities",
  "share_undeveloped_agricultural"
)
required_displacement_columns <- c(
  "GEOID", "displacement_risk_category", "displacement_risk_source",
  "vulnerable_population", "demographic_change",
  "housing_market_category", "gentrification_typology"
)

missing_hazard_columns <- setdiff(required_hazard_columns, names(environmental_hazards))
missing_crash_columns <- setdiff(required_crash_columns, names(ksi_crashes))
missing_development_columns <- setdiff(
  required_development_columns,
  names(development_permits)
)
missing_land_use_columns <- setdiff(
  required_land_use_columns,
  names(land_use_by_tract)
)
missing_displacement_columns <- setdiff(
  required_displacement_columns,
  names(displacement_risk_by_tract)
)

if (length(missing_hazard_columns) > 0) {
  stop(
    "Environmental-hazard data are missing: ",
    str_c(missing_hazard_columns, collapse = ", ")
  )
}

if (length(missing_crash_columns) > 0) {
  stop(
    "Crash-injury data are missing: ",
    str_c(missing_crash_columns, collapse = ", ")
  )
}

if (length(missing_development_columns) > 0) {
  stop(
    "Development-pressure data are missing: ",
    str_c(missing_development_columns, collapse = ", ")
  )
}

if (length(missing_land_use_columns) > 0) {
  stop(
    "Land-use tract data are missing: ",
    str_c(missing_land_use_columns, collapse = ", ")
  )
}

if (length(missing_displacement_columns) > 0) {
  stop(
    "Displacement-risk tract data are missing: ",
    str_c(missing_displacement_columns, collapse = ", ")
  )
}

if (
  anyDuplicated(land_use_by_tract$GEOID) > 0 ||
    anyDuplicated(displacement_risk_by_tract$GEOID) > 0
) {
  stop("Land-use and displacement-risk tract identifiers must be unique.")
}

crash_analysis_years <- sort(unique(ksi_crashes$crash_year))
crash_year_count <- length(crash_analysis_years)

if (crash_year_count < 1) {
  stop("Crash-injury data do not contain a valid analysis year.")
}

hazard_download_date <- NA_character_
if (file.exists(environmental_hazard_qaqc_file)) {
  hazard_download_date <- read_csv(
    environmental_hazard_qaqc_file,
    show_col_types = FALSE
  ) %>%
    filter(metric == "download_date") %>%
    pull(value) %>%
    first(default = NA_character_)
}

crash_retrieved_at_utc <- NA_character_
if (file.exists(crash_injury_qaqc_file)) {
  crash_retrieved_at_utc <- read_csv(
    crash_injury_qaqc_file,
    show_col_types = FALSE
  ) %>%
    filter(metric == "retrieved_at_utc") %>%
    pull(value) %>%
    first(default = NA_character_)
}

crash_source_year_label <- str_c(range(crash_analysis_years), collapse = "–")

development_analysis_years <- sort(unique(development_permits$permit_year))
development_year_count <- length(development_analysis_years)

if (development_year_count < 1) {
  stop("Development permits do not contain a valid analysis year.")
}

read_qaqc_value <- function(path, metric_name) {
  if (!file.exists(path)) {
    return(NA_character_)
  }

  read_csv(path, show_col_types = FALSE) %>%
    filter(metric == metric_name) %>%
    pull(value) %>%
    first(default = NA_character_)
}

development_retrieved_at_utc <- read_qaqc_value(
  development_pressure_qaqc_file,
  "retrieved_at_utc"
)
development_coordinate_coverage <- suppressWarnings(
  as.numeric(read_qaqc_value(
    development_pressure_qaqc_file,
    "classified_records_with_valid_coordinates"
  )) /
    (as.numeric(read_qaqc_value(
      development_pressure_qaqc_file,
      "classified_new_housing_permits"
    )) + as.numeric(read_qaqc_value(
      development_pressure_qaqc_file,
      "classified_residential_demolition_permits"
    )))
)

safe_moe_prop <- function(numerator, denominator, numerator_moe, denominator_moe) {
  result <- suppressWarnings(tidycensus::moe_prop(
    numerator,
    denominator,
    numerator_moe,
    denominator_moe
  ))
  result[is.na(denominator) | denominator <= 0] <- NA_real_
  result
}

# Clean column names and prepare data
cat("Cleaning and preparing data...\n")

census_data_clean <- census_data %>%
  rowwise() %>%
  mutate(
    low_intensity_structure_units = sum(
      c_across(c(
        detached_unitsE, mobile_other_unitsE,
        nonstandard_other_unitsE
      )),
      na.rm = FALSE
    ),
    attached_small_structure_units = sum(
      c_across(c(
        attached_unitsE, two_unit_unitsE, three_four_unit_unitsE,
        five_nine_unit_unitsE
      )),
      na.rm = FALSE
    ),
    medium_large_structure_units = sum(
      c_across(c(
        ten_nineteen_unit_unitsE, twenty_fortynine_unit_unitsE,
        fifty_plus_unit_unitsE
      )),
      na.rm = FALSE
    ),
    recent_2010_plus_units = sum(
      c_across(c(built_2020_or_laterE, built_2010_2019E)),
      na.rm = FALSE
    ),
    structure_units_total_moe = structure_units_totalM,
    structure_year_total_moe = structure_year_totalM,
    low_intensity_structure_units_moe = tidycensus::moe_sum(
      moe = c(
        detached_unitsM, mobile_other_unitsM,
        nonstandard_other_unitsM
      ),
      estimate = c(
        detached_unitsE, mobile_other_unitsE,
        nonstandard_other_unitsE
      )
    ),
    attached_small_structure_units_moe = tidycensus::moe_sum(
      moe = c(
        attached_unitsM, two_unit_unitsM, three_four_unit_unitsM,
        five_nine_unit_unitsM
      ),
      estimate = c(
        attached_unitsE, two_unit_unitsE, three_four_unit_unitsE,
        five_nine_unit_unitsE
      )
    ),
    medium_large_structure_units_moe = tidycensus::moe_sum(
      moe = c(
        ten_nineteen_unit_unitsM, twenty_fortynine_unit_unitsM,
        fifty_plus_unit_unitsM
      ),
      estimate = c(
        ten_nineteen_unit_unitsE, twenty_fortynine_unit_unitsE,
        fifty_plus_unit_unitsE
      )
    ),
    recent_2010_plus_units_moe = tidycensus::moe_sum(
      moe = c(built_2020_or_laterM, built_2010_2019M),
      estimate = c(built_2020_or_laterE, built_2010_2019E)
    ),
    poverty_total_moe = poverty_totalM,
    poverty_below_moe = poverty_belowM,
    age_population_total_moe = age_population_totalM,
    disability_population_total_moe = disability_population_totalM,
    older_adult_population = sum(
      c_across(c(
        age_male_65_66E, age_male_67_69E, age_male_70_74E,
        age_male_75_79E, age_male_80_84E, age_male_85_plusE,
        age_female_65_66E, age_female_67_69E, age_female_70_74E,
        age_female_75_79E, age_female_80_84E, age_female_85_plusE
      )),
      na.rm = FALSE
    ),
    older_adult_population_moe = tidycensus::moe_sum(
      moe = c(
        age_male_65_66M, age_male_67_69M, age_male_70_74M,
        age_male_75_79M, age_male_80_84M, age_male_85_plusM,
        age_female_65_66M, age_female_67_69M, age_female_70_74M,
        age_female_75_79M, age_female_80_84M, age_female_85_plusM
      ),
      estimate = c(
        age_male_65_66E, age_male_67_69E, age_male_70_74E,
        age_male_75_79E, age_male_80_84E, age_male_85_plusE,
        age_female_65_66E, age_female_67_69E, age_female_70_74E,
        age_female_75_79E, age_female_80_84E, age_female_85_plusE
      )
    ),
    disability_under5_total =
      disability_male_under5_totalE + disability_female_under5_totalE,
    disability_under5_with =
      disability_male_under5_withE + disability_female_under5_withE,
    disability_under5_total_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_under5_totalM,
        disability_female_under5_totalM
      ),
      estimate = c(
        disability_male_under5_totalE,
        disability_female_under5_totalE
      )
    ),
    disability_under5_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_under5_withM,
        disability_female_under5_withM
      ),
      estimate = c(
        disability_male_under5_withE,
        disability_female_under5_withE
      )
    ),
    disability_5_17_total =
      disability_male_5_17_totalE + disability_female_5_17_totalE,
    disability_5_17_with =
      disability_male_5_17_withE + disability_female_5_17_withE,
    disability_5_17_total_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_5_17_totalM,
        disability_female_5_17_totalM
      ),
      estimate = c(
        disability_male_5_17_totalE,
        disability_female_5_17_totalE
      )
    ),
    disability_5_17_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_5_17_withM,
        disability_female_5_17_withM
      ),
      estimate = c(
        disability_male_5_17_withE,
        disability_female_5_17_withE
      )
    ),
    disability_18_34_total =
      disability_male_18_34_totalE + disability_female_18_34_totalE,
    disability_18_34_with =
      disability_male_18_34_withE + disability_female_18_34_withE,
    disability_18_34_total_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_18_34_totalM,
        disability_female_18_34_totalM
      ),
      estimate = c(
        disability_male_18_34_totalE,
        disability_female_18_34_totalE
      )
    ),
    disability_18_34_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_18_34_withM,
        disability_female_18_34_withM
      ),
      estimate = c(
        disability_male_18_34_withE,
        disability_female_18_34_withE
      )
    ),
    disability_35_64_total =
      disability_male_35_64_totalE + disability_female_35_64_totalE,
    disability_35_64_with =
      disability_male_35_64_withE + disability_female_35_64_withE,
    disability_35_64_total_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_35_64_totalM,
        disability_female_35_64_totalM
      ),
      estimate = c(
        disability_male_35_64_totalE,
        disability_female_35_64_totalE
      )
    ),
    disability_35_64_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_35_64_withM,
        disability_female_35_64_withM
      ),
      estimate = c(
        disability_male_35_64_withE,
        disability_female_35_64_withE
      )
    ),
    disability_65_74_total =
      disability_male_65_74_totalE + disability_female_65_74_totalE,
    disability_65_74_with =
      disability_male_65_74_withE + disability_female_65_74_withE,
    disability_65_74_total_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_65_74_totalM,
        disability_female_65_74_totalM
      ),
      estimate = c(
        disability_male_65_74_totalE,
        disability_female_65_74_totalE
      )
    ),
    disability_65_74_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_65_74_withM,
        disability_female_65_74_withM
      ),
      estimate = c(
        disability_male_65_74_withE,
        disability_female_65_74_withE
      )
    ),
    disability_75plus_total =
      disability_male_75plus_totalE + disability_female_75plus_totalE,
    disability_75plus_with =
      disability_male_75plus_withE + disability_female_75plus_withE,
    disability_75plus_total_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_75plus_totalM,
        disability_female_75plus_totalM
      ),
      estimate = c(
        disability_male_75plus_totalE,
        disability_female_75plus_totalE
      )
    ),
    disability_75plus_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_75plus_withM,
        disability_female_75plus_withM
      ),
      estimate = c(
        disability_male_75plus_withE,
        disability_female_75plus_withE
      )
    ),
    disability_population_with = sum(
      c_across(c(
        disability_male_under5_withE,
        disability_male_5_17_withE,
        disability_male_18_34_withE,
        disability_male_35_64_withE,
        disability_male_65_74_withE,
        disability_male_75plus_withE,
        disability_female_under5_withE,
        disability_female_5_17_withE,
        disability_female_18_34_withE,
        disability_female_35_64_withE,
        disability_female_65_74_withE,
        disability_female_75plus_withE
      )),
      na.rm = FALSE
    ),
    disability_population_with_moe = tidycensus::moe_sum(
      moe = c(
        disability_male_under5_withM,
        disability_male_5_17_withM,
        disability_male_18_34_withM,
        disability_male_35_64_withM,
        disability_male_65_74_withM,
        disability_male_75plus_withM,
        disability_female_under5_withM,
        disability_female_5_17_withM,
        disability_female_18_34_withM,
        disability_female_35_64_withM,
        disability_female_65_74_withM,
        disability_female_75plus_withM
      ),
      estimate = c(
        disability_male_under5_withE,
        disability_male_5_17_withE,
        disability_male_18_34_withE,
        disability_male_35_64_withE,
        disability_male_65_74_withE,
        disability_male_75plus_withE,
        disability_female_under5_withE,
        disability_female_5_17_withE,
        disability_female_18_34_withE,
        disability_female_35_64_withE,
        disability_female_65_74_withE,
        disability_female_75plus_withE
      )
    ),
    race_ethnicity_total_moe = race_ethnicity_totalM,
    nh_white_alone_moe = nh_white_aloneM,
    nh_black_alone_moe = nh_black_aloneM,
    nh_aian_alone_moe = nh_aian_aloneM,
    nh_asian_alone_moe = nh_asian_aloneM,
    nh_nhpi_alone_moe = nh_nhpi_aloneM,
    nh_other_race_alone_moe = nh_other_race_aloneM,
    nh_two_or_more_races_moe = nh_two_or_more_racesM,
    hispanic_latino_any_race_moe = hispanic_latino_any_raceM,
    people_of_color_population = sum(
      c_across(c(
        nh_black_aloneE, nh_aian_aloneE, nh_asian_aloneE,
        nh_nhpi_aloneE, nh_other_race_aloneE,
        nh_two_or_more_racesE, hispanic_latino_any_raceE
      )),
      na.rm = FALSE
    ),
    people_of_color_population_moe = tidycensus::moe_sum(
      moe = c(
        nh_black_aloneM, nh_aian_aloneM, nh_asian_aloneM,
        nh_nhpi_aloneM, nh_other_race_aloneM,
        nh_two_or_more_racesM, hispanic_latino_any_raceM
      ),
      estimate = c(
        nh_black_aloneE, nh_aian_aloneE, nh_asian_aloneE,
        nh_nhpi_aloneE, nh_other_race_aloneE,
        nh_two_or_more_racesE, hispanic_latino_any_raceE
      )
    )
  ) %>%
  ungroup() %>%
  # Source-table MOEs end in M; explicitly named derived MOEs are retained.
  select(-ends_with("M")) %>%
  rename_with(~str_remove(., "E$"), ends_with("E") & !all_of("NAME")) %>%
  mutate(
    low_intensity_structure_share = if_else(
      structure_units_total > 0,
      low_intensity_structure_units / structure_units_total,
      NA_real_
    ),
    attached_small_structure_share = if_else(
      structure_units_total > 0,
      attached_small_structure_units / structure_units_total,
      NA_real_
    ),
    medium_large_structure_share = if_else(
      structure_units_total > 0,
      medium_large_structure_units / structure_units_total,
      NA_real_
    ),
    recent_2010_plus_share = if_else(
      structure_year_total > 0,
      recent_2010_plus_units / structure_year_total,
      NA_real_
    ),
    low_intensity_structure_share_moe = tidycensus::moe_prop(
      low_intensity_structure_units,
      structure_units_total,
      low_intensity_structure_units_moe,
      structure_units_total_moe
    ),
    attached_small_structure_share_moe = tidycensus::moe_prop(
      attached_small_structure_units,
      structure_units_total,
      attached_small_structure_units_moe,
      structure_units_total_moe
    ),
    medium_large_structure_share_moe = tidycensus::moe_prop(
      medium_large_structure_units,
      structure_units_total,
      medium_large_structure_units_moe,
      structure_units_total_moe
    ),
    recent_2010_plus_share_moe = tidycensus::moe_prop(
      recent_2010_plus_units,
      structure_year_total,
      recent_2010_plus_units_moe,
      structure_year_total_moe
    ),
    poverty_rate = if_else(
      poverty_total > 0,
      poverty_below / poverty_total,
      NA_real_
    ),
    poverty_rate_moe = safe_moe_prop(
      poverty_below,
      poverty_total,
      poverty_below_moe,
      poverty_total_moe
    ),
    older_adult_share = if_else(
      age_population_total > 0,
      older_adult_population / age_population_total,
      NA_real_
    ),
    older_adult_share_moe = safe_moe_prop(
      older_adult_population,
      age_population_total,
      older_adult_population_moe,
      age_population_total_moe
    ),
    raw_disability_rate = if_else(
      disability_population_total > 0,
      disability_population_with / disability_population_total,
      NA_real_
    ),
    raw_disability_rate_moe = safe_moe_prop(
      disability_population_with,
      disability_population_total,
      disability_population_with_moe,
      disability_population_total_moe
    ),
    disability_under5_rate = if_else(
      disability_under5_total > 0,
      disability_under5_with / disability_under5_total,
      NA_real_
    ),
    disability_under5_rate_moe = safe_moe_prop(
      disability_under5_with,
      disability_under5_total,
      disability_under5_with_moe,
      disability_under5_total_moe
    ),
    disability_5_17_rate = if_else(
      disability_5_17_total > 0,
      disability_5_17_with / disability_5_17_total,
      NA_real_
    ),
    disability_5_17_rate_moe = safe_moe_prop(
      disability_5_17_with,
      disability_5_17_total,
      disability_5_17_with_moe,
      disability_5_17_total_moe
    ),
    disability_18_34_rate = if_else(
      disability_18_34_total > 0,
      disability_18_34_with / disability_18_34_total,
      NA_real_
    ),
    disability_18_34_rate_moe = safe_moe_prop(
      disability_18_34_with,
      disability_18_34_total,
      disability_18_34_with_moe,
      disability_18_34_total_moe
    ),
    disability_35_64_rate = if_else(
      disability_35_64_total > 0,
      disability_35_64_with / disability_35_64_total,
      NA_real_
    ),
    disability_35_64_rate_moe = safe_moe_prop(
      disability_35_64_with,
      disability_35_64_total,
      disability_35_64_with_moe,
      disability_35_64_total_moe
    ),
    disability_65_74_rate = if_else(
      disability_65_74_total > 0,
      disability_65_74_with / disability_65_74_total,
      NA_real_
    ),
    disability_65_74_rate_moe = safe_moe_prop(
      disability_65_74_with,
      disability_65_74_total,
      disability_65_74_with_moe,
      disability_65_74_total_moe
    ),
    disability_75plus_rate = if_else(
      disability_75plus_total > 0,
      disability_75plus_with / disability_75plus_total,
      NA_real_
    ),
    disability_75plus_rate_moe = safe_moe_prop(
      disability_75plus_with,
      disability_75plus_total,
      disability_75plus_with_moe,
      disability_75plus_total_moe
    ),
    people_of_color_share = if_else(
      race_ethnicity_total > 0,
      1 - nh_white_alone / race_ethnicity_total,
      NA_real_
    ),
    people_of_color_share_moe = safe_moe_prop(
      nh_white_alone,
      race_ethnicity_total,
      nh_white_alone_moe,
      race_ethnicity_total_moe
    ),
    nh_white_alone_share = if_else(
      race_ethnicity_total > 0,
      nh_white_alone / race_ethnicity_total,
      NA_real_
    ),
    nh_white_alone_share_moe = safe_moe_prop(
      nh_white_alone,
      race_ethnicity_total,
      nh_white_alone_moe,
      race_ethnicity_total_moe
    ),
    nh_black_alone_share = if_else(
      race_ethnicity_total > 0,
      nh_black_alone / race_ethnicity_total,
      NA_real_
    ),
    nh_black_alone_share_moe = safe_moe_prop(
      nh_black_alone,
      race_ethnicity_total,
      nh_black_alone_moe,
      race_ethnicity_total_moe
    ),
    nh_asian_alone_share = if_else(
      race_ethnicity_total > 0,
      nh_asian_alone / race_ethnicity_total,
      NA_real_
    ),
    nh_asian_alone_share_moe = safe_moe_prop(
      nh_asian_alone,
      race_ethnicity_total,
      nh_asian_alone_moe,
      race_ethnicity_total_moe
    ),
    hispanic_latino_share = if_else(
      race_ethnicity_total > 0,
      hispanic_latino_any_race / race_ethnicity_total,
      NA_real_
    ),
    hispanic_latino_share_moe = safe_moe_prop(
      hispanic_latino_any_race,
      race_ethnicity_total,
      hispanic_latino_any_race_moe,
      race_ethnicity_total_moe
    ),
    race_ethnicity_counts_reconcile = abs(
      people_of_color_population + nh_white_alone - race_ethnicity_total
    ) <= 0.5
  ) %>%
  select(
    -starts_with("age_male_"),
    -starts_with("age_female_"),
    -starts_with("disability_male_"),
    -starts_with("disability_female_")
  ) %>%
  left_join(tract_functional_role, by = "GEOID") %>%
  mutate(
    local_activity_density_per_sqmi = if_else(
      !is.na(full_tract_land_sqmi) & full_tract_land_sqmi > 0,
      local_jobs_and_workers / full_tract_land_sqmi,
      NA_real_
    )
  ) %>%
  st_transform(4326)  # Transform to WGS84 for mapping

county_tract_count <- nrow(census_data_clean)

# Clipping changes tract geometry only; ACS attributes remain tract-level
# estimates and are not re-estimated for the portion inside the city.
census_data_clean <- suppressWarnings(
  census_data_clean %>%
    st_filter(austin_boundary, .predicate = st_intersects) %>%
    st_intersection(st_geometry(austin_boundary))
) %>%
  st_make_valid()

nonempty_positive_area <- !st_is_empty(census_data_clean) &
  as.numeric(st_area(st_transform(census_data_clean, accessibility_equal_area_crs))) > 0

census_data_clean <- census_data_clean[nonempty_positive_area, ]

cat(
  "Clipped ",
  county_tract_count,
  " three-county tracts to ",
  nrow(census_data_clean),
  " tracts intersecting the City of Austin boundary.\n",
  sep = ""
)

# Directly age-standardize disability prevalence using the fixed Austin city
# weights above. If a tract has a zero/missing age-band denominator, use the
# citywide age-specific rate only for constructing the raw estimate, flag the
# substitution, and treat the tract as unreliable for clustering.
census_data_clean <- census_data_clean %>%
  rowwise() %>%
  mutate(
    disability_age_band_imputations = sum(is.na(c(
      disability_under5_rate,
      disability_5_17_rate,
      disability_18_34_rate,
      disability_35_64_rate,
      disability_65_74_rate,
      disability_75plus_rate
    ))),
    age_standardized_disability_rate = sum(
      disability_standardization_reference$standard_weight *
        coalesce(
          c(
            disability_under5_rate,
            disability_5_17_rate,
            disability_18_34_rate,
            disability_35_64_rate,
            disability_65_74_rate,
            disability_75plus_rate
          ),
          disability_standardization_reference$reference_disability_rate
        )
    ),
    age_standardized_disability_rate_moe = if_else(
      disability_age_band_imputations == 0,
      sqrt(sum((
        disability_standardization_reference$standard_weight *
          c(
            disability_under5_rate_moe,
            disability_5_17_rate_moe,
            disability_18_34_rate_moe,
            disability_35_64_rate_moe,
            disability_65_74_rate_moe,
            disability_75plus_rate_moe
          )
      )^2)),
      NA_real_
    ),
    disability_age_counts_reconcile = abs(
      disability_under5_total + disability_5_17_total +
        disability_18_34_total + disability_35_64_total +
        disability_65_74_total + disability_75plus_total -
        disability_population_total
    ) <= 0.5
  ) %>%
  ungroup()

# Aggregate origin-level H8 accessibility to clipped census tracts. H8
# resident-worker counts are apportioned to tract intersections by area and
# used as weights. If an intersecting tract has no resident-worker weight, use
# overlap area instead. Because the H8 origin set is center-in-polygon, a small
# number of City-boundary tract fragments may not intersect an origin hex;
# assign those the nearest H8 origin as a transparent validation fallback.
cat("Aggregating H8 accessibility to census tracts...\n")

h8_access_sf <- st_sf(
  h8_access,
  geometry = cell_to_polygon(h8_access$h3_id),
  crs = 4326
) %>%
  st_make_valid() %>%
  st_transform(accessibility_equal_area_crs) %>%
  mutate(h8_area_m2 = as.numeric(st_area(geometry)))

tracts_equal_area <- census_data_clean %>%
  select(GEOID) %>%
  st_transform(accessibility_equal_area_crs)

tract_h8_overlap <- suppressWarnings(
  st_intersection(
    tracts_equal_area,
    h8_access_sf %>%
      select(h3_id, access_total_jobs, workers_all, h8_area_m2)
  )
) %>%
  mutate(
    overlap_area_m2 = as.numeric(st_area(geometry)),
    h8_area_share = overlap_area_m2 / h8_area_m2,
    allocated_workers = workers_all * h8_area_share
  )

tract_access <- tract_h8_overlap %>%
  st_drop_geometry() %>%
  group_by(GEOID) %>%
  summarise(
    access_h8_cells = n_distinct(h3_id),
    access_worker_weight = sum(allocated_workers, na.rm = TRUE),
    access_overlap_area_m2 = sum(overlap_area_m2, na.rm = TRUE),
    worker_weighted_access = if_else(
      access_worker_weight > 0,
      sum(access_total_jobs * allocated_workers, na.rm = TRUE) /
        access_worker_weight,
      NA_real_
    ),
    area_weighted_access = weighted.mean(
      access_total_jobs,
      overlap_area_m2,
      na.rm = TRUE
    ),
    transit_jobs_45min = coalesce(
      worker_weighted_access,
      area_weighted_access
    ),
    access_aggregation_method = if_else(
      access_worker_weight > 0,
      "area-apportioned resident-worker weighted H8 mean",
      "area-weighted H8 mean"
    ),
    .groups = "drop"
  ) %>%
  select(
    GEOID, access_h8_cells, access_worker_weight,
    access_overlap_area_m2, transit_jobs_45min,
    access_aggregation_method
  )

tracts_without_h8_overlap <- tracts_equal_area %>%
  anti_join(tract_access, by = "GEOID")

if (nrow(tracts_without_h8_overlap) > 0) {
  nearest_h8_index <- st_nearest_feature(
    tracts_without_h8_overlap,
    h8_access_sf
  )

  nearest_h8_access <- h8_access_sf[nearest_h8_index, ] %>%
    st_drop_geometry()

  nearest_tract_access <- tibble(
    GEOID = tracts_without_h8_overlap$GEOID,
    access_h8_cells = 1L,
    access_worker_weight = nearest_h8_access$workers_all,
    access_overlap_area_m2 = 0,
    transit_jobs_45min = nearest_h8_access$access_total_jobs,
    access_aggregation_method = "nearest H8 origin fallback"
  )

  tract_access <- bind_rows(tract_access, nearest_tract_access)
}

census_data_clean <- census_data_clean %>%
  left_join(tract_access, by = "GEOID")

cat(
  "H8 access assigned to ",
  sum(!is.na(census_data_clean$transit_jobs_45min)),
  " of ",
  nrow(census_data_clean),
  " ACS tracts; ",
  sum(census_data_clean$access_aggregation_method == "nearest H8 origin fallback"),
  " used the boundary fallback.\n",
  sep = ""
)

# Aggregate local place-based exposures with a fixed one-mile window around an
# internal representative point for each clipped tract. A fixed window avoids
# allowing tract size alone to determine exposure. Environmental facilities
# are available through a one-mile City buffer. Crash data cover the City, so
# crash density is normalized by the part of each window inside the City.
cat("Aggregating environmental-hazard and KSI crash exposures...\n")

tract_representative_points <- suppressWarnings(
  census_data_clean %>%
    select(GEOID) %>%
    st_transform(accessibility_equal_area_crs) %>%
    st_point_on_surface()
)

tract_exposure_buffers <- tract_representative_points %>%
  st_buffer(exposure_buffer_miles * meters_per_mile)

# Development pressure is measured inside each clipped tract rather than in the
# one-mile context window. Counts are later normalized by the 2024 ACS housing
# stock and the five-year permit observation period.
development_permit_counts <- census_data_clean %>%
  select(GEOID) %>%
  st_transform(accessibility_equal_area_crs) %>%
  st_join(
    development_permits %>% st_transform(accessibility_equal_area_crs),
    left = TRUE
  ) %>%
  st_drop_geometry() %>%
  group_by(GEOID) %>%
  summarise(
    new_housing_permits_2020_2024 = n_distinct(
      if_else(new_housing_permit, permit_id, NA_character_),
      na.rm = TRUE
    ),
    new_housing_units_permitted_2020_2024 = sum(
      if_else(new_housing_permit, new_housing_units, 0),
      na.rm = TRUE
    ),
    residential_demolition_permits_2020_2024 = n_distinct(
      if_else(residential_demolition_permit, permit_id, NA_character_),
      na.rm = TRUE
    ),
    residential_units_demolished_2020_2024 = sum(
      if_else(
        residential_demolition_permit,
        residential_units_demolished,
        0
      ),
      na.rm = TRUE
    ),
    .groups = "drop"
  )

environmental_hazard_counts <- tract_exposure_buffers %>%
  st_join(
    environmental_hazards %>% st_transform(accessibility_equal_area_crs),
    left = TRUE
  ) %>%
  st_drop_geometry() %>%
  group_by(GEOID) %>%
  summarise(
    hazard_facilities_1mi = n_distinct(registry_id, na.rm = TRUE),
    brownfield_facilities_1mi = n_distinct(
      if_else(has_brownfields, registry_id, NA_character_),
      na.rm = TRUE
    ),
    tri_facilities_1mi = n_distinct(
      if_else(has_tri, registry_id, NA_character_),
      na.rm = TRUE
    ),
    rcra_lqg_tsd_facilities_1mi = n_distinct(
      if_else(has_rcra_lqg_tsd, registry_id, NA_character_),
      na.rm = TRUE
    ),
    rmp_facilities_1mi = n_distinct(
      if_else(has_rmp, registry_id, NA_character_),
      na.rm = TRUE
    ),
    superfund_sems_facilities_1mi = n_distinct(
      if_else(has_superfund_sems, registry_id, NA_character_),
      na.rm = TRUE
    ),
    npdes_major_facilities_1mi = n_distinct(
      if_else(has_npdes_major, registry_id, NA_character_),
      na.rm = TRUE
    ),
    air_major_facilities_1mi = n_distinct(
      if_else(has_air_major, registry_id, NA_character_),
      na.rm = TRUE
    ),
    .groups = "drop"
  )

city_boundary_equal_area <- austin_boundary %>%
  st_transform(accessibility_equal_area_crs)

crash_observation_buffers <- suppressWarnings(
  st_intersection(
    tract_exposure_buffers,
    st_geometry(city_boundary_equal_area)
  )
) %>%
  mutate(
    crash_observation_area_sqmi =
      as.numeric(st_area(geometry)) / square_meters_per_square_mile
  )

crash_exposure_counts <- crash_observation_buffers %>%
  st_join(
    ksi_crashes %>% st_transform(accessibility_equal_area_crs),
    left = TRUE
  ) %>%
  st_drop_geometry() %>%
  group_by(GEOID) %>%
  summarise(
    crash_observation_area_sqmi = first(crash_observation_area_sqmi),
    ksi_crashes_1mi = n_distinct(crash_id, na.rm = TRUE),
    fatal_crashes_1mi = n_distinct(
      if_else(fatal_crash, crash_id, NA_character_),
      na.rm = TRUE
    ),
    vulnerable_road_user_ksi_crashes_1mi = n_distinct(
      if_else(vulnerable_road_user_ksi_crash, crash_id, NA_character_),
      na.rm = TRUE
    ),
    .groups = "drop"
  ) %>%
  mutate(
    annual_ksi_crash_density =
      ksi_crashes_1mi / crash_year_count / crash_observation_area_sqmi,
    annual_vru_ksi_crash_density =
      vulnerable_road_user_ksi_crashes_1mi /
        crash_year_count /
        crash_observation_area_sqmi
  )

count_columns <- c(
  "hazard_facilities_1mi", "brownfield_facilities_1mi",
  "tri_facilities_1mi", "rcra_lqg_tsd_facilities_1mi",
  "rmp_facilities_1mi", "superfund_sems_facilities_1mi",
  "npdes_major_facilities_1mi", "air_major_facilities_1mi",
  "ksi_crashes_1mi", "fatal_crashes_1mi",
  "vulnerable_road_user_ksi_crashes_1mi",
  "new_housing_permits_2020_2024",
  "new_housing_units_permitted_2020_2024",
  "residential_demolition_permits_2020_2024",
  "residential_units_demolished_2020_2024"
)

census_data_clean <- census_data_clean %>%
  left_join(environmental_hazard_counts, by = "GEOID") %>%
  left_join(crash_exposure_counts, by = "GEOID") %>%
  left_join(development_permit_counts, by = "GEOID") %>%
  left_join(
    land_use_by_tract %>%
      select(all_of(required_land_use_columns)),
    by = "GEOID"
  ) %>%
  left_join(
    displacement_risk_by_tract %>%
      select(all_of(required_displacement_columns)) %>%
      rename(
        displacement_risk_category_published = displacement_risk_category
      ),
    by = "GEOID"
  ) %>%
  mutate(
    across(all_of(count_columns), ~replace_na(.x, 0)),
    annual_new_housing_units_per_1000 = if_else(
      !is.na(housing_units_total) & housing_units_total > 0,
      new_housing_units_permitted_2020_2024 /
        development_year_count * 1000 / housing_units_total,
      NA_real_
    ),
    annual_residential_demolition_permits_per_1000 = if_else(
      !is.na(housing_units_total) & housing_units_total > 0,
      residential_demolition_permits_2020_2024 /
        development_year_count * 1000 / housing_units_total,
      NA_real_
    ),
    exposure_buffer_miles = exposure_buffer_miles,
    exposure_geography_method = paste0(
      exposure_buffer_miles,
      "-mile buffer around tract point-on-surface"
    ),
    land_use_category_detailed = factor(land_use_category_detailed),
    land_use_category = factor(land_use_category),
    land_use_category_cluster = factor(land_use_category_cluster),
    displacement_risk_category_display = factor(
      replace_na(
        displacement_risk_category_published,
        "Unknown / outside published coverage"
      ),
      levels = c(
        "No published displacement-risk designation",
        "Vulnerable",
        "Active Displacement Risk",
        "Chronic Displacement Risk",
        "Unknown / outside published coverage"
      )
    ),
    displacement_risk_category_cluster = factor(
      displacement_risk_category_published,
      levels = c(
        "No published displacement-risk designation",
        "Vulnerable",
        "Active Displacement Risk",
        "Chronic Displacement Risk"
      )
    )
  )

if (
  any(is.na(census_data_clean$annual_ksi_crash_density)) ||
    any(census_data_clean$crash_observation_area_sqmi <= 0)
) {
  stop("Crash-exposure aggregation produced a missing or zero-area tract window.")
}

if (any(
  is.na(census_data_clean$total_jobs) |
    is.na(census_data_clean$workers_all) |
    is.na(census_data_clean$jobs_resident_worker_balance) |
    is.na(census_data_clean$local_activity_density_per_sqmi)
)) {
  stop("Functional-role aggregation is incomplete for City-intersecting tracts.")
}

cat(
  "Exposure measures assigned to ", nrow(census_data_clean),
  " tracts using ", nrow(environmental_hazards),
  " EPA candidate facilities and ", nrow(ksi_crashes),
  " KSI crashes.\n",
  sep = ""
)

cat(
  "Experimental measures assigned using ", nrow(development_permits),
  " geocoded development permits, ACS built-form estimates, ",
  nrow(census_data_clean), " tract-level LODES functional-role records, ",
  sum(!is.na(census_data_clean$land_use_category_cluster)),
  " cluster-ready land-use categories, and ",
  sum(!is.na(census_data_clean$displacement_risk_category_cluster)),
  " published displacement-risk categories.\n",
  sep = ""
)

impute_median <- function(x) {
  replace_na(x, median(x, na.rm = TRUE))
}

safe_rate <- function(numerator, denominator) {
  if_else(!is.na(denominator) & denominator > 0, numerator / denominator, NA_real_)
}

z_score <- function(x) {
  as.numeric(scale(x))
}

winsorize <- function(x, probabilities = c(0.01, 0.99)) {
  limits <- quantile(
    x,
    probabilities,
    na.rm = TRUE,
    names = FALSE,
    type = 7
  )
  pmin(pmax(x, limits[1]), limits[2])
}

empirical_logit <- function(numerator, denominator) {
  log((numerator + 0.5) / (denominator - numerator + 0.5))
}

bounded_logit <- function(x, epsilon = 0.005) {
  qlogis(pmin(pmax(x, epsilon), 1 - epsilon))
}

lower_overlay_threshold <- function(x) {
  as.numeric(quantile(x, overlay_tail_probability, na.rm = TRUE, names = FALSE))
}

upper_overlay_threshold <- function(x) {
  as.numeric(quantile(x, 1 - overlay_tail_probability, na.rm = TRUE, names = FALSE))
}

# Preserve the current place/access/service-fit proof of concept while adding a
# separately labeled unified resident-context experiment. Income, employment,
# education, vehicle availability, and race/ethnicity remain audit overlays;
# poverty enters only the bounded experimental family below. No demographic
# measure enters the directional place-and-access conditions index.
cat("Preparing cluster inputs and post-clustering overlays...\n")

census_data_normalized <- census_data_clean %>%
  mutate(
    employment_rate = safe_rate(employed, labor_force),
    educational_attainment = safe_rate(
      bachelors + masters + professional + doctorate,
      education_total
    ),
    children_household_share = safe_rate(
      households_with_children,
      households_total
    ),
    no_vehicle_share = safe_rate(no_vehicle_households, households_total),
    log_transit_jobs_45min = log1p(transit_jobs_45min),
    log_hazard_facilities_1mi = log1p(hazard_facilities_1mi),
    log_annual_ksi_crash_density = log1p(annual_ksi_crash_density),
    log_annual_new_housing_unit_rate = log1p(
      annual_new_housing_units_per_1000
    ),
    log_annual_demolition_permit_rate = log1p(
      annual_residential_demolition_permits_per_1000
    ),
    older_adult_reliable =
      !is.na(age_population_total) &
      age_population_total >= demographic_min_universe &
      !is.na(older_adult_population) &
      older_adult_population >= 0 &
      older_adult_population <= age_population_total &
      is.finite(older_adult_share_moe) &
      older_adult_share_moe <= demographic_moe_threshold,
    older_adult_reliable_strict =
      older_adult_reliable &
      older_adult_share_moe <= demographic_moe_strict_threshold,
    older_adult_reliable_permissive =
      !is.na(age_population_total) &
      age_population_total >= demographic_min_universe &
      !is.na(older_adult_population) &
      older_adult_population >= 0 &
      older_adult_population <= age_population_total &
      is.finite(older_adult_share_moe) &
      older_adult_share_moe <= demographic_moe_permissive_threshold,
    age_standardized_disability_reliable =
      !is.na(disability_population_total) &
      disability_population_total >= demographic_min_universe &
      disability_age_counts_reconcile &
      disability_age_band_imputations == 0 &
      !is.na(disability_population_with) &
      disability_population_with >= 0 &
      disability_population_with <= disability_population_total &
      is.finite(age_standardized_disability_rate_moe) &
      age_standardized_disability_rate_moe <= demographic_moe_threshold,
    age_standardized_disability_reliable_strict =
      age_standardized_disability_reliable &
      age_standardized_disability_rate_moe <=
        demographic_moe_strict_threshold,
    age_standardized_disability_reliable_permissive =
      !is.na(disability_population_total) &
      disability_population_total >= demographic_min_universe &
      disability_age_counts_reconcile &
      disability_age_band_imputations == 0 &
      !is.na(disability_population_with) &
      disability_population_with >= 0 &
      disability_population_with <= disability_population_total &
      is.finite(age_standardized_disability_rate_moe) &
      age_standardized_disability_rate_moe <=
        demographic_moe_permissive_threshold,
    poverty_rate_reliable =
      !is.na(poverty_total) &
      poverty_total >= demographic_min_universe &
      !is.na(poverty_below) &
      poverty_below >= 0 &
      poverty_below <= poverty_total &
      is.finite(poverty_rate_moe) &
      poverty_rate_moe <= demographic_moe_threshold,
    poverty_rate_reliable_strict =
      poverty_rate_reliable &
      poverty_rate_moe <= demographic_moe_strict_threshold,
    poverty_rate_reliable_permissive =
      !is.na(poverty_total) &
      poverty_total >= demographic_min_universe &
      !is.na(poverty_below) &
      poverty_below >= 0 &
      poverty_below <= poverty_total &
      is.finite(poverty_rate_moe) &
      poverty_rate_moe <= demographic_moe_permissive_threshold,
    older_adult_logit_raw = empirical_logit(
      older_adult_population,
      age_population_total
    ),
    age_standardized_disability_logit_raw = bounded_logit(
      age_standardized_disability_rate
    ),
    poverty_rate_logit_raw = empirical_logit(
      poverty_below,
      poverty_total
    ),
    older_adult_logit = winsorize(if_else(
      older_adult_reliable,
      older_adult_logit_raw,
      NA_real_
    )),
    age_standardized_disability_logit = winsorize(if_else(
      age_standardized_disability_reliable,
      age_standardized_disability_logit_raw,
      NA_real_
    )),
    poverty_rate_logit = winsorize(if_else(
      poverty_rate_reliable,
      poverty_rate_logit_raw,
      NA_real_
    )),
    structure_counts_reconcile = abs(
      low_intensity_structure_units +
        attached_small_structure_units +
        medium_large_structure_units -
        structure_units_total
    ) <= 0.5,
    structure_share_moe_max = pmax(
      low_intensity_structure_share_moe,
      attached_small_structure_share_moe,
      medium_large_structure_share_moe,
      na.rm = TRUE
    ),
    structure_composition_reliable =
      !is.na(structure_units_total) &
      structure_units_total >= 100 &
      structure_counts_reconcile &
      is.finite(structure_share_moe_max) &
      structure_share_moe_max <= 0.20,
    structure_composition_reliable_15pp =
      !is.na(structure_units_total) &
      structure_units_total >= 100 &
      structure_counts_reconcile &
      is.finite(structure_share_moe_max) &
      structure_share_moe_max <= 0.15,
    stock_age_reliable =
      !is.na(structure_year_total) &
      structure_year_total >= 100 &
      !is.na(recent_2010_plus_share) &
      recent_2010_plus_units <= structure_year_total &
      is.finite(recent_2010_plus_share_moe) &
      recent_2010_plus_share_moe <= 0.20,
    stock_age_reliable_15pp =
      !is.na(structure_year_total) &
      structure_year_total >= 100 &
      !is.na(recent_2010_plus_share) &
      recent_2010_plus_units <= structure_year_total &
      is.finite(recent_2010_plus_share_moe) &
      recent_2010_plus_share_moe <= 0.15,
    smoothed_low_intensity_share =
      (low_intensity_structure_units + 0.5) /
        (structure_units_total + 1.5),
    smoothed_attached_small_share =
      (attached_small_structure_units + 0.5) /
        (structure_units_total + 1.5),
    smoothed_medium_large_share =
      (medium_large_structure_units + 0.5) /
        (structure_units_total + 1.5),
    built_form_intensity_ilr_raw = sqrt(2 / 3) * log(
      smoothed_low_intensity_share /
        sqrt(
          smoothed_attached_small_share *
            smoothed_medium_large_share
        )
    ),
    multifamily_scale_ilr_raw = sqrt(1 / 2) * log(
      smoothed_attached_small_share /
        smoothed_medium_large_share
    ),
    recent_stock_logit_raw = log(
      (recent_2010_plus_units + 0.5) /
        (structure_year_total - recent_2010_plus_units + 0.5)
    ),
    built_form_intensity_ilr = if_else(
      structure_composition_reliable,
      winsorize(built_form_intensity_ilr_raw),
      NA_real_
    ),
    multifamily_scale_ilr = if_else(
      structure_composition_reliable,
      winsorize(multifamily_scale_ilr_raw),
      NA_real_
    ),
    recent_stock_logit = if_else(
      stock_age_reliable,
      winsorize(recent_stock_logit_raw),
      NA_real_
    ),
    log_local_activity_density = winsorize(
      log1p(local_activity_density_per_sqmi)
    ),
    job_worker_balance_cluster_raw = winsorize(
      jobs_resident_worker_balance
    ),
    missing_cluster_input = if_any(
      c(
        median_home_value, median_rent, avg_household_size,
        children_household_share, transit_jobs_45min,
        hazard_facilities_1mi, annual_ksi_crash_density
      ),
      is.na
    ),
    missing_experimental_input = if_any(
      c(
        annual_new_housing_units_per_1000,
        annual_residential_demolition_permits_per_1000,
        built_form_intensity_ilr,
        multifamily_scale_ilr,
        recent_stock_logit,
        log_local_activity_density,
        job_worker_balance_cluster_raw
      ),
      is.na
    ),
    missing_resident_context_input =
      !coalesce(older_adult_reliable, FALSE) |
      !coalesce(age_standardized_disability_reliable, FALSE) |
      !coalesce(poverty_rate_reliable, FALSE),
    missing_overlay_input = if_any(
      c(
        median_income, poverty_rate, employment_rate,
        educational_attainment, no_vehicle_share
      ),
      is.na
    )
  )

overlay_thresholds <- tibble(
  overlay_filter = c(
    "lower_income_overlay", "higher_poverty_overlay",
    "lower_employment_overlay", "lower_education_overlay",
    "higher_no_vehicle_overlay"
  ),
  source_indicator = c(
    "median_income", "poverty_rate", "employment_rate",
    "educational_attainment", "no_vehicle_share"
  ),
  comparison = c("<=", ">=", "<=", "<=", ">="),
  quantile = c(
    overlay_tail_probability, 1 - overlay_tail_probability,
    overlay_tail_probability, overlay_tail_probability,
    1 - overlay_tail_probability
  ),
  threshold = c(
    lower_overlay_threshold(census_data_normalized$median_income),
    upper_overlay_threshold(census_data_normalized$poverty_rate),
    lower_overlay_threshold(census_data_normalized$employment_rate),
    lower_overlay_threshold(census_data_normalized$educational_attainment),
    upper_overlay_threshold(census_data_normalized$no_vehicle_share)
  )
)

census_data_normalized <- census_data_normalized %>%
  mutate(
    lower_income_overlay = median_income <= overlay_thresholds$threshold[1],
    higher_poverty_overlay = poverty_rate >= overlay_thresholds$threshold[2],
    lower_employment_overlay = employment_rate <= overlay_thresholds$threshold[3],
    lower_education_overlay =
      educational_attainment <= overlay_thresholds$threshold[4],
    higher_no_vehicle_overlay =
      no_vehicle_share >= overlay_thresholds$threshold[5],
    income_percentile = percent_rank(median_income),
    poverty_burden_percentile = percent_rank(poverty_rate),
    employment_percentile = percent_rank(employment_rate),
    educational_attainment_percentile = percent_rank(educational_attainment),
    no_vehicle_percentile = percent_rank(no_vehicle_share),
    across(
      c(
        share_residential,
        share_mixed_use,
        share_commercial_office,
        share_industrial_logistics,
        share_institutional_civic,
        share_open_space,
        share_transportation_utilities,
        share_undeveloped_agricultural
      ),
      ~if_else(adequate_composition_coverage, .x, NA_real_),
      .names = "{.col}_cluster"
    ),
    across(
      c(
        median_home_value, median_rent, avg_household_size,
        children_household_share, log_transit_jobs_45min,
        log_hazard_facilities_1mi, log_annual_ksi_crash_density,
        log_annual_new_housing_unit_rate,
        log_annual_demolition_permit_rate,
        built_form_intensity_ilr,
        multifamily_scale_ilr,
        recent_stock_logit,
        log_local_activity_density,
        job_worker_balance_cluster_raw,
        older_adult_logit,
        age_standardized_disability_logit,
        poverty_rate_logit
      ),
      impute_median,
      .names = "{.col}_imputed"
    ),
    median_home_value_z = z_score(median_home_value_imputed),
    median_rent_z = z_score(median_rent_imputed),
    avg_household_size_z = z_score(avg_household_size_imputed),
    children_household_share_z = z_score(children_household_share_imputed),
    housing_market_profile_cluster = case_when(
      !is.na(median_home_value) & !is.na(median_rent) ~
        (median_home_value_z + median_rent_z) / 2,
      !is.na(median_home_value) ~ median_home_value_z,
      !is.na(median_rent) ~ median_rent_z,
      TRUE ~ 0
    ),
    avg_household_size_cluster = avg_household_size_imputed,
    children_household_share_cluster = children_household_share_imputed,
    family_service_fit_cluster = (
      avg_household_size_z + children_household_share_z
    ) / 2,
    log_transit_jobs_45min_cluster = log_transit_jobs_45min_imputed,
    log_hazard_facilities_1mi_cluster = log_hazard_facilities_1mi_imputed,
    log_annual_ksi_crash_density_cluster =
      log_annual_ksi_crash_density_imputed,
    log_annual_new_housing_unit_rate_z = z_score(
      log_annual_new_housing_unit_rate_imputed
    ),
    log_annual_demolition_permit_rate_z = z_score(
      log_annual_demolition_permit_rate_imputed
    ),
    development_pressure_cluster = (
      log_annual_new_housing_unit_rate_z +
        log_annual_demolition_permit_rate_z
    ) / 2,
    built_form_intensity_cluster = built_form_intensity_ilr_imputed,
    multifamily_scale_cluster = multifamily_scale_ilr_imputed,
    recent_stock_cluster = recent_stock_logit_imputed,
    local_activity_intensity_cluster =
      log_local_activity_density_imputed,
    job_worker_balance_cluster =
      job_worker_balance_cluster_raw_imputed,
    older_adult_need_cluster = older_adult_logit_imputed,
    age_standardized_disability_need_cluster =
      age_standardized_disability_logit_imputed,
    poverty_constraint_cluster = poverty_rate_logit_imputed,
    built_form_input_imputed =
      !structure_composition_reliable | !stock_age_reliable,
    functional_role_input_imputed = if_any(
      c(
        local_activity_density_per_sqmi,
        jobs_resident_worker_balance
      ),
      is.na
    ),
    age_disability_input_imputed =
      !coalesce(older_adult_reliable, FALSE) |
      !coalesce(age_standardized_disability_reliable, FALSE),
    poverty_constraint_input_imputed =
      !coalesce(poverty_rate_reliable, FALSE),
    exposure_burden_cluster = (
      z_score(log_hazard_facilities_1mi_imputed) +
        z_score(log_annual_ksi_crash_density_imputed)
    ) / 2,
    transit_access_score = z_score(log_transit_jobs_45min_imputed),
    environmental_safety_score = -z_score(log_hazard_facilities_1mi_imputed),
    traffic_safety_score = -z_score(log_annual_ksi_crash_density_imputed),
    place_access_index = (
      transit_access_score +
        environmental_safety_score +
        traffic_safety_score
    ) / 3,
    cluster_input_imputed = missing_cluster_input
  )

# Prepare the current people/service-fit, place, and access proof-of-concept
# indicators. The separate unified family is defined below.
cluster_vars <- c(
  "housing_market_profile_cluster",
  "family_service_fit_cluster",
  "log_transit_jobs_45min_cluster",
  "log_hazard_facilities_1mi_cluster",
  "log_annual_ksi_crash_density_cluster"
)

indicator_roles <- tribble(
  ~indicator, ~domain, ~analysis_role, ~direction_in_place_access_index,
  "Housing market profile (home value and rent)", "Place", "Cluster input", "Profile only",
  "Family/service-fit profile (household size and children)", "People / service fit", "Cluster input", "Profile only",
  "Transit access to jobs", "Access", "Cluster input", "Higher",
  "EPA hazard candidates within one mile", "Place / exposure", "Cluster input", "Lower",
  "Annual KSI crash density within one mile", "Place / exposure", "Cluster input", "Lower",
  "Residential development pressure (new units and demolition)", "Housing market / change", "Experimental cluster input", "Not included",
  "Share age 65 or older", "People / service needs", "Unified experimental cluster input", "Profile only",
  "Age-standardized disability prevalence", "People / service needs", "Unified experimental cluster input", "Profile only",
  "Housing structure composition and recent construction era", "Built form", "Experimental cluster input", "Not included",
  "Local job/resident-worker balance and activity intensity", "Functional role", "Experimental cluster input", "Not included",
  "Broad parcel-area land-use category", "Land use / urban function", "Mixed-data experimental cluster input", "Profile only",
  "City-updated displacement-risk category", "Displacement policy context", "Mixed-data experimental input; embeds vulnerability indicators", "Not included",
  "Median household income", "Social/economic context", "Overlay / filter", "Not included",
  "Poverty rate", "Economic constraint", "Overlay / bounded unified experimental input", "Not included",
  "Employment rate", "Social/economic context", "Overlay / filter", "Not included",
  "Educational attainment", "Social/economic context", "Overlay / filter", "Not included",
  "Households without a vehicle", "Transportation context", "Overlay / filter", "Not included",
  "Race and ethnicity", "Equity audit", "Post-clustering audit only", "Not included",
  "Eviction filing rate", "Housing stability", "Planned overlay / filter (input pending)", "Not included"
)

baseline_domains <- c(
  "housing_market", "people_service_fit", "access",
  "environmental_hazard", "traffic_safety"
)
built_form_vars <- c(
  "built_form_intensity_cluster",
  "multifamily_scale_cluster",
  "recent_stock_cluster"
)
functional_role_vars <- c(
  "local_activity_intensity_cluster",
  "job_worker_balance_cluster"
)

make_model_spec <- function(
    variables,
    domains,
    balance_domains = character(),
    weights = NULL,
    model_family = "place_candidate",
    reliability_flags = character()) {
  if (length(variables) != length(domains)) {
    stop("Every model variable must have one domain label.")
  }

  if (is.null(weights)) {
    weights <- rep(1, length(variables))
    for (domain_name in balance_domains) {
      domain_index <- domains == domain_name
      if (any(domain_index)) {
        weights[domain_index] <- 1 / sqrt(sum(domain_index))
      }
    }
  }

  if (
    length(weights) != length(variables) ||
      any(!is.finite(weights)) ||
      any(weights <= 0)
  ) {
    stop("Model weights must be finite, positive, and match the variables.")
  }

  resident_domain_index <- domains %in% c(
    "resident_needs",
    "economic_constraint"
  )
  resident_context_share <- sum(weights[resident_domain_index]^2) /
    sum(weights^2)

  list(
    variables = variables,
    domains = domains,
    weights = weights,
    model_family = model_family,
    reliability_flags = reliability_flags,
    resident_context_share = resident_context_share
  )
}

unified_place_vars <- c(
  "housing_market_profile_cluster",
  "log_transit_jobs_45min_cluster",
  "log_hazard_facilities_1mi_cluster",
  "log_annual_ksi_crash_density_cluster",
  "development_pressure_cluster"
)
unified_place_domains <- c(
  "housing_market", "access", "exposure", "exposure",
  "development_change"
)
resident_needs_vars <- c(
  "family_service_fit_cluster",
  "older_adult_need_cluster",
  "age_standardized_disability_need_cluster"
)
resident_needs_domains <- rep("resident_needs", length(resident_needs_vars))
mixed_resident_context_vars <- c(
  unified_place_vars,
  resident_needs_vars,
  "poverty_constraint_cluster"
)
mixed_resident_context_domains <- c(
  unified_place_domains,
  resident_needs_domains,
  "economic_constraint"
)

# For a requested resident-context share f of total squared Euclidean distance,
# the four place-domain units imply R = 4f/(1-f) squared-weight units for
# resident context. Split R equally between the service-needs and poverty
# blocks, then equally across the three service-needs coordinates.
make_resident_context_weights <- function(target_share) {
  if (!is.finite(target_share) || target_share <= 0 || target_share >= 1) {
    stop("Resident-context target share must be strictly between zero and one.")
  }

  place_squared_weight <- 4
  resident_squared_weight <-
    place_squared_weight * target_share / (1 - target_share)
  block_squared_weight <- resident_squared_weight / 2
  weights <- c(
    1,
    1,
    1 / sqrt(2),
    1 / sqrt(2),
    1,
    rep(sqrt(block_squared_weight / length(resident_needs_vars)), 3),
    sqrt(block_squared_weight)
  )
  actual_share <- sum(weights[6:9]^2) / sum(weights^2)

  if (!isTRUE(all.equal(actual_share, target_share, tolerance = 1e-12))) {
    stop("Resident-context squared-distance target was not achieved.")
  }

  weights
}

model_specs <- list(
  baseline = make_model_spec(cluster_vars, baseline_domains),
  plus_development_pressure = make_model_spec(
    c(cluster_vars, "development_pressure_cluster"),
    c(baseline_domains, "development_change")
  ),
  plus_built_form = make_model_spec(
    c(cluster_vars, built_form_vars),
    c(baseline_domains, rep("built_form", length(built_form_vars))),
    balance_domains = "built_form"
  ),
  plus_functional_role = make_model_spec(
    c(cluster_vars, functional_role_vars),
    c(
      baseline_domains,
      rep("functional_role", length(functional_role_vars))
    ),
    balance_domains = "functional_role"
  ),
  all_candidates = make_model_spec(
    c(
      cluster_vars, "development_pressure_cluster",
      built_form_vars, functional_role_vars
    ),
    c(
      baseline_domains, "development_change",
      rep("built_form", length(built_form_vars)),
      rep("functional_role", length(functional_role_vars))
    ),
    balance_domains = c("built_form", "functional_role")
  ),
  domain_balanced_all_candidates = make_model_spec(
    c(
      cluster_vars, "development_pressure_cluster",
      built_form_vars, functional_role_vars
    ),
    c(
      "housing_market", "people_service_fit", "access",
      "exposure", "exposure", "development_change",
      rep("built_form", length(built_form_vars)),
      rep("functional_role", length(functional_role_vars))
    ),
    balance_domains = c("exposure", "built_form", "functional_role")
  ),
  resident_context_reference = make_model_spec(
    c(unified_place_vars, "family_service_fit_cluster"),
    c(unified_place_domains, "resident_needs"),
    balance_domains = c("exposure", "resident_needs"),
    model_family = "resident_context"
  ),
  resident_context_age_disability = make_model_spec(
    c(unified_place_vars, resident_needs_vars),
    c(unified_place_domains, resident_needs_domains),
    balance_domains = c("exposure", "resident_needs"),
    model_family = "resident_context",
    reliability_flags = c(
      "older_adult_reliable",
      "age_standardized_disability_reliable"
    )
  ),
  resident_context_mixed_20 = make_model_spec(
    mixed_resident_context_vars,
    mixed_resident_context_domains,
    weights = make_resident_context_weights(
      resident_context_weight_targets[1]
    ),
    model_family = "resident_context",
    reliability_flags = c(
      "older_adult_reliable",
      "age_standardized_disability_reliable",
      "poverty_rate_reliable"
    )
  ),
  resident_context_mixed_25 = make_model_spec(
    mixed_resident_context_vars,
    mixed_resident_context_domains,
    weights = make_resident_context_weights(
      resident_context_weight_targets[2]
    ),
    model_family = "resident_context",
    reliability_flags = c(
      "older_adult_reliable",
      "age_standardized_disability_reliable",
      "poverty_rate_reliable"
    )
  ),
  resident_context_mixed_33 = make_model_spec(
    mixed_resident_context_vars,
    mixed_resident_context_domains,
    weights = make_resident_context_weights(
      resident_context_weight_targets[3]
    ),
    model_family = "resident_context",
    reliability_flags = c(
      "older_adult_reliable",
      "age_standardized_disability_reliable",
      "poverty_rate_reliable"
    )
  )
)

model_labels <- c(
  baseline = "Baseline five inputs",
  plus_development_pressure = "Baseline + development pressure",
  plus_built_form = "Baseline + built form",
  plus_functional_role = "Baseline + functional role",
  all_candidates = "Baseline + development, built form, and functional role",
  domain_balanced_all_candidates =
    "Domain-balanced + development, built form, and functional role",
  resident_context_reference =
    "Unified reference: existing family profile only",
  resident_context_age_disability =
    "Unified reference + age and disability service needs",
  resident_context_mixed_20 =
    "Unified age/disability/poverty: 20% resident-context weight",
  resident_context_mixed_25 =
    "Unified age/disability/poverty: 25% resident-context weight",
  resident_context_mixed_33 =
    "Unified age/disability/poverty: 33% resident-context weight"
)
model_plot_labels <- c(
  baseline = "Baseline",
  plus_development_pressure = "+ Development pressure",
  plus_built_form = "+ Built form",
  plus_functional_role = "+ Functional role",
  all_candidates = "+ All candidates",
  domain_balanced_all_candidates = "Domain-balanced + all",
  resident_context_reference = "Unified reference",
  resident_context_age_disability = "+ Age/disability",
  resident_context_mixed_20 = "+ Poverty; context 20%",
  resident_context_mixed_25 = "+ Poverty; context 25%",
  resident_context_mixed_33 = "+ Poverty; context 33%"
)

choose_two <- function(x) {
  x * (x - 1) / 2
}

adjusted_rand_index <- function(first_assignment, second_assignment) {
  complete <- !is.na(first_assignment) & !is.na(second_assignment)
  contingency <- table(
    first_assignment[complete],
    second_assignment[complete]
  )
  n <- sum(contingency)

  if (n < 2) {
    return(NA_real_)
  }

  observed <- sum(choose_two(contingency))
  row_pairs <- sum(choose_two(rowSums(contingency)))
  column_pairs <- sum(choose_two(colSums(contingency)))
  total_pairs <- choose_two(n)
  expected <- row_pairs * column_pairs / total_pairs
  maximum <- (row_pairs + column_pairs) / 2

  if (maximum == expected) {
    return(NA_real_)
  }

  (observed - expected) / (maximum - expected)
}

fit_cluster_model <- function(data, specification, model_key) {
  variable_names <- specification$variables
  variable_domains <- specification$domains
  variable_weights <- specification$weights
  diagnostic_k <- 1:10
  complete_index <- complete.cases(
    st_drop_geometry(data)[, variable_names, drop = FALSE]
  )
  raw_data <- data %>%
    st_drop_geometry() %>%
    filter(complete_index) %>%
    select(all_of(variable_names))
  scaled_data_unweighted <- scale(raw_data)
  scaled_data <- sweep(
    scaled_data_unweighted,
    MARGIN = 2,
    STATS = variable_weights,
    FUN = "*"
  )

  if (any(!is.finite(scaled_data))) {
    stop("Non-finite scaled value in model specification: ", model_key)
  }

  set.seed(cluster_random_seed)
  diagnostic_fits <- lapply(diagnostic_k, function(k) {
    kmeans(scaled_data, centers = k, nstart = cluster_nstart)
  })
  wss <- vapply(
    diagnostic_fits,
    function(fit) fit$tot.withinss,
    numeric(1)
  )
  model_distance <- dist(scaled_data)
  average_silhouette <- c(
    NA_real_,
    vapply(
      diagnostic_fits[-1],
      function(fit) {
        mean(cluster::silhouette(fit$cluster, model_distance)[, 3])
      },
      numeric(1)
    )
  )
  total_sum_squares <- diagnostic_fits[[1]]$totss
  calinski_harabasz <- c(
    NA_real_,
    vapply(
      seq_along(diagnostic_fits)[-1],
      function(index) {
        k <- diagnostic_k[index]
        fit <- diagnostic_fits[[index]]
        between_sum_squares <- total_sum_squares - fit$tot.withinss
        (between_sum_squares / (k - 1)) /
          (fit$tot.withinss / (nrow(scaled_data) - k))
      },
      numeric(1)
    )
  )
  smallest_cluster <- vapply(
    diagnostic_fits,
    function(fit) min(table(fit$cluster)),
    numeric(1)
  )
  largest_cluster <- vapply(
    diagnostic_fits,
    function(fit) max(table(fit$cluster)),
    numeric(1)
  )

  stability_k <- 2:6
  stability_sample_size <- floor(
    nrow(scaled_data) * experimental_stability_sample_share
  )
  # Pre-generate the same tract subsamples for every specification so model
  # stability comparisons are paired rather than affected by sample draws.
  set.seed(cluster_random_seed)
  stability_sample_indices <- replicate(
    experimental_stability_bootstraps,
    sample.int(
      nrow(scaled_data),
      size = stability_sample_size,
      replace = FALSE
    ),
    simplify = FALSE
  )
  stability_summary <- map_dfr(
    stability_k,
    function(k) {
      full_fit <- diagnostic_fits[[which(diagnostic_k == k)]]
      set.seed(
        cluster_random_seed +
          100 * k +
          match(model_key, names(model_specs))
      )
      ari_values <- map_dbl(
        stability_sample_indices,
        function(sample_index) {
          sample_fit <- kmeans(
            scaled_data[sample_index, , drop = FALSE],
            centers = k,
            nstart = cluster_nstart
          )
          adjusted_rand_index(
            full_fit$cluster[sample_index],
            sample_fit$cluster
          )
        }
      )

      tibble(
        k = k,
        subsample_stability_median_ari = median(
          ari_values,
          na.rm = TRUE
        ),
        subsample_stability_p10_ari = as.numeric(quantile(
          ari_values,
          0.10,
          na.rm = TRUE,
          names = FALSE
        ))
      )
    }
  )

  set.seed(cluster_random_seed)
  gap_result <- cluster::clusGap(
    scaled_data,
    FUNcluster = function(model_data, k) {
      kmeans(model_data, centers = k, nstart = cluster_nstart)
    },
    K.max = max(diagnostic_k),
    B = experimental_gap_bootstraps,
    verbose = FALSE
  )
  gap_one_se_k <- cluster::maxSE(
    gap_result$Tab[, "gap"],
    gap_result$Tab[, "SE.sim"],
    method = "Tibs2001SEmax"
  )

  selected_fit <- diagnostic_fits[[
    which(diagnostic_k == selected_cluster_count)
  ]]
  assignments <- rep(NA_integer_, nrow(data))
  assignments[complete_index] <- selected_fit$cluster

  pca <- prcomp(scaled_data, center = FALSE, scale. = FALSE)
  first_pc_variance <- summary(pca)$importance[2, 1]

  diagnostics <- tibble(
    model = model_key,
    model_label = unname(model_labels[model_key]),
    model_family = specification$model_family,
    resident_context_squared_distance_share =
      specification$resident_context_share,
    input_count = length(variable_names),
    domain_count = n_distinct(variable_domains),
    k = diagnostic_k,
    within_cluster_sum_squares = wss,
    incremental_wss_reduction_percent = c(
      NA_real_,
      100 * (head(wss, -1) - tail(wss, -1)) / head(wss, -1)
    ),
    average_silhouette = average_silhouette,
    calinski_harabasz = calinski_harabasz,
    smallest_cluster = smallest_cluster,
    largest_cluster = largest_cluster,
    smallest_cluster_share = smallest_cluster / nrow(scaled_data),
    gap_statistic = gap_result$Tab[, "gap"],
    gap_standard_error = gap_result$Tab[, "SE.sim"],
    selected_for_proof_of_concept = k == selected_cluster_count,
    gap_one_se_recommendation = k == gap_one_se_k
  ) %>%
    left_join(stability_summary, by = "k")

  list(
    variables = variable_names,
    domains = variable_domains,
    weights = variable_weights,
    complete_index = complete_index,
    raw_data = raw_data,
    scaled_data_unweighted = scaled_data_unweighted,
    scaled_data = scaled_data,
    diagnostic_fits = diagnostic_fits,
    diagnostics = diagnostics,
    gap_one_se_k = gap_one_se_k,
    selected_fit = selected_fit,
    assignments = assignments,
    pca = pca,
    first_pc_variance = first_pc_variance
  )
}

cat("Evaluating baseline and experimental cluster specifications...\n")

model_results <- imap(
  model_specs,
  ~fit_cluster_model(census_data_normalized, .x, .y)
)

experimental_model_diagnostics <- map_dfr(model_results, "diagnostics")
baseline_result <- model_results$baseline
cluster_diagnostics <- baseline_result$diagnostics
gap_one_se_k <- baseline_result$gap_one_se_k
kmeans_result <- baseline_result$selected_fit
cluster_data <- baseline_result$raw_data
cluster_data_scaled <- baseline_result$scaled_data

census_data_normalized <- census_data_normalized %>%
  mutate(cluster_complete = baseline_result$complete_index)

cat(
  "Baseline diagnostic summary: silhouette selects k = ",
  cluster_diagnostics$k[which.max(cluster_diagnostics$average_silhouette)],
  "; Calinski-Harabasz selects k = ",
  cluster_diagnostics$k[which.max(cluster_diagnostics$calinski_harabasz)],
  "; gap one-SE selects k = ", gap_one_se_k, ".\n",
  sep = ""
)

# Retain the baseline five-cluster assignment for the principal proof of
# concept. Experimental assignments and diagnostics are exported separately.
cat("Retaining baseline k = ", selected_cluster_count, " for primary maps.\n", sep = "")

# Descriptive labels for the refactored five-cluster proof of concept. Labels
# use only cluster-defining people/service-fit, place, exposure, and access
# characteristics; overlay variables do not enter the names.
cluster_labels <- c(
  "1" = "High-Cost Family Areas with Low Exposure",
  "2" = "Family Areas with Moderate Transit and Elevated Exposure",
  "3" = "Family-Oriented Low-Transit Low-Exposure Areas",
  "4" = "Mixed-Household Moderate-Exposure Areas",
  "5" = "Transit-Rich Small-Household High-Exposure Areas"
)

cluster_palette <- c(
  "High-Cost Family Areas with Low Exposure" = "#1b9e77",
  "Family Areas with Moderate Transit and Elevated Exposure" = "#d95f02",
  "Family-Oriented Low-Transit Low-Exposure Areas" = "#66a61e",
  "Mixed-Household Moderate-Exposure Areas" = "#7570b3",
  "Transit-Rich Small-Household High-Exposure Areas" = "#e7298a",
  "Not clustered / missing input" = "#d9d9d9"
)

cluster_assignments <- rep(NA_character_, nrow(census_data_normalized))
cluster_assignments[census_data_normalized$cluster_complete] <- as.character(kmeans_result$cluster)

# Add cluster assignments back to the spatial data
census_data_clustered <- census_data_normalized %>%
  mutate(
    cluster = factor(cluster_assignments, levels = names(cluster_labels)),
    cluster_label = factor(
      if_else(
        is.na(cluster),
        "Not clustered / missing input",
        cluster_labels[as.character(cluster)]
      ),
      levels = names(cluster_palette)
    )
  )

# Assemble the selected-k assignments and comparison statistics for every
# experimental specification. Numeric cluster IDs are specification-specific;
# they should not be compared as if the same number represented the same type.
experimental_cluster_assignments <- tibble(GEOID = census_data_normalized$GEOID)

for (model_key in names(model_results)) {
  experimental_cluster_assignments[[paste0("experiment_cluster_", model_key)]] <-
    model_results[[model_key]]$assignments
}

census_data_clustered <- census_data_clustered %>%
  left_join(experimental_cluster_assignments, by = "GEOID")

baseline_assignments <- model_results$baseline$assignments
resident_context_reference_assignments <-
  model_results$resident_context_reference$assignments

experimental_model_summary <- imap_dfr(
  model_results,
  function(result, model_key) {
    diagnostics <- result$diagnostics
    selected_row <- diagnostics %>%
      filter(k == selected_cluster_count)
    cluster_sizes <- table(result$assignments)

    tibble(
      model = model_key,
      model_label = unname(model_labels[model_key]),
      model_family = model_specs[[model_key]]$model_family,
      resident_context_squared_distance_share =
        model_specs[[model_key]]$resident_context_share,
      input_count = length(result$variables),
      domain_count = n_distinct(result$domains),
      input_variables = str_c(result$variables, collapse = ";"),
      input_domains = str_c(result$domains, collapse = ";"),
      post_scale_weights = str_c(
        round(result$weights, 4),
        collapse = ";"
      ),
      complete_tracts = sum(result$complete_index),
      first_pc_variance_share = result$first_pc_variance,
      silhouette_recommended_k = diagnostics$k[
        which.max(diagnostics$average_silhouette)
      ],
      calinski_harabasz_recommended_k = diagnostics$k[
        which.max(diagnostics$calinski_harabasz)
      ],
      gap_one_se_recommended_k = result$gap_one_se_k,
      silhouette_at_selected_k = selected_row$average_silhouette,
      calinski_harabasz_at_selected_k = selected_row$calinski_harabasz,
      incremental_wss_reduction_at_selected_k =
        selected_row$incremental_wss_reduction_percent,
      smallest_selected_cluster = min(cluster_sizes),
      largest_selected_cluster = max(cluster_sizes),
      smallest_selected_cluster_share =
        min(cluster_sizes) / sum(cluster_sizes),
      subsample_stability_median_ari_k2 = diagnostics %>%
        filter(k == 2) %>%
        pull(subsample_stability_median_ari),
      subsample_stability_p10_ari_k2 = diagnostics %>%
        filter(k == 2) %>%
        pull(subsample_stability_p10_ari),
      subsample_stability_median_ari_selected_k =
        selected_row$subsample_stability_median_ari,
      subsample_stability_p10_ari_selected_k =
        selected_row$subsample_stability_p10_ari,
      adjusted_rand_vs_baseline = adjusted_rand_index(
        baseline_assignments,
        result$assignments
      ),
      adjusted_rand_vs_resident_context_reference = adjusted_rand_index(
        resident_context_reference_assignments,
        result$assignments
      )
    )
  }
)

experimental_model_input_weights <- imap_dfr(
  model_specs,
  function(specification, model_key) {
    total_squared_weight <- sum(specification$weights^2)
    domain_squared_weights <- tibble(
      domain = specification$domains,
      squared_weight = specification$weights^2
    ) %>%
      group_by(domain) %>%
      summarise(
        domain_squared_weight = sum(squared_weight),
        .groups = "drop"
      )

    tibble(
      model = model_key,
      model_label = unname(model_labels[model_key]),
      model_family = specification$model_family,
      input_variable = specification$variables,
      domain = specification$domains,
      post_standardization_weight = specification$weights,
      squared_weight = specification$weights^2,
      input_squared_distance_share =
        specification$weights^2 / total_squared_weight
    ) %>%
      left_join(domain_squared_weights, by = "domain") %>%
      mutate(
        domain_squared_distance_share =
          domain_squared_weight / total_squared_weight,
        resident_context_squared_distance_share =
          specification$resident_context_share
      )
  }
)

experimental_cluster_profiles <- imap_dfr(
  model_results,
  function(result, model_key) {
    census_data_normalized %>%
      st_drop_geometry() %>%
      mutate(experiment_cluster = factor(result$assignments)) %>%
      filter(!is.na(experiment_cluster)) %>%
      group_by(experiment_cluster) %>%
      summarise(
        n_tracts = n(),
        avg_home_value = mean(median_home_value, na.rm = TRUE),
        avg_household_size = mean(avg_household_size, na.rm = TRUE),
        avg_transit_jobs_45min = mean(transit_jobs_45min, na.rm = TRUE),
        avg_hazard_facilities_1mi = mean(
          hazard_facilities_1mi,
          na.rm = TRUE
        ),
        avg_annual_ksi_crash_density = mean(
          annual_ksi_crash_density,
          na.rm = TRUE
        ),
        avg_annual_new_housing_units_per_1000 = mean(
          annual_new_housing_units_per_1000,
          na.rm = TRUE
        ),
        avg_annual_demolition_permits_per_1000 = mean(
          annual_residential_demolition_permits_per_1000,
          na.rm = TRUE
        ),
        avg_low_intensity_structure_share = mean(
          low_intensity_structure_share,
          na.rm = TRUE
        ),
        avg_attached_small_structure_share = mean(
          attached_small_structure_share,
          na.rm = TRUE
        ),
        avg_medium_large_structure_share = mean(
          medium_large_structure_share,
          na.rm = TRUE
        ),
        avg_recent_2010_plus_share = mean(
          recent_2010_plus_share,
          na.rm = TRUE
        ),
        avg_local_jobs = mean(total_jobs, na.rm = TRUE),
        avg_resident_workers = mean(workers_all, na.rm = TRUE),
        avg_job_worker_balance = mean(
          jobs_resident_worker_balance,
          na.rm = TRUE
        ),
        avg_local_activity_density = mean(
          local_activity_density_per_sqmi,
          na.rm = TRUE
        ),
        avg_median_income = mean(median_income, na.rm = TRUE),
        avg_poverty_rate = mean(poverty_rate, na.rm = TRUE),
        avg_no_vehicle_share = mean(no_vehicle_share, na.rm = TRUE),
        avg_older_adult_share = mean(older_adult_share, na.rm = TRUE),
        avg_raw_disability_rate = mean(raw_disability_rate, na.rm = TRUE),
        avg_age_standardized_disability_rate = mean(
          age_standardized_disability_rate,
          na.rm = TRUE
        ),
        share_age_disability_input_imputed = mean(
          age_disability_input_imputed,
          na.rm = TRUE
        ),
        share_poverty_constraint_input_imputed = mean(
          poverty_constraint_input_imputed,
          na.rm = TRUE
        ),
        share_lower_income_overlay = mean(
          lower_income_overlay,
          na.rm = TRUE
        ),
        share_higher_poverty_overlay = mean(
          higher_poverty_overlay,
          na.rm = TRUE
        ),
        share_lower_employment_overlay = mean(
          lower_employment_overlay,
          na.rm = TRUE
        ),
        share_lower_education_overlay = mean(
          lower_education_overlay,
          na.rm = TRUE
        ),
        share_higher_no_vehicle_overlay = mean(
          higher_no_vehicle_overlay,
          na.rm = TRUE
        ),
        .groups = "drop"
      ) %>%
      mutate(
        model = model_key,
        model_label = unname(model_labels[model_key]),
        model_family = model_specs[[model_key]]$model_family,
        .before = 1
      )
  }
)

experimental_cluster_centers <- imap_dfr(
  model_results,
  function(result, model_key) {
    as_tibble(result$selected_fit$centers, rownames = "cluster") %>%
      mutate(
        model = model_key,
        model_label = unname(model_labels[model_key]),
        model_family = model_specs[[model_key]]$model_family,
        .before = 1
      )
  }
)

candidate_correlation_data <- cluster_data %>%
  mutate(
    current_first_principal_component = baseline_result$pca$x[, 1],
    development_pressure_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(development_pressure_cluster),
    built_form_intensity_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(built_form_intensity_cluster),
    multifamily_scale_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(multifamily_scale_cluster),
    recent_stock_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(recent_stock_cluster),
    local_activity_intensity_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(local_activity_intensity_cluster),
    job_worker_balance_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(job_worker_balance_cluster),
    older_adult_need_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(older_adult_need_cluster),
    age_standardized_disability_need_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(age_standardized_disability_need_cluster),
    poverty_constraint_cluster = census_data_normalized %>%
      st_drop_geometry() %>%
      filter(baseline_result$complete_index) %>%
      pull(poverty_constraint_cluster)
  )

experimental_candidate_correlations <- cor(
  candidate_correlation_data,
  use = "pairwise.complete.obs"
) %>%
  as.data.frame() %>%
  rownames_to_column("candidate_indicator") %>%
  as_tibble() %>%
  filter(candidate_indicator %in% c(
    "development_pressure_cluster",
    "built_form_intensity_cluster",
    "multifamily_scale_cluster",
    "recent_stock_cluster",
    "local_activity_intensity_cluster",
    "job_worker_balance_cluster",
    "older_adult_need_cluster",
    "age_standardized_disability_need_cluster",
    "poverty_constraint_cluster"
  )) %>%
  pivot_longer(
    cols = -candidate_indicator,
    names_to = "comparison_indicator",
    values_to = "correlation"
  ) %>%
  mutate(absolute_correlation = abs(correlation)) %>%
  arrange(candidate_indicator, desc(absolute_correlation))

overlay_percentile_variables <- c(
  "income_percentile", "poverty_burden_percentile",
  "employment_percentile", "educational_attainment_percentile",
  "no_vehicle_percentile"
)
overlay_flag_variables <- c(
  "lower_income_overlay", "higher_poverty_overlay",
  "lower_employment_overlay", "lower_education_overlay",
  "higher_no_vehicle_overlay"
)

experimental_overlay_sorting <- imap_dfr(
  model_results,
  function(result, model_key) {
    map_dfr(
      2:6,
      function(k) {
        assignments <- rep(NA_integer_, nrow(census_data_normalized))
        assignments[result$complete_index] <-
          result$diagnostic_fits[[k]]$cluster
        analysis_data <- census_data_normalized %>%
          st_drop_geometry() %>%
          mutate(experiment_cluster = factor(assignments))

        percentile_sorting <- map_dfr(
          overlay_percentile_variables,
          function(variable_name) {
            model_data <- tibble(
              outcome = analysis_data[[variable_name]],
              cluster = analysis_data$experiment_cluster
            ) %>%
              filter(!is.na(outcome), !is.na(cluster))
            fit <- lm(outcome ~ cluster, data = model_data)

            tibble(
              indicator = variable_name,
              measure_type = "percentile_between_cluster_variance",
              r_squared = summary(fit)$r.squared,
              adjusted_r_squared = summary(fit)$adj.r.squared,
              minimum_cluster_flagged_share = NA_real_,
              maximum_cluster_flagged_share = NA_real_,
              flagged_share_range = NA_real_
            )
          }
        )

        flag_sorting <- map_dfr(
          overlay_flag_variables,
          function(variable_name) {
            cluster_shares <- analysis_data %>%
              filter(!is.na(experiment_cluster)) %>%
              group_by(experiment_cluster) %>%
              summarise(
                flagged_share = mean(
                  .data[[variable_name]],
                  na.rm = TRUE
                ),
                .groups = "drop"
              )

            tibble(
              indicator = variable_name,
              measure_type = "binary_overlay_cluster_range",
              r_squared = NA_real_,
              adjusted_r_squared = NA_real_,
              minimum_cluster_flagged_share = min(
                cluster_shares$flagged_share,
                na.rm = TRUE
              ),
              maximum_cluster_flagged_share = max(
                cluster_shares$flagged_share,
                na.rm = TRUE
              ),
              flagged_share_range =
                maximum_cluster_flagged_share -
                  minimum_cluster_flagged_share
            )
          }
        )

        bind_rows(percentile_sorting, flag_sorting) %>%
          mutate(
            model = model_key,
            model_label = unname(model_labels[model_key]),
            model_family = model_specs[[model_key]]$model_family,
            k = k,
            indicator_used_as_input =
              indicator %in% c(
                "poverty_burden_percentile",
                "higher_poverty_overlay"
              ) &
              "poverty_constraint_cluster" %in% result$variables,
            .before = 1
          )
      }
    )
  }
)

built_form_model_keys <- names(model_specs)[map_lgl(
  model_specs,
  ~"built_form" %in% .x$domains
)]

built_form_reliability_sensitivity <- map_dfr(
  built_form_model_keys,
  function(model_key) {
    specification <- model_specs[[model_key]]
    reliable_index <-
      census_data_normalized$structure_composition_reliable &
      census_data_normalized$stock_age_reliable
    reliable_raw <- census_data_normalized %>%
      st_drop_geometry() %>%
      filter(reliable_index) %>%
      select(all_of(specification$variables))
    reliable_scaled <- sweep(
      scale(reliable_raw),
      MARGIN = 2,
      STATS = specification$weights,
      FUN = "*"
    )

    map_dfr(
      2:6,
      function(k) {
        set.seed(cluster_random_seed)
        sensitivity_fit <- kmeans(
          reliable_scaled,
          centers = k,
          nstart = cluster_nstart
        )
        full_assignments_on_reliable <-
          model_results[[model_key]]$diagnostic_fits[[k]]$cluster[
            reliable_index[
              model_results[[model_key]]$complete_index
            ]
          ]

        tibble(
          model = model_key,
          model_label = unname(model_labels[model_key]),
          k = k,
          reliable_tracts = sum(reliable_index),
          excluded_unreliable_tracts = sum(!reliable_index),
          average_silhouette = mean(
            cluster::silhouette(
              sensitivity_fit$cluster,
              dist(reliable_scaled)
            )[, 3]
          ),
          smallest_cluster = min(table(sensitivity_fit$cluster)),
          smallest_cluster_share =
            smallest_cluster / reliable_tracts,
          adjusted_rand_vs_primary_on_same_tracts = adjusted_rand_index(
            full_assignments_on_reliable,
            sensitivity_fit$cluster
          )
        )
      }
    )
  }
)

resident_context_model_keys <- names(model_specs)[map_lgl(
  model_specs,
  ~identical(.x$model_family, "resident_context")
)]
resident_context_model_diagnostics <- experimental_model_diagnostics %>%
  filter(model %in% resident_context_model_keys)
resident_context_model_summary <- experimental_model_summary %>%
  filter(model %in% resident_context_model_keys)
resident_context_cluster_profiles <- experimental_cluster_profiles %>%
  filter(model %in% resident_context_model_keys)

# Profiles for every policy-relevant candidate k make it possible to judge
# whether an apparently stable partition is also substantively actionable.
resident_context_candidate_cluster_profiles <- map_dfr(
  resident_context_model_keys,
  function(model_key) {
    result <- model_results[[model_key]]

    map_dfr(
      2:6,
      function(k) {
        assignments <- rep(NA_integer_, nrow(census_data_normalized))
        assignments[result$complete_index] <-
          result$diagnostic_fits[[k]]$cluster

        census_data_normalized %>%
          st_drop_geometry() %>%
          mutate(experiment_cluster = factor(assignments)) %>%
          filter(!is.na(experiment_cluster)) %>%
          group_by(experiment_cluster) %>%
          summarise(
            n_tracts = n(),
            avg_median_home_value = mean(
              median_home_value,
              na.rm = TRUE
            ),
            avg_median_rent = mean(median_rent, na.rm = TRUE),
            avg_household_size = mean(avg_household_size, na.rm = TRUE),
            avg_children_household_share = mean(
              children_household_share,
              na.rm = TRUE
            ),
            avg_older_adult_share = mean(
              older_adult_share,
              na.rm = TRUE
            ),
            avg_age_standardized_disability_rate = mean(
              age_standardized_disability_rate,
              na.rm = TRUE
            ),
            avg_transit_jobs_45min = mean(
              transit_jobs_45min,
              na.rm = TRUE
            ),
            avg_hazard_facilities_1mi = mean(
              hazard_facilities_1mi,
              na.rm = TRUE
            ),
            avg_annual_ksi_crash_density = mean(
              annual_ksi_crash_density,
              na.rm = TRUE
            ),
            avg_annual_new_housing_units_per_1000 = mean(
              annual_new_housing_units_per_1000,
              na.rm = TRUE
            ),
            avg_annual_demolition_permits_per_1000 = mean(
              annual_residential_demolition_permits_per_1000,
              na.rm = TRUE
            ),
            poverty_universe = sum(poverty_total, na.rm = TRUE),
            population_below_poverty = sum(
              poverty_below,
              na.rm = TRUE
            ),
            population_weighted_poverty_rate =
              population_below_poverty / poverty_universe,
            avg_no_vehicle_share = mean(
              no_vehicle_share,
              na.rm = TRUE
            ),
            share_age_disability_input_imputed = mean(
              age_disability_input_imputed,
              na.rm = TRUE
            ),
            share_poverty_constraint_input_imputed = mean(
              poverty_constraint_input_imputed,
              na.rm = TRUE
            ),
            .groups = "drop"
          ) %>%
          mutate(
            model = model_key,
            model_label = unname(model_labels[model_key]),
            k = k,
            poverty_used_as_cluster_input =
              "poverty_constraint_cluster" %in% result$variables,
            .before = 1
          )
      }
    )
  }
)

resident_context_candidate_cluster_assignments <- map_dfr(
  resident_context_model_keys,
  function(model_key) {
    result <- model_results[[model_key]]

    map_dfr(
      2:6,
      function(k) {
        assignments <- rep(NA_integer_, nrow(census_data_normalized))
        assignments[result$complete_index] <-
          result$diagnostic_fits[[k]]$cluster

        tibble(
          GEOID = census_data_normalized$GEOID,
          model = model_key,
          model_label = unname(model_labels[model_key]),
          k = k,
          cluster = assignments
        )
      }
    )
  }
)

# Refit the demographic-inclusive models on tracts meeting strict, primary,
# and permissive ACS reliability rules. The primary all-tract models use
# neutral median substitutions; this complete-case check reveals whether those
# substitutions materially change the solution.
reliability_tier_suffix <- c(
  strict_5pp = "_strict",
  primary_10pp = "",
  permissive_15pp = "_permissive"
)
resident_context_reliability_model_keys <- resident_context_model_keys[
  map_lgl(
    model_specs[resident_context_model_keys],
    ~length(.x$reliability_flags) > 0
  )
]

resident_context_reliability_sensitivity <- map_dfr(
  resident_context_reliability_model_keys,
  function(model_key) {
    specification <- model_specs[[model_key]]

    imap_dfr(
      reliability_tier_suffix,
      function(suffix, reliability_tier) {
        reliability_flags <- paste0(
          specification$reliability_flags,
          suffix
        )
        reliable_index <- reduce(
          reliability_flags,
          function(current, flag_name) {
            current & coalesce(census_data_normalized[[flag_name]], FALSE)
          },
          .init = rep(TRUE, nrow(census_data_normalized))
        )
        reliable_raw <- census_data_normalized %>%
          st_drop_geometry() %>%
          filter(reliable_index) %>%
          select(all_of(specification$variables))

        # Rebuild each screened coordinate from the published estimate for
        # this tier. In particular, permissive-only tracts must not retain the
        # neutral substitution used by the primary 10-point model.
        if ("older_adult_need_cluster" %in% specification$variables) {
          reliable_raw$older_adult_need_cluster <- winsorize(
            census_data_normalized$older_adult_logit_raw[reliable_index]
          )
        }
        if (
          "age_standardized_disability_need_cluster" %in%
            specification$variables
        ) {
          reliable_raw$age_standardized_disability_need_cluster <- winsorize(
            census_data_normalized$age_standardized_disability_logit_raw[
              reliable_index
            ]
          )
        }
        if ("poverty_constraint_cluster" %in% specification$variables) {
          reliable_raw$poverty_constraint_cluster <- winsorize(
            census_data_normalized$poverty_rate_logit_raw[reliable_index]
          )
        }

        reliable_scaled <- sweep(
          scale(reliable_raw),
          MARGIN = 2,
          STATS = specification$weights,
          FUN = "*"
        )

        map_dfr(
          2:6,
          function(k) {
            set.seed(cluster_random_seed)
            sensitivity_fit <- kmeans(
              reliable_scaled,
              centers = k,
              nstart = cluster_nstart
            )
            full_assignments_on_reliable <-
              model_results[[model_key]]$diagnostic_fits[[k]]$cluster[
                reliable_index[
                  model_results[[model_key]]$complete_index
                ]
              ]

            tibble(
              model = model_key,
              model_label = unname(model_labels[model_key]),
              reliability_tier = reliability_tier,
              k = k,
              reliable_tracts = sum(reliable_index),
              excluded_unreliable_tracts = sum(!reliable_index),
              average_silhouette = mean(cluster::silhouette(
                sensitivity_fit$cluster,
                dist(reliable_scaled)
              )[, 3]),
              smallest_cluster = min(table(sensitivity_fit$cluster)),
              smallest_cluster_share =
                smallest_cluster / reliable_tracts,
              adjusted_rand_vs_primary_on_same_tracts = adjusted_rand_index(
                full_assignments_on_reliable,
                sensitivity_fit$cluster
              )
            )
          }
        )
      }
    )
  }
)

# Race and ethnicity never enter clustering. Audit each resident-context model
# at k = 2:6 using population-weighted composition and sampling uncertainty.
race_ethnicity_audit_groups <- tribble(
  ~group, ~count_variable, ~count_moe_variable,
  ~share_moe_count_variable, ~share_moe_count_moe_variable,
  "People of color", "people_of_color_population", "people_of_color_population_moe",
  "nh_white_alone", "nh_white_alone_moe",
  "Hispanic or Latino (any race)", "hispanic_latino_any_race", "hispanic_latino_any_race_moe",
  "hispanic_latino_any_race", "hispanic_latino_any_race_moe",
  "Non-Hispanic Black alone", "nh_black_alone", "nh_black_alone_moe",
  "nh_black_alone", "nh_black_alone_moe",
  "Non-Hispanic Asian alone", "nh_asian_alone", "nh_asian_alone_moe",
  "nh_asian_alone", "nh_asian_alone_moe",
  "Non-Hispanic White alone", "nh_white_alone", "nh_white_alone_moe",
  "nh_white_alone", "nh_white_alone_moe"
)

experimental_race_ethnicity_audit <- map_dfr(
  resident_context_model_keys,
  function(model_key) {
    result <- model_results[[model_key]]

    map_dfr(
      2:6,
      function(k) {
        assignments <- rep(NA_integer_, nrow(census_data_normalized))
        assignments[result$complete_index] <-
          result$diagnostic_fits[[k]]$cluster

        pmap_dfr(
          race_ethnicity_audit_groups,
          function(
              group,
              count_variable,
              count_moe_variable,
              share_moe_count_variable,
              share_moe_count_moe_variable) {
            audit_data <- tibble(
              cluster = factor(assignments),
              group_population =
                census_data_normalized[[count_variable]],
              group_population_moe =
                census_data_normalized[[count_moe_variable]],
              share_moe_numerator =
                census_data_normalized[[share_moe_count_variable]],
              share_moe_numerator_moe =
                census_data_normalized[[share_moe_count_moe_variable]],
              total_population =
                census_data_normalized$race_ethnicity_total,
              total_population_moe =
                census_data_normalized$race_ethnicity_total_moe
            ) %>%
              filter(
                !is.na(cluster),
                !is.na(group_population),
                !is.na(total_population),
                total_population > 0
              )

            analytical_group_population <- sum(
              audit_data$group_population
            )
            analytical_total_population <- sum(
              audit_data$total_population
            )
            analytical_group_share <-
              analytical_group_population / analytical_total_population
            analytical_other_population <-
              analytical_total_population - analytical_group_population

            cluster_audit <- audit_data %>%
              group_by(cluster) %>%
              summarise(
                cluster_tracts = n(),
                group_population = sum(group_population),
                total_population = sum(total_population),
                group_population_moe = if_else(
                  any(is.na(group_population_moe)),
                  NA_real_,
                  sqrt(sum(group_population_moe^2))
                ),
                share_moe_numerator = sum(share_moe_numerator),
                share_moe_numerator_moe = if_else(
                  any(is.na(share_moe_numerator_moe)),
                  NA_real_,
                  sqrt(sum(share_moe_numerator_moe^2))
                ),
                total_population_moe = if_else(
                  any(is.na(total_population_moe)),
                  NA_real_,
                  sqrt(sum(total_population_moe^2))
                ),
                .groups = "drop"
              ) %>%
              mutate(
                cluster_group_share = group_population / total_population,
                cluster_group_share_moe = safe_moe_prop(
                  share_moe_numerator,
                  total_population,
                  share_moe_numerator_moe,
                  total_population_moe
                ),
                analytical_universe_group_share = analytical_group_share,
                cluster_minus_universe_percentage_points = 100 * (
                  cluster_group_share - analytical_group_share
                ),
                representation_ratio =
                  cluster_group_share / analytical_group_share,
                group_population_share_assigned_to_cluster =
                  group_population / analytical_group_population,
                other_population_share_assigned_to_cluster =
                  (total_population - group_population) /
                    analytical_other_population
              )

            dissimilarity_index <- if (
              analytical_group_population > 0 &&
                analytical_other_population > 0
            ) {
              0.5 * sum(abs(
                cluster_audit$group_population_share_assigned_to_cluster -
                  cluster_audit$other_population_share_assigned_to_cluster
              ))
            } else {
              NA_real_
            }

            cluster_audit %>%
              mutate(
                model = model_key,
                model_label = unname(model_labels[model_key]),
                k = k,
                group = group,
                group_versus_rest_dissimilarity_index =
                  dissimilarity_index,
                minimum_cluster_group_share = min(cluster_group_share),
                maximum_cluster_group_share = max(cluster_group_share),
                cluster_group_share_range =
                  maximum_cluster_group_share -
                    minimum_cluster_group_share,
                low_precision_flag =
                  total_population < demographic_min_universe |
                  is.na(cluster_group_share_moe) |
                  cluster_group_share_moe >
                    demographic_moe_strict_threshold,
                .before = 1
              )
          }
        )
      }
    )
  }
)

# A separate poverty guardrail makes direct socioeconomic sorting visible and
# avoids interpreting a poverty-defined cluster as intrinsically disadvantaged.
experimental_poverty_concentration_guardrail <- map_dfr(
  resident_context_model_keys,
  function(model_key) {
    result <- model_results[[model_key]]

    map_dfr(
      2:6,
      function(k) {
        assignments <- rep(NA_integer_, nrow(census_data_normalized))
        assignments[result$complete_index] <-
          result$diagnostic_fits[[k]]$cluster
        analysis_data <- census_data_normalized %>%
          st_drop_geometry() %>%
          mutate(experiment_cluster = factor(assignments)) %>%
          filter(!is.na(experiment_cluster))
        analytical_poverty_rate <-
          sum(analysis_data$poverty_below, na.rm = TRUE) /
            sum(analysis_data$poverty_total, na.rm = TRUE)

        analysis_data %>%
          group_by(experiment_cluster) %>%
          summarise(
            n_tracts = n(),
            poverty_universe = sum(poverty_total, na.rm = TRUE),
            population_below_poverty = sum(poverty_below, na.rm = TRUE),
            population_weighted_poverty_rate =
              population_below_poverty / poverty_universe,
            mean_tract_poverty_rate = mean(poverty_rate, na.rm = TRUE),
            share_higher_poverty_overlay = mean(
              higher_poverty_overlay,
              na.rm = TRUE
            ),
            share_poverty_constraint_imputed = mean(
              poverty_constraint_input_imputed,
              na.rm = TRUE
            ),
            .groups = "drop"
          ) %>%
          mutate(
            model = model_key,
            model_label = unname(model_labels[model_key]),
            k = k,
            poverty_used_as_cluster_input =
              "poverty_constraint_cluster" %in% result$variables,
            analytical_universe_poverty_rate = analytical_poverty_rate,
            cluster_minus_universe_percentage_points = 100 * (
              population_weighted_poverty_rate - analytical_poverty_rate
            ),
            poverty_representation_ratio =
              population_weighted_poverty_rate / analytical_poverty_rate,
            .before = 1
          )
      }
    )
  }
)

# ---- Mixed-data land-use and displacement-risk experiments ------------------

# Gower distance puts numeric ranges and nominal mismatches on a common 0-1
# scale. PAM then identifies observed medoid tracts rather than synthetic
# centroids. Each conceptual domain receives one unit of total Gower weight;
# variables within a multi-variable domain divide that unit equally.
make_gower_spec <- function(
    numeric_variables,
    categorical_variables,
    domains,
    label) {
  variables <- c(numeric_variables, categorical_variables)
  if (length(variables) != length(domains)) {
    stop("Every mixed-data variable must have one domain label.")
  }

  domain_counts <- table(domains)
  weights <- 1 / as.numeric(domain_counts[domains])

  list(
    numeric_variables = numeric_variables,
    categorical_variables = categorical_variables,
    variables = variables,
    domains = domains,
    weights = weights,
    label = label
  )
}

land_use_share_cluster_vars <- paste0(
  c(
    "share_residential", "share_mixed_use", "share_commercial_office",
    "share_industrial_logistics", "share_institutional_civic",
    "share_open_space", "share_transportation_utilities",
    "share_undeveloped_agricultural"
  ),
  "_cluster"
)

mixed_model_specs <- list(
  baseline_land_use_shares = make_gower_spec(
    c(cluster_vars, land_use_share_cluster_vars),
    character(),
    c(
      baseline_domains,
      rep("land_use_composition", length(land_use_share_cluster_vars))
    ),
    "Baseline + continuous land-use shares"
  ),
  baseline_land_use = make_gower_spec(
    cluster_vars,
    "land_use_category_cluster",
    c(baseline_domains, "land_use"),
    "Baseline + land use"
  ),
  baseline_displacement = make_gower_spec(
    cluster_vars,
    "displacement_risk_category_cluster",
    c(baseline_domains, "displacement_policy_context"),
    "Baseline + displacement risk"
  ),
  baseline_land_use_displacement = make_gower_spec(
    cluster_vars,
    c(
      "land_use_category_cluster",
      "displacement_risk_category_cluster"
    ),
    c(baseline_domains, "land_use", "displacement_policy_context"),
    "Baseline + land use + displacement risk"
  ),
  age_disability_land_use_shares = make_gower_spec(
    c(
      unified_place_vars,
      resident_needs_vars,
      land_use_share_cluster_vars
    ),
    character(),
    c(
      unified_place_domains,
      resident_needs_domains,
      rep("land_use_composition", length(land_use_share_cluster_vars))
    ),
    "Age/disability resident needs + continuous land-use shares"
  ),
  age_disability_land_use = make_gower_spec(
    c(unified_place_vars, resident_needs_vars),
    "land_use_category_cluster",
    c(
      unified_place_domains,
      resident_needs_domains,
      "land_use"
    ),
    "Age/disability resident needs + land use"
  ),
  resident_poverty_land_use = make_gower_spec(
    mixed_resident_context_vars,
    "land_use_category_cluster",
    c(mixed_resident_context_domains, "land_use"),
    "Age/disability/poverty + land use"
  ),
  resident_poverty_land_use_displacement = make_gower_spec(
    mixed_resident_context_vars,
    c(
      "land_use_category_cluster",
      "displacement_risk_category_cluster"
    ),
    c(
      mixed_resident_context_domains,
      "land_use",
      "displacement_policy_context"
    ),
    "Age/disability/poverty + land use + displacement risk"
  )
)

mixed_candidate_k <- 2:6

tract_neighbors <- st_touches(st_geometry(census_data_normalized))
tract_neighbor_edges <- map_dfr(
  seq_along(tract_neighbors),
  function(first_index) {
    second_indices <- tract_neighbors[[first_index]]
    second_indices <- second_indices[second_indices > first_index]
    tibble(first_index = first_index, second_index = second_indices)
  }
)

fit_gower_pam_model <- function(data, specification, model_key) {
  model_frame <- data %>%
    st_drop_geometry() %>%
    select(all_of(specification$variables))
  complete_index <- complete.cases(model_frame)
  complete_data <- model_frame[complete_index, , drop = FALSE]

  complete_data <- complete_data %>%
    mutate(
      across(
        all_of(specification$categorical_variables),
        ~droplevels(factor(.x))
      )
    )

  if (nrow(complete_data) <= max(mixed_candidate_k)) {
    stop("Too few complete tracts for mixed-data model: ", model_key)
  }

  gower_distance <- cluster::daisy(
    complete_data,
    metric = "gower",
    weights = specification$weights
  )
  distance_matrix <- as.matrix(gower_distance)

  diagnostic_fits <- set_names(
    lapply(
      mixed_candidate_k,
      function(k) cluster::pam(gower_distance, k = k, diss = TRUE)
    ),
    as.character(mixed_candidate_k)
  )

  stability_sample_size <- floor(
    nrow(complete_data) * experimental_stability_sample_share
  )
  set.seed(cluster_random_seed)
  stability_samples <- replicate(
    experimental_stability_bootstraps,
    sample.int(
      nrow(complete_data),
      size = stability_sample_size,
      replace = FALSE
    ),
    simplify = FALSE
  )

  stability_summary <- map_dfr(
    mixed_candidate_k,
    function(k) {
      full_assignment <- diagnostic_fits[[as.character(k)]]$clustering
      set.seed(
        cluster_random_seed +
          1000 * k +
          10 * match(model_key, names(mixed_model_specs))
      )
      ari_values <- map_dbl(
        stability_samples,
        function(sample_index) {
          sample_distance <- as.dist(
            distance_matrix[sample_index, sample_index, drop = FALSE]
          )
          sample_fit <- cluster::pam(
            sample_distance,
            k = k,
            diss = TRUE
          )
          adjusted_rand_index(
            full_assignment[sample_index],
            sample_fit$clustering
          )
        }
      )

      tibble(
        k = k,
        subsample_stability_median_ari = median(ari_values, na.rm = TRUE),
        subsample_stability_p10_ari = as.numeric(quantile(
          ari_values,
          0.10,
          na.rm = TRUE,
          names = FALSE
        ))
      )
    }
  )

  diagnostics <- map_dfr(
    mixed_candidate_k,
    function(k) {
      fit <- diagnostic_fits[[as.character(k)]]
      full_assignment <- rep(NA_integer_, nrow(data))
      full_assignment[complete_index] <- fit$clustering
      valid_edges <- tract_neighbor_edges %>%
        filter(
          !is.na(full_assignment[first_index]),
          !is.na(full_assignment[second_index])
        )

      tibble(
        model = model_key,
        model_label = specification$label,
        k = k,
        complete_tracts = sum(complete_index),
        average_silhouette = fit$silinfo$avg.width,
        pam_objective = unname(fit$objective[[2]]),
        smallest_cluster = min(table(fit$clustering)),
        largest_cluster = max(table(fit$clustering)),
        smallest_cluster_share = min(table(fit$clustering)) /
          length(fit$clustering),
        adjacent_pair_agreement = if (nrow(valid_edges) > 0) {
          mean(
            full_assignment[valid_edges$first_index] ==
              full_assignment[valid_edges$second_index]
          )
        } else {
          NA_real_
        }
      )
    }
  ) %>%
    left_join(stability_summary, by = "k")

  list(
    complete_index = complete_index,
    complete_data = complete_data,
    gower_distance = gower_distance,
    diagnostic_fits = diagnostic_fits,
    diagnostics = diagnostics
  )
}

cat("Evaluating Gower/PAM land-use and displacement-risk experiments...\n")
mixed_model_results <- imap(
  mixed_model_specs,
  ~fit_gower_pam_model(census_data_normalized, .x, .y)
)

mixed_model_diagnostics <- map_dfr(mixed_model_results, "diagnostics")

mixed_cluster_assignments <- imap_dfr(
  mixed_model_results,
  function(result, model_key) {
    map_dfr(
      mixed_candidate_k,
      function(k) {
        assignments <- rep(NA_integer_, nrow(census_data_normalized))
        assignments[result$complete_index] <-
          result$diagnostic_fits[[as.character(k)]]$clustering
        tibble(
          GEOID = census_data_normalized$GEOID,
          model = model_key,
          model_label = mixed_model_specs[[model_key]]$label,
          k = k,
          cluster = assignments
        )
      }
    )
  }
)

mixed_selected_assignments <- mixed_cluster_assignments %>%
  filter(k == selected_cluster_count) %>%
  select(GEOID, model, cluster) %>%
  pivot_wider(
    names_from = model,
    values_from = cluster,
    names_prefix = "mixed_cluster_"
  )

census_data_clustered <- census_data_clustered %>%
  left_join(mixed_selected_assignments, by = "GEOID")

mixed_model_summary <- imap_dfr(
  mixed_model_results,
  function(result, model_key) {
    specification <- mixed_model_specs[[model_key]]
    diagnostics <- result$diagnostics
    selected_row <- diagnostics %>%
      filter(k == selected_cluster_count)

    tibble(
      model = model_key,
      model_label = specification$label,
      method = "Gower distance + PAM",
      input_count = length(specification$variables),
      domain_count = n_distinct(specification$domains),
      numeric_inputs = str_c(
        specification$numeric_variables,
        collapse = ";"
      ),
      categorical_inputs = str_c(
        specification$categorical_variables,
        collapse = ";"
      ),
      complete_tracts = sum(result$complete_index),
      silhouette_recommended_k = diagnostics$k[
        which.max(diagnostics$average_silhouette)
      ],
      silhouette_at_selected_k = selected_row$average_silhouette,
      smallest_selected_cluster = selected_row$smallest_cluster,
      smallest_selected_cluster_share = selected_row$smallest_cluster_share,
      adjacent_pair_agreement_selected_k =
        selected_row$adjacent_pair_agreement,
      subsample_stability_median_ari_selected_k =
        selected_row$subsample_stability_median_ari,
      subsample_stability_p10_ari_selected_k =
        selected_row$subsample_stability_p10_ari,
      land_use_used_as_input =
        any(specification$domains %in% c("land_use", "land_use_composition")),
      displacement_risk_used_as_input =
        "displacement_risk_category_cluster" %in% specification$variables,
      displacement_input_embeds_vulnerability =
        "displacement_risk_category_cluster" %in% specification$variables
    )
  }
)

# Equal domain weight can allow a nominal category to become the partition.
# Refit categorical specifications across a prespecified influence range to
# distinguish robust multidimensional structure from category replication.
categorical_weight_multipliers <- c(0.10, 0.25, 0.50, 0.75, 1.00)
mixed_categorical_weight_sensitivity <- map_dfr(
  names(mixed_model_specs)[map_lgl(
    mixed_model_specs,
    ~length(.x$categorical_variables) > 0
  )],
  function(model_key) {
    specification <- mixed_model_specs[[model_key]]
    model_frame <- census_data_normalized %>%
      st_drop_geometry() %>%
      select(all_of(specification$variables))
    complete_index <- complete.cases(model_frame)
    complete_data <- model_frame[complete_index, , drop = FALSE] %>%
      mutate(
        across(
          all_of(specification$categorical_variables),
          ~droplevels(factor(.x))
        )
      )
    categorical_index <- specification$variables %in%
      specification$categorical_variables

    map_dfr(
      categorical_weight_multipliers,
      function(weight_multiplier) {
        sensitivity_weights <- specification$weights
        sensitivity_weights[categorical_index] <-
          sensitivity_weights[categorical_index] * weight_multiplier
        distance <- cluster::daisy(
          complete_data,
          metric = "gower",
          weights = sensitivity_weights
        )
        fits <- set_names(
          lapply(
            mixed_candidate_k,
            function(k) cluster::pam(distance, k = k, diss = TRUE)
          ),
          as.character(mixed_candidate_k)
        )
        silhouettes <- map_dbl(fits, ~.x$silinfo$avg.width)
        selected_assignment <-
          fits[[as.character(selected_cluster_count)]]$clustering

        tibble(
          model = model_key,
          model_label = specification$label,
          categorical_weight_multiplier = weight_multiplier,
          categorical_weight_share =
            sum(sensitivity_weights[categorical_index]) /
              sum(sensitivity_weights),
          silhouette_recommended_k = mixed_candidate_k[
            which.max(silhouettes)
          ],
          silhouette_at_selected_k = silhouettes[
            as.character(selected_cluster_count)
          ],
          smallest_selected_cluster = min(table(selected_assignment)),
          land_use_category_ari = if (
            "land_use_category_cluster" %in%
              specification$categorical_variables
          ) {
            adjusted_rand_index(
              selected_assignment,
              complete_data$land_use_category_cluster
            )
          } else {
            NA_real_
          },
          displacement_category_ari = if (
            "displacement_risk_category_cluster" %in%
              specification$categorical_variables
          ) {
            adjusted_rand_index(
              selected_assignment,
              complete_data$displacement_risk_category_cluster
            )
          } else {
            NA_real_
          }
        )
      }
    )
  }
)

mixed_model_input_weights <- imap_dfr(
  mixed_model_specs,
  function(specification, model_key) {
    tibble(
      model = model_key,
      model_label = specification$label,
      input_variable = specification$variables,
      variable_type = if_else(
        specification$variables %in% specification$categorical_variables,
        "nominal",
        "numeric"
      ),
      domain = specification$domains,
      gower_weight = specification$weights
    ) %>%
      group_by(model, domain) %>%
      mutate(
        domain_gower_weight = sum(gower_weight),
        domain_gower_weight_share = domain_gower_weight /
          sum(specification$weights)
      ) %>%
      ungroup()
  }
)

mixed_model_medoids <- imap_dfr(
  mixed_model_results,
  function(result, model_key) {
    complete_geoids <- census_data_normalized$GEOID[result$complete_index]
    map_dfr(
      mixed_candidate_k,
      function(k) {
        fit <- result$diagnostic_fits[[as.character(k)]]
        tibble(
          model = model_key,
          model_label = mixed_model_specs[[model_key]]$label,
          k = k,
          cluster = seq_along(fit$id.med),
          medoid_GEOID = complete_geoids[fit$id.med]
        )
      }
    )
  }
)

mixed_cluster_profiles <- mixed_cluster_assignments %>%
  left_join(
    census_data_normalized %>% st_drop_geometry(),
    by = "GEOID"
  ) %>%
  filter(!is.na(cluster)) %>%
  group_by(model, model_label, k, cluster) %>%
  summarise(
    n_tracts = n(),
    avg_home_value = mean(median_home_value, na.rm = TRUE),
    avg_household_size = mean(avg_household_size, na.rm = TRUE),
    avg_transit_jobs_45min = mean(transit_jobs_45min, na.rm = TRUE),
    avg_hazard_facilities_1mi = mean(hazard_facilities_1mi, na.rm = TRUE),
    avg_annual_ksi_crash_density = mean(
      annual_ksi_crash_density,
      na.rm = TRUE
    ),
    avg_older_adult_share = mean(older_adult_share, na.rm = TRUE),
    avg_age_standardized_disability_rate = mean(
      age_standardized_disability_rate,
      na.rm = TRUE
    ),
    population_weighted_poverty_rate =
      sum(poverty_below, na.rm = TRUE) /
        sum(poverty_total, na.rm = TRUE),
    avg_median_income = mean(median_income, na.rm = TRUE),
    avg_no_vehicle_share = mean(no_vehicle_share, na.rm = TRUE),
    avg_land_use_diversity = mean(
      normalized_land_use_diversity,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

mixed_categorical_profiles <- imap_dfr(
  mixed_model_specs,
  function(specification, model_key) {
    assignments <- mixed_cluster_assignments %>%
      filter(model == model_key)

    map_dfr(
      specification$categorical_variables,
      function(variable_name) {
        assignments %>%
          left_join(
            census_data_normalized %>%
              st_drop_geometry() %>%
              select(GEOID, all_of(variable_name)),
            by = "GEOID"
          ) %>%
          filter(!is.na(cluster), !is.na(.data[[variable_name]])) %>%
          count(k, cluster, category = .data[[variable_name]], name = "tracts") %>%
          group_by(k, cluster) %>%
          mutate(category_share = tracts / sum(tracts)) %>%
          ungroup() %>%
          mutate(
            model = model_key,
            model_label = specification$label,
            categorical_variable = variable_name,
            .before = 1
          )
      }
    )
  }
)

mixed_overlay_sorting <- mixed_cluster_assignments %>%
  left_join(
    census_data_normalized %>%
      st_drop_geometry() %>%
      select(GEOID, all_of(c(overlay_percentile_variables, overlay_flag_variables))),
    by = "GEOID"
  ) %>%
  group_by(model, model_label, k) %>%
  group_modify(
    ~{
      analysis_data <- .x %>% filter(!is.na(cluster))
      percentile_results <- map_dfr(
        overlay_percentile_variables,
        function(variable_name) {
          model_data <- analysis_data %>%
            transmute(
              outcome = .data[[variable_name]],
              cluster = factor(cluster)
            ) %>%
            filter(!is.na(outcome), !is.na(cluster))
          fit <- lm(outcome ~ cluster, data = model_data)
          tibble(
            indicator = variable_name,
            measure_type = "percentile_between_cluster_variance",
            r_squared = summary(fit)$r.squared,
            minimum_cluster_flagged_share = NA_real_,
            maximum_cluster_flagged_share = NA_real_,
            flagged_share_range = NA_real_
          )
        }
      )
      flag_results <- map_dfr(
        overlay_flag_variables,
        function(variable_name) {
          shares <- analysis_data %>%
            group_by(cluster) %>%
            summarise(
              flagged_share = mean(.data[[variable_name]], na.rm = TRUE),
              .groups = "drop"
            )
          tibble(
            indicator = variable_name,
            measure_type = "binary_overlay_cluster_range",
            r_squared = NA_real_,
            minimum_cluster_flagged_share = min(shares$flagged_share),
            maximum_cluster_flagged_share = max(shares$flagged_share),
            flagged_share_range = maximum_cluster_flagged_share -
              minimum_cluster_flagged_share
          )
        }
      )
      bind_rows(percentile_results, flag_results)
    }
  ) %>%
  ungroup() %>%
  mutate(
    poverty_directly_used_as_input = model %in% c(
      "resident_poverty_land_use",
      "resident_poverty_land_use_displacement"
    ),
    displacement_risk_used_as_input = str_detect(model, "displacement")
  )

mixed_race_ethnicity_audit <- pmap_dfr(
  race_ethnicity_audit_groups,
  function(
      group,
      count_variable,
      count_moe_variable,
      share_moe_count_variable,
      share_moe_count_moe_variable) {
    mixed_cluster_assignments %>%
      left_join(
        census_data_normalized %>%
          st_drop_geometry() %>%
          transmute(
            GEOID,
            group_population = .data[[count_variable]],
            total_population = race_ethnicity_total
          ),
        by = "GEOID"
      ) %>%
      filter(
        !is.na(cluster),
        !is.na(group_population),
        !is.na(total_population),
        total_population > 0
      ) %>%
      group_by(model, model_label, k) %>%
      mutate(
        analytical_group_share =
          sum(group_population) / sum(total_population)
      ) %>%
      group_by(model, model_label, k, cluster, analytical_group_share) %>%
      summarise(
        cluster_tracts = n(),
        group_population = sum(group_population),
        total_population = sum(total_population),
        .groups = "drop"
      ) %>%
      mutate(
        group = group,
        cluster_group_share = group_population / total_population,
        cluster_minus_universe_percentage_points = 100 * (
          cluster_group_share - analytical_group_share
        ),
        representation_ratio =
          cluster_group_share / analytical_group_share,
        .before = 1
      )
  }
)

cat("Mixed-data diagnostic summary:\n")
print(
  mixed_model_summary %>%
    select(
      model_label,
      complete_tracts,
      silhouette_recommended_k,
      silhouette_at_selected_k,
      smallest_selected_cluster,
      subsample_stability_median_ari_selected_k,
      adjacent_pair_agreement_selected_k
    )
)

# Create visualizations
cat("Creating visualizations...\n")

# 1. Elbow plot for cluster selection
elbow_plot <- ggplot(cluster_diagnostics, aes(x = k, y = within_cluster_sum_squares)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue", size = 3) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "#d95f02",
    linetype = "dashed"
  ) +
  labs(
    title = "Within-Cluster Variation by Candidate Cluster Count",
    subtitle = paste0(
      "Five clusters retained for policy-relevant detail; ",
      "see cluster_diagnostics.csv for separation metrics"
    ),
    x = "Number of Clusters",
    y = "Within-Cluster Sum of Squares"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14)
  )

# 2. Directional Place-and-Access Conditions Map
place_access_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = place_access_index), color = NA) +
  scale_fill_gradient2(
    low = "#d73027",
    mid = "#ffffbf",
    high = "#1a9850",
    midpoint = 0,
    name = "Place and Access\nConditions",
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Austin Place and Access Conditions by Census Tract",
    subtitle = paste0(
      "Higher transit access and lower EPA hazard/KSI crash exposure; ",
      "social and economic overlays excluded"
    ),
    caption = paste0(
      "Data: ", access_jobs_year, " LODES jobs; CapMetro ",
      access_snapshot_label, "; EPA FRS; Austin Open Data crash records"
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 3. K-means Cluster Map
cluster_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = cluster_label), color = "white", linewidth = 0.1) +
  scale_fill_manual(
    values = cluster_palette,
    name = "Place Profile"
  ) +
  labs(
    title = "Austin Census Tract Place Profiles",
    subtitle = paste0(
      "Five-cluster solution using housing market, family/service fit, transit, ",
      "hazard, and KSI crash indicators"
    ),
    caption = paste0(
      "Data: ACS ", acs_year, "; ", access_jobs_year,
      " LODES/2026 network; EPA FRS; Austin Open Data/CRIS. ",
      "Social and economic overlays excluded from clustering."
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 0, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank(),
    legend.position = c(0.04, 0.08),
    legend.justification = c(0, 0),
    legend.background = element_rect(fill = "white", color = NA),
    legend.text = element_text(size = 8)
  )

# 4. Median Income Map
income_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = median_income), color = NA) +
  scale_fill_viridis_c(
    option = "plasma",
    name = "Median\nIncome ($)",
    labels = scales::comma,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Overlay: Median Household Income by Census Tract",
    subtitle = "Post-clustering context and project screening; not used to define clusters",
    caption = paste0("Data: ACS ", acs_year, " 5-Year Estimates")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 5. Poverty Overlay Map
poverty_overlay_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = poverty_rate), color = NA) +
  scale_fill_viridis_c(
    option = "magma",
    name = "Poverty Rate",
    labels = scales::percent,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Overlay: Poverty Rate by Census Tract",
    subtitle = paste0(
      "Primary-model overlay; bounded input only in unified ",
      "resident-context experiments"
    ),
    caption = paste0("Data: ACS ", acs_year, " 5-Year Estimates")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 6. Transit Access Map
transit_access_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = transit_jobs_45min), color = NA) +
  scale_fill_viridis_c(
    option = "mako",
    name = paste0("Jobs by Transit\nwithin ", transit_threshold_minutes, " min"),
    labels = scales::comma,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Transit Access to Jobs by Census Tract",
    subtitle = paste0(
      "H8 access aggregated primarily with resident-worker weights; ",
      transit_threshold_minutes, "-minute walk-plus-transit threshold"
    ),
    caption = paste0(
      "Data: ", access_jobs_year,
      " LODES jobs; CapMetro ", access_snapshot_label
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 7. Environmental Hazard Exposure Map
environmental_hazard_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = hazard_facilities_1mi), color = NA) +
  scale_fill_viridis_c(
    option = "inferno",
    trans = "sqrt",
    name = paste0("EPA Candidates\nwithin ", exposure_buffer_miles, " mile"),
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "EPA Environmental-Hazard Candidate Proximity",
    subtitle = "Unique candidate facilities near each tract's internal representative point",
    caption = paste0(
      "Data: EPA Facility Registry Service",
      if_else(
        is.na(hazard_download_date),
        "",
        paste0("; downloaded ", hazard_download_date)
      )
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 8. KSI Crash Exposure Map
crash_injury_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = annual_ksi_crash_density), color = NA) +
  scale_fill_viridis_c(
    option = "rocket",
    trans = "sqrt",
    name = "Annual KSI Crashes\nper sq. mile",
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Fatal and Suspected-Serious-Injury Crash Exposure",
    subtitle = paste0(
      crash_source_year_label,
      " average within the City-observed portion of each one-mile window"
    ),
    caption = "Data: City of Austin Open Data, derived from TxDOT CRIS"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 9. Households with Children Map
family_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = children_household_share), color = NA) +
  scale_fill_viridis_c(
    option = "viridis",
    name = "Households\nwith Children",
    labels = scales::percent,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Households with Children by Census Tract",
    subtitle = "Non-stigmatizing people/service-fit input used in clustering",
    caption = paste0("Data: ACS ", acs_year, " 5-Year Estimates")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 10. No-Vehicle Overlay Map
no_vehicle_overlay_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = no_vehicle_share), color = NA) +
  scale_fill_viridis_c(
    option = "cividis",
    name = "Households with\nNo Vehicle",
    labels = scales::percent,
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Overlay: Households without a Vehicle",
    subtitle = "Transportation context and project screening; not used to define clusters",
    caption = paste0("Data: ACS ", acs_year, " 5-Year Estimates")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 11. Experimental Residential Development Pressure Map
development_pressure_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = development_pressure_cluster), color = NA) +
  scale_fill_gradient2(
    low = "#2166ac",
    mid = "#f7f7f7",
    high = "#b2182b",
    midpoint = 0,
    name = "Relative Development\nPressure",
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Experimental Residential Development-Pressure Profile",
    subtitle = paste0(
      "2020–2024 new housing and residential demolition activity, ",
      "normalized by housing stock"
    ),
    caption = paste0(
      "Data: City of Austin issued construction permits; ",
      scales::percent(development_coordinate_coverage, accuracy = 0.1),
      " of classified records geocoded"
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 12. Experimental Built-Form Map
built_form_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = built_form_intensity_ilr), color = NA) +
  scale_fill_gradient2(
    low = "#762a83",
    mid = "#f7f7f7",
    high = "#1b7837",
    midpoint = 0,
    name = "Housing Structure\nComposition (ILR)",
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Experimental Housing-Stock Built Form",
    subtitle = paste0(
      "Higher values indicate more detached/mobile-home structure; ",
      "lower values indicate more multifamily structure"
    ),
    caption = paste0(
      "Data: ACS ", acs_year,
      " 5-Year Estimates. Grey tracts fail the primary MOE/denominator rule."
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 13. Experimental Functional-Role Map
functional_role_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = jobs_resident_worker_balance), color = NA) +
  scale_fill_gradient2(
    low = "#2166ac",
    mid = "#f7f7f7",
    high = "#b2182b",
    midpoint = 0,
    limits = c(-1, 1),
    name = "Jobs–Resident\nWorker Balance",
    na.value = "#d9d9d9"
  ) +
  labs(
    title = "Experimental Local Functional Role",
    subtitle = paste0(
      "Negative values indicate resident-worker orientation; ",
      "positive values indicate employment-center orientation"
    ),
    caption = paste0(
      "Data: ", access_jobs_year,
      " Census LODES WAC/RAC; activity intensity is a second model input."
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 10),
    plot.caption = element_text(hjust = 1, size = 8),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

# 14. Experimental Cluster-Separation Comparison
experimental_diagnostics_plot <- experimental_model_diagnostics %>%
  filter(model_family == "place_candidate", k >= 2) %>%
  mutate(
    plot_model_label = factor(
      unname(model_plot_labels[model]),
      levels = unname(model_plot_labels)
    )
  ) %>%
  ggplot(aes(x = k, y = average_silhouette, color = plot_model_label)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "grey35",
    linetype = "dashed"
  ) +
  scale_x_continuous(breaks = 2:10) +
  labs(
    title = "Cluster Separation across Experimental Specifications",
    subtitle = "Higher average silhouette indicates clearer separation; dashed line marks k = 5",
    x = "Number of Clusters",
    y = "Average Silhouette Width",
    color = "Specification"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 8),
    legend.position = "bottom"
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

# 15. Experimental Subsample-Stability Comparison
experimental_stability_plot <- experimental_model_diagnostics %>%
  filter(model_family == "place_candidate", k %in% 2:6) %>%
  mutate(
    plot_model_label = factor(
      unname(model_plot_labels[model]),
      levels = unname(model_plot_labels)
    )
  ) %>%
  ggplot(aes(
    x = k,
    y = subsample_stability_median_ari,
    color = plot_model_label
  )) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "grey35",
    linetype = "dashed"
  ) +
  scale_x_continuous(breaks = 2:6) +
  coord_cartesian(ylim = c(0, 1)) +
  labs(
    title = "Subsample Stability across Experimental Specifications",
    subtitle = paste0(
      "Median adjusted Rand index across ",
      experimental_stability_bootstraps,
      " 80% subsamples; higher values indicate more reproducible assignments"
    ),
    x = "Number of Clusters",
    y = "Median Subsample Adjusted Rand Index",
    color = "Specification"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 8),
    legend.position = "bottom"
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

# 16. Unified Resident-Context Cluster-Separation Comparison
resident_context_plot_labels <- model_plot_labels[
  resident_context_model_keys
]
resident_context_diagnostics_plot <- resident_context_model_diagnostics %>%
  filter(k >= 2) %>%
  mutate(
    plot_model_label = factor(
      unname(resident_context_plot_labels[model]),
      levels = unname(resident_context_plot_labels)
    )
  ) %>%
  ggplot(aes(x = k, y = average_silhouette, color = plot_model_label)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "grey35",
    linetype = "dashed"
  ) +
  scale_x_continuous(breaks = 2:10) +
  labs(
    title = "Cluster Separation in Unified Resident-Context Experiments",
    subtitle = paste0(
      "Resident-context shares refer to squared Euclidean distance; ",
      "dashed line marks k = 5"
    ),
    x = "Number of Clusters",
    y = "Average Silhouette Width",
    color = "Specification"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 8),
    legend.position = "bottom"
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

# 17. Unified Resident-Context Subsample-Stability Comparison
resident_context_stability_plot <- resident_context_model_diagnostics %>%
  filter(k %in% 2:6) %>%
  mutate(
    plot_model_label = factor(
      unname(resident_context_plot_labels[model]),
      levels = unname(resident_context_plot_labels)
    )
  ) %>%
  ggplot(aes(
    x = k,
    y = subsample_stability_median_ari,
    color = plot_model_label
  )) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "grey35",
    linetype = "dashed"
  ) +
  scale_x_continuous(breaks = 2:6) +
  coord_cartesian(ylim = c(0, 1)) +
  labs(
    title = "Stability of Unified Resident-Context Experiments",
    subtitle = paste0(
      "Median adjusted Rand index across ",
      experimental_stability_bootstraps,
      " paired 80% subsamples"
    ),
    x = "Number of Clusters",
    y = "Median Subsample Adjusted Rand Index",
    color = "Specification"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 8),
    legend.position = "bottom"
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

# 18. Mixed-Data Separation and Stability
mixed_diagnostics_plot <- mixed_model_diagnostics %>%
  mutate(
    plot_model_label = factor(
      model_label,
      levels = map_chr(mixed_model_specs, "label")
    )
  ) %>%
  ggplot(aes(x = k, y = average_silhouette, color = plot_model_label)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "grey35",
    linetype = "dashed"
  ) +
  scale_x_continuous(breaks = mixed_candidate_k) +
  labs(
    title = "Separation in Mixed-Data Land-Use and Displacement Experiments",
    subtitle = "Gower distance with PAM; dashed line marks the five-cluster comparison",
    x = "Number of Clusters",
    y = "Average Silhouette Width",
    color = "Specification"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 8),
    legend.position = "bottom"
  ) +
  guides(color = guide_legend(nrow = 3, byrow = TRUE))

mixed_stability_plot <- mixed_model_diagnostics %>%
  mutate(
    plot_model_label = factor(
      model_label,
      levels = map_chr(mixed_model_specs, "label")
    )
  ) %>%
  ggplot(aes(
    x = k,
    y = subsample_stability_median_ari,
    color = plot_model_label
  )) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(
    xintercept = selected_cluster_count,
    color = "grey35",
    linetype = "dashed"
  ) +
  scale_x_continuous(breaks = mixed_candidate_k) +
  coord_cartesian(ylim = c(0, 1)) +
  labs(
    title = "Stability of Mixed-Data Land-Use and Displacement Experiments",
    subtitle = paste0(
      "Median adjusted Rand index across ",
      experimental_stability_bootstraps,
      " paired 80% subsamples"
    ),
    x = "Number of Clusters",
    y = "Median Subsample Adjusted Rand Index",
    color = "Specification"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 8),
    legend.position = "bottom"
  ) +
  guides(color = guide_legend(nrow = 3, byrow = TRUE))

mixed_categorical_weight_sensitivity_plot <-
  mixed_categorical_weight_sensitivity %>%
  mutate(
    silhouette_recommended_k = factor(silhouette_recommended_k),
    model_label = factor(
      model_label,
      levels = map_chr(
        mixed_model_specs[map_lgl(
          mixed_model_specs,
          ~length(.x$categorical_variables) > 0
        )],
        "label"
      )
    )
  ) %>%
  ggplot(aes(
    x = categorical_weight_multiplier,
    y = silhouette_at_selected_k,
    color = silhouette_recommended_k
  )) +
  geom_line(aes(group = 1), color = "grey55", linewidth = 0.6) +
  geom_point(size = 2.4) +
  facet_wrap(vars(model_label), ncol = 2) +
  scale_x_continuous(breaks = categorical_weight_multipliers) +
  labs(
    title = "Sensitivity to Categorical-Input Weight",
    subtitle = paste0(
      "Points show five-cluster silhouette; color shows silhouette-selected k. ",
      "A multiplier of 1 gives each categorical domain full weight."
    ),
    x = "Categorical Domain Weight Multiplier",
    y = "Average Silhouette Width at k = 5",
    color = "Selected k"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    strip.text = element_text(face = "bold", size = 9),
    legend.position = "bottom"
  )

mixed_map_data <- census_data_normalized %>%
  select(GEOID) %>%
  left_join(
    mixed_cluster_assignments %>%
      filter(k == selected_cluster_count),
    by = "GEOID"
  ) %>%
  mutate(
    cluster = factor(cluster, levels = seq_len(selected_cluster_count)),
    model_label = factor(
      str_wrap(model_label, width = 42),
      levels = str_wrap(map_chr(mixed_model_specs, "label"), width = 42)
    )
  )

mixed_cluster_comparison_map <- ggplot(mixed_map_data) +
  geom_sf(aes(fill = cluster), color = "white", linewidth = 0.05) +
  facet_wrap(vars(model_label), ncol = 2) +
  scale_fill_brewer(
    palette = "Set1",
    na.value = "#D9D9D9",
    name = "Cluster ID"
  ) +
  coord_sf(datum = NA) +
  labs(
    title = "Five-Cluster Mixed-Data Comparison",
    subtitle = paste0(
      "Cluster IDs are model-specific and are not equivalent across panels; ",
      "grey tracts lack a required land-use or displacement input"
    ),
    caption = "Gower distance and partitioning around medoids (PAM)"
  ) +
  theme_void(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold", size = 9),
    legend.position = "bottom"
  )

land_use_category_map <- ggplot(census_data_clustered) +
  geom_sf(aes(fill = land_use_category), color = "white", linewidth = 0.08) +
  scale_fill_manual(
    values = c(
      "Residential dominant" = "#F4E04D",
      "Residential and open-space mix" = "#D9C84A",
      "Mixed residential and activity" = "#E69F00",
      "Employment and special-purpose" = "#8E44AD",
      "Open space and undeveloped" = "#009E73",
      "Mixed / other" = "#CC79A7",
      "Unknown / insufficient inventory" = "#D9D9D9"
    ),
    drop = FALSE,
    name = "Land-use category"
  ) +
  coord_sf(datum = NA) +
  labs(
    title = "Broad Tract Land-Use Category",
    subtitle = "Continuous parcel-area shares are retained in the analytical file",
    caption = "Source: City of Austin Land Use Inventory Detailed"
  ) +
  theme_void(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "bottom"
  ) +
  guides(fill = guide_legend(ncol = 2, byrow = TRUE))

displacement_risk_category_map <- ggplot(census_data_clustered) +
  geom_sf(
    aes(fill = displacement_risk_category_display),
    color = "white",
    linewidth = 0.08
  ) +
  scale_fill_manual(
    values = c(
      "No published displacement-risk designation" = "#D9D9D9",
      "Vulnerable" = "#FEC44F",
      "Active Displacement Risk" = "#FC8D59",
      "Chronic Displacement Risk" = "#B30000",
      "Unknown / outside published coverage" = "#6A51A3"
    ),
    drop = FALSE,
    name = "Published category"
  ) +
  coord_sf(datum = NA) +
  labs(
    title = "City-Updated Displacement-Risk Category",
    subtitle = "Derived from the Uprooted framework; unknown coverage is not treated as no designation",
    caption = "Source: City of Austin Displacement Risk Areas 2022"
  ) +
  theme_void(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "bottom"
  ) +
  guides(fill = guide_legend(ncol = 2, byrow = TRUE))

# Save plots
cat("Saving plots...\n")

ggsave(file.path(output_dir, "elbow_plot.png"), elbow_plot, width = 10, height = 6, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "place_access_conditions_map.png"), place_access_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "cluster_map.png"), cluster_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "income_overlay_map.png"), income_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "poverty_overlay_map.png"), poverty_overlay_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "transit_access_map.png"), transit_access_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "environmental_hazard_map.png"), environmental_hazard_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "crash_injury_map.png"), crash_injury_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "family_map.png"), family_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "no_vehicle_overlay_map.png"), no_vehicle_overlay_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "development_pressure_experiment_map.png"), development_pressure_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "built_form_experiment_map.png"), built_form_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "functional_role_experiment_map.png"), functional_role_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "experimental_cluster_diagnostics.png"), experimental_diagnostics_plot, width = 12, height = 8.5, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "experimental_cluster_stability.png"), experimental_stability_plot, width = 12, height = 8.5, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "resident_context_cluster_diagnostics.png"), resident_context_diagnostics_plot, width = 12, height = 8.5, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "resident_context_cluster_stability.png"), resident_context_stability_plot, width = 12, height = 8.5, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "mixed_model_diagnostics.png"), mixed_diagnostics_plot, width = 12, height = 8.5, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "mixed_model_stability.png"), mixed_stability_plot, width = 12, height = 8.5, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "mixed_categorical_weight_sensitivity.png"), mixed_categorical_weight_sensitivity_plot, width = 12, height = 12, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "mixed_cluster_comparison_map.png"), mixed_cluster_comparison_map, width = 13, height = 15, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "land_use_category_map.png"), land_use_category_map, width = 12, height = 10, dpi = 300, bg = "white")
ggsave(file.path(output_dir, "displacement_risk_category_map.png"), displacement_risk_category_map, width = 12, height = 10, dpi = 300, bg = "white")

# Summarize cluster-defining indicators separately from post-clustering
# overlays so the reporting structure mirrors the methodological distinction.
cat("\n=== Cluster-Defining Profiles ===\n")

cluster_stats <- census_data_clustered %>%
  st_drop_geometry() %>%
  filter(!is.na(cluster)) %>%
  group_by(cluster, cluster_label) %>%
  summarise(
    n_tracts = n(),
    avg_home_value = mean(median_home_value, na.rm = TRUE),
    avg_median_rent = mean(median_rent, na.rm = TRUE),
    avg_household_size = mean(avg_household_size, na.rm = TRUE),
    avg_children_household_share = mean(children_household_share, na.rm = TRUE),
    avg_transit_jobs_45min = mean(transit_jobs_45min, na.rm = TRUE),
    avg_hazard_facilities_1mi = mean(hazard_facilities_1mi, na.rm = TRUE),
    avg_annual_ksi_crash_density = mean(
      annual_ksi_crash_density,
      na.rm = TRUE
    ),
    avg_annual_vru_ksi_crash_density = mean(
      annual_vru_ksi_crash_density,
      na.rm = TRUE
    ),
    avg_place_access_index = mean(place_access_index, na.rm = TRUE),
    share_cluster_input_imputed = mean(cluster_input_imputed, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(cluster)

print(cluster_stats)

cat("\n=== Post-Clustering Social and Economic Overlays ===\n")

cluster_overlay_summary <- census_data_clustered %>%
  st_drop_geometry() %>%
  filter(!is.na(cluster)) %>%
  group_by(cluster, cluster_label) %>%
  summarise(
    n_tracts = n(),
    avg_median_income = mean(median_income, na.rm = TRUE),
    avg_poverty_rate = mean(poverty_rate, na.rm = TRUE),
    avg_employment_rate = mean(employment_rate, na.rm = TRUE),
    avg_educational_attainment = mean(educational_attainment, na.rm = TRUE),
    avg_no_vehicle_share = mean(no_vehicle_share, na.rm = TRUE),
    avg_older_adult_share = mean(older_adult_share, na.rm = TRUE),
    avg_raw_disability_rate = mean(raw_disability_rate, na.rm = TRUE),
    avg_age_standardized_disability_rate = mean(
      age_standardized_disability_rate,
      na.rm = TRUE
    ),
    share_lower_income_overlay = mean(lower_income_overlay, na.rm = TRUE),
    share_higher_poverty_overlay = mean(higher_poverty_overlay, na.rm = TRUE),
    share_lower_employment_overlay = mean(lower_employment_overlay, na.rm = TRUE),
    share_lower_education_overlay = mean(lower_education_overlay, na.rm = TRUE),
    share_higher_no_vehicle_overlay = mean(higher_no_vehicle_overlay, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(cluster)

print(cluster_overlay_summary)

cat("\n=== Experimental Specification Comparison ===\n")
print(
  experimental_model_summary %>%
    select(
      model_label, input_count, domain_count, first_pc_variance_share,
      resident_context_squared_distance_share,
      silhouette_recommended_k, calinski_harabasz_recommended_k,
      gap_one_se_recommended_k, silhouette_at_selected_k,
      smallest_selected_cluster, largest_selected_cluster,
      subsample_stability_median_ari_k2,
      subsample_stability_median_ari_selected_k,
      adjusted_rand_vs_baseline,
      adjusted_rand_vs_resident_context_reference
    )
)

overlay_filter_columns <- c(
  "lower_income_overlay", "higher_poverty_overlay",
  "lower_employment_overlay", "lower_education_overlay",
  "higher_no_vehicle_overlay"
)

cluster_overlay_crosstab <- census_data_clustered %>%
  st_drop_geometry() %>%
  filter(!is.na(cluster)) %>%
  select(cluster, cluster_label, all_of(overlay_filter_columns)) %>%
  pivot_longer(
    cols = all_of(overlay_filter_columns),
    names_to = "overlay_filter",
    values_to = "flagged"
  ) %>%
  group_by(cluster, cluster_label, overlay_filter) %>%
  summarise(
    tracts_with_data = sum(!is.na(flagged)),
    flagged_tracts = sum(flagged, na.rm = TRUE),
    flagged_share = mean(flagged, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(cluster, overlay_filter)

cluster_centers <- as_tibble(
  kmeans_result$centers,
  rownames = "cluster"
) %>%
  mutate(
    cluster_label = cluster_labels[cluster],
    .after = cluster
  )

cluster_input_correlations <- cor(
  cluster_data,
  use = "pairwise.complete.obs"
) %>%
  as.data.frame() %>%
  rownames_to_column("cluster_input") %>%
  as_tibble()

cluster_input_missingness <- tibble(
  source_indicator = c(
    "median_home_value", "median_rent", "avg_household_size",
    "children_household_share", "transit_jobs_45min",
    "hazard_facilities_1mi", "annual_ksi_crash_density"
  ),
  missing_tracts = map_int(
    source_indicator,
    ~sum(is.na(census_data_clustered[[.x]]))
  ),
  handling = c(
    "Use rent component when available; neutral profile if both housing components are missing",
    "Use home-value component when available; neutral profile if both housing components are missing",
    "Median imputation before family/service-fit composite",
    "Median imputation before family/service-fit composite",
    "Median imputation",
    "No imputation expected; zero is a valid count",
    "No imputation expected; zero is a valid density"
  )
)

analysis_qaqc_summary <- tibble(
  metric = c(
    "acs_year",
    "city_boundary_year",
    "analysis_tracts",
    "cluster_count",
    "silhouette_recommended_cluster_count",
    "calinski_harabasz_recommended_cluster_count",
    "gap_one_se_recommended_cluster_count",
    "cluster_input_count",
    "tracts_with_imputed_cluster_input",
    "tracts_missing_both_housing_components",
    "tracts_with_missing_overlay_input",
    "exposure_buffer_miles",
    "epa_hazard_candidate_facilities",
    "epa_frs_download_date",
    "ksi_crash_records",
    "ksi_crash_analysis_years",
    "crash_data_retrieved_at_utc",
    "development_permit_records",
    "development_permit_analysis_years",
    "development_permit_coordinate_coverage",
    "development_permit_retrieved_at_utc",
    "lodes_functional_role_year",
    "tract_functional_role_source_records",
    "city_tract_local_jobs",
    "city_tract_resident_workers",
    "city_tracts_with_zero_local_activity",
    "built_form_reliable_tracts_primary_20pp",
    "built_form_unreliable_tracts_primary_20pp",
    "built_form_reliable_tracts_sensitivity_15pp",
    "built_form_structure_reconciliation_failures",
    "built_form_housing_table_total_reconciliation_failures",
    "built_form_share_bounds_or_sum_failures",
    "built_form_winsorized_coordinate_values",
    "experimental_model_count",
    "experimental_gap_bootstraps",
    "experimental_stability_bootstraps",
    "experimental_stability_sample_share",
    "tracts_with_missing_experimental_input",
    "tracts_with_imputed_built_form_input",
    "tracts_with_imputed_functional_role_input",
    "access_jobs_year",
    "access_network_snapshot"
  ),
  value = c(
    as.character(acs_year),
    as.character(city_boundary_year),
    as.character(nrow(census_data_clustered)),
    as.character(length(cluster_labels)),
    as.character(
      cluster_diagnostics$k[which.max(cluster_diagnostics$average_silhouette)]
    ),
    as.character(
      cluster_diagnostics$k[which.max(cluster_diagnostics$calinski_harabasz)]
    ),
    as.character(gap_one_se_k),
    as.character(length(cluster_vars)),
    as.character(sum(census_data_clustered$cluster_input_imputed)),
    as.character(sum(
      is.na(census_data_clustered$median_home_value) &
        is.na(census_data_clustered$median_rent)
    )),
    as.character(sum(census_data_clustered$missing_overlay_input)),
    as.character(exposure_buffer_miles),
    as.character(nrow(environmental_hazards)),
    hazard_download_date,
    as.character(nrow(ksi_crashes)),
    crash_source_year_label,
    crash_retrieved_at_utc,
    as.character(nrow(development_permits)),
    str_c(range(development_analysis_years), collapse = "–"),
    as.character(development_coordinate_coverage),
    development_retrieved_at_utc,
    as.character(access_jobs_year),
    as.character(nrow(tract_functional_role)),
    as.character(sum(census_data_clustered$total_jobs, na.rm = TRUE)),
    as.character(sum(census_data_clustered$workers_all, na.rm = TRUE)),
    as.character(sum(
      census_data_clustered$local_jobs_and_workers == 0,
      na.rm = TRUE
    )),
    as.character(sum(
      census_data_clustered$structure_composition_reliable &
        census_data_clustered$stock_age_reliable,
      na.rm = TRUE
    )),
    as.character(sum(census_data_clustered$built_form_input_imputed)),
    as.character(sum(
      census_data_clustered$structure_composition_reliable_15pp &
        census_data_clustered$stock_age_reliable_15pp,
      na.rm = TRUE
    )),
    as.character(sum(
      !census_data_clustered$structure_counts_reconcile |
        is.na(census_data_clustered$structure_counts_reconcile)
    )),
    as.character(sum(
      abs(
        census_data_clustered$structure_units_total -
          census_data_clustered$housing_units_total
      ) > 0.5 |
        abs(
          census_data_clustered$structure_year_total -
            census_data_clustered$housing_units_total
        ) > 0.5,
      na.rm = TRUE
    )),
    as.character(sum(
      census_data_clustered$low_intensity_structure_share < 0 |
        census_data_clustered$low_intensity_structure_share > 1 |
        census_data_clustered$attached_small_structure_share < 0 |
        census_data_clustered$attached_small_structure_share > 1 |
        census_data_clustered$medium_large_structure_share < 0 |
        census_data_clustered$medium_large_structure_share > 1 |
        abs(
          census_data_clustered$low_intensity_structure_share +
            census_data_clustered$attached_small_structure_share +
            census_data_clustered$medium_large_structure_share - 1
        ) > 1e-8,
      na.rm = TRUE
    )),
    as.character(
      sum(
        census_data_clustered$structure_composition_reliable &
          abs(
            census_data_clustered$built_form_intensity_ilr_raw -
              census_data_clustered$built_form_intensity_ilr
          ) > 1e-12,
        na.rm = TRUE
      ) +
        sum(
          census_data_clustered$structure_composition_reliable &
            abs(
              census_data_clustered$multifamily_scale_ilr_raw -
                census_data_clustered$multifamily_scale_ilr
            ) > 1e-12,
          na.rm = TRUE
        ) +
        sum(
          census_data_clustered$stock_age_reliable &
            abs(
              census_data_clustered$recent_stock_logit_raw -
                census_data_clustered$recent_stock_logit
            ) > 1e-12,
          na.rm = TRUE
        )
    ),
    as.character(length(model_specs)),
    as.character(experimental_gap_bootstraps),
    as.character(experimental_stability_bootstraps),
    as.character(experimental_stability_sample_share),
    as.character(sum(census_data_clustered$missing_experimental_input)),
    as.character(sum(census_data_clustered$built_form_input_imputed)),
    as.character(sum(census_data_clustered$functional_role_input_imputed)),
    as.character(access_jobs_year),
    access_snapshot_label
  )
)

analysis_qaqc_summary <- bind_rows(
  analysis_qaqc_summary,
  tibble(
    metric = c(
      "resident_context_experimental_model_count",
      "resident_context_target_squared_distance_shares",
      "demographic_minimum_universe",
      "demographic_primary_moe_threshold",
      "older_adult_reliable_tracts_primary_10pp",
      "older_adult_reliable_tracts_strict_5pp",
      "older_adult_reliable_tracts_permissive_15pp",
      "age_standardized_disability_reliable_tracts_primary_10pp",
      "age_standardized_disability_reliable_tracts_strict_5pp",
      "age_standardized_disability_reliable_tracts_permissive_15pp",
      "poverty_rate_reliable_tracts_primary_10pp",
      "poverty_rate_reliable_tracts_strict_5pp",
      "poverty_rate_reliable_tracts_permissive_15pp",
      "tracts_with_age_disability_neutral_imputation",
      "tracts_with_poverty_constraint_neutral_imputation",
      "tracts_with_disability_age_band_substitution",
      "disability_age_count_reconciliation_failures",
      "race_ethnicity_count_reconciliation_failures",
      "tracts_with_nonpositive_race_ethnicity_universe",
      "race_ethnicity_audit_low_precision_rows",
      "older_adult_winsorized_reliable_values",
      "age_standardized_disability_winsorized_reliable_values",
      "poverty_rate_winsorized_reliable_values",
      "disability_standardization_population_difference",
      "disability_standardization_weight_sum"
    ),
    value = as.character(c(
      length(resident_context_model_keys),
      str_c(resident_context_weight_targets, collapse = ";"),
      demographic_min_universe,
      demographic_moe_threshold,
      sum(census_data_clustered$older_adult_reliable, na.rm = TRUE),
      sum(census_data_clustered$older_adult_reliable_strict, na.rm = TRUE),
      sum(census_data_clustered$older_adult_reliable_permissive, na.rm = TRUE),
      sum(
        census_data_clustered$age_standardized_disability_reliable,
        na.rm = TRUE
      ),
      sum(
        census_data_clustered$age_standardized_disability_reliable_strict,
        na.rm = TRUE
      ),
      sum(
        census_data_clustered$age_standardized_disability_reliable_permissive,
        na.rm = TRUE
      ),
      sum(census_data_clustered$poverty_rate_reliable, na.rm = TRUE),
      sum(census_data_clustered$poverty_rate_reliable_strict, na.rm = TRUE),
      sum(census_data_clustered$poverty_rate_reliable_permissive, na.rm = TRUE),
      sum(census_data_clustered$age_disability_input_imputed, na.rm = TRUE),
      sum(census_data_clustered$poverty_constraint_input_imputed, na.rm = TRUE),
      sum(census_data_clustered$disability_age_band_imputations > 0, na.rm = TRUE),
      sum(
        !coalesce(
          census_data_clustered$disability_age_counts_reconcile,
          FALSE
        )
      ),
      sum(
        !coalesce(
          census_data_clustered$race_ethnicity_counts_reconcile,
          FALSE
        )
      ),
      sum(
        is.na(census_data_clustered$race_ethnicity_total) |
          census_data_clustered$race_ethnicity_total <= 0
      ),
      sum(experimental_race_ethnicity_audit$low_precision_flag),
      sum(
        census_data_clustered$older_adult_reliable &
          abs(
            census_data_clustered$older_adult_logit_raw -
              census_data_clustered$older_adult_logit
          ) > 1e-12,
        na.rm = TRUE
      ),
      sum(
        census_data_clustered$age_standardized_disability_reliable &
          abs(
            census_data_clustered$age_standardized_disability_logit_raw -
              census_data_clustered$age_standardized_disability_logit
          ) > 1e-12,
        na.rm = TRUE
      ),
      sum(
        census_data_clustered$poverty_rate_reliable &
          abs(
            census_data_clustered$poverty_rate_logit_raw -
              census_data_clustered$poverty_rate_logit
          ) > 1e-12,
        na.rm = TRUE
      ),
      sum(disability_standardization_reference$reference_population) -
        austin_disability_reference_raw$disability_population_totalE,
      sum(disability_standardization_reference$standard_weight)
    ))
  )
)

analysis_qaqc_summary <- bind_rows(
  analysis_qaqc_summary,
  tibble(
    metric = c(
      "mixed_gower_pam_model_count",
      "mixed_candidate_cluster_counts",
      "land_use_cluster_ready_tracts",
      "land_use_low_or_missing_coverage_tracts",
      "displacement_risk_cluster_ready_tracts",
      "displacement_risk_outside_published_coverage_tracts",
      "minimum_complete_tracts_across_mixed_models",
      "maximum_complete_tracts_across_mixed_models",
      "land_use_composition_coverage_threshold",
      "mixed_distance_method",
      "mixed_clustering_method"
    ),
    value = as.character(c(
      length(mixed_model_specs),
      str_c(mixed_candidate_k, collapse = ";"),
      sum(!is.na(census_data_clustered$land_use_category_cluster)),
      sum(is.na(census_data_clustered$land_use_category_cluster)),
      sum(!is.na(census_data_clustered$displacement_risk_category_cluster)),
      sum(is.na(census_data_clustered$displacement_risk_category_cluster)),
      min(mixed_model_summary$complete_tracts),
      max(mixed_model_summary$complete_tracts),
      0.50,
      "Gower",
      "partitioning around medoids (PAM)"
    ))
  )
)

# Save data
cat("\nSaving processed data...\n")
saveRDS(census_data_clustered, file.path(output_dir, "austin_opportunity_data.rds"))
write_csv(
  census_data_clustered %>% st_drop_geometry(),
  file.path(output_dir, "austin_opportunity_data.csv")
)
write_csv(cluster_stats, file.path(output_dir, "cluster_input_summary.csv"))
write_csv(
  cluster_overlay_summary,
  file.path(output_dir, "cluster_overlay_summary.csv")
)
write_csv(
  cluster_overlay_crosstab,
  file.path(output_dir, "cluster_overlay_crosstab.csv")
)
write_csv(cluster_centers, file.path(output_dir, "cluster_centers_scaled.csv"))
write_csv(cluster_diagnostics, file.path(output_dir, "cluster_diagnostics.csv"))
write_csv(
  experimental_model_diagnostics,
  file.path(output_dir, "experimental_model_diagnostics.csv")
)
write_csv(
  experimental_model_summary,
  file.path(output_dir, "experimental_model_summary.csv")
)
write_csv(
  experimental_model_input_weights,
  file.path(output_dir, "experimental_model_input_weights.csv")
)
write_csv(
  experimental_cluster_profiles,
  file.path(output_dir, "experimental_cluster_profiles.csv")
)
write_csv(
  experimental_cluster_centers,
  file.path(output_dir, "experimental_cluster_centers_scaled.csv")
)
write_csv(
  experimental_cluster_assignments,
  file.path(output_dir, "experimental_cluster_assignments.csv")
)
write_csv(
  experimental_candidate_correlations,
  file.path(output_dir, "experimental_candidate_correlations.csv")
)
write_csv(
  experimental_overlay_sorting,
  file.path(output_dir, "experimental_overlay_sorting.csv")
)
write_csv(
  built_form_reliability_sensitivity,
  file.path(output_dir, "built_form_reliability_sensitivity.csv")
)
write_csv(
  resident_context_model_diagnostics,
  file.path(output_dir, "resident_context_model_diagnostics.csv")
)
write_csv(
  resident_context_model_summary,
  file.path(output_dir, "resident_context_model_summary.csv")
)
write_csv(
  resident_context_cluster_profiles,
  file.path(output_dir, "resident_context_cluster_profiles.csv")
)
write_csv(
  resident_context_candidate_cluster_profiles,
  file.path(output_dir, "resident_context_candidate_cluster_profiles.csv")
)
write_csv(
  resident_context_candidate_cluster_assignments,
  file.path(output_dir, "resident_context_candidate_cluster_assignments.csv")
)
write_csv(
  resident_context_reliability_sensitivity,
  file.path(output_dir, "resident_context_reliability_sensitivity.csv")
)
write_csv(
  experimental_race_ethnicity_audit,
  file.path(output_dir, "experimental_race_ethnicity_audit.csv")
)
write_csv(
  experimental_poverty_concentration_guardrail,
  file.path(output_dir, "experimental_poverty_concentration_guardrail.csv")
)
write_csv(
  mixed_model_diagnostics,
  file.path(output_dir, "mixed_model_diagnostics.csv")
)
write_csv(
  mixed_model_summary,
  file.path(output_dir, "mixed_model_summary.csv")
)
write_csv(
  mixed_model_input_weights,
  file.path(output_dir, "mixed_model_input_weights.csv")
)
write_csv(
  mixed_categorical_weight_sensitivity,
  file.path(output_dir, "mixed_categorical_weight_sensitivity.csv")
)
write_csv(
  mixed_model_medoids,
  file.path(output_dir, "mixed_model_medoids.csv")
)
write_csv(
  mixed_cluster_assignments,
  file.path(output_dir, "mixed_cluster_assignments.csv")
)
write_csv(
  mixed_cluster_profiles,
  file.path(output_dir, "mixed_cluster_profiles.csv")
)
write_csv(
  mixed_categorical_profiles,
  file.path(output_dir, "mixed_categorical_profiles.csv")
)
write_csv(
  mixed_overlay_sorting,
  file.path(output_dir, "mixed_overlay_sorting.csv")
)
write_csv(
  mixed_race_ethnicity_audit,
  file.path(output_dir, "mixed_race_ethnicity_audit.csv")
)
write_csv(
  disability_standardization_reference,
  file.path(output_dir, "disability_standardization_reference.csv")
)
write_csv(
  cluster_input_correlations,
  file.path(output_dir, "cluster_input_correlations.csv")
)
write_csv(
  cluster_input_missingness,
  file.path(output_dir, "cluster_input_missingness.csv")
)
write_csv(indicator_roles, file.path(output_dir, "indicator_roles.csv"))
write_csv(overlay_thresholds, file.path(output_dir, "overlay_filter_thresholds.csv"))
write_csv(analysis_qaqc_summary, file.path(output_dir, "analysis_qaqc_summary.csv"))

cat("\n=== Analysis Complete ===\n")
cat("Output files created:\n")
cat("  - output/elbow_plot.png\n")
cat("  - output/place_access_conditions_map.png\n")
cat("  - output/cluster_map.png\n")
cat("  - output/income_overlay_map.png\n")
cat("  - output/poverty_overlay_map.png\n")
cat("  - output/transit_access_map.png\n")
cat("  - output/environmental_hazard_map.png\n")
cat("  - output/crash_injury_map.png\n")
cat("  - output/family_map.png\n")
cat("  - output/no_vehicle_overlay_map.png\n")
cat("  - output/development_pressure_experiment_map.png\n")
cat("  - output/built_form_experiment_map.png\n")
cat("  - output/functional_role_experiment_map.png\n")
cat("  - output/experimental_cluster_diagnostics.png\n")
cat("  - output/experimental_cluster_stability.png\n")
cat("  - output/resident_context_cluster_diagnostics.png\n")
cat("  - output/resident_context_cluster_stability.png\n")
cat("  - output/mixed_model_diagnostics.png\n")
cat("  - output/mixed_model_stability.png\n")
cat("  - output/mixed_categorical_weight_sensitivity.png\n")
cat("  - output/mixed_cluster_comparison_map.png\n")
cat("  - output/land_use_category_map.png\n")
cat("  - output/displacement_risk_category_map.png\n")
cat("  - output/austin_opportunity_data.rds\n")
cat("  - output/austin_opportunity_data.csv\n")
cat("  - output/cluster_input_summary.csv\n")
cat("  - output/cluster_overlay_summary.csv\n")
cat("  - output/cluster_overlay_crosstab.csv\n")
cat("  - output/cluster_centers_scaled.csv\n")
cat("  - output/cluster_diagnostics.csv\n")
cat("  - output/experimental_model_diagnostics.csv\n")
cat("  - output/experimental_model_summary.csv\n")
cat("  - output/experimental_model_input_weights.csv\n")
cat("  - output/experimental_cluster_profiles.csv\n")
cat("  - output/experimental_cluster_centers_scaled.csv\n")
cat("  - output/experimental_cluster_assignments.csv\n")
cat("  - output/experimental_candidate_correlations.csv\n")
cat("  - output/experimental_overlay_sorting.csv\n")
cat("  - output/built_form_reliability_sensitivity.csv\n")
cat("  - output/resident_context_model_diagnostics.csv\n")
cat("  - output/resident_context_model_summary.csv\n")
cat("  - output/resident_context_cluster_profiles.csv\n")
cat("  - output/resident_context_candidate_cluster_profiles.csv\n")
cat("  - output/resident_context_candidate_cluster_assignments.csv\n")
cat("  - output/resident_context_reliability_sensitivity.csv\n")
cat("  - output/experimental_race_ethnicity_audit.csv\n")
cat("  - output/experimental_poverty_concentration_guardrail.csv\n")
cat("  - output/mixed_model_diagnostics.csv\n")
cat("  - output/mixed_model_summary.csv\n")
cat("  - output/mixed_model_input_weights.csv\n")
cat("  - output/mixed_categorical_weight_sensitivity.csv\n")
cat("  - output/mixed_model_medoids.csv\n")
cat("  - output/mixed_cluster_assignments.csv\n")
cat("  - output/mixed_cluster_profiles.csv\n")
cat("  - output/mixed_categorical_profiles.csv\n")
cat("  - output/mixed_overlay_sorting.csv\n")
cat("  - output/mixed_race_ethnicity_audit.csv\n")
cat("  - output/disability_standardization_reference.csv\n")
cat("  - output/cluster_input_correlations.csv\n")
cat("  - output/cluster_input_missingness.csv\n")
cat("  - output/indicator_roles.csv\n")
cat("  - output/overlay_filter_thresholds.csv\n")
cat("  - output/analysis_qaqc_summary.csv\n")
