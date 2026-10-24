# NPPES healthcare destinations: processing note

Processing checkpoint: October 1, 2026. These are candidate organization records for review, not a final inventory of distinct healthcare sites.

## Source and scope

We downloaded the CMS NPPES monthly bulk file, Version 2, released September 14, 2026, from the [CMS download page](https://download.cms.gov/nppes/NPI_Files.html). The cached archive is `NPPES_Data_Dissemination_September_2026_V2.zip`; the main provider file is `npidata_pfile_20050523-20260913.csv`. The national CSV was read from the ZIP in chunks, retaining only records meeting the selection rules. The original ZIP, filtered extract, taxonomy crosswalk, and processing metadata are saved locally.

The study area is Bastrop, Caldwell, Hays, Travis, and Williamson counties. Only the following four taxonomy codes were selected:

| NUCC code | Description | Output category |
|---|---|---|
| 3336C0003X | Pharmacy, Community/Retail Pharmacy | pharmacy |
| 282N00000X | General Acute Care Hospital | hospital |
| 261QU0200X | Clinic/Center, Urgent Care | urgent_care |
| 261Q00000X | Clinic/Center | general_clinic_review |

General Clinic/Center is retained separately because this broad code does not establish urgent-care service.

## Selection and cleaning

1. Use the business **practice-location address**, rather than the mailing address. Retain Texas records with a ZIP corresponding to a 2020 Census ZCTA intersecting one of the five 2024 county boundaries. This initial geographic screen yielded 113 candidate ZIP codes; it was intentionally broader than the final county boundary.
2. Examine all 15 taxonomy slots and retain a record if any slot contains a selected code. Retain organization NPIs only (`Entity Type Code = 2`); individual NPIs are excluded from this facility-oriented extract.
3. Retain records whose `NPI Deactivation Date` is blank. This is the implemented registry-status rule, not confirmation that a facility is open or licensed. Reactivation dates are not currently evaluated, so reactivated records with a populated deactivation date could be missed.
4. Remove duplicate NPI rows introduced when a ZIP intersects multiple counties. The extract has one row per NPI. Initial county labels from the ZIP crosswalk are preliminary; the mapped layer uses the point's actual county instead.
5. Assign the category using the **first matching taxonomy in source-slot order**. This is not necessarily the designated primary taxonomy. All original taxonomy slots remain in the full extract, but a record matching multiple selected categories appears in only one current output category.
6. Prepare a compact table with NPI, organization and legal names, practice address, phone, selected taxonomy, category, and source. Trim whitespace and treat blanks and `<UNAVAIL>`/`<UNAVAILABLE>` as missing. Prefer the other organization name when available, otherwise use the legal business name.

## Geocoding and geographic screening

The 867 selected organization records yielded 788 distinct geocoder inputs, keyed by first-line street address, city, state, and five-digit ZIP. Second-line suite information is retained in the attribute table but not submitted for geocoding. Trailing suite/building/unit text was removed from the submitted first-line address.

The U.S. Census batch geocoder, using `Public_AR_Current`, matched 685 of the 788 inputs. Raw responses were saved. Matched coordinates were joined back to the NPI records and screened for plausible coordinates. Points were then spatially joined to the five county polygons using point-within-polygon matching. Records without a county match were excluded from the mapped layer.

| Category | Selected NPIs before geocoding | Not geocoded | Geocoded outside metro | Mapped NPIs in metro |
|---|---:|---:|---:|---:|
| Community/retail pharmacy | 506 | 61 | 67 | 378 |
| General acute-care hospital | 60 | 4 | 17 | 39 |
| Urgent care | 103 | 19 | 11 | 73 |
| General clinic review | 198 | 25 | 14 | 159 |
| **Total** | **867** | **109** | **109** | **649** |

The 109 records without coordinates have not yet been confirmed inside or outside the metro. They remain in the review table. Counts above represent organization NPIs, not necessarily unique physical facilities.

## Outputs and validation

Paths are relative to the project root:

- `data/destinations/healthcare/raw/cms_nppes/`: original downloaded archive.
- `data/destinations/healthcare/interim/cms_nppes/nppes_austin_metro_healthcare_providers.csv`: full selected source records, including taxonomy slots and preliminary ZIP-based county labels.
- `data/destinations/healthcare/interim/cms_nppes/nppes_selected_healthcare_facilities.csv`: compact table of all 867 candidates, including records later excluded geographically or not geocoded.
- `data/destinations/healthcare/processed/healthcare_cms_nppes.gpkg`: 649 mapped NPIs in four layers, with WGS84 coordinates, geocoder fields, spatially assigned county, and H7/H8 cells.
- `data/destinations/healthcare/qaqc/cms_nppes/nppes_geocoding_review.csv`: 218 records, distinguishing geocoding failures from points outside the metro.

Mapped layers were checked for unique NPIs within each layer and valid point geometry. Acquisition, cleaning, geocoding, and layer creation are implemented in the four `01`–`04` CMS NPPES scripts in this folder.

## Remaining decisions before accessibility analysis

NPPES is an identifier registry; an NPI does not establish licensure, current operation, walk-in access, or service availability. Multiple organization NPIs can represent one site, and one organization can operate several sites. Physical-site deduplication and service verification have not yet been performed. The separate NPPES non-primary practice-location reference file has not been processed, so additional locations may be missing.

The initial ZIP/ZCTA screen can miss postal ZIPs without a corresponding ZCTA. Census coordinates are address matches, often street-based, and have not been checked against building entrances. Unmatched addresses need further review. General clinics require classification before being included as urgent care. Multi-taxonomy assignment and reactivation handling should be reviewed before final counts are adopted.

These NPPES candidates have not been matched or merged with Data Axle. The existing TSBP-based final pharmacy inventory remains a separate product; the NPPES pharmacy layer is available for comparison and does not replace it.
