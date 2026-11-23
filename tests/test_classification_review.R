if(dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"),.libPaths()))
for(p in list.files("R",pattern="\\.R$",full.names=TRUE)) source(p)
stopifnot(identical(classify_access(c(0,9999,10000,49999,50000,NA_real_),10000,50000),
 c("Limited access","Limited access","Intermediate","Intermediate","Strong access","Unknown")),
 identical(classify_burden(c(0,999,1000,1001,NA_real_),1000),
 c("Not flagged","Not flagged","Elevated burden","Elevated burden","Unknown")))
spec <- read_classification_spec("config/classification-review.yml")
x <- data.frame(access_total_jobs=c(0,0,0,30,30,30),rsei_tox_conc=c(0,0,0,90,90,90))
t <- candidate_thresholds(x,spec)
stopifnot(nrow(t)==6,!anyDuplicated(t$rule),t$high[t$rule=="burden_tertile"]==90,
 sum(classify_burden(x$rsei_tox_conc,90)=="Elevated burden")==3)
# Identical values are kept together, not forced into equal-count bins.
expect_error <- function(expr) stopifnot(inherits(try(force(expr),silent=TRUE),"try-error"))
x$rsei_tox_conc[1] <- NA_real_;expect_error(candidate_thresholds(x,spec))
cat("Classification checks passed: exact cutoffs, missingness, and ties.\n")
# Selected mockup uses a strict access cutoff and inclusive burden cutoff.
m <- classify_mockup(c(49999,50000,50001,NA_real_),c(99,100,101,NA_real_),spec$mockup)
stopifnot(identical(m$mockup_strong_access,c(FALSE,FALSE,TRUE,NA)),
          identical(m$mockup_elevated_burden,c(FALSE,TRUE,TRUE,NA)),
          m$mockup_access_label[4]=="Unknown",m$mockup_burden_label[4]=="Unknown")
expect_error(classify_mockup(1,1,list(strong_access_above=NA_real_,elevated_rsei_at_least=100)))
cat("Mockup cutoff checks passed.\n")
