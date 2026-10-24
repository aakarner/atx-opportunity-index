old_root <- Sys.getenv("ATX_LEGACY_ACCESSIBILITY_OUTPUT", "accessibility/output")
new_root <- Sys.getenv("ATX_NEW_ACCESSIBILITY_OUTPUT", "/private/tmp")
old_path <- file.path(old_root, "h8_auto_metro/dual_accessibility.csv")

if (!file.exists(old_path)) {
  cat("Skipping parity check: legacy comparison output is unavailable.\n")
  quit(status = 0)
}

suppressPackageStartupMessages({library(dplyr); library(readr)})
old <- read_csv(old_path, show_col_types = FALSE)
checks <- data.frame(
  destination = c("groceries", "groceries", "childcare", "childcare"),
  period = c("am_peak", "midday", "am_peak", "midday"),
  directory = c(
    "atx_access_grocery_third_nearest_drive_am_peak",
    "atx_access_grocery_third_nearest_drive_midday",
    "atx_access_childcare_fifth_nearest_drive_am_peak",
    "atx_access_childcare_fifth_nearest_drive_midday"
  )
)

for (i in seq_len(nrow(checks))) {
  new_path <- file.path(new_root, checks$directory[[i]], "accessibility.csv")
  if (!file.exists(new_path)) stop("Missing new comparison output: ", new_path)
  new <- read_csv(new_path, show_col_types = FALSE)
  comparison <- inner_join(
    filter(old, destination == checks$destination[[i]], period == checks$period[[i]]),
    new, by = c("origin_h3" = "geography_id")
  )
  stopifnot(nrow(comparison) == nrow(new))
  finite <- is.finite(comparison$travel_time_minutes)
  stopifnot(
    all.equal(
      comparison$travel_time_minutes[finite], comparison$access_value[finite],
      tolerance = 1e-10, check.attributes = FALSE
    ) == TRUE,
    sum(!finite) == sum(is.na(comparison$access_value))
  )
}
cat("Grocery and childcare replacement outputs match the legacy results.\n")
