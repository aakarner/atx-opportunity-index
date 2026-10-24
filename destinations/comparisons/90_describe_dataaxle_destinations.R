# Describe the complete cleaned Data Axle candidate inventory, across all
# destinations, before eligibility decisions.
#
# Run each destination's 02_clean_dataaxle_<destination>.R first, then:
#   Rscript destinations/comparisons/90_describe_dataaxle_destinations.R
#
# Writes data/destinations/comparisons/dataaxle_descriptive/
source("00_setup_packages.R")
setup_project_packages(c("dplyr", "readr", "tibble"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_config.R")
inputs <- file.path(destination_data_root, dataaxle_destinations, "interim", "dataaxle", "dataaxle_standardized.csv")
inputs <- inputs[file.exists(inputs)]
output_dir <- destination_comparison_dir("dataaxle_descriptive")
if (!length(inputs)) stop("Run destinations/<destination>/02_clean_dataaxle_<destination>.R first.")
x <- dplyr::bind_rows(lapply(inputs, readr::read_csv,
  col_types=readr::cols(.default=readr::col_character()), show_col_types=FALSE))
if (anyDuplicated(x[c("collection", "destination_id")])) stop("Duplicate collection-destination keys in master.")
# NAICS, SIC, ZIP and IDs remain text. Blank descriptions are explicit unknowns.
unknown <- function(z) {
  z[is.na(z) | trimws(z) %in% c("", "Not Available", "N/A", "NA")] <- "Unknown"
  z
}
for (field in c("naics", "naics6", "naics_description", "sic", "sic_description",
                "location_type", "city", "county", "website", "phone")) x[[field]] <- unknown(x[[field]])
flag <- function(z) !is.na(z) & tolower(z) == "true"
examples <- function(z) paste(head(sort(unique(z[!is.na(z)])),5), collapse="; ")
totals <- x %>% count(collection, name="collection_records")
frequency <- function(keys) {
  x %>% group_by(across(all_of(c("collection",keys)))) %>% summarise(
    records=n(), example_businesses=examples(name),
    websites_available=sum(website != "Unknown"),
    headquarters_records=sum(grepl("headquarter",location_type,ignore.case=TRUE)),
    shared_address_records=sum(flag(shared_address)),
    source_conflict_records=sum(!is.na(attribute_conflicts) & nzchar(attribute_conflicts)),
    incomplete_address_records=sum(flag(identity_incomplete)),
    coordinate_conflict_records=sum(flag(coordinate_conflict)),
    map_ready_records=sum(flag(map_ready)),
    provisional_rule_included=sum(screen_decision=="include" & classification_basis=="provisional_rule"),
    pending_review_records=sum(screen_decision=="review"), .groups="drop") %>%
    left_join(totals,by="collection") %>%
    mutate(percent_of_collection=100*records/collection_records) %>%
    relocate(collection,all_of(keys),records,percent_of_collection,collection_records) %>%
    arrange(collection,desc(records),across(all_of(keys)))
}
naics <- frequency(c("naics","naics_description"))
naics6 <- frequency("naics6")
naics_sic <- frequency(c("naics","naics_description","sic","sic_description"))
for (entry in list(list(naics,"naics_summary.csv"),list(naics6,"naics6_summary.csv"),
                   list(naics_sic,"naics_sic_summary.csv"),
                   list(frequency("location_type"),"location_type_summary.csv"),
                   list(frequency(c("county","city")),"geography_summary.csv"))) {
  readr::write_csv(entry[[1]],file.path(output_dir,entry[[2]]))
}
completeness <- x %>% group_by(collection) %>% summarise(records=n(),
  missing_naics=sum(naics=="Unknown"),missing_naics_description=sum(naics_description=="Unknown"),
  missing_sic=sum(sic=="Unknown"),missing_sic_description=sum(sic_description=="Unknown"),
  missing_website=sum(website=="Unknown"),missing_phone=sum(phone=="Unknown"),
  incomplete_address=sum(flag(identity_incomplete)), .groups="drop")
readr::write_csv(completeness,file.path(output_dir,"attribute_completeness.csv"))
# A stable record listing supports later checks without changing existing decisions.
listing <- x %>% select(collection,destination_id,record_fingerprint,name,address,city,state,zip,
  naics,naics_description,sic,sic_description,location_type,website,phone,
  latitude,longitude,destination_type,reason,screen_decision,classification_basis) %>%
  arrange(collection,naics,sic,name)
readr::write_csv(listing,file.path(output_dir,"records_for_review.csv"))
# Group-level notes are human inputs: create once, never overwrite on refresh.
notes_path <- file.path(destination_manual_dir(), "dataaxle_category_decisions.csv")
if (!file.exists(notes_path)) {
  dir.create(dirname(notes_path),recursive=TRUE,showWarnings=FALSE)
  notes <- naics_sic %>% select(collection,naics,naics_description,sic,sic_description) %>%
    mutate(proposed_decision="",proposed_destination_type="",eligibility_rule="",evidence="",reviewer="",reviewed_on="")
  readr::write_csv(notes,notes_path)
}
# Summary reconciliation uses all candidates, including pending and excluded rows.
for (z in list(naics,naics6,naics_sic)) {
  check <- z %>% group_by(collection) %>% summarise(n=sum(records),p=sum(percent_of_collection),.groups="drop") %>%
    left_join(totals,by="collection")
  stopifnot(all(check$n==check$collection_records),all(abs(check$p-100)<1e-8))
}
escape <- function(z) gsub("[\r\n]"," ",gsub("|","/",as.character(z),fixed=TRUE))
lines <- c("# Data Axle destination classification review", "",
  paste0("Based on ",nrow(x)," cleaned collection-destination records in the current master."),"",
  "Counts include every candidate, including records awaiting review. Percentages use each collection's full cleaned record count. They are not population-weighted measures or estimates of service capacity.","",
  "NAICS and SIC labels below are retained as exported, including truncated descriptions. Detailed Data Axle code extensions are not treated as independently verified classifications. Example businesses are up to five alphabetically selected names, not a representative sample.","",
  "The same destination may appear in more than one collection. Current provisional inclusion flags are diagnostic context, not final eligibility decisions.","")
for (category in totals$collection) {
  tab <- naics_sic[naics_sic$collection==category,]
  lines <- c(lines,paste0("## ",category),"",
    "| NAICS | NAICS description | SIC description | Records | Share | Example businesses |",
    "|---|---|---|---:|---:|---|")
  for (i in seq_len(nrow(tab))) lines <- c(lines,paste0("| ",paste(escape(c(tab$naics[i],tab$naics_description[i],tab$sic_description[i],
    tab$records[i],sprintf("%.1f%%",tab$percent_of_collection[i]),tab$example_businesses[i])),collapse=" | ")," |"))
  lines <- c(lines,"")
}
lines <- c(lines,"## How to record decisions","",
 "Use data/destinations/manual/dataaxle_category_decisions.csv for proposed group-level decisions: retain, exclude, reclassify, or needs_review. Document the eligible service, public-access conditions, and evidence. The file is never overwritten and is not applied automatically to individual records. Newly encountered groups appear in the refreshed frequency tables and can be appended to the notes file.","",
 "Use records_for_review.csv to investigate individual locations. Record final record-level decisions through data/destinations/manual/dataaxle_reviews.csv (applied by each 02_clean_dataaxle script). These descriptive outputs do not change classification rules, manual reviews, or accessibility inputs.")
writeLines(lines,file.path(output_dir,"classification_review.md"))
print(totals)
message("Descriptive tables and report: ",output_dir,"\nGroup decision notes: ",notes_path)
