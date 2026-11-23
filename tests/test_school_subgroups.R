source("scripts/prepare/pull_school_subgroups.R")
# Combine points and tests, rather than averaging rounded subject scores.
stopifnot(pooled_growth(10, 20, 50, 90, 100, 90) == 100 * 100 / 120)
# Masked/absent rates and empty denominators must not be reconstructed.
stopifnot(is.na(pooled_growth(10, 20, NA, 90, 100, 90)),
  is.na(pooled_growth(0, 0, 0, 90, 100, 90)),
  is.na(pooled_growth(10, 20, 50, NA, 100, 90)))
# Growth is points-based: retain bonus-driven scores, and never turn masks into zero.
stopifnot(pooled_growth(10.25, 10, 103, 10.25, 10, 103) == 102.5,
  identical(tea_number(c("-1", "*", "", "0", "103")), c(NA_real_, NA_real_, NA_real_, 0, 103)))
cat("Subgroup pooling and masking checks passed.\n")
