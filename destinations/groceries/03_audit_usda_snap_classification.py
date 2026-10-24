#!/usr/bin/env python3
"""Audit USDA SNAP retailer classifications for possible grocery omissions.

This script preserves USDA Store_Type. It creates a review queue using retailer-name
signals and supporting matches to the Data Axle grocery candidate export. Proposed
classes are QA flags only; no record is automatically added to the final grocery layer.
"""
from __future__ import annotations

import csv
import json
import math
import re
from collections import Counter
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data/destinations/groceries/raw/usda_snap/metro_records.json"
AXLE = ROOT / "data/destinations/groceries/interim/dataaxle/dataaxle_standardized.csv"
OUT = ROOT / "data/destinations/groceries/qaqc/usda_snap"
OUT.mkdir(parents=True, exist_ok=True)

GROCERY_TYPES = {"Supermarket", "Super Store", "Grocery Store"}
FULL_SERVICE_PATTERNS = [
    ("heb_food_store", re.compile(r"\bH\s*E\s*B\s+FOOD\s+STORE\b", re.I)),
    ("central_market", re.compile(r"\bCENTRAL\s+MARKET\b", re.I)),
    ("randalls", re.compile(r"\bRANDALLS\b", re.I)),
    ("whole_foods", re.compile(r"\bWHOLE\s+FOODS\b", re.I)),
    ("trader_joes", re.compile(r"\bTRADER\s+JOE", re.I)),
    ("aldi", re.compile(r"\bALDI\b", re.I)),
    ("costco", re.compile(r"\bCOSTCO\b", re.I)),
    ("sams_club", re.compile(r"\bSAM'?S\s+CLUB\b", re.I)),
    ("walmart_supercenter", re.compile(r"\bWALMART\s+SUPERCENTER\b", re.I)),
]
EXCLUSION_CUES = re.compile(r"\b(FUEL|GAS|CONVENIENCE|PHARMACY|DISTRIBUTION|WAREHOUSE|OFFICE)\b", re.I)
GENERIC_GROCERY_CUES = re.compile(r"\b(GROCERY|SUPERMARKET|FOOD\s+STORE|FOOD\s+MARKET)\b", re.I)


def norm_text(value: object) -> str:
    s = str(value or "").upper().replace("&", " AND ")
    s = re.sub(r"[^A-Z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def norm_address(value: object) -> str:
    s = norm_text(value)
    replacements = {
        " STREET": " ST", " ROAD": " RD", " AVENUE": " AVE", " BOULEVARD": " BLVD",
        " DRIVE": " DR", " HIGHWAY": " HWY", " LANE": " LN", " COURT": " CT",
        " PARKWAY": " PKWY", " NORTH": " N", " SOUTH": " S", " EAST": " E", " WEST": " W",
    }
    for old, new in replacements.items():
        s = s.replace(old, new)
    return s


def num(v):
    try:
        x = float(v)
        return x if math.isfinite(x) else None
    except (TypeError, ValueError):
        return None


def haversine_m(lat1, lon1, lat2, lon2):
    if None in (lat1, lon1, lat2, lon2):
        return None
    r = 6371008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2-lat1); dl = math.radians(lon2-lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*r*math.asin(math.sqrt(a))


def load_snap():
    obj = json.loads(RAW.read_text())
    features = obj if isinstance(obj, list) else obj.get("features", [])
    return [x.get("attributes", x) for x in features]


def load_axle():
    with AXLE.open(newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["_name"] = norm_text(r.get("name"))
        r["_address"] = norm_address(r.get("address"))
        r["_zip"] = str(r.get("zip") or "")[:5]
        r["_lat"] = num(r.get("latitude")); r["_lon"] = num(r.get("longitude"))
    return rows


def best_axle_match(s, axle):
    sname = norm_text(s.get("Store_Name")); saddr = norm_address(s.get("Store_Street_Address"))
    szip = str(s.get("Zip_Code") or "")[:5]
    slat = num(s.get("Latitude")); slon = num(s.get("Longitude"))
    best = None
    for a in axle:
        same_addr = bool(saddr and saddr == a["_address"] and (not szip or not a["_zip"] or szip == a["_zip"]))
        dist = haversine_m(slat, slon, a["_lat"], a["_lon"])
        sim = SequenceMatcher(None, sname, a["_name"]).ratio() if sname and a["_name"] else 0.0
        candidate = same_addr or (dist is not None and dist <= 500 and sim >= 0.55)
        if not candidate:
            continue
        score = (1000 if same_addr else 0) + sim * 100 - (min(dist, 500)/25 if dist is not None else 20)
        if best is None or score > best[0]:
            best = (score, a, same_addr, sim, dist)
    return best


def classify(s, match):
    name = str(s.get("Store_Name") or "")
    stype = str(s.get("Store_Type") or "")
    if stype in GROCERY_TYPES:
        return "included_by_snap_type", "snap_grocery_type", "eligible_candidate", "USDA type is in the working grocery subset"

    full_rule = next((label for label, pattern in FULL_SERVICE_PATTERNS if pattern.search(name)), "")
    exclusion = bool(EXCLUSION_CUES.search(name))
    generic = bool(GENERIC_GROCERY_CUES.search(name))
    strong_axle = False
    axle_reason = ""
    if match:
        _, a, same_addr, sim, dist = match
        strong_axle = same_addr or (dist is not None and dist <= 150 and sim >= 0.80)
        axle_reason = f"Data Axle grocery candidate: {a.get('name','')} (address_match={same_addr}; name_similarity={sim:.2f}; distance_m={'' if dist is None else round(dist,1)})"

    if full_rule and not exclusion:
        return "high", full_rule, "likely_grocery_review", f"Known full-service name pattern conflicts with SNAP type {stype}"
    if full_rule and exclusion:
        return "medium", full_rule + "+exclusion_cue", "ambiguous_chain_format", f"Grocery-chain name also contains a fuel/convenience/restricted-format cue; {axle_reason or 'manual verification required'}"
    if strong_axle:
        return "medium", "dataaxle_grocery_match", "possible_grocery_review", axle_reason
    if generic:
        return "low", "generic_grocery_name", "possible_grocery_review", f"Name suggests food retail but SNAP type is {stype}"
    return "not_flagged", "", "not_currently_grocery", "No grocery-specific audit signal"


def main():
    snap = load_snap(); axle = load_axle()
    audit = []
    for s in snap:
        match = best_axle_match(s, axle)
        priority, signal, proposed, reason = classify(s, match)
        a = match[1] if match else {}
        same_addr = match[2] if match else False
        sim = match[3] if match else None
        dist = match[4] if match else None
        audit.append({
            "snap_record_id": s.get("Record_ID", ""),
            "snap_object_id": s.get("ObjectId", ""),
            "name": s.get("Store_Name", ""),
            "address": s.get("Store_Street_Address", ""),
            "address2": s.get("Additonal_Address", ""),
            "city": s.get("City", ""),
            "county": s.get("County", ""),
            "zip": s.get("Zip_Code", ""),
            "latitude": s.get("Latitude", ""),
            "longitude": s.get("Longitude", ""),
            "snap_store_type": s.get("Store_Type", ""),
            "current_grocery_subset": str(s.get("Store_Type") in GROCERY_TYPES).lower(),
            "audit_priority": priority,
            "audit_signal": signal,
            "proposed_class": proposed,
            "audit_reason": reason,
            "dataaxle_candidate_name": a.get("name", ""),
            "dataaxle_candidate_id": a.get("destination_id", ""),
            "dataaxle_same_address_zip": str(bool(same_addr)).lower() if match else "",
            "dataaxle_name_similarity": "" if sim is None else f"{sim:.3f}",
            "dataaxle_distance_m": "" if dist is None else f"{dist:.1f}",
            "manual_decision": "",
            "manual_reason": "",
            "evidence_url": "",
            "reviewer": "",
            "review_date": "",
        })

    fields = list(audit[0])
    with (OUT / "snap_classification_audit.csv").open("w", newline="", encoding="utf-8") as f:
        w=csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(audit)

    flagged=[r for r in audit if r["current_grocery_subset"]=="false" and r["audit_priority"] in {"high","medium","low"}]
    order={"high":0,"medium":1,"low":2}
    flagged.sort(key=lambda r:(order[r["audit_priority"]],r["county"],r["name"]))
    with (OUT / "snap_possible_grocery_omissions.csv").open("w", newline="", encoding="utf-8") as f:
        w=csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(flagged)

    counts=Counter((r["snap_store_type"],r["audit_priority"],r["proposed_class"]) for r in audit)
    with (OUT / "snap_classification_audit_summary.csv").open("w", newline="", encoding="utf-8") as f:
        fields2=["snap_store_type","audit_priority","proposed_class","records"]
        w=csv.DictWriter(f,fieldnames=fields2); w.writeheader()
        for (stype,priority,proposed),n in sorted(counts.items()):
            w.writerow(dict(snap_store_type=stype,audit_priority=priority,proposed_class=proposed,records=n))

    print(f"SNAP records: {len(audit)}")
    print(f"Current SNAP grocery types: {sum(r['current_grocery_subset']=='true' for r in audit)}")
    print(f"Flagged possible omissions: {len(flagged)}")
    print(Counter(r['audit_priority'] for r in flagged))
    for r in flagged[:20]:
        print(r['audit_priority'], '|',r['name'],'|',r['snap_store_type'],'|',r['audit_signal'],'|',r['dataaxle_candidate_name'])

if __name__ == "__main__":
    main()
