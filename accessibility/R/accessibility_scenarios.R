read_accessibility_scenarios <- function(path = "config/destination_accessibility.yml") {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("Package 'yaml' is required.")
  config <- yaml::read_yaml(path)
  required <- c("geography", "inventories", "modes", "periods", "measures")
  missing <- setdiff(required, names(config))
  if (length(missing)) stop("Accessibility configuration is missing: ", paste(missing, collapse = ", "))
  config
}

accessibility_scenario_table <- function(config) {
  rows <- lapply(names(config$measures), function(name) {
    x <- config$measures[[name]]
    data.frame(
      scenario = name,
      destination = x$inventory,
      measure = x$method,
      modes = paste(x$modes, collapse = ","),
      periods = paste(x$periods, collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
