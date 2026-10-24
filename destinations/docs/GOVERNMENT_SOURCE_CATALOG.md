# Government destination sources

Discovery checked 2026-09-11. These are source recommendations, not new imported
layers. Portal/directory availability was checked; individual downloads, current
schemas, coordinates, and completeness have not yet been validated. Retain the
existing Data Axle extracts for comparison and supplementation.

## Recommended sources by destination

| Destination | Official source | Coverage and access | Preparation and limitations |
|---|---|---|---|
| Public libraries | [Austin Public Library Locations](https://data.austintexas.gov/Locations-and-Maps/Austin-Public-Library-Locations/tc36-hn4j); [Texas State Library public-library directory](https://www.tsl.texas.gov/ldn/contactinfo) and [annual statistics](https://www.tsl.texas.gov/ldn/statistics) | City location dataset; statewide directory and annual library/branch reports support metro coverage | Use physical branches/outlets rather than library-system headquarters; separate bookmobiles. Inspect address/coordinate fields before import. |
| Recreation/community centers | [City recreation-center dataset](https://data.austintexas.gov/d/8dff-2vkt); [official location directory](https://www.austintexas.gov/parks/locations/community-recreation-centers) | Austin-operated facilities; portal and directory | Confirm current sites/programs. Recreation centers are a specific service category, not every community organization. Other metro municipalities need separate inventories. |
| Neighborhood/social-service centers | [Austin Neighborhood Centers](https://www.austintexas.gov/services/get-help-neighborhood-centers) | City-operated service locations, addresses and service descriptions | Curate/geocode actual service sites and check closures or relocations. Strong defined subset for food assistance, navigation and related services; not a complete nonprofit inventory. |
| Senior activity/meal sites | [City congregate meal sites](https://www.austintexas.gov/parks/programs/congregate-meal-program) | Austin program sites with addresses and service schedules | Retain age eligibility and operating days. Several services share recreation-center premises: use a facility table plus service flags rather than duplicate opportunities. Reconcile page counts against listed sites before import. |
| Museums/cultural centers | [ACME Museums and Cultural Centers map](https://datahub.austintexas.gov/Recreation-and-Culture/ACME-Museums-and-Cultural-Centers-Map/gzdv-b9db) | City departmental inventory; map has an underlying dataset | Verify underlying data export and site status. This covers departmental facilities, not all private, university, or regional museums. |
| Childcare | [HHSC CCL Daycare and Residential Operations](https://data.texas.gov/d/bc5r-88dy) | Statewide dataset/API; already used by this project | Filter operation type/status to childcare; retain capacity, ages and subsidy fields. Includes residential operations; addresses and supplied coordinates require QA. |
| Groceries/food retail | [USDA SNAP Retailer Locator](https://www.fns.usda.gov/snap/retailer-locator) | Nationwide downloadable CSV with coordinates; historical file includes retailer type and authorization dates | Use appropriate retailer types and active/vintage criteria. SNAP participation is not a complete census of groceries or evidence of healthy-food availability. Keep supermarkets, convenience stores, specialty retailers, and markets distinguishable. |
| Food establishment cross-check | [Austin Food Establishment Inspection Scores](https://data.austintexas.gov/Health-and-Community-Services/Food-Establishment-Inspection-Scores/ecmv-9xxi/about_data) | APH inspection jurisdiction, broader than Austin but not the whole metro | Inspection rows repeat establishments. Deduplicate facility identifiers and use inspection dates; distinguish restaurants from groceries and institutions. Not a complete current grocery register. |
| Primary care/community health centers | [HRSA Data Downloads](https://data.hrsa.gov/data/download); [site data explanation](https://data.hrsa.gov/Content/Documents/topics/About-ESR-Dashboard.pdf) | National Health Center Service Delivery and Look-Alike sites; downloadable data and mapping resources | Use service-delivery sites, not administrative/grantee addresses. Covers the relevant HRSA programs, not all primary-care practices. Retain site/service type and status. |
| Hospitals | [CMS Hospital General Information](https://data.cms.gov/provider-data/dataset/xubh-q36u) | National CSV/API; Medicare-registered hospitals with address, type, ownership and emergency-services flag | Geocode/validate facility addresses. Does not replace an urgent-care inventory; do not treat all hospitals as equivalent opportunities. |
| Mental-health/substance-use treatment | [SAMHSA FindTreatment.gov](https://findtreatment.gov/help) | National facility search with downloadable results, addresses, services and payment information | Retain treatment type, population served, inpatient/outpatient setting and eligibility. Confirm download schema and local listing coverage. |
| Pharmacies | [Texas State Board of Pharmacy download tables](https://www.pharmacy.texas.gov/dbsearch/tables.asp) | Public pharmacy CSV, updated daily; Texas licensing universe | Select active, physically local, public-facing pharmacies; separate nonresident, institutional and other classes. Inspect schema and geocode addresses if coordinates are absent. |
| Public schools | [TEA geographic data](https://tea.texas.gov/families-and-students/school-district-locator/geographic-data) | Statewide school geographic data and campus identifiers | Use school points, not district boundaries. TEA warns of approximate/unmatched locations. Check campus status, grade span, and charter/other school coverage. Proximity alone does not establish enrollment eligibility. |

## Geographic design for the Austin project

Recommendation: use the strongest service-specific official inventory available,
not necessarily the lowest level of government. Statewide/national sources are
particularly useful because the same definitions can be applied across the
metro. City-operated facility lists describe an operator's inventory, not every
opportunity inside a jurisdiction.

Keep origin geography separate from destination collection coverage. Assemble
and retain destinations across Travis, Williamson, Hays, Bastrop and Caldwell as
an initial project scope; for peripheral origins, verify whether destinations
beyond those counties or the available OD matrix can still fall within the
largest travel-time cutoff. A county boundary or fixed five-mile buffer alone
does not establish adequate destination coverage. Flag source-coverage gaps
rather than interpreting absent records as zero opportunities.

For City-only park, recreation and cultural inventories, the next expansion is
a documented municipality/county-by-category coverage matrix. Merge additional
operator inventories and resolve overlaps using source facility IDs, addresses,
names and spatial checks. Do not assume another jurisdiction has no facilities
because its download has not been collected.

## Acquisition order

1. Libraries: combine Austin with the statewide branch directory.
2. Recreation, neighborhood and cultural centers: small City inventories useful
   for replacing vague business classifications with named service sites.
3. SNAP food retailers, pharmacy licenses and HRSA health-center sites: broader
   geographic coverage for food and healthcare destinations.
4. CMS hospitals, treatment facilities and TEA schools as the corresponding
   service definitions are settled.
5. Regional expansion of City-only categories and targeted Data Axle comparisons.

## Important unresolved gaps

No single comprehensive government point inventory of all community organizations
or all healthy-food businesses was established in this search. Municipal
neighborhood/recreation centers provide defensible service-specific subsets.
The City museum inventory does not establish metro-wide museum completeness.
A directly usable official metro-wide urgent-care dataset was not verified;
surgical centers, hospitals and emergency facilities should remain distinct.

Government provenance does not itself establish accurate coordinates. Check
addresses, duplicate sites, operational dates, public access and entrances using
the same QA framework already developed for Data Axle. Retain source agency,
source ID, snapshot date, geographic/administrative coverage, service type,
location provenance and review status on every standardized record.
