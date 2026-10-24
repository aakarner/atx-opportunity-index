suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(stringr)
})

dataaxle_path <- "data/destinations/healthcare/processed/healthcare_dataaxle.gpkg"
nppes_path <- "data/destinations/healthcare/processed/healthcare_cms_nppes.gpkg"
out_dir <- "data/destinations/healthcare/qa"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

d <- st_read(dataaxle_path, layer = "candidates_urgent_care", quiet = TRUE)
n <- st_read(nppes_path, layer = "urgent_care", quiet = TRUE)

d <- d |>
  mutate(
    review_decision = "retain",
    review_reason = "Named urgent-care facility; address reviewed against provider website or locator",
    evidence_url = case_when(
      str_detect(str_to_lower(name), "carenow") ~ "https://www.carenow.com/locations/austin",
      str_detect(str_to_lower(name), "baylor scott") ~ "https://www.bswhealth.com/locations/clinical-group/urgent-care-greater-austin-region",
      str_detect(str_to_lower(name), "next level") ~ "https://www.nextlevelurgentcare.com/locations/city/austin-tx/",
      str_detect(str_to_lower(name), "carbon health") ~ "https://carbonhealth.com/locations/cities/texas/austin",
      str_detect(str_to_lower(name), "concentra") ~ "https://www.concentra.com/urgent-care-centers/texas/austin/",
      str_detect(str_to_lower(name), "texas children's") ~ "https://www.texaschildrens.org/urgent-care",
      str_detect(str_to_lower(name), "texas medclinic") ~ "https://www.texasmedclinic.com/locations/",
      str_detect(str_to_lower(name), "afc urgent") ~ "https://www.afcurgentcare.com/north-austin/",
      str_detect(str_to_lower(name), "express md") ~ "https://expressmdcare.com/",
      str_detect(str_to_lower(name), "lewis urgent") ~ "https://lewisfamilymed.com/urgent-care/",
      TRUE ~ if_else(is.na(website), NA_character_, paste0("https://", str_to_lower(website)))
    ),
    canonical_name = name
  )

# Website-supported names for DataAxle records whose generic labels obscured the
# actual walk-in service at the address.
d <- d |>
  mutate(
    canonical_name = case_when(
      name == "Ascension Medical Group Round" ~ "Ascension Seton Express Care - Round Rock",
      name == "Baylor Scott-White Clinic" & city == "Georgetown" & str_detect(address, "4945") ~ "Baylor Scott & White Urgent Care - Georgetown (Williams)",
      name == "Baylor Scott-White Clinic" & city == "Pflugerville" ~ "Baylor Scott & White Urgent Care - Pflugerville Central",
      name == "Baylor Scott-White Health" & city == "Georgetown" ~ "Baylor Scott & White Urgent Care - Georgetown Central",
      TRUE ~ canonical_name
    )
  )

exclude <- function(condition, reason, url = NA_character_) {
  rows <- which(condition)
  d$review_decision[rows] <<- "exclude"
  d$review_reason[rows] <<- reason
  if (!is.na(url)) d$evidence_url[rows] <<- url
}

exclude(str_detect(str_to_lower(d$name), "ally medical emergency|premier er|us acute care solutions"),
        "Emergency-room or emergency-physician organization; not walk-in urgent care")
exclude(d$name == "Carenow Urgent Care-Southpark",
        "Provider website identifies the location as coming soon; exclude until operational",
        "https://www.carenow.com/locations/austin/southpark")
exclude(d$name == "Lone Star Urgent Care LP",
        "The urgent-care tenant formerly reported at this address is listed as permanently closed")
exclude(d$name == "Med Spring Urgent Care",
        "Legacy MedSpring listing; no current provider-controlled location page confirmed")
exclude(d$name == "Carenow Anderson Mill",
        "Duplicate of the CareNow Anderson Mill record at the same coordinate and address")
exclude(d$name == "Baylor Scott-White Clinic" & d$city == "Cedar Park",
        "Duplicate generic clinic record; retain the explicit urgent-care record at the same address")
exclude(d$name == "Carenow Urgent Care-Southwest" & str_detect(d$address, "US-290"),
        "Duplicate address representation; retain the record matching the provider's 5033 W Highway 290 address")
exclude(d$name == "Fastmed Urgent Care" & d$city == "Bastrop",
        "Legacy duplicate at 717 Highway 71 W; current provider page identifies CareNow at this address",
        "https://www.carenow.com/locations/austin/bastrop")

# Attach the nearest NPPES urgent-care candidate as comparison evidence only.
d_metric <- st_transform(d, 26914)
n_metric <- st_transform(n, 26914)
nearest <- st_nearest_feature(d_metric, n_metric)
distance_m <- as.numeric(st_distance(d_metric, n_metric[nearest, ], by_element = TRUE))
d$nppes_nearest_m <- round(distance_m, 1)
d$nppes_nearest_npi <- n$npi[nearest]
d$nppes_nearest_name <- n$organization_name[nearest]
d$nppes_within_250m <- distance_m <= 250

qa <- d |>
  st_drop_geometry() |>
  select(destination_id, dataaxle_id, name, canonical_name, address, city, county,
         phone, website, review_decision, review_reason, evidence_url,
         nppes_nearest_m, nppes_nearest_npi, nppes_nearest_name, nppes_within_250m)
write.csv(qa, file.path(out_dir, "dataaxle_urgent_care_website_review.csv"), row.names = FALSE, na = "")

final <- d |>
  filter(review_decision == "retain") |>
  mutate(
    source = "DataAxle; address and service-type website review",
    analysis_ready = TRUE,
    manual_review_status = "website_reviewed"
  )
st_write(
  final,
  "data/destinations/healthcare/processed/urgent_care_dataaxle_verified.gpkg",
  layer = "urgent_care", delete_dsn = TRUE, quiet = TRUE
)

summary <- qa |>
  count(review_decision, review_reason, name = "records") |>
  arrange(review_decision, desc(records))
write.csv(summary, file.path(out_dir, "dataaxle_urgent_care_review_summary.csv"), row.names = FALSE)

cat("DataAxle urgent-care website review\n")
print(table(qa$review_decision))
cat("Retained records within 250 m of an NPPES candidate:",
    sum(final$nppes_within_250m), "of", nrow(final), "\n")
