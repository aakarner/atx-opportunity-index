# Address parsing helpers for geocoder input
#
# Sourced by the destination pull scripts. Not run directly.
#
# Several source datasets store a full formatted address in what looks like a
# street field. HHSC's location_address is one: it holds the street line, city,
# state, and ZIP+4 in a single string, while city and zipcode repeat the same
# values separately. Submitting that whole string as the street line duplicates
# the city and state in the request, which the Census batch geocoder tolerates
# often enough to return a match but never an exact one, and which fails
# outright whenever a unit designator or unusual street type is also present.

# Secondary unit designators, including misspellings observed in the HHSC data.
# TIGER indexes street segments rather than suites, so anything after the street
# name confuses the parser and is removed.
secondary_unit_pattern <- regex(
  paste0(
    "\\s+(",
    paste(
      c(
        "ste", "sute", "suite", "unit", "apt", "apartment",
        "bldg", "building", "fl", "floor", "rm", "room",
        "trlr", "trailer", "lot", "spc", "space", "#"
      ),
      collapse = "|"
    ),
    ")\\s*[a-z0-9\\-]*\\s*$"
  ),
  ignore_case = TRUE
)

# Strip the city, state, and ZIP that follow the street line. The city value is
# used as the anchor rather than a general pattern, because a greedy match on
# capitalized words would eat the street name itself.
strip_trailing_locality <- function(address, city) {
  address <- str_squish(address)

  anchored <- if_else(
    !is.na(city) & str_trim(city) != "",
    str_remove(
      address,
      regex(
        paste0(
          "\\s+",
          str_replace_all(str_squish(city), "\\s+", "\\\\s+"),
          "\\s+TX\\b.*$"
        ),
        ignore_case = TRUE
      )
    ),
    address
  )

  # Fallback for records whose city field is blank or does not appear in the
  # address string: cut at the state token instead.
  if_else(
    anchored == address & str_detect(address, regex("\\sTX[-\\s]", ignore_case = TRUE)),
    str_remove(address, regex("\\s+[^\\s]+(\\s+[^\\s]+)?\\s+TX[-\\s].*$", ignore_case = TRUE)),
    anchored
  )
}

# ZIP+4 arrives space-separated in some sources. Census expects five digits or
# a hyphenated ZIP+4; a space-separated pair parses as neither.
normalize_zip <- function(zip) {
  zip %>%
    str_squish() %>%
    str_extract("\\d{5}")
}

# Full street-line cleaning: locality removal, then unit removal, then
# whitespace and punctuation normalization.
clean_street_line <- function(address, city) {
  address %>%
    strip_trailing_locality(city) %>%
    str_remove(secondary_unit_pattern) %>%
    str_replace_all("\\.", "") %>%
    str_squish()
}

# Diagnostic: show what the cleaning does to a sample, so the transformation is
# inspected rather than trusted. Call before submitting anything.
preview_address_cleaning <- function(data,
                                     address_column = "street_address",
                                     city_column    = "city",
                                     zip_column     = "zip",
                                     sample_size    = 20) {
  data %>%
    slice_sample(n = min(sample_size, nrow(data))) %>%
    transmute(
      original_street = .data[[address_column]],
      cleaned_street  = clean_street_line(
        .data[[address_column]], .data[[city_column]]
      ),
      city            = .data[[city_column]],
      original_zip    = .data[[zip_column]],
      cleaned_zip     = normalize_zip(.data[[zip_column]])
    )
}
