# Final pharmacy layer: source and cleaning note

## Purpose

The final pharmacy layer is intended to represent active, community-facing
pharmacy locations in the Austin metropolitan area. It combines the regulatory
coverage of the Texas State Board of Pharmacy (TSBP) with the generally more
accurate point locations available from Data Axle.

## Source roles

- **TSBP license data** determine whether a location is eligible. The inventory
  retains active Community Pharmacy and Community Sterile Compounding Pharmacy
  licenses that are not identified as closed-door facilities.
- **Data Axle pharmacy records** supplement coordinates and business identity.
  A Data Axle record is used only when it can be linked confidently to an
  eligible TSBP license. A Data Axle-only business is not automatically added.
- **U.S. Census batch geocoder results** provide fallback coordinates for
  eligible TSBP records that do not have a reliable Data Axle match.

This division of roles avoids treating a commercial business listing as proof
of pharmacy eligibility while still benefiting from Data Axle's point-location
accuracy.

## Screening the original TSBP roster

The original TSBP pharmacy roster contains community pharmacies together with
hospital, clinic, emergency-center, central-processing, nuclear, and other
pharmacy licenses. It also contains inactive licenses and pharmacies that do
not serve walk-in customers. The following reproducible screening rule was
therefore applied before any matching or geocoding:

1. Retain Texas records whose `COUNTY` is Bastrop, Caldwell, Hays, Travis, or
   Williamson. This produced 522 metro-area licenses.
2. Require `LIC_STATUS` to equal **Active**. Expired, probation, and revoked
   licenses were left in the full review table but excluded from the final
   candidate inventory.
3. Require `CLASS` to equal **Community Pharmacy** or **Community Sterile
   Compounding**. Institutional or hospital, institutional sterile
   compounding, clinic, freestanding emergency medical care, central
   processing, and nuclear pharmacy classes were excluded as separate facility
   types rather than ordinary community pharmacy destinations.
4. Require `CLOSED DOOR` to equal **N**. This removes community-class licenses
   identified by TSBP as closed-door operations.

There were 516 active licenses, 343 of which had one of the two selected
community classes. Removing 25 closed-door licenses produced **318 community
pharmacy candidates**. In the source data, these consist of 301 Community
Pharmacy licenses and 17 Community Sterile Compounding licenses.

Fields such as ownership type, 24-hour service, home delivery, infusion,
nonsterile compounding, disability access, language services, and Medicaid
participation were preserved as descriptive attributes; they were not used to
exclude otherwise eligible pharmacies. This screening identifies likely
community-facing pharmacies, but `CLOSED DOOR = N` alone does not prove that
any person can obtain service without membership, health-system affiliation,
or other restrictions. The final matching and manual-review steps provide
additional checks, and access restrictions remain a limitation for later
review.

## Cleaning and matching rules

1. TSBP records were limited to the five-county Austin metropolitan area:
   Bastrop, Caldwell, Hays, Travis, and Williamson counties.
2. Only eligible community-pharmacy license classes and open-door facilities
   were retained. Names, addresses, ZIP codes, phone numbers, ownership, and
   service attributes were standardized without replacing the original TSBP
   meaning.
3. TSBP addresses were submitted to the U.S. Census batch geocoder.
4. TSBP and Data Axle records were compared using phone number, street number,
   ZIP code, business name, and major-chain identity. A match was accepted when
   the evidence met a conservative rule, such as an identical phone number,
   matching street number and chain, matching street number with a similar
   name, or a very high name similarity.
5. For an accepted match, the Data Axle coordinates were used because visual
   review found them more accurate for storefronts and pharmacies located
   inside H-E-B, Randall's, Costco, Walmart, Sam's Club, CVS, and Walgreens.
   The Census coordinate was retained when no reliable Data Axle match existed.
6. Multiple eligible licenses at the same physical pharmacy were consolidated
   into one destination point. All associated license numbers and licensed
   names remain in the attribute table.
7. Records without a plausible coordinate from either source were manually
   checked against current pharmacy or health-system pages. Verified addresses
   were placed using a documented address coordinate and flagged as manually
   reviewed in `coordinate_source`.

## Final inventory and quality checks

The October 2026 build started with **318 eligible TSBP licenses** and produced
**316 unique pharmacy sites**. Data Axle matched 280 licenses. It recovered 46
licenses for which Census geocoding had failed; after same-site deduplication,
these contributed **45 additional physical pharmacy points**. The final sites
use the following coordinate sources:

- 233 Data Axle coordinates preferred over available Census coordinates;
- 45 Data Axle coordinates that recovered missing Census geocodes; and
- 33 Census geocoder coordinates where no reliable Data Axle match was found;
  and
- 5 manually verified address coordinates.

The five previously unresolved licenses were confirmed as current pharmacy
destinations and retained: Gattis Pharmacy in Hutto, Costco Pharmacy #1767 in
Liberty Hill, Dell Children's Outpatient Pharmacy - North in Austin, CVS
Pharmacy #17954 in Liberty Hill, and North Central Pharmacy in Austin. Their
coordinates and review references are recorded in
`destinations/pharmacies/manual_coordinate_overrides.csv`.

The final layer passed checks for unique site identifiers, valid point
geometry, and plausible longitude and latitude values. It is saved as
`data/destinations/pharmacies/processed/pharmacies_final.gpkg`, layer
`pharmacies`. The reproducible build script is
`destinations/pharmacies/05_build_final_pharmacies_inventory.R`.

## Interpretation and future review

The layer is a compiled inventory of licensed pharmacy destinations. It does
not measure current medicine availability, operating hours, prescription
capacity, affordability, or public access on a particular day. TSBP status and
commercial listings can change. Before the final accessibility analysis, a
sample of matched locations should be checked against current store or
regulatory information.
