# Audit the current exported screen against the undissolved City source.
.libPaths(c('.R-library', .libPaths()))
suppressPackageStartupMessages(library(sf))
h <- st_transform(targets::tar_read(h8_geometry), 5070)
s <- targets::tar_read(flood_constraint_source)
r <- jsonlite::read_json('site/assets/flood-eligibility.json', simplifyVector=TRUE)$hex
stopifnot(setequal(h$h3_id, r$id), !anyDuplicated(r$id))
v <- r$overlap_share[match(h$h3_id, r$id)]
a <- as.numeric(st_area(h))
hits <- lengths(st_intersects(h, s$polygons)) > 0
stopifnot(identical(hits, v > 0))
partial <- v[v > 0 & v < 1]
# Keep no overlap separate from positive overlaps under 1%.
distribution <- data.frame(overlap=c('No overlap','>0 to <1%','1 to <5%',
  '5 to <10%','10 to <25%','25 to <50%','50 to <100%','100%'),
  hexes=c(sum(v==0),sum(v>0 & v<.01),sum(v>=.01 & v<.05),
    sum(v>=.05 & v<.1),sum(v>=.1 & v<.25),sum(v>=.25 & v<.5),
    sum(v>=.5 & v<1),sum(v==1)))
summary <- list(hex_count=length(v), raw_source_touched_hexes=sum(hits),
  full=sum(r$excluded), partial=length(partial), no_overlap=sum(v==0),
  full_hex_area_km2=sum(a)/1e6, flood_area_km2=sum(a*v)/1e6,
  area_share=sum(a*v)/sum(a), median_partial_share=median(partial),
  partial_below_one_tenth_percent=sum(partial<.001),
  minimum_positive_overlap_m2=min((a*v)[v>0]),
  source_manifest_sha256=digest::digest(file='data/raw/austin_fully_developed_floodplain/2026-11-09/manifest.json',algo='sha256'),
  distribution=distribution)
jsonlite::write_json(summary,'output/components/flood-eligibility/overlap-audit.json',auto_unbox=TRUE,pretty=TRUE,digits=12)
print(summary)
