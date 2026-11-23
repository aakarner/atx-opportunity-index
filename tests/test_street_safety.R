.libPaths(c('.R-library', .libPaths()))
source('R/street_safety.R')
policy <- yaml::read_yaml('config/burdens.yml')$domain_components$street_safety_pedestrian_environment
anchor <- policy$scoring$crash_full_burden_density
high <- policy$scoring$crash_high_burden_density
fixture <- data.frame(annual_ksi_density = c(0, anchor/2, anchor, 2*anchor, high, high-1e-8, NA, high, 0, NA),
  major_frontage_m = c(rep(100, 8), 0, NA), major_served_m = c(100,60,0,100,50,50,25,0,0,NA),
  inventory_observed = c(rep(TRUE,6), FALSE,FALSE,TRUE,NA))
x <- score_street_safety(fixture, policy)
stopifnot(isTRUE(all.equal(x$crash_score[1:4], c(0,50,100,100))),
  isTRUE(all.equal(x$major_frontage_score, c(0,40,100,0,50,50,75,NA,NA,NA))),
  x$crash_high[5], !x$crash_high[6], x$major_frontage_high[5], x$any_high[7], x$any_high[8], is.na(x$any_high[9]),
  identical(tail(x$frontage_status,3), c('no_pedestrian_inventory','no_major_street','no_city_observation_area')),
  x$flag_detail[8]=='High; other component unavailable')
cat('Street-safety scoring and missingness checks passed.\n')
