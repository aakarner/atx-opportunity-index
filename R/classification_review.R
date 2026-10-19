# Exploratory screening rules. These never alter the component measurements.
read_classification_spec <- function(path) {
  spec <- yaml::read_yaml(path)
  if (!length(spec$access_fixed) || !length(spec$burden_fixed)) stop("No candidate rules configured.")
  for (x in spec$access_fixed) {
    if (any(!is.finite(c(x$limited_below,x$strong_at_least))) ||
        x$limited_below < 0 || x$limited_below >= x$strong_at_least) stop("Invalid access thresholds.")
  }
  for (x in spec$burden_fixed) if (!is.finite(x$elevated_at_least) || x$elevated_at_least <= 0) stop("Invalid burden threshold.")
  validate_mockup_spec(spec$mockup)
  spec
}


validate_mockup_spec <- function(spec) {
  for (field in c("strong_access_above", "elevated_rsei_at_least")) {
    value <- spec[[field]]
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 0) {
      stop("Invalid mockup threshold: ", field)
    }
  }
  invisible(spec)
}

classify_mockup <- function(access, burden, spec) {
  validate_mockup_spec(spec)
  if(length(access) != length(burden)) stop("Mockup measurements must have matching lengths.")
  strong <- access > spec$strong_access_above
  elevated <- burden >= spec$elevated_rsei_at_least
  data.frame(mockup_strong_access = strong, mockup_elevated_burden = elevated,
    mockup_access_label = ifelse(is.na(strong), "Unknown", ifelse(strong, "Strong access", "Not flagged as strong")),
    mockup_burden_label = ifelse(is.na(elevated), "Unknown", ifelse(elevated, "Elevated burden", "Not flagged")))
}

candidate_thresholds <- function(h8, spec) {
  access <- h8$access_total_jobs; burden <- h8$rsei_tox_conc
  if (anyNA(access) || anyNA(burden)) stop("Candidate baseline requires complete H8 measurements.")
  a <- as.numeric(quantile(access,c(1/3,2/3),type=7))
  b <- as.numeric(quantile(burden,2/3,type=7))
  rows <- list(data.frame(dimension="access",rule="access_tertiles",label="Access: baseline tertiles",
    low=a[1],high=a[2],basis="Relative comparator: unweighted Austin H8 baseline; not an adequacy standard"),
    data.frame(dimension="burden",rule="burden_tertile",label="RSEI: upper baseline tertile",
    low=NA_real_,high=b,basis="Relative comparator: unweighted Austin H8 baseline; not a health standard"))
  for (x in spec$access_fixed) rows[[length(rows)+1L]] <- data.frame(dimension="access",rule=x$id,label=x$label,
    low=x$limited_below,high=x$strong_at_least,basis="Illustrative fixed job-count threshold; not adopted or validated for adequacy")
  for (x in spec$burden_fixed) rows[[length(rows)+1L]] <- data.frame(dimension="burden",rule=x$id,label=x$label,
    low=NA_real_,high=x$elevated_at_least,basis="Illustrative fixed RSEI threshold; not a health/safety standard")
  out <- dplyr::bind_rows(rows)
  require_unique_id(out,"rule","Candidate rules")
  out$reference <- "All available H8 origins centered in Austin; same numeric thresholds applied to tract means"
  out
}

classify_access <- function(x, low, high) {
  ifelse(is.na(x),"Unknown",ifelse(x>=high,"Strong access",ifelse(x<low,"Limited access","Intermediate")))
}
classify_burden <- function(x, high) {
  ifelse(is.na(x),"Unknown",ifelse(x>=high,"Elevated burden","Not flagged"))
}

compare_classifications <- function(h8, tracts, thresholds, tract_rsei_crosswalk, city) {
  h8 <- sf::st_transform(h8,5070); tracts <- sf::st_transform(tracts,5070); city <- sf::st_transform(city,5070)
  sets <- list(H8=h8,Tract=tracts)
  flags <- list(); summaries <- list(); pairs <- list(); agreements <- list()
  for (geo in names(sets)) {
    x <- sets[[geo]]
    id <- if(geo=="H8") x$h3_id else x$GEOID
    access <- if(geo=="H8") x$access_total_jobs else x$transit_jobs_45min
    # City-area denominators make boundary H8 cells comparable with clipped tracts.
    clipped <- if(geo=="H8") suppressWarnings(sf::st_intersection(x, sf::st_union(sf::st_geometry(city)))) else x
    clip_ids <- if(geo=="H8") clipped$h3_id else clipped$GEOID
    area_by_id <- tapply(as.numeric(sf::st_area(clipped))/1e6,clip_ids,sum)
    area <- unname(area_by_id[id])
    if(anyNA(area) || any(area<=0)) stop("Missing City-clipped comparison area.")
    weights <- if(geo=="H8") x$workers_all else rep(NA_real_,nrow(x))
    classes <- list()
    for(i in seq_len(nrow(thresholds))) {
      t <- thresholds[i,]
      v <- if(t$dimension=="access") access else x$rsei_tox_conc
      cls <- if(t$dimension=="access") classify_access(v,t$low,t$high) else classify_burden(v,t$high)
      classes[[t$rule]] <- cls
      flags[[length(flags)+1L]] <- data.frame(geography=geo,id=id,rule=t$rule,dimension=t$dimension,
        value=v,classification=cls,city_area_km2=area,workers=weights)
      for(c in unique(cls)) {
        keep <- cls==c
        summaries[[length(summaries)+1L]] <- data.frame(geography=geo,rule=t$rule,classification=c,
          units=sum(keep),unit_pct=100*mean(keep),city_area_km2=sum(area[keep]),
          area_pct=100*sum(area[keep])/sum(area),
          worker_pct=if(geo=="H8") 100*sum(weights[keep])/sum(weights) else NA_real_)
      }
    }
    for(a in thresholds$rule[thresholds$dimension=="access"]) {
      for(b in thresholds$rule[thresholds$dimension=="burden"]) {
        strong <- classes[[a]]=="Strong access"; high <- classes[[b]]=="Elevated burden"
        pairs[[length(pairs)+1L]] <- data.frame(geography=geo,access_rule=a,burden_rule=b,
          strong_access=sum(strong),elevated_burden=sum(high),both=sum(strong & high),
          strong_not_flagged=sum(strong & classes[[b]]=="Not flagged"),
          limited_and_elevated=sum(classes[[a]]=="Limited access" & high))
      }
    }
    for(dimension in c("access","burden")) {
      rules <- thresholds$rule[thresholds$dimension==dimension]
      for(ij in combn(rules,2,simplify=FALSE)) agreements[[length(agreements)+1L]] <- data.frame(
        geography=geo,dimension=dimension,rule_a=ij[1],rule_b=ij[2],
        changed_units=sum(classes[[ij[1]]]!=classes[[ij[2]]]),
        changed_pct=100*mean(classes[[ij[1]]]!=classes[[ij[2]]]))
    }
  }
  # Native-grid hotspot fractions preserve sub-tract information hidden by means.
  hotspots <- lapply(which(thresholds$dimension=="burden"), function(i) {
    t <- thresholds[i,]
    dplyr::bind_rows(lapply(split(tract_rsei_crosswalk,tract_rsei_crosswalk$GEOID),function(z) {
      coverage <- sum(z$overlap_area_m2)/z$reporting_area_m2[1]
      data.frame(GEOID=z$GEOID[1],rule=t$rule,
        native_flagged_area_share=if(abs(coverage-1)<1e-6) sum(z$overlap_area_m2[z$ToxConc>=t$high])/z$reporting_area_m2[1] else NA_real_)
    }))
  })
  list(flags=dplyr::bind_rows(flags),summary=dplyr::bind_rows(summaries),
       pairs=dplyr::bind_rows(pairs),switches=dplyr::bind_rows(agreements),hotspots=dplyr::bind_rows(hotspots))
}

write_classification_review <- function(comparison, thresholds, h8, tracts, sites, city, spec, output_dir, source_files) {
  h8 <- sf::st_transform(h8,5070); tracts <- sf::st_transform(tracts,5070); city <- sf::st_transform(city,5070)
  directory <- file.path(output_dir,"classification-review")
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  paths <- write_pipeline_csv(thresholds,directory,"candidate_thresholds.csv")
  provenance <- as.data.frame(jsonlite::read_json(source_files[endsWith(source_files,".json")],simplifyVector=TRUE))
  paths <- c(paths,write_pipeline_csv(provenance,directory,"rsei_source_provenance.csv"))
  for(n in names(comparison)) paths <- c(paths,write_pipeline_csv(comparison[[n]],directory,paste0(n,".csv")))
  # Wide, georeferenced tables make every flagged location inspectable in GIS.
  spatial <- list(H8=h8,Tract=tracts)
  gpkg <- file.path(directory,"candidate_flags.gpkg")
  map_paths <- character()
  mockup_summary <- list()
  palette <- c("Strong access"="#16766d","Intermediate"="#e7e9e4","Limited access"="#c29040",
               "Elevated burden"="#a13e54","Not flagged"="#e7e9e4","Unknown"="#6e7174",
               "No H8 origin"="#b7c4cf")
  for(geo in names(spatial)) {
    x <- spatial[[geo]]; ids <- if(geo=="H8") x$h3_id else x$GEOID
    selected <- classify_mockup(if(geo=="H8") x$access_total_jobs else x$transit_jobs_45min,
                                x$rsei_tox_conc, spec$mockup)
    x <- cbind(x, selected)
    mockup_summary[[geo]] <- data.frame(geography=geo, units=nrow(x),
      strong_access=sum(selected$mockup_strong_access,na.rm=TRUE),
      elevated_burden=sum(selected$mockup_elevated_burden,na.rm=TRUE),
      both=sum(selected$mockup_strong_access & selected$mockup_elevated_burden,na.rm=TRUE),
      unknown_access=sum(is.na(selected$mockup_strong_access)),
      unknown_burden=sum(is.na(selected$mockup_elevated_burden)))
    panels <- list()
    for(i in seq_len(nrow(thresholds))) {
      t <- thresholds[i,]
      f <- comparison$flags[comparison$flags$geography==geo & comparison$flags$rule==t$rule,]
      x[[t$rule]] <- f$classification[match(ids,f$id)]
      panel <- x[,if(geo=="H8") "h3_id" else "GEOID"]
      panel$classification <- x[[t$rule]]
      cutoff <- if(t$dimension=="access") paste0("Limited < ",format(round(t$low),big.mark=",",scientific=FALSE,trim=TRUE),"; strong >= ",format(round(t$high),big.mark=",",scientific=FALSE,trim=TRUE)," jobs") else paste0("Elevated >= ",format(signif(t$high,4),trim=TRUE)," ToxConc")
      panel$rule_label <- paste(t$label,cutoff,sep="\n")
      panel$dimension <- t$dimension
      panels[[length(panels)+1L]] <- panel
    }
    sf::st_write(x,gpkg,layer=tolower(geo),delete_dsn=geo=="H8",quiet=TRUE)
    wide <- sf::st_drop_geometry(x)
    if(geo=="H8") {
      hits <- sf::st_intersects(sf::st_transform(h3jsr::cell_to_point(x$h3_id),sf::st_crs(tracts)),tracts)
      wide$center_tract <- vapply(hits,function(z) if(length(z)==1) tracts$GEOID[z] else NA_character_,character(1))
    }
    paths <- c(paths,write_pipeline_csv(wide,directory,paste0(tolower(geo),"_flagged_locations.csv")))
    for(dimension in c("access","burden")) {
      pdat <- dplyr::bind_rows(panels);pdat <- pdat[pdat$dimension==dimension,]
      pdat$rule_label <- factor(pdat$rule_label,levels=unique(pdat$rule_label))
      # Report maps clip H8 shapes at Austin; source H8 measures cover full cells.
      if(geo=="H8") pdat <- suppressWarnings(sf::st_intersection(pdat,sf::st_union(sf::st_geometry(city))))
      plot <- ggplot2::ggplot()
      if(geo=="H8") plot <- plot + ggplot2::geom_sf(data=city,ggplot2::aes(fill="No H8 origin"),colour=NA)
      plot <- plot+ggplot2::geom_sf(data=pdat,ggplot2::aes(fill=classification),colour=NA)+
        ggplot2::geom_sf(data=city,fill=NA,colour="#59666d",linewidth=.2)+
        ggplot2::facet_wrap(~rule_label,nrow=1)+
        ggplot2::scale_fill_manual(values=palette,name=NULL,drop=TRUE)+component_map_theme()+
        ggplot2::labs(title=paste(geo,if(dimension=="access") "job-access classifications" else "industrial-burden flags"),
          subtitle="Candidate rules for discussion; no adopted adequacy or health standards",
          caption=if(dimension=="access") "2023 jobs; 45-minute walk + transit access on the pinned summer 2026 network.\nTracts use resident-worker-weighted access; H8 cells are displayed clipped to Austin." else "EPA RSEI 2022 v2.3.12; modeled air toxicity-weighted concentration, averaged by area.\nNot flagged does not mean safe. All maps use the same H8-derived or fixed numerical cutoffs.")
      path <- file.path(directory,paste0(tolower(geo),"_",dimension,".png"))
      ggplot2::ggsave(path,plot,width=14,height=7,dpi=160,bg="white")
      map_paths <- c(map_paths,path)
    }
  }
  mockup_summary <- dplyr::bind_rows(mockup_summary)
  paths <- c(paths,write_pipeline_csv(mockup_summary,directory,"mockup_summary.csv"),
    write_pipeline_csv(data.frame(dimension=c("access","burden"),operator=c(">",">="),
      threshold=c(spec$mockup$strong_access_above,spec$mockup$elevated_rsei_at_least)),directory,"mockup_thresholds.csv"))
  # Distribution summaries and example locations accompany map patterns.
  fields <- c("access_total_jobs","access_low_wage_jobs","access_middle_wage_jobs","access_high_wage_jobs","rsei_tox_conc")
  dist <- dplyr::bind_rows(lapply(fields,function(f) data.frame(measure=f,
    min=min(h8[[f]]),q33=unname(quantile(h8[[f]],1/3)),median=median(h8[[f]]),
    q67=unname(quantile(h8[[f]],2/3)),q90=unname(quantile(h8[[f]],.9)),max=max(h8[[f]]))))
  paths <- c(paths,write_pipeline_csv(dist,directory,"distributions.csv"))
  # Existing examples remain illustrative origins, not proposed developments.
  examples <- sf::st_drop_geometry(sites)
  examples$h3_id <- h3jsr::point_to_cell(sf::st_transform(sites,4326),res=8,simple=TRUE)
  j <- match(examples$h3_id,h8$h3_id)
  examples$jobs_45min <- h8$access_total_jobs[j]
  examples$low_wage_jobs_45min <- h8$access_low_wage_jobs[j]
  examples$rsei_tox_conc_h8 <- h8$rsei_tox_conc[j]
  for(i in seq_len(nrow(thresholds))) {
    t <- thresholds[i,]
    examples[[t$rule]] <- if(t$dimension=="access") classify_access(examples$jobs_45min,t$low,t$high) else classify_burden(examples$rsei_tox_conc_h8,t$high)
  }
  examples <- cbind(examples,classify_mockup(examples$jobs_45min,examples$rsei_tox_conc_h8,spec$mockup))
  paths <- c(paths,write_pipeline_csv(examples,directory,"example_locations.csv"))
  # Continuous concentrations vs accessibility, not a synthetic net score.
  scatter <- ggplot2::ggplot(sf::st_drop_geometry(h8),ggplot2::aes(x=access_total_jobs,y=rsei_tox_conc))+
    ggplot2::geom_point(alpha=.35,size=1.3,colour="#345b67")+
    ggplot2::scale_x_continuous(trans="log1p",breaks=c(0,10,100,1000,10000,100000,300000),
      labels=c("0","10","100","1,000","10,000","100,000","300,000"))+
    ggplot2::scale_y_continuous(trans="log1p",breaks=c(10,30,100,300,1000,3000),labels=map_number_labels)+ggplot2::theme_minimal(base_size=12)+
    ggplot2::labs(title="Job access and industrial burden can coexist",x="Jobs reachable in 45 minutes (log1p scale)",
      y="RSEI toxicity-weighted concentration (log1p scale)",caption="One point per Austin H8 origin. Neither axis is a rank or combined index.")
  path <- file.path(directory,"access_burden_scatter.png")
  ggplot2::ggsave(path,scatter,width=10,height=6,dpi=160,bg="white");map_paths<-c(map_paths,path)
  city_km2 <- sum(as.numeric(sf::st_area(city)))/1e6
  h8_km2 <- sum(comparison$summary$city_area_km2[comparison$summary$geography=="H8" & comparison$summary$rule=="access_tertiles"])
  coverage_note <- paste0("The available H8 origins cover ",round(h8_km2,1)," of ",round(city_km2,1),
    " square kilometers of Austin (",round(100*h8_km2/city_km2,1),"%). Blue-grey areas on H8 maps have no source origin. H8 area percentages use the covered area as denominator; tract percentages use the City-clipped tract area. These denominators differ.")
  headline <- dplyr::bind_rows(lapply(seq_len(nrow(thresholds)),function(i) {
    t <- thresholds[i,]
    cls <- if(t$dimension=="access") "Strong access" else "Elevated burden"
    z <- comparison$summary[comparison$summary$rule==t$rule & comparison$summary$classification==cls,]
    data.frame(rule=t$label,flag=cls,cutoff=t$high,
      hexagons=sum(z$units[z$geography=="H8"]),
      hexagon_pct=round(sum(z$unit_pct[z$geography=="H8"]),1),
      tracts=sum(z$units[z$geography=="Tract"]))
  }))
  paths <- c(paths,write_pipeline_csv(headline,directory,"headline_comparison.csv"))
  compact <- comparison$summary
  compact[vapply(compact,is.numeric,logical(1))] <- lapply(compact[vapply(compact,is.numeric,logical(1))],function(v) round(v,2))
  hidden <- merge(comparison$hotspots,comparison$flags[comparison$flags$geography=="Tract",c("id","rule","classification")],
                  by.x=c("GEOID","rule"),by.y=c("id","rule"))
  hidden <- hidden[hidden$classification=="Not flagged" & hidden$native_flagged_area_share>=.1,]
  hidden <- hidden[order(-hidden$native_flagged_area_share),]
  paths <- c(paths,write_pipeline_csv(hidden,directory,"tract_hotspots_hidden_by_mean.csv"))
  plots <- vapply(map_paths,function(p) paste0('<figure><img src="',basename(p),'" alt="',basename(p),'"></figure>'),character(1))
  links <- paste0('<li><a href="',basename(c(paths,gpkg)),'">',basename(c(paths,gpkg)),'</a></li>',collapse="")
  html <- paste0('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Austin: candidate benefit and burden flags</title><style>body{font:16px/1.5 system-ui;color:#24383e;background:#f4f5f1;margin:0}main{max-width:1300px;margin:auto;padding:32px}h1{line-height:1.15}h2{margin-top:2em}.notice{background:#fff1d7;padding:18px;border-left:5px solid #b48030}table{border-collapse:collapse;font-size:13px;background:white;width:100%}td,th{padding:8px;text-align:left;border-bottom:1px solid #ddd}th{background:#e2eae6}img{width:100%;height:auto}figure{margin:24px 0;background:white}.table-scroll{overflow:auto}p{max-width:1050px}a{color:#126d70}</style><main>',
    '<p>AUSTIN OPPORTUNITY INDEX / METHODS REVIEW</p><h1>What gets flagged?</h1><p>Real job-access estimates and EPA industrial-air modeling, with alternative rules for discussion.</p>',
    '<div class="notice"><b>These are candidate classifications, not adopted standards.</b> The fixed thresholds are sensitivity scenarios. The tertile rules are relative comparisons. No combined score, development recommendation, or health/safety determination is made.</div>',
    '<h2>Selected rules for the mockup</h2><p><strong>Strong access: &gt; ',
    format(spec$mockup$strong_access_above,big.mark=",",scientific=FALSE,trim=TRUE),
    ' jobs reachable within 45 minutes. Elevated industrial burden: RSEI &ge; ',
    spec$mockup$elevated_rsei_at_least,'.</strong> These fixed rules apply to H8 cells and tract means. Exactly the access cutoff does not qualify as strong access. Missing values remain unknown. No lower access cutoff has been selected.</p>',
    report_html_table(mockup_summary),
    '<p>The location tables and GeoPackage include fields prefixed with <code>mockup_</code> for these selections. The comparisons below retain their original candidate rules, including the inclusive 50,000-job comparator.</p>',
    '<h2>Candidate comparison at a glance</h2>',report_html_table(headline),
    '<p>Access thresholds are jobs reachable in 45 minutes; burden thresholds are RSEI air ToxConc. Compare the maps before choosing a rule. Neither a high access flag nor the absence of an industrial-burden flag establishes an adequate location across all dimensions.</p>',
    '<h2>How to read this comparison</h2><p>Every rule is applied to ',nrow(h8),' H8 origins and ',nrow(tracts),' City-clipped tracts. Tertile cutoffs come from all available Austin H8 origins (equal weight per cell); identical numerical cutoffs are used for tract means. Equal values stay together. Limited access is strictly below the lower cutoff; strong access and elevated burden include the upper cutoff. Unknown stays unknown.</p>',
    '<p>Access uses 2023 jobs and a June 25, 2026 network snapshot for the pinned July 13 morning. RSEI uses 2022 emissions, model v2.3.12. This is a mixed-vintage baseline, not a current-year exposure estimate. Tract access is resident-worker weighted with documented fallbacks. RSEI means are area weighted from the native 810 m grid; no population multiplier. H8 measures describe full source cells, while map shapes and area shares are clipped to Austin. Worker shares use existing H8 worker counts, including the full boundary cells, and are not a precise City resident total.</p>',
    '<p>Municipal boundary: ',report_html_escape(city$boundary_source),' · snapshot ',report_html_escape(city$boundary_snapshot),'. Includes Dog’s Head; ETJ excluded. Census tract geometry and ACS remain 2024.</p>',
    '<p>',coverage_note,' Tract access uses a nearest-H8 fallback in ',sum(tracts$access_aggregation_method=="nearest H8 origin fallback"),' boundary tracts; these remain explicitly flagged in the location tables.</p>',
    '<h2>Candidate thresholds</h2>',report_html_table(thresholds),
    '<h2>Distribution of the underlying H8 measures</h2>',report_html_table(dist),
    '<h2>How much gets flagged?</h2>',report_html_table(compact),
    '<h2>Where classifications change</h2>',paste(plots[1:4],collapse=""),
    '<h2>Benefit and burden together</h2>',plots[5],report_html_table(comparison$pairs),
    '<h2>Sensitivity to rule choice</h2>',report_html_table(comparison$switches),
    '<h2>Existing example locations</h2>',report_html_table(examples),
    '<h2>Hotspots hidden by tract averages</h2><p>Below: up to 20 tract/rule combinations whose mean is not flagged but at least 10% of tract area exceeds that same cutoff in the native EPA grid. This 10% is a review aid, not a proposed policy rule. Full results are in the downloads.</p>',report_html_table(head(hidden,20)),
    '<h2>Sources and limits</h2><p><a href="https://www.epa.gov/rsei/rsei-data-dictionary-aggregated-grid-cell-geographic-microdata">EPA data dictionary</a> · <a href="https://www.epa.gov/rsei/documentation-risk-screening-environmental-indicators-rsei-geographic-microdata-rsei-gm">EPA geographic microdata documentation</a>. RSEI covers modeled TRI-related air releases, not all pollution. Concentration is multiplied by relative inhalation toxicity weights; it is not an excess-cancer-risk or safe-exposure estimate. Aggregated data cannot identify which facility or chemical drives a hotspot. Cancer and noncancer values are retained separately and are not added to the total.</p>',
    '<p>Pipeline checks preserve missing measurements, validate complete overlap, and retain source-record status. EPA documents absent national-file cells as unaffected by modeled releases; those are model zeros, not evidence of clean air. Source URL, version, reporting year and SHA-256 are retained in the source manifest.</p>',
    '<h2>Download the evidence</h2><ul>',links,'</ul><p>Rebuild: <code>Rscript scripts/run_pipeline.R classification_report</code>. All rules remain separate from the production component measures.</p></main></html>')
  report <- file.path(directory,"review.html");writeLines(html,report)
  c(report,paths,gpkg,map_paths)
}
