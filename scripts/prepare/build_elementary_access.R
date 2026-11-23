# Current published elementary assignments and the unchanged TEA growth measures.
# Run after pull_elementary_boundaries.py and the existing AISD preparation.
source("scripts/prepare/pull_school_subgroups.R")
source("scripts/prepare/build_school_assignments.R")

build_elementary_access <- function() {
  districts <- c("227901", "246909", "227904", "227910", "227907", "227909", "246913", "105906", "227913")
  district_names <- c("Austin ISD", "Round Rock ISD", "Pflugerville ISD", "Del Valle ISD", "Manor ISD",
    "Eanes ISD", "Leander ISD", "Hays CISD", "Lake Travis ISD")
  raw <- "data/raw/elementary_boundaries/2026_27"
  processed <- "data/processed/school_indicators"
  qa <- "data/qaqc/elementary_access"
  dir.create(qa, recursive=TRUE, showWarnings=FALSE)
  campuses <- normalize_school_campuses(read_tea_export("data/raw/tea_accountability/tea_2026_campus_rate.csv", 2026), 2026, districts)
  write_csv(campuses, file.path(processed,"expanded_campus_year.csv"), na="")
  subgroup <- run_school_subgroups(districts,"expanded")

  aliases <- c("BERKMAN"="CLAUDE BERKMAN", "VOIGT"="XENIA VOIGT", "CARAWAY"="KATHY CARAWAY",
    "ROBERTSON"="VIC ROBERTSON", "JOHNSON"="JOE LEE JOHNSON", "SOMMER"="PATSY SOMMER",
    "CALLISON"="NEYSA CALLISON", "HERRINGTON"="LINDA HERRINGTON", "ENGLAND"="ELSA ENGLAND",
    "BARRON"="RUTH BARRON", "DELCO"="WILHELMINA DELCO", "SPRING HILL"="SPRINGHILL",
    "SHADOW GLEN"="SHADOWGLEN", "AKIN"="MONTA JANE AKIN", "BUSH"="LAURA WELCH BUSH",
    "CAMACHO"="CHRISTINE CAMACHO", "COX"="CHARLOTTE COX", "GIDDENS"="LOIS F GIDDENS",
    "HISLE"="DONALD LEWIS HISLE", "KNOWLES"="PATRICIA KNOWLES", "MASON"="C C MASON",
    "NAUMANN"="PAULINE NAUMANN", "PLAIN"="JIM PLAIN", "REAGAN"="RONALD REAGAN",
    "REED"="OFFICER LEONARD A REED", "WINKLEY"="WILLIAM J WINKLEY", "CULLEN"="JIM CULLEN",
    "FUENTES"="SUSIE FUENTES", "NEGLEY"="LAURA B NEGLEY", "PFLUGER"="RALPH PFLUGER",
    "RAMAGE"="LAMONT RAMAGE")
  key <- function(x) { k <- sub(" SCHOOL$", "", school_name_key(x)); i <- match(k,names(aliases)); k[!is.na(i)] <- aliases[i[!is.na(i)]]; k }
  normalize <- function(x, district, field, label) {
    x <- st_transform(st_make_valid(x), 5070)
    x <- st_sf(assigned_school_label=as.character(x[[field]]), geometry=st_geometry(x)) |>
      group_by(assigned_school_label) |> summarise(.groups="drop")
    lookup <- campuses |> filter(district_id==district, school_type=="Elementary")
    stopifnot(!anyDuplicated(key(lookup$campus_name)))
    ix <- match(key(x$assigned_school_label),key(lookup$campus_name))
    # A non-neighborhood facility is included in PfISD's published polygon layer.
    # Preserve its coverage, but never substitute another school's performance.
    expected_unmatched <- district=="227904" & x$assigned_school_label=="OPPORTUNITY CENTER"
    if (any(is.na(ix) & !expected_unmatched)) stop("Unmatched ",district,": ",paste(x$assigned_school_label[is.na(ix)],collapse=", "))
    x$campus_id <- lookup$campus_id[ix]
    x$campus_name <- ifelse(is.na(ix),x$assigned_school_label,lookup$campus_name[ix])
    x$district_id <- district
    x$district_name <- district_names[match(district,districts)]
    x$source_layer_label <- label
    x
  }
  rr <- st_read(file.path(raw,"round_rock_elementary.geojson"),quiet=TRUE)
  everett <- st_read(file.path(raw,"round_rock_everett.geojson"),quiet=TRUE)
  # Separate published overlay fills a hole in the district's main layer.
  overlap <- suppressWarnings(st_intersection(st_union(st_make_valid(rr)),st_union(everett)))
  stopifnot(!length(overlap) || sum(as.numeric(st_area(overlap))) < 1)
  rr <- bind_rows(rr["ELEM_NAME"],everett["ELEM_NAME"])
  pf <- st_read(file.path(raw,"pflugerville_elementary.esrijson"),quiet=TRUE)
  dv <- st_read(file.path(raw,"del_valle_elementary.geojson"),quiet=TRUE)
  mi <- st_read(file.path(raw,"manor_elementary.geojson"),quiet=TRUE)
  ea <- st_read(file.path(raw,"eanes_elementary.geojson"),quiet=TRUE)
  le <- st_read(file.path(raw,"leander_elementary.geojson"),quiet=TRUE)
  hy <- st_read(file.path(raw,"hays_elementary.geojson"),quiet=TRUE)
  lt <- st_read(file.path(raw,"lake_travis_elementary.geojson"),quiet=TRUE)
  extra <- bind_rows(normalize(rr,"246909","ELEM_NAME","Round Rock ISD 2526 + The Everett"),
    normalize(pf,"227904","ELEM_NAME","Elementary Schools 2025-26"),
    normalize(dv,"227910","name","Current elementary scenario"),
    normalize(mi,"227907","name","24-25 Elementary Schools"),
    normalize(ea,"227909","name","School Year 2026-27 / Elementary"),
    normalize(le,"246913","DisplayName","Elementary School Zones / Leander_AZ_Finder_24_25_WFL1"),
    normalize(hy,"105906","name","Elementary School Zones 2026-2027; assignments as of 2026-11-10"),
    normalize(lt,"227913","name","Official elementary map; effective 2023-24; approximate PDF-derived polygons"))
  # Manor and Del Valle publish campus suffixes; independently reconcile names.
  for (entry in list(list(x=mi,id="227907",field="name"),list(x=dv,id="227910",field="name"),
                    list(x=ea,id="227909",field="name"))) {
    x <- entry$x
    ids <- if(entry$id=="227907") x$campus_id else paste0(entry$id,vapply(x$schools,function(s) jsonlite::fromJSON(s)$code[1],character(1)))
    matched <- extra$campus_id[match(paste(entry$id,x[[entry$field]]),paste(extra$district_id,extra$assigned_school_label))]
    stopifnot(identical(ids,matched))
  }
  aisd <- st_read(file.path(processed,"aisd_growth_assignments_2026_27.gpkg"),layer="elementary",quiet=TRUE) |> st_transform(5070)
  aisd <- st_sf(st_drop_geometry(aisd),geometry=st_geometry(aisd))
  aisd$district_id <- "227901"; aisd$district_name <- "Austin ISD"
  aisd$source_layer_label <- "AISD 2026–27 assignments"
  fields <- c("assigned_school_label","campus_id","campus_name","district_id","district_name","source_layer_label")
  zones <- bind_rows(aisd[fields],extra[fields]) |> st_make_valid()
  zones <- st_cast(zones,"MULTIPOLYGON",warn=FALSE)
  zones$source_object_id <- paste0(zones$district_id,":",seq_len(nrow(zones)))
  zones$school_level <- "elementary"
  zones$assignment_school_year <- "2026-27"
  zones$growth_school_year <- "2025-26"
  zones$accountability_year <- 2026L
  zones$boundary_year_basis <- ifelse(zones$district_id %in% c("227901","227909","105906"),
    "Explicit 2026–27 layer", "Current district-published locator; legacy layer label retained")
  zones$boundary_year_basis[zones$district_id=="227913"] <-
    "Current district-linked PDF checked 2026-11-10; 2023–24 effective label; approximate map-derived boundaries"
  ix <- match(zones$campus_id,campuses$campus_id)
  zones$score_status <- ifelse(is.na(ix),"No matched neighborhood elementary campus",
    ifelse(!campuses$eligible[ix],campuses$exclusion_reason[ix],
      ifelse(is.na(campuses$growth[ix]),"Growth missing or suppressed","Available")))
  zones$usable_growth <- ifelse(zones$score_status=="Available",campuses$growth[ix],NA_real_)
  sx <- match(zones$campus_id,subgroup$campus_id)
  zones$subgroup_growth <- ifelse(zones$score_status=="Available",subgroup$ed_growth_pooled[sx],NA_real_)
  zones$minimum_growth_tests <- pmin(subgroup$ed_growth_reading_denominator[sx],subgroup$ed_growth_math_denominator[sx])
  zones$subgroup_status <- ifelse(zones$score_status!="Available",zones$score_status,
    ifelse(is.na(zones$subgroup_growth),"Subgroup growth missing or suppressed","Available"))
  zones$grade_span <- campuses$grade_span[ix]
  stopifnot(!any(st_is_empty(zones)), all(st_is_valid(zones)), all(!is.na(zones$campus_id) | zones$score_status!="Available"))
  path <- file.path(processed,"elementary_growth_assignments_2026_27.gpkg")
  output <- st_transform(zones,4326)
  invalid <- !st_is_valid(output)
  st_geometry(output)[invalid] <- st_geometry(st_make_valid(output[invalid,]))
  stopifnot(all(st_is_valid(output)),!any(st_is_empty(output)))
  repair <- data.frame(source_object_id=zones$source_object_id,
    area_change_sq_m=as.numeric(st_area(st_transform(output,5070)))-as.numeric(st_area(zones)))
  stopifnot(all(abs(repair$area_change_sq_m)<10))
  write_csv(repair,file.path(qa,"geometry_repairs.csv"))
  st_write(output,path,layer="elementary",delete_dsn=TRUE,quiet=TRUE)
  write_csv(st_drop_geometry(zones),file.path(qa,"campus_crosswalk.csv"),na="")
  checks <- zones |> group_by(district_name) |> summarise(polygons=n(),campuses=n_distinct(campus_id,na.rm=TRUE),
    overall_available=sum(!is.na(usable_growth)),subgroup_available=sum(!is.na(subgroup_growth)),.groups="drop") |> st_drop_geometry()
  write_csv(checks,file.path(qa,"district_summary.csv"))
  inputs <- c(list.files(raw,pattern="\\.(geojson|esrijson|kml|pdf)$",full.names=TRUE),
    file.path(raw,c("source_manifest.json","lake_travis_pdf_georeferencing.json")),
    file.path(processed,"aisd_growth_assignments_2026_27.gpkg"),
    "data/raw/tea_accountability/tea_2026_campus_rate.csv",
    file.path(processed,"expanded_subgroup_comparison_2026.csv"))
  write_csv(data.frame(path=inputs,sha256=vapply(inputs,function(p)digest::digest(file=p,algo="sha256"),character(1))),
    file.path(qa,"input_manifest.csv"))
  print(checks)
  invisible(zones)
}

if(sys.nframe()==0L) build_elementary_access()
