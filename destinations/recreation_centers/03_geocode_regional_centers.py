"""Cache address candidates for the documented regional center inventory."""
import json,pathlib,urllib.request,urllib.parse,concurrent.futures
base=pathlib.Path('data/destinations/recreation_centers/interim/regional')
rows=json.loads((base/'facility_inventory.json').read_text())
cache=base/'geocoder';cache.mkdir(exist_ok=True)
def fetch(r):
 p=cache/(r['facility_id']+'.json')
 if p.exists(): return
 params=urllib.parse.urlencode(dict(SingleLine=f"{r['address']}, {r['city']}, TX {r['zip']}",f='json',outFields='Match_addr,Addr_type',maxLocations=3))
 with urllib.request.urlopen('https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates?'+params,timeout=45) as response:
  data=json.load(response)
 if 'error' in data: raise RuntimeError(data['error'])
 p.write_text(json.dumps(data,indent=2))
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(fetch,rows))
print('Cached geocoder responses:',len(rows))
