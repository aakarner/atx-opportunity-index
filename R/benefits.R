# Dated, team-supplied DAM release. Keep the source outside the repository.
dam_files <- function(root) {
  if (!nzchar(root)) stop("Set DAM_DATA_DIR to the dated DAM snapshot directory.")
  paths <- c(manifest="manifest.json", results="accessibility/accessibility_results.csv",
             dictionary="accessibility/measure_dictionary.csv", population="demographics/h3_population_counts.csv")
  setNames(normalizePath(file.path(root, paths), mustWork=TRUE), names(paths))
}

read_benefit_inputs <- function(files, spec, ids) {
  names(files) <- basename(files)
  manifest <- jsonlite::read_json(files[["manifest.json"]], simplifyVector=TRUE)
  stopifnot(manifest$source_commit == spec$source_commit, substr(manifest$created_utc, 1, 10) == spec$snapshot)
  for (file in files[names(files) != "manifest.json"]) {
    ix <- match(basename(file), basename(manifest$files$path))
    stopifnot(digest::digest(file=file, algo="sha256") == manifest$files$sha256[ix])
  }
  results <- readr::read_csv(files[["accessibility_results.csv"]], col_types="cccccccdccc", progress=FALSE)
  series <- readr::read_csv(files[["measure_dictionary.csv"]], col_types=readr::cols(.default="c"))
  keys <- c("scenario","mode","period","measure_id")
  stopifnot(!anyDuplicated(series[keys]), nrow(series)==manifest$series,
    nrow(results)==manifest$accessibility_rows, !anyDuplicated(results[c("h3_id",keys)]),
    all(results$period=="am_peak"), setequal(unique(results$mode),names(spec$budgets)),
    length(unique(results$h3_id))==manifest$origins,
    all(results$result_status %in% c("modeled","incomplete_basket","not_reached_within_model","missing")),
    all(is.finite(results$value)==(results$result_status=="modeled")), all(results$value >= 0, na.rm=TRUE))
  unknown <- dplyr::anti_join(results,series,by=c(keys,"unit","direction"))
  stopifnot(!nrow(unknown), all(table(results$h3_id)==nrow(series)))
  results <- results[results$h3_id %in% ids,]
  pop <- readr::read_csv(files[["h3_population_counts.csv"]], col_types=readr::cols(h3_id="c"), show_col_types=FALSE)
  stopifnot(setequal(results$h3_id, ids), !anyDuplicated(pop$h3_id), all(ids %in% pop$h3_id))
  list(results=results, series=series, population=pop[match(ids,pop$h3_id),], ids=ids)
}

benefit_scores <- function(inputs,spec) {
  ids <- inputs$ids
  r <- inputs$results
  series <- transform(inputs$series, field=paste(mode,scenario,measure_id,sep="__"))
  report <- data.frame(id=ids)
  scored <- data.frame(id=ids)
  sensitivity <- list()
  for (i in seq_len(nrow(series))) {
    s <- series[i,]
    x <- r[r$scenario==s$scenario & r$mode==s$mode & r$measure_id==s$measure_id,]
    report[[s$field]] <- x$value[match(ids,x$h3_id)]
  }
  stopifnot(setequal(spec$profiles$general,names(spec$destinations)),
    all(vapply(spec$profiles,function(m) length(m)>0 && !anyDuplicated(m) &&
      all(m %in% names(spec$destinations)),logical(1))))
  for (mode in names(spec$budgets)) {
    limit <- c(drive=60,walk_transit=90)[[mode]]
    budgets <- spec$budgets[[mode]]
    stopifnot(all(budgets>0 & budgets<=limit),spec$defaults[[mode]] %in% budgets)
    nearest <- data.frame(row.names=ids)
    for (dest in names(spec$destinations)) {
      x <- r[r$mode==mode & r$scenario==paste0(dest,"_nearest"),]
      stopifnot(nrow(x)==length(ids), all(x$unit=="minutes"))
      x <- x[match(ids,x$h3_id),]
      v <- x$value
      v[x$result_status=="not_reached_within_model"] <- Inf
      nearest[[dest]] <- v
      report[[paste(mode,dest,"status",sep="_")]] <- x$result_status
    }
    for (profile in names(spec$profiles)) {
      mean_minutes <- rowMeans(nearest[spec$profiles[[profile]]])
      mean_minutes[!is.finite(mean_minutes)] <- NA_real_
      report[[paste(mode,profile,"mean_minutes",sep="_")]] <- mean_minutes
    }
    ref <- paste0(mode,"__essential_destinations__")
    complete_mean <- rowMeans(nearest)
    complete_mean[!is.finite(complete_mean)] <- NA_real_
    stopifnot(isTRUE(all.equal(complete_mean,report[[paste0(ref,"mean_nearest__8")]],tolerance=1e-6,check.attributes=FALSE)))
    for (budget in unique(c(15,30,60,spec$budgets[[mode]]))) {
      passed <- nearest <= budget
      if (budget %in% c(15,30,60)) stopifnot(isTRUE(all.equal(
        rowSums(passed),report[[paste0(ref,"category_count__",budget)]],check.attributes=FALSE)))
      if (!budget %in% spec$budgets[[mode]]) next
      prefix <- paste(mode,budget,sep="_")
      for (dest in names(nearest)) scored[[paste(prefix,dest,sep="_")]] <- as.numeric(passed[,dest])
      for (profile in names(spec$profiles)) {
        members <- spec$profiles[[profile]]
        count <- rowSums(passed[,members,drop=FALSE])
        scored[[paste(prefix,profile,sep="_")]] <- count
        sensitivity[[length(sensitivity)+1L]] <- data.frame(mode,minutes=budget,profile,
          destinations=length(members),origins=length(count),unknown=sum(is.na(count)),
          zero=sum(count==0,na.rm=TRUE),full=sum(count==length(members),na.rm=TRUE),
          mean_types=mean(count,na.rm=TRUE))
      }
    }
  }
  list(raw=report, scores=scored, series=series, sensitivity=dplyr::bind_rows(sensitivity))
}

benefit_tracts <- function(data, pop, tracts, h8, crosswalk) {
  ix <- match(crosswalk$h3_id, data$scores$id)
  pop_ix <- match(crosswalk$h3_id,pop$h3_id)
  area <- as.numeric(sf::st_area(sf::st_transform(tracts,sf::st_crs(h8))))
  job_fields <- subset(data$series, scenario=="jobs_cumulative")$field
  # Spread estimated H8 residents and resident workers uniformly within each cell.
  weights <- crosswalk$h8_area_share * pop$total_population[pop_ix]
  workers <- crosswalk$h8_area_share * h8$workers_all[match(crosswalk$h3_id,h8$h3_id)]
  stopifnot(all(is.na(weights) | (is.finite(weights) & weights>=0)), all(is.finite(workers) & workers>=0))
  scores <- as.matrix(data$scores[-1])
  jobs <- as.matrix(data$raw[job_fields])
  mean_fields <- function(mat,rows,w) {
    pos <- which(w>0)
    if (!length(pos)) return(setNames(rep(NA_real_,ncol(mat)),colnames(mat)))
    colSums(mat[rows[pos],,drop=FALSE] * w[pos])/sum(w[pos])
  }
  dplyr::bind_rows(lapply(seq_len(nrow(tracts)), function(i) {
    k <- which(crosswalk$GEOID==tracts$GEOID[i])
    w <- workers[k]
    method <- "resident-worker weighted"
    if (!sum(w)) {w <- crosswalk$overlap_area_m2[k]; method <- "area weighted"}
    if (!length(k)) method <- "no overlapping H8"
    data.frame(id=tracts$GEOID[i], resident_weight=sum(weights[k],na.rm=TRUE),
      resident_weight_area_share=min(1,sum(crosswalk$overlap_area_m2[k][!is.na(weights[k])])/area[i]),
      area_coverage=min(1,sum(crosswalk$overlap_area_m2[k])/area[i]), job_method=method,
      as.list(mean_fields(scores,ix[k],weights[k])),as.list(mean_fields(jobs,ix[k],w)),check.names=FALSE)
  }))
}

write_benefit_review <- function(data, tract, inputs, spec, h8, tracts, sites, directory) {
  dest <- file.path(directory,"benefits")
  dir.create(dest,showWarnings=FALSE,recursive=TRUE)
  counts <- data$scores
  h <- dplyr::left_join(data$raw,counts,by="id")
  gpkg <- file.path(dest,"benefits.gpkg")
  for (level in c("h8","tract")) {
    if (level=="h8") {rows <- h; geom <- h8; key <- "h3_id"} else {rows <- tract; geom <- tracts; key <- "GEOID"}
    geo <- sf::st_sf(rows,geometry=sf::st_geometry(geom)[match(rows$id,geom[[key]])])
    sf::st_write(geo,gpkg,layer=level,delete_layer=TRUE,quiet=TRUE)
  }
  csv <- function(x,name) {p <- file.path(dest,name); readr::write_csv(x,p); p}
  site_ids <- h3jsr::point_to_cell(sites,res=8)
  examples <- data.frame(site_id=sites$site_id,id=site_ids)
  example_scores <- dplyr::left_join(examples,counts,by="id")
  destination_coverage <- list()
  comparisons <- list()
  equity <- list()
  for (mode in names(spec$defaults)) {
    for (minutes in spec$budgets[[mode]]) {
      for (name in names(spec$destinations)) {
        x <- counts[[paste(mode,minutes,name,sep="_")]]
        destination_coverage[[length(destination_coverage)+1L]] <- data.frame(mode,minutes,
          destination=name, reached=sum(x==1,na.rm=TRUE), known=sum(!is.na(x)))
      }
    }
    prefix <- paste(mode,spec$defaults[[mode]],sep="_")
    general <- counts[[paste0(prefix,"_general")]]/length(spec$profiles$general)
    for (profile in names(spec$profiles)) {
      share <- counts[[paste(prefix,profile,sep="_")]]/length(spec$profiles[[profile]])
      comparisons[[length(comparisons)+1L]] <- data.frame(mode,profile,
        higher=sum(share>general,na.rm=TRUE),same=sum(share==general,na.rm=TRUE),lower=sum(share<general,na.rm=TRUE),
        mean_difference=mean(share-general,na.rm=TRUE))
      for (group in c("total_population","no_vehicle_households","adults_65_plus","families_with_own_children")) {
        w <- inputs$population[[group]]
        valid <- is.finite(share) & is.finite(w)
        equity[[length(equity)+1L]] <- data.frame(mode,profile,group,
          weight_covered=sum(w[valid]),weighted_share_full=weighted.mean(share[valid]==1,w[valid]))
      }
    }
  }
  c(gpkg,csv(data$sensitivity,"threshold-sensitivity.csv"),csv(example_scores,"example-site-scores.csv"),
    csv(dplyr::bind_rows(comparisons),"profile-comparison.csv"),csv(dplyr::bind_rows(equity),"population-context.csv"),
    csv(data$series,"measure-dictionary.csv"),csv(dplyr::bind_rows(destination_coverage),"destination-coverage.csv"))
}

write_benefit_assets <- function(data,tract,spec,zones,directory="site/assets") {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  schools <- dplyr::bind_rows(lapply(zones,function(z) {
    sf::st_transform(z[c("school_level","campus_id","campus_name","usable_growth","score_status")],4326)
  }))
  schools_file <- file.path(directory,"school-zones.geojson")
  sf::st_write(schools,schools_file,driver="GeoJSON",delete_dsn=TRUE,quiet=TRUE,layer_options="COORDINATE_PRECISION=7")
  # Column-oriented JSON keeps field names from being repeated for each origin.
  path <- file.path(directory,"benefits.json")
  jsonlite::write_json(list(spec=spec,series=data$series,
    hex=dplyr::left_join(data$raw,data$scores,by="id"),tract=tract),path,dataframe="columns",
    digits=NA,auto_unbox=TRUE,na="null",null="null")
  c(path,schools_file)
}

write_benefit_brief <- function(files,spec,tract,site_profiles) {
  root <- dirname(files[1])
  load_csv <- function(name) readr::read_csv(file.path(root,name),show_col_types=FALSE)
  sens <- load_csv("threshold-sensitivity.csv")
  profile_names <- c(general="All eight", families="Families", older="Older adults",
                     single="Single adults",supportive="Supportive housing (partial)")
  default_rows <- sens$minutes==unlist(spec$defaults)[sens$mode]
  summary <- transform(sens[default_rows,], Profile=profile_names[profile],
    Mode=ifelse(mode=="drive","Driving","Transit + walk"),
    `None reached (%)`=round(100*zero/origins,1), `All reached (%)`=round(100*full/origins,1),
    check.names=FALSE)
  summary <- summary[c("Profile","Mode","minutes","destinations","None reached (%)","All reached (%)")]
  ex <- load_csv("example-site-scores.csv")
  sites <- dplyr::left_join(ex,site_profiles,by="site_id")
  examples <- data.frame(Site=sites$label,
    "All eight · drive"=sites[[paste("drive", spec$defaults$drive,"general",sep="_")]],
    "All eight · transit"=sites[[paste("walk_transit",spec$defaults$walk_transit,"general",sep="_")]],
    "Family · transit"=sites[[paste("walk_transit",spec$defaults$walk_transit,"families",sep="_")]],
    "Elementary assignment"=sites$school_elementary_campus_name,
    "Growth or status"=ifelse(is.na(sites$school_elementary_growth),sites$school_elementary_status,sites$school_elementary_growth),
    check.names=FALSE)
  budget <- subset(sens,profile=="general")
  budget <- budget[order(budget$mode,budget$minutes),]
  budget <- data.frame(Mode=budget$mode,Minutes=budget$minutes,"No types"=budget$zero,
    "All eight"=budget$full,"Mean types"=round(budget$mean_types,2),check.names=FALSE)
  drivers <- load_csv("destination-coverage.csv")
  drivers <- drivers[drivers$minutes==unlist(spec$defaults)[drivers$mode],]
  reach <- data.frame(Destination=unlist(spec$destinations),check.names=FALSE)
  for (mode in names(spec$defaults)) {
    v <- drivers[drivers$mode==mode,]
    reach[[paste(mode,spec$defaults[[mode]],"min (%)")]] <- round(100*(v$reached/v$known)[match(rownames(reach),v$destination)],1)
  }
  comparisons <- subset(load_csv("profile-comparison.csv"),profile!="general")
  comparisons$profile <- unname(profile_names[comparisons$profile])
  links <- paste0('<li><a href="',basename(files),'">',basename(files),'</a></li>',collapse="")
  p <- file.path(root,"review.html")
  writeLines(c('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Austin housing siting benefits review</title>',
    '<style>body{font:16px/1.55 system-ui;color:#233d46;margin:3rem auto;max-width:850px;padding:0 1rem}h1,h2{line-height:1.2}h2{margin-top:2rem}th,td{padding:.4rem .65rem;border-bottom:1px solid #ddd;text-align:left}th{background:#eef4ef}.table-scroll{overflow:auto}table{border-collapse:collapse;font-size:.9rem}a{color:#155e52}small{color:#52666b}</style><main>',
    paste0('<small>Housing siting research · DAM release ',spec$snapshot,'</small><h1>Which everyday destinations can a resident reach?</h1>'),
    '<p>Compare a proposed address under separate driving and transit scenarios. Count one point per destination type within the trial time budget. Use the component list to see which trip a resident would still need to make. Jobs and assigned-school growth are separate benefits.</p>',
    '<h2>Three example locations</h2><p>Each cell is a count of reachable types. Driving and transit use the trial defaults shown below. The school column uses the example address and the 2025–26 AISD assignment.</p>',report_html_table(examples),
    '<h2>Choosing a time budget</h2><p>The rows below count H8 origins. As the budget rises, more sites tie. At 15 minutes driving all three examples reach every family destination. At 30 minutes by transit the family basket distinguishes all three. At 45 minutes the South and East Austin examples tie as the South Austin library trip enters the budget.</p>',
    report_html_table(budget),
    '<h2>Which destinations drive the count?</h2><p>Share of modeled origins reaching each type at the trial default. A higher count of eligible facilities does not establish availability of a slot, appointment or program.</p>',
    report_html_table(reach),
    '<h2>How much the housing profile changes the result</h2><p>Each percentage uses all reporting origins as its denominator. The older-adult and single-adult baskets currently have identical members. A separate job-access measure can still distinguish the questions staff ask about these developments. The supportive-housing basket omits behavioral health and supportive services.</p>',
    report_html_table(summary),
    '<p>Compare the fraction of the selected basket reached with the fraction of all eight types reached in the same cell. Higher, same and lower are counts of cells at the default budget. The mean difference is expressed on a 0–1 scale. Smaller baskets can score fully even where several other types are unavailable.</p>',report_html_table(comparisons),
    '<h2>Coverage and interpretation</h2>',
    paste0('<p>',nrow(tract),' clipped tracts are in the layer. ',sum(tract$resident_weight==0),
      ' have no positive resident weight in the covered cells. Their daily-access scores are unavailable. ',
      sum(tract$resident_weight_area_share<.5),' tracts have resident weights covering less than half their area. Inspect the containing hexagon when reviewing a specific site.</p>'),
    '<p>The morning transit model permits up to 20 minutes of walking and a 90-minute total trip. A modeled non-reach fails these trial thresholds. Unknown inputs remain missing. Park acreage, alternatives such as the fifth childcare facility, and jobs retain their native units. Childcare eligibility, vacancies, affordability, insurance acceptance and destination quality require separate review.</p>',
    '<p>Compare trial budgets with local trip evidence by purpose and mode and with residents’ accounts of a reasonable trip. The published survey describes observed travel. It does not establish an acceptable time for reaching a service. <a href="https://ftp.txdot.gov/pub/txdot-info/tpp/survey/austin-2017-household.pdf">2017 CAMPO household travel survey</a>.</p>',
    '<h2>Decisions for the City review</h2><ol><li>Which services belong in each profile? Which would need an on-site or provider check?</li><li>Which time budgets would staff use to compare otherwise similar sites?</li><li>Can reviewers use the count, jobs and schools separately, or does a funding decision require a point rule?</li></ol>',
    '<h2>Analysis files</h2><p>The GeoPackage has H8 and tract layers. Population comparisons use separate person, household or family weights across the modeled H8 origins. Their populations overlap. The dictionary describes all DAM source series.</p>',
    paste0('<ul>',links,'</ul></main></html>')),p)
  p
}
