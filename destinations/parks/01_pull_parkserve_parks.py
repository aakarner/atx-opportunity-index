#!/usr/bin/env python3
"""Download ParkServe polygons for the five-county Austin metropolitan area."""
from __future__ import annotations
import hashlib, json, urllib.parse, urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'data/destinations/parks/raw/parkserve'
OUT.mkdir(parents=True,exist_ok=True)
SERVICE='https://server7.tplgis.org/arcgis7/rest/services/ParkServe/ParkServe_Shareable/MapServer/0'
FIPS=['48021','48055','48209','48453','48491']
WHERE='park_county_fips IN ('+','.join("'%s'"%x for x in FIPS)+')'

def fetch(url,path):
    with urllib.request.urlopen(url,timeout=120) as response:
        path.write_bytes(response.read())

def query_url(offset):
    params={'where':WHERE,'outFields':'*','returnGeometry':'true','outSR':'4326',
            'orderByFields':'objectid','resultOffset':str(offset),'resultRecordCount':'1000','f':'geojson'}
    return SERVICE+'/query?'+urllib.parse.urlencode(params)

pages=[]; offset=0
while True:
    path=OUT/f'parkserve_metro_page_{len(pages)+1}.geojson'
    fetch(query_url(offset),path)
    obj=json.loads(path.read_text())
    n=len(obj.get('features',[])); pages.append((path,n))
    if n<1000: break
    offset+=n
fetch(SERVICE+'?f=pjson',OUT/'layer.json')
manifest={'retrieved_at_utc':datetime.now(timezone.utc).isoformat(),'service_url':SERVICE,
          'where':WHERE,'records':sum(n for _,n in pages),'pages':[
          {'path':str(p.relative_to(ROOT)),'records':n,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p,n in pages]}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f"Saved {manifest['records']} ParkServe records to {OUT}")
