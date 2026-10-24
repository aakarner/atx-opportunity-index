# Compare SNAP and Data Axle food-retailer inventories without treating SNAP
# nonparticipation as an error.
#
# Inputs: data/destinations/groceries/raw/usda_snap/metro_records.json,
#         data/destinations/{groceries,healthy_foods}/raw/dataaxle/*.csv
# Writes: data/destinations/comparisons/groceries_usda_snap_dataaxle/
#
#   Rscript destinations/comparisons/92_compare_usda_snap_dataaxle_groceries.R
source("00_setup_packages.R")
setup_project_packages(c("tidyverse","sf","jsonlite","digest","ggplot2"))
source("destinations/R/destination_paths.R")
source("destinations/R/dataaxle_helpers.R")
out <- destination_comparison_dir("groceries_usda_snap_dataaxle")
snap_dir <- destination_dir("groceries", "raw", "usda_snap", create = FALSE)
source_path <- file.path(snap_dir, "metro_records.json")
if(!file.exists(source_path)) stop("Run destinations/groceries/01_pull_usda_snap_groceries.R first.")
j <- jsonlite::fromJSON(source_path)
s <- as_tibble(j$attributes) %>% transmute(snap_id=as.character(Record_ID),object_id=as.character(ObjectId),
 name=Store_Name,address=Store_Street_Address,address2=Additonal_Address,city=City,state=State,
 zip=as.character(Zip_Code),county=toupper(County),store_type=Store_Type,
 latitude=as.numeric(Latitude),longitude=as.numeric(Longitude),incentive_program=Incentive_Program)
stopifnot(!anyDuplicated(s$object_id))
file_groups <- list(groceries=list.files(destination_dir("groceries","raw","dataaxle",create=FALSE),pattern="[.]csv$",full.names=TRUE,ignore.case=TRUE),
 healthy_foods=list.files(destination_dir("healthy_foods","raw","dataaxle",create=FALSE),pattern="[.]csv$",full.names=TRUE,ignore.case=TRUE))
raw <- bind_rows(lapply(names(file_groups),function(k) bind_rows(lapply(file_groups[[k]],ax_read,collection=k))))
a <- ax_consolidate(raw)
a$county <- toupper(a$county)
counties <- c("TRAVIS","WILLIAMSON","HAYS","BASTROP","CALDWELL")
a$in_scope <- a$state=="TX" & a$county %in% counties
readr::write_csv(a[!a$in_scope,],file.path(out,"dataaxle_outside_or_unknown_county.csv"))
a <- a[a$in_scope,]
valid <- function(x) is.finite(x$latitude)&is.finite(x$longitude)&abs(x$latitude)<=90&abs(x$longitude)<=180
# Address matching remains possible even where supplied coordinates are invalid.
d <- matrix(Inf,nrow(a),nrow(s))
av <- valid(a); sv <- valid(s)
if(any(av)&any(sv)) {
 ap<-st_as_sf(a[av,],coords=c("longitude","latitude"),crs=4326)%>%st_transform(26914)
 sp<-st_as_sf(s[sv,],coords=c("longitude","latitude"),crs=4326)%>%st_transform(26914)
 d[av,sv]<-matrix(as.numeric(st_distance(ap,sp)),sum(av),sum(sv))
}
key <- function(x) {x[is.na(x)]<-"";toupper(gsub("[^A-Za-z0-9]","",x))}
address_key <- function(x) {
 x[is.na(x)]<-"";x<-toupper(gsub("[^A-Za-z0-9 ]"," ",x))
 for(pair in list(c("STREET","ST"),c("ROAD","RD"),c("DRIVE","DR"),c("BOULEVARD","BLVD"),
 c("AVENUE","AVE"),c("LANE","LN"),c("PARKWAY","PKWY"),c("HIGHWAY","HWY"),
 c("NORTH","N"),c("SOUTH","S"),c("EAST","E"),c("WEST","W")))
  x<-gsub(paste0("\\b",pair[1],"\\b"),pair[2],x)
 key(x)
}
name_key <- function(x) {
 x[is.na(x)]<-"";x<-toupper(x)
 x<-gsub("[0-9]+","",x)
 x<-gsub("\\b(INC|LLC|LTD|CORPORATION)\\b","",x)
 key(x)
}
aa<-address_key(a$address);sa<-address_key(s$address)
# Match the listed primary street address and ZIP. Suite information is retained
# in output; differing secondary addresses need human checking.
addr <- outer(paste(aa,a$zip),paste(sa,s$zip),"==") & outer(nzchar(aa),nzchar(sa),"&")
n1<-name_key(a$name);n2<-name_key(s$name)
sim<-1-adist(n1,n2)/outer(nchar(n1),nchar(n2),pmax);sim[!is.finite(sim)]<-0
hits<-which(addr | (sim>=.6 & d<=500),arr.ind=TRUE)
candidates <- tibble(ax_index=hits[,1],snap_index=hits[,2],
 destination_id=a$destination_id[hits[,1]],collection=a$collection[hits[,1]],dataaxle_name=a$name[hits[,1]],
 dataaxle_address=a$address[hits[,1]],dataaxle_zip=a$zip[hits[,1]],naics=a$naics[hits[,1]],
 snap_object_id=s$object_id[hits[,2]],snap_name=s$name[hits[,2]],snap_address=s$address[hits[,2]],
 snap_address2=s$address2[hits[,2]],snap_type=s$store_type[hits[,2]],same_address_zip=addr[hits],
 name_similarity=sim[hits],coordinate_distance_m=d[hits]) %>%
 mutate(candidate_basis=case_when(same_address_zip & name_similarity>=.6~"address_and_name",
 same_address_zip~"address_only_review",TRUE~"name_and_proximity_review"),
 priority=case_when(candidate_basis=="address_and_name"~1L,candidate_basis=="address_only_review"~2L,TRUE~3L)) %>%
 arrange(priority,desc(name_similarity),coordinate_distance_m,destination_id,snap_object_id)
# A strong candidate needs a unique address/name pair on both sides. Do not
# force one-to-one links among several plausible retailers at the same address.
strong<-candidates%>%filter(candidate_basis=="address_and_name")%>%
 add_count(destination_id,name="ax_candidates")%>%add_count(snap_object_id,name="snap_candidates")%>%
 filter(ax_candidates==1,snap_candidates==1)
stopifnot(!anyDuplicated(strong$destination_id),!anyDuplicated(strong$snap_object_id))
candidates$strong_unique_candidate <- paste(candidates$destination_id,candidates$snap_object_id) %in%
 paste(strong$destination_id,strong$snap_object_id)
candidates$manual_decision <- "";candidates$review_notes<-""
readr::write_csv(candidates,file.path(out,"candidate_matches.csv"))
readr::write_csv(strong,file.path(out,"strong_unique_candidates.csv"))
best<-candidates%>%group_by(destination_id)%>%slice_head(n=1)%>%ungroup()%>%
 select(destination_id,snap_object_id,snap_name,snap_address,snap_type,candidate_basis,name_similarity,coordinate_distance_m)
ax_review<-a%>%left_join(best,by="destination_id")%>%mutate(
 match_status=case_when(destination_id%in%strong$destination_id~"strong_unique_candidate",
 destination_id%in%candidates$destination_id~"manual_review_candidate",TRUE~"no_candidate"))
snap_review<-s%>%mutate(match_status=case_when(object_id%in%strong$snap_object_id~"strong_unique_candidate",
 object_id%in%candidates$snap_object_id~"manual_review_candidate",TRUE~"no_candidate"))
grocery_types<-c("Supermarket","Super Store","Grocery Store")
snap_review$grocery_comparison_subset<-snap_review$store_type%in%grocery_types
readr::write_csv(snap_review %>% filter(grocery_comparison_subset,match_status=="no_candidate"),
 file.path(out,"snap_groceries_without_dataaxle_candidate.csv"))
readr::write_csv(strong %>% filter(coordinate_distance_m>250) %>% arrange(desc(coordinate_distance_m)),
 file.path(out,"coordinate_discrepancies_over_250m.csv"))
stopifnot(nrow(ax_review)==nrow(a),nrow(snap_review)==nrow(s),
 !anyDuplicated(snap_review$snap_id),!anyDuplicated(ax_review$destination_id),
 all(strong$same_address_zip),all(strong$name_similarity>=.6),
 all(candidates$same_address_zip | (candidates$name_similarity>=.6 & candidates$coordinate_distance_m<=500)))

for(z in list(list(ax_review,"dataaxle_review.csv"),list(snap_review,"snap_metro_retailers.csv"),
 list(snap_review%>%count(county,store_type,name="retailers"),"snap_county_type_counts.csv"),
 list(snap_review%>%count(store_type,match_status,name="retailers"),"snap_type_match_summary.csv"),
 list(ax_review%>%count(collection,match_status,name="records"),"dataaxle_match_summary.csv"),
 list(strong%>%count(collection,snap_type,name="candidate_pairs"),"classification_crosswalk.csv")))
 readr::write_csv(z[[1]],file.path(out,z[[2]]))
counts <- full_join(a%>%count(county,collection)%>%pivot_wider(names_from=collection,values_from=n,values_fill=0),
 s%>%group_by(county)%>%summarise(snap_all=n(),snap_grocery_subset=sum(store_type%in%grocery_types),.groups="drop"),by="county")
readr::write_csv(counts,file.path(out,"county_comparison.csv"))
manifest<-jsonlite::fromJSON(file.path(snap_dir,"manifest.json"))
readr::write_csv(tibble(path=c(unlist(file_groups),source_path),sha256=vapply(c(unlist(file_groups),source_path),function(p) digest::digest(file=p,algo="sha256"),character(1))),file.path(out,"input_checksums.csv"))
# Separate comparable grocery points from other SNAP retail types on the map.
map_data<-bind_rows(a%>%filter(collection=="groceries")%>%transmute(name,latitude,longitude,source="Data Axle groceries"),
 s%>%filter(store_type%in%grocery_types)%>%transmute(name,latitude,longitude,source="SNAP grocery subset"))
map_data<-map_data[valid(map_data),]
map<-ggplot(map_data,aes(longitude,latitude,colour=source))+geom_point(alpha=.65,size=1.5)+
 coord_quickmap()+scale_colour_manual(values=c("Data Axle groceries"="#d45a32","SNAP grocery subset"="#177b98"))+
 labs(title="Grocery locations in the five-county Austin metro",subtitle="Source locations as supplied; comparable SNAP retailer types only",
 x="Longitude",y="Latitude",colour=NULL,caption=paste("SNAP source updated",substr(manifest$source_data_updated_utc,1,10),"| Data Axle manual exports. Coincidence does not establish identity."))+
 theme_minimal(base_size=11)+theme(legend.position="bottom",plot.title=element_text(face="bold"))
ggsave(file.path(out,"grocery_source_locations.png"),map,width=10,height=8,dpi=150,bg="white")
gpkg<-file.path(out,"snap_dataaxle_comparison.gpkg")
for(z in list(list(ax_review,"dataaxle_food_candidates"),list(snap_review,"snap_all_retailers")))
 st_write(st_as_sf(z[[1]][valid(z[[1]]),],coords=c("longitude","latitude"),crs=4326,remove=FALSE),gpkg,layer=z[[2]],delete_layer=TRUE,quiet=TRUE)
lines<-c("# SNAP and Data Axle food-retailer comparison","",
 paste0("SNAP retrieved ",manifest$retrieved_at_utc,"; source updated ",manifest$source_data_updated_utc,"."),"",
 "Coverage: Texas records assigned to Travis, Williamson, Hays, Bastrop and Caldwell counties. County attributes, rather than supplied coordinates, define inclusion so coordinate errors do not silently change the study universe.","",
 paste0("SNAP: ",nrow(s)," currently authorized retailer records. Comparable grocery subset (Supermarket, Super Store, Grocery Store): ",sum(s$store_type%in%grocery_types),". Data Axle: ",sum(a$collection=="groceries")," grocery and ",sum(a$collection=="healthy_foods")," healthy-food records."),"",
 "## SNAP retailer mix","","| Type | Records | Share |","|---|---:|---:|")
for(type in sort(unique(s$store_type))) lines<-c(lines,sprintf("| %s | %d | %.1f%% |",type,sum(s$store_type==type),100*mean(s$store_type==type)))
lines<-c(lines,"","## Data Axle matching results","","| Collection | Strong unique candidate | Other review candidate | No candidate |","|---|---:|---:|---:|")
for(k in unique(a$collection)) {t<-ax_review[ax_review$collection==k,];lines<-c(lines,sprintf("| %s | %d | %d | %d |",k,sum(t$match_status=="strong_unique_candidate"),sum(t$match_status=="manual_review_candidate"),sum(t$match_status=="no_candidate")))}
lines<-c(lines,"","## Comparable SNAP grocery subset","",
 paste0("Of ",sum(snap_review$grocery_comparison_subset)," SNAP supermarkets/super stores/grocery stores: ",
 sum(snap_review$grocery_comparison_subset & snap_review$match_status=="strong_unique_candidate")," have strong unique candidates, ",
 sum(snap_review$grocery_comparison_subset & snap_review$match_status=="manual_review_candidate")," have other review candidates, and ",
 sum(snap_review$grocery_comparison_subset & snap_review$match_status=="no_candidate")," have no candidate in the provided Data Axle exports."),"",
 paste0("Among strong pairs, median coordinate separation is ",round(median(strong$coordinate_distance_m),1),
 " metres; ",sum(strong$coordinate_distance_m>250)," pairs exceed 250 metres. Neither source is assumed correct. See coordinate_discrepancies_over_250m.csv."),"",
 "Healthy-food matches must be interpreted separately: few or absent candidates are not proof of nonparticipation or poor source coverage. Their narrow business categories, address variants, and the candidate rules require review.","",
 "## Method and interpretation","",
 "Matching searches all SNAP retailer types, so a grocery listed as Convenience Store or Other is not automatically missed. Candidates share normalized primary street address and ZIP, or have normalized-name edit similarity at least 0.60 and are within 500 metres. Strong candidates additionally share address/ZIP, have name similarity at least 0.60, and are unique on both sides. These remain candidates, not manually confirmed identities. Common chain names and co-located businesses can produce ambiguity.","",
 "Addresses standardize punctuation, common road suffixes and directions; names remove punctuation, store numbers and selected corporate suffixes. Secondary SNAP address fields are retained for review. No fuzzy address or outside-county search is performed. Coordinate separation is measured in NAD83 / UTM zone 14N; invalid coordinate pairs do not prevent address matches.","",
 "SNAP covers participating authorized retailers; Data Axle covers the user's downloaded business categories. No candidate does not mean closed, absent, or erroneous: it may reflect nonparticipation, export/category scope, different names/addresses, vintage differences, or missed matching. Counts are listings, not capacity or healthy-food availability. Specialty Store and Farmers and Markets are not a direct equivalent of the Data Axle healthy-food collection, which includes juice retailers. Retailer definitions require separate review.","",
 "Use candidate_matches.csv and strong_unique_candidates.csv to inspect agreement and coordinate gaps; county_comparison.csv compares geography; classification_crosswalk.csv shows SNAP types for strong candidate pairs. SNAP unmatched records in the grocery subset identify stores to investigate as possible additions. Do not overwrite either source's coordinates or eligibility using automated matches alone.","",
 "[Official USDA dataset](https://www.arcgis.com/home/item.html?id=8b260f9a10b0459aa441ad8588c2251c)","",
 "![Grocery locations](grocery_source_locations.png)")
writeLines(lines,file.path(out,"snap_dataaxle_assessment.md"))
print(counts,width=Inf);print(ax_review%>%count(collection,match_status),n=Inf)
print(strong%>%count(collection,snap_type),n=Inf)
print(summary(strong$coordinate_distance_m))
