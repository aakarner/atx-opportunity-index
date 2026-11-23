# One pinned municipal footprint shared by targets and source preparation.
# Municipal scope preserves Austin full- and limited-purpose limits, excluding ETJ.
validate_municipal_spec <- function(spec) {
  if(!all(c("snapshot_date","path","url","jurisdiction_types","city_name","refresh","sha256") %in% names(spec)) ||
     !setequal(unlist(spec$jurisdiction_types),c("FULL","LTD")) || spec$city_name!="CITY OF AUSTIN" ||
     !grepl("^[a-f0-9]{64}$",spec$sha256) ||
     !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",spec$snapshot_date)) stop("Invalid municipal boundary specification.")
  invisible(spec)
}
municipal_request <- function(url,query=list()) {
  request <- httr2::request(url) |> httr2::req_user_agent("atx-opportunity-index municipal boundary")
  if(length(query))request<-do.call(httr2::req_url_query,c(list(request),query))
  response<-httr2::req_perform(httr2::req_retry(httr2::req_timeout(request,180),max_tries=3))
  body<-httr2::resp_body_json(response,simplifyVector=FALSE)
  if(!is.null(body$error))stop("Municipal GIS service returned an error.")
  list(raw=httr2::resp_body_raw(response),body=body,url=request$url)
}
acquire_municipal_boundary <- function(spec) {
  validate_municipal_spec(spec)
  paths<-c(spec$path,paste0(spec$path,".metadata.json"),paste0(spec$path,".manifest.json"))
  if(all(file.exists(paths)) && !isTRUE(spec$refresh)) {
    m<-jsonlite::read_json(paths[3],simplifyVector=TRUE)
    if(m$sha256!=spec$sha256 || m$sha256!=digest::digest(paths[1],algo="sha256",file=TRUE) || m$snapshot_date!=spec$snapshot_date ||
       m$service_url!=spec$url || !setequal(m$jurisdiction_types,unlist(spec$jurisdiction_types)))stop("Municipal boundary cache does not match its manifest/configuration.")
    return(paths)
  }
  where<-"CITY_NAME = 'CITY OF AUSTIN' AND JURISDICTION_TYPE IN ('FULL','LTD')"
  metadata<-municipal_request(spec$url,list(f="json"))
  ids<-municipal_request(paste0(spec$url,"/query"),list(where=where,returnIdsOnly="true",f="json"))
  expected<-sort(as.integer(unlist(ids$body$objectIds)))
  if(!length(expected))stop("No Austin municipal features returned.")
  geo<-municipal_request(paste0(spec$url,"/query"),list(where=where,outFields="OBJECTID,CITY_NAME,JURISDICTION_TYPE,JURISDICTION_LABEL",outSR=4326,orderByFields="OBJECTID",f="geojson"))
  if(digest::digest(geo$raw,algo="sha256",serialize=FALSE)!=spec$sha256)stop("Downloaded municipal geometry differs from the pinned snapshot. Use a new dated snapshot and reviewed checksum.")
  actual<-sort(vapply(geo$body$features,function(f) as.integer(f$properties$OBJECTID),integer(1)))
  if(!identical(actual,expected) || anyDuplicated(actual) || isTRUE(geo$body$exceededTransferLimit))stop("Incomplete municipal boundary download.")
  dir.create(dirname(spec$path),recursive=TRUE,showWarnings=FALSE)
  temporary<-paste0(spec$path,".partial.geojson");writeBin(geo$raw,temporary)
  on.exit(unlink(temporary),add=TRUE)
  raw<-sf::st_read(temporary,quiet=TRUE)
  if(!nrow(raw) || any(raw$CITY_NAME!=spec$city_name) || any(!raw$JURISDICTION_TYPE %in% unlist(spec$jurisdiction_types)))stop("Incorrect municipal jurisdiction filter.")
  if(!file.rename(temporary,spec$path))stop("Cannot finalize municipal boundary.")
  writeBin(metadata$raw,paths[2])
  jsonlite::write_json(list(source="City of Austin BOUNDARIES_jurisdictions",service_url=spec$url,
    query_url=geo$url,snapshot_date=spec$snapshot_date,retrieved_utc=format(Sys.time(),tz="UTC",usetz=TRUE),
    jurisdiction_types=unlist(spec$jurisdiction_types),feature_count=length(actual),object_ids=actual,
    source_edit_time_ms=metadata$body$editingInfo$lastEditDate,
    sha256=digest::digest(spec$path,algo="sha256",file=TRUE)),paths[3],auto_unbox=TRUE,pretty=TRUE)
  paths
}
read_municipal_boundary <- function(paths,spec) {
  raw<-sf::st_read(paths[1],quiet=TRUE)
  if(!nrow(raw) || anyNA(raw$CITY_NAME) || any(raw$CITY_NAME!=spec$city_name) ||
     anyNA(raw$JURISDICTION_TYPE) || any(!raw$JURISDICTION_TYPE %in% unlist(spec$jurisdiction_types)))stop("Invalid municipal boundary source.")
  # Union in projected coordinates removes overlaps between jurisdiction pieces.
  geometry<-sf::st_union(sf::st_make_valid(sf::st_transform(raw,5070)))
  city<-sf::st_make_valid(sf::st_transform(sf::st_sf(GEOID="4805000",NAME="Austin",geometry=geometry),4326))
  if(any(!sf::st_is_valid(city)) || any(sf::st_is_empty(city)))stop("Invalid municipal footprint.")
  city$boundary_snapshot<-spec$snapshot_date
  city$boundary_source<-"City of Austin GIS: full and limited purpose"
  city$boundary_sha256<-digest::digest(paths[1],algo="sha256",file=TRUE)
  city
}
load_municipal_boundary <- function(config_path="config/pipeline.yml") {
  spec<-yaml::read_yaml(config_path)$municipal_boundary
  read_municipal_boundary(acquire_municipal_boundary(spec),spec)
}
municipal_h8_ids <- function(city,res=8L) {
  sort(unique(unlist(h3jsr::polygon_to_cells(sf::st_geometry(city),res=res),use.names=FALSE)))
}
validate_access_boundary <- function(jobs,city) {
  expected<-municipal_h8_ids(city)
  if(!setequal(jobs$h3_id,expected))stop("Access origins do not match the municipal boundary. Rebuild accessibility source preparation.")
  if(!all(c("city_boundary_sha256","city_boundary_snapshot") %in% names(jobs)) ||
     anyNA(jobs$city_boundary_sha256) || any(jobs$city_boundary_sha256!=city$boundary_sha256) ||
     anyNA(jobs$city_boundary_snapshot) || any(jobs$city_boundary_snapshot!=city$boundary_snapshot))stop("Access snapshot boundary provenance is stale.")
  jobs
}

# Prepared spatial layers must be regenerated when the municipal footprint changes.
prepared_boundary_files <- function(path) {
  files <- c(path,paste0(path,".boundary.json"))
  if(!all(file.exists(files)))stop("Missing prepared boundary provenance: rerun the source preparation script for ",path)
  files
}
validate_prepared_boundary <- function(paths,city) {
  provenance <- jsonlite::read_json(paths[2],simplifyVector=TRUE)
  if(!identical(provenance$boundary_sha256,city$boundary_sha256) ||
     !identical(provenance$boundary_snapshot,city$boundary_snapshot))stop("Prepared spatial source has a stale municipal boundary: ",paths[1])
  paths[1]
}
