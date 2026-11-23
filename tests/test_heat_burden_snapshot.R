.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages(library(sf))
source('R/heat_burden.R')
r<-readRDS('output/components/heat-burden/analysis.rds');x<-r$scores
old<-read.csv('output/components/heat-validation/current_heat_indicators.csv')
i<-match(x$h3_id,old$h3_id)
stopifnot(nrow(x)==1029,!anyDuplicated(x$h3_id),!anyNA(i),
  isTRUE(all.equal(x$heat_score,old$quality_relative_rank[i],tolerance=1e-10)),
  all(x$heat_high==(x$heat_score>=90)),all(x$heat_thin_coverage==(x$dates_half_land<8)),
  sum(x$heat_high)==103,sum(x$heat_thin_coverage)==257,
  sum(x$heat_high & x$heat_thin_coverage)==21,all(is.finite(x$heat_score)))
e<-read.csv('output/components/heat-burden/scores.csv')
stopifnot(isTRUE(all.equal(e$heat_score,x$heat_score,tolerance=1e-10)))
g<-st_read('output/components/heat-burden/heat_burden.gpkg',quiet=TRUE)
stopifnot(nrow(g)==1029,setequal(g$h3_id,x$h3_id),st_crs(g)==st_crs(r$geometry))
# Prepared inputs are pinned; reject changed content rather than silently reranking.
spec<-r$spec;path<-tempfile(fileext='.csv');writeLines('changed',path)
spec$inputs$indicators$path<-path
bad<-try(read_heat_inputs(heat_input_files(spec),spec),silent=TRUE)
stopifnot(inherits(bad,'try-error'));unlink(path)
cat('Heat snapshot checks passed: all IDs, unchanged validated ranks, exact flags, retained thin scores, exports, CRS and rejection of changed reference inputs.\n')
