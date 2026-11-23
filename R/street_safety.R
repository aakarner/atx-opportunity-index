# Higher scores mean greater burden. Fixed anchors are policy, not recalculated quantiles.
score_street_safety <- function(x, policy) {
  s <- policy$scoring
  stopifnot(is.finite(s$crash_full_burden_density), s$crash_full_burden_density>0,
    s$crash_high_burden_density>0, s$crash_high_burden_density<=s$crash_full_burden_density,
    s$major_frontage_high_burden_score>=0,s$major_frontage_high_burden_score<=100)
  total <- x$major_frontage_m
  served <- x$major_served_m
  present <- !is.na(total)
  if (any(x$annual_ksi_density < 0, na.rm = TRUE) || any(present != !is.na(served)) ||
      any(!is.finite(total[present]) | !is.finite(served[present]) | served[present] < 0 |
          served[present] > total[present]) || anyNA(x$inventory_observed[present]))
    stop('Invalid street length or crash density')
  x$frontage_status <- ifelse(is.na(total), 'no_city_observation_area',
    ifelse(total == 0, 'no_major_street',
      ifelse(served == 0 & !x$inventory_observed, 'no_pedestrian_inventory', 'available')))
  x$major_coverage_pct <- NA_real_
  available <- which(x$frontage_status == 'available')
  # Stabilize exact half-coverage ties across spatial sums and browser serialization.
  x$major_coverage_pct[available] <- round(100 * served[available] / total[available], 10)
  x$major_frontage_score <- 100 - x$major_coverage_pct
  density <- x$annual_ksi_density
  density[!is.finite(density)] <- NA_real_
  x$crash_score <- pmin(100,100*density/s$crash_full_burden_density)
  x$crash_high <- density>=s$crash_high_burden_density
  x$major_frontage_high <- x$major_frontage_score>=s$major_frontage_high_burden_score
  # R's three-valued OR retains known warnings but never infers a pass from missing data.
  x$any_high <- x$crash_high | x$major_frontage_high
  x$flag_status <- ifelse(is.na(x$any_high),'Incomplete assessment',
    ifelse(x$any_high,'High component burden','Below both flags'))
  both_known <- !is.na(x$crash_high)&!is.na(x$major_frontage_high)
  x$flag_detail <- 'Incomplete assessment'
  x$flag_detail[which(both_known & !x$any_high)] <- 'Below both flags'
  x$flag_detail[which(both_known & x$crash_high & !x$major_frontage_high)] <- 'Crash only'
  x$flag_detail[which(both_known & !x$crash_high & x$major_frontage_high)] <- 'Major frontage only'
  x$flag_detail[which(both_known & x$crash_high & x$major_frontage_high)] <- 'Both components'
  x$flag_detail[which(!both_known & x$any_high)] <- 'High; other component unavailable'
  x$scoring_version <- s$version
  x
}

build_street_safety <- function(study, frontage, crashes, population, policy) {
  s <- policy$scoring; crs <- sf::st_crs(study$geometry)
  crashes <- sf::st_transform(crashes,crs)
  years <- seq(s$crash_first_year,s$crash_last_year)
  if(anyNA(crashes$crash_id)||anyDuplicated(crashes$crash_id)||anyNA(crashes$ksi_crash)||
     !all(crashes$ksi_crash)||anyNA(crashes$crash_year)||!all(crashes$crash_year %in% years))
    stop('Crash records do not match the configured KSI observation period')
  population <- as.data.frame(population)
  stopifnot(!anyDuplicated(study$geometry$h3_id), !anyDuplicated(population$h3_id))
  results <- list()
  for (k in names(study$windows)) {
    radius <- study$radii[[k]]
    windows <- study$windows[[k]]
    local <- frontage$data[frontage$data$scenario == k, ]
    hits<-sf::st_intersects(windows,crashes)
    count<-function(flag=rep(TRUE,nrow(crashes)))vapply(hits,function(i)sum(flag[i]),integer(1))
    area<-as.numeric(sf::st_area(windows))/2589988.110336
    raw<-data.frame(h3_id=windows$h3_id,observed_area_sqmi=area,
      observed_area_share=windows$observed_area_share,
      ksi_count=count(),vru_ksi_count=count(crashes$vulnerable_road_user_ksi_crash),
      observation_years=length(years))
    raw$annual_ksi_density<-raw$ksi_count/(length(years)*area)
    raw<-merge(raw,local,by='h3_id',all.x=TRUE,sort=FALSE)
    raw<-merge(data.frame(h3_id=study$geometry$h3_id),raw,by='h3_id',all.x=TRUE,sort=FALSE)
    raw<-merge(raw,population[,c('h3_id','total_population','children_under_18')],by='h3_id',all.x=TRUE,sort=FALSE)
    raw$radius_miles<-radius;raw$scenario<-k
    results[[k]]<-score_street_safety(raw,policy)
  }
  list(results=results,windows=study$windows,geometry=study$geometry,policy=policy,
    provenance=list(frontage_sources=frontage$sources,crash_point_count=nrow(crashes),
      crash_data_sha256=digest::digest(crashes,algo='sha256'),
      hex_geometry_sha256=digest::digest(study$geometry,algo='sha256'),
      reference='Frozen quantiles of all 1,029 half-mile origins; 2020–2024 KSI; R type 7, unweighted',
      interpretation='Area density, not exposure-adjusted crash risk. Zero history does not establish safety.'))
}

write_street_safety <- function(result,directory='output/components/street-safety') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  files<-character()
  for(k in names(result$results)) {
    path<-file.path(directory,paste0(k,'.csv'))
    utils::write.csv(result$results[[k]],path,row.names=FALSE,na='');files<-c(files,path)
    g<-merge(sf::st_as_sf(result$geometry),result$results[[k]],by='h3_id',all.x=TRUE,sort=FALSE)
    sf::st_write(g,file.path(directory,'street_safety.gpkg'),layer=paste0(k,'_hex'),delete_layer=TRUE,quiet=TRUE)
    w<-merge(sf::st_as_sf(result$windows[[k]])['h3_id'],result$results[[k]],by='h3_id',all.x=TRUE,sort=FALSE)
    sf::st_write(w,file.path(directory,'street_safety.gpkg'),layer=paste0(k,'_windows'),delete_layer=TRUE,quiet=TRUE)
  }
  jsonlite::write_json(list(policy=result$policy,provenance=result$provenance),file.path(directory,'metadata.json'),
    auto_unbox=TRUE,pretty=TRUE,na='null',digits=17)
  saveRDS(result,file.path(directory,'analysis.rds'))
  c(files,file.path(directory,c('street_safety.gpkg','metadata.json','analysis.rds')))
}
