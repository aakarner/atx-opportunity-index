# Data Axle settings shared by every destination's Data Axle scripts.
#
# Manual exports live in data/destinations/<destination>/raw/dataaxle/. The
# destination folder name is the Data Axle "collection" used in the rules
# below and in data/destinations/manual/dataaxle_reviews.csv. Collections are
# collection labels, not final classes: NAICS rules and manual review decide
# the destination_type of each record.
dataaxle_destinations <- c(
  "groceries", "healthy_foods", "healthcare", "libraries", "museums",
  "parks", "pharmacies", "community_organizations"
)

# Scope of the shared-address and source-ID duplicate checks.
#   "all_destinations"  : compare against every destination's exports (as the
#                         original combined script did). Flags, e.g., a grocery
#                         and its in-store pharmacy, or a "grocery" listing at a
#                         clinic's address, for review.
#   "within_destination": compare only within one destination.
dataaxle_duplicate_scope <- "all_destinations"

# Broad coordinate sanity screen only. Do not clip destinations to city limits
# or a small buffer before assessing the coverage needed by the OD analysis.
dataaxle_bbox <- c(xmin = -99, ymin = 29, xmax = -96, ymax = 32)
dataaxle_rule_version <- "2026-09-10-v1"

# These are Data Axle's extended codes observed in the supplied exports.
# Preserve all eight digits; naics6 is supplied separately for broader grouping.
# 'include' is a provisional code-based screen, not independent verification.
dataaxle_rules <- tibble::tribble(
  ~collection, ~code, ~destination_type, ~decision, ~reason,
  "pharmacies", "45611009", "pharmacies", "review", "Confirm active public-facing pharmacy rather than institutional or administrative site",
  "groceries", "44511001", "groceries", "include", "Grocery retailer code",
  "groceries", "44511003", "groceries", "include", "Grocery retailer code",
  "groceries", "44511006", "groceries", "include", "Grocery retailer code",
  "groceries", "44511007", "groceries", "include", "Grocery retailer code",
  "healthy_foods", "44523001", "produce_markets", "review", "Confirm food retail and public access",
  "healthy_foods", "44523003", "produce_markets", "review", "Confirm food retail and public access",
  "healthy_foods", "44523005", "juice_retailers", "review", "Juice retail is not automatically a produce market",
  "healthcare", "62149306", "urgent_care", "review", "Confirm walk-in urgent care at this location",
  "healthcare", "62149305", "ambulatory_surgery", "review", "Surgical center is not automatically urgent care",
  "healthcare", "62149304", "emergency_care", "review", "Confirm emergency service and facility location",
  "healthcare", "62211001", "hospitals", "review", "Confirm hospital facility rather than office or service listing",
  "healthcare", "62211002", "hospitals", "review", "Confirm hospital facility rather than office or service listing",
  "healthcare", "62211003", "hospitals", "review", "Confirm hospital facility rather than office or service listing",
  "healthcare", "62221001", "behavioral_health", "review", "Confirm direct service, setting, and eligibility",
  "healthcare", "62221002", "behavioral_health", "review", "Confirm direct service, setting, and eligibility",
  "healthcare", "62221003", "behavioral_health", "review", "Confirm direct service, setting, and eligibility",
  "healthcare", "62221006", "behavioral_health", "review", "Confirm direct service, setting, and eligibility",
  "libraries", "51921006", "libraries", "include", "Public library code",
  "museums", "71211001", "museums", "include", "Museum code",
  "parks", "71219004", "parks", "review", "Confirm public access and usable entrance coordinates"
)
