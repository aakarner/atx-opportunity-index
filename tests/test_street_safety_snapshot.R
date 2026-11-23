.libPaths(c('.R-library', .libPaths()))
suppressPackageStartupMessages(library(sf))
r <- readRDS('output/components/street-safety/analysis.rds')
s <- r$policy$scoring
for (k in names(r$results)) {
  x <- r$results[[k]]
  scored <- x$frontage_status == 'available'
  expected_counts <- if (k == 'primary') c(874,125,30) else c(731,271,27)
  stopifnot(nrow(x)==1029, !anyDuplicated(x$h3_id),
    all(table(factor(x$frontage_status, levels=c('available','no_major_street','no_pedestrian_inventory'))) == expected_counts),
    identical(is.finite(x$major_frontage_score), scored),
    all(x$major_frontage_score[scored] >= 0 & x$major_frontage_score[scored] <= 100),
    all(abs(x$major_frontage_score[scored] - 100*(1-x$major_served_m[scored]/x$major_frontage_m[scored])) < 1e-10),
    identical(x$major_frontage_high, x$major_frontage_score>=50),
    isTRUE(all.equal(x$crash_score, pmin(100,100*x$annual_ksi_density/s$crash_full_burden_density))))
  csv <- read.csv(file.path('output/components/street-safety', paste0(k,'.csv')))
  for (layer in c('hex','windows')) {
    g <- st_read('output/components/street-safety/street_safety.gpkg',layer=paste(k,layer,sep='_'),quiet=TRUE)
    stopifnot(nrow(g)==1029, st_crs(g)$epsg==26914)
    for (field in c('crash_score','major_frontage_score','major_served_m','major_frontage_m'))
      stopifnot(isTRUE(all.equal(g[[field]][match(csv$h3_id,g$h3_id)], csv[[field]], tolerance=1e-10)))
  }
}
p <- r$results$primary
q <- r$results$sensitivity[match(p$h3_id, r$results$sensitivity$h3_id), ]
stopifnot(all(p$major_frontage_m >= q$major_frontage_m - 1e-7), all(p$major_served_m >= q$major_served_m - 1e-7),
  all(p$ksi_count >= q$ksi_count), abs(quantile(p$annual_ksi_density,.95)-s$crash_full_burden_density)<1e-10,
  abs(quantile(p$annual_ksi_density,.9)-s$crash_high_burden_density)<1e-10)
cat('Street-safety snapshot, radii, and exports verified.\n')
