# Descriptive statistics and screening support for ParkServe open-access parks.
source("00_setup_packages.R")
setup_project_packages(c("tidyverse", "sf", "jsonlite"))
source("destinations/R/destination_paths.R")
out <- destination_comparison_dir("parks_parkserve_descriptive")
gpkg <- file.path(destination_dir("parks","processed"),"parks_parkserve_austin_metro.gpkg")
layer_meta <- file.path(destination_dir("parks","raw","parkserve",create=FALSE),"layer.json")
sf_use_s2(FALSE)
parks <- st_read(gpkg,layer="open_access_parks",quiet=TRUE) |> st_make_valid() |>
 mutate(park_size_acres=as.numeric(park_size_acres),playground_count=as.numeric(playground_count))
meta <- fromJSON(layer_meta,simplifyVector=FALSE)
get_domain <- function(field) {
 f <- Filter(function(x) identical(x$name,field),meta$fields)[[1]]
 bind_rows(lapply(f$domain$codedValues,function(x)tibble(code=as.character(x$code),label=trimws(x$name))))
}
designations <- get_domain("park_designation")
managers <- get_domain("park_manager_type")
# Account for a legacy spelling present in the service records.
managers <- bind_rows(managers,tibble(code="SPECIAL_DISTRICT",label="Special District or Authority"),tibble(code="UNKNOWN",label="Unknown")) |> distinct(code,.keep_all=TRUE)
summary_stats <- function(data, group) st_drop_geometry(data) |>
 group_by(across(all_of(group))) |>
 summarise(records=n(),total_acres=sum(park_size_acres,na.rm=TRUE),median_acres=median(park_size_acres,na.rm=TRUE),
           playgrounds=sum(playground_count,na.rm=TRUE),missing_acres=sum(is.na(park_size_acres)),.groups="drop") |>
 mutate(share_percent=100*records/nrow(data)) |>
 arrange(desc(records))
manager_summary <- summary_stats(parks,"park_manager_type") |> left_join(managers,by=c("park_manager_type"="code")) |>
 select(manager_code=park_manager_type,manager_type=label,everything())
owner_summary <- summary_stats(parks,"park_owner_type") |> left_join(managers,by=c("park_owner_type"="code")) |>
 select(owner_code=park_owner_type,owner_type=label,everything())
designation_summary <- summary_stats(parks,"park_designation") |> left_join(designations,by=c("park_designation"="code")) |>
 mutate(designation=coalesce(label,park_designation)) |> select(designation_code=park_designation,designation,everything(),-label)
county_summary <- summary_stats(parks,"park_county")
local_manager <- parks |> st_drop_geometry() |> mutate(park_local_manager=coalesce(na_if(trimws(park_local_manager),""),"Missing")) |>
 group_by(park_local_manager) |> summarise(records=n(),counties=n_distinct(park_county),
 total_acres=sum(park_size_acres,na.rm=TRUE),median_acres=median(park_size_acres,na.rm=TRUE),.groups="drop") |>
 mutate(share_percent=100*records/nrow(parks)) |> arrange(desc(records),park_local_manager)
cross <- parks |> st_drop_geometry() |> count(park_manager_type,park_designation,name="records") |>
 left_join(managers,by=c("park_manager_type"="code")) |> rename(manager_type=label) |>
 left_join(designations,by=c("park_designation"="code")) |> rename(designation=label) |>
 mutate(share_percent=100*records/nrow(parks)) |> arrange(desc(records))
# Decision-support grouping; no records are removed by this descriptive step.
public_manager <- parks$park_manager_type %in% c("MUNI","CNTY","STATE","FED","SPECIAL_DIST","SPECIAL_DISTRICT")
standard_rec <- parks$park_designation %in% c("LP","LREC","SP","SREC","REC")
conservation <- parks$park_designation %in% c("LCA","PCON","CONE","NWR","SCA","WPA","RNA")
parks <- parks |> mutate(screening_group=case_when(
 public_manager & standard_rec ~ "public park or recreation - retain candidate",
 public_manager & conservation ~ "public conservation or natural area - policy decision",
 public_manager ~ "public manager, other designation - review",
 park_manager_type %in% c("PRIV","HOA","SCHOOL_K12","NONPROFIT","UNIV") ~ "nonpublic manager - verify unrestricted public use",
 TRUE ~ "unknown manager - review"))
screening_summary <- summary_stats(parks,"screening_group")
for(z in list(list(manager_summary,"manager_type_summary.csv"),list(owner_summary,"owner_type_summary.csv"),
 list(designation_summary,"designation_summary.csv"),list(local_manager,"local_manager_summary.csv"),
 list(county_summary,"county_summary.csv"),list(cross,"manager_designation_crosswalk.csv"),
 list(screening_summary,"retention_screening_summary.csv"))) write_csv(z[[1]],file.path(out,z[[2]]),na="")
review_gpkg<-file.path(out,"parkserve_open_access_screening.gpkg");if(file.exists(review_gpkg))file.remove(review_gpkg)
st_write(parks,review_gpkg,layer="open_access_screening",quiet=TRUE)
lines<-c("# ParkServe open-access park descriptive statistics","",
 paste0("The source contains ",nrow(parks)," operational records coded Open Access. Open access describes reported public access; it does not imply public ownership or management."),"",
 "## Field meanings","",
 "- Park manager type is a standardized category for the organization managing the site, such as a municipality, county, private entity, HOA, or special district.",
 "- Park local manager is the source's free-text organization name. Spelling, capitalization, and name order are not standardized, so one agency can appear under several labels.",
 "- Park designation describes the legal or functional land designation rather than a detailed list of amenities. LP means Local Park, LREC Local Recreation Area, LCA Local Conservation Area, PPRK Private Park, and PCON Private Conservation.","",
 "## Suggested use","",
 "Start with public parks and recreation areas managed by municipalities, counties, states, federal agencies, or special districts. Keep public conservation areas as a separate policy decision. Manually verify HOA, private, school, nonprofit, university, and unknown-manager records even when ParkServe codes them as open access.","",
 "The screening_group field is decision support only. It does not change the ParkServe source or establish final eligibility.")
writeLines(lines,file.path(out,"descriptive_assessment.md"))
print(manager_summary,n=Inf);print(designation_summary,n=Inf);print(screening_summary,n=Inf)
