"""Snapshot the complete public City inventory; verify IDs, edits and hashes."""
from pathlib import Path
import concurrent.futures, datetime, hashlib, json, urllib.parse, urllib.request, time
URL='https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/Sidewalks_(Public)/FeatureServer/0'
ROOT=Path('data/raw/austin_pedestrian_inventory/2026-11-09')
FIELDS='OBJECTID,SIDEWALKS_ID,PEDESTRIAN_FACILITY_TYPE,FULL_STREET_NAME,MANAGING_AGENCY,WIDTH,YEAR_BUILT,DATE_CONSTRUCTION_COMPLETED'
def request(path='',**params):
    url=URL+path+'?'+urllib.parse.urlencode({'f':'json',**params})
    for attempt in range(4):
        try:
            raw=urllib.request.urlopen(url,timeout=120).read(); data=json.loads(raw)
            if 'error' in data: raise RuntimeError(data['error'])
            return raw,data
        except Exception:
            if attempt==3: raise
            time.sleep(2**attempt)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    manifest=ROOT/'manifest.json'
    if manifest.exists():
        m=json.loads(manifest.read_text())
        assert m['source_url']==URL
        for f in m['files']: assert sha(ROOT/f['path'])==f['sha256']
        print('Verified cached snapshot:',m['feature_count']);return
    raw,meta=request(); edit=meta['editingInfo']['lastEditDate']
    prior=ROOT/'layer.json'
    if prior.exists(): assert json.loads(prior.read_text())['editingInfo']['lastEditDate']==edit,'Source changed; use a new snapshot directory.'
    prior.write_bytes(raw)
    _,data=request('/query',where='1=1',returnIdsOnly='true')
    ids=sorted(data['objectIds']);assert len(ids)==len(set(ids)) and ids
    (ROOT/'source_ids.json').write_text(json.dumps(ids))
    batches=[ids[i:i+2000] for i in range(0,len(ids),2000)]
    def page(item):
        i,batch=item; path=ROOT/f'page-{i:04d}.geojson'
        if path.exists(): data=json.loads(path.read_text())
        else:
            raw,data=request('/query',where=f'OBJECTID >= {batch[0]} AND OBJECTID <= {batch[-1]}',outFields=FIELDS,outSR=4326,returnZ='false',returnM='false',orderByFields='OBJECTID',f='geojson')
            assert not data.get('exceededTransferLimit',False)
            assert sorted(f['properties']['OBJECTID'] for f in data['features'])==batch
            path.write_bytes(raw)
        assert sorted(f['properties']['OBJECTID'] for f in data['features'])==batch
        return {'path':path.name,'count':len(batch),'sha256':sha(path)}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        pages=[]
        for i,p in enumerate(pool.map(page,enumerate(batches))):
            pages.append(p)
            if (i+1)%20==0: print(f'{i+1}/{len(batches)} pages verified',flush=True)
    _,end=request();_,check=request('/query',where='1=1',returnIdsOnly='true')
    assert end['editingInfo']['lastEditDate']==edit,'Source edited during acquisition; snapshot not finalized.'
    assert sorted(check['objectIds'])==ids
    extras=[{'path':p.name,'sha256':sha(p)} for p in [prior,ROOT/'source_ids.json']]
    m={'source_url':URL,'retrieved_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_edit_ms':edit,'feature_count':len(ids),'query':'Entire published layer; no spatial or category filter','fields':FIELDS,'files':extras+pages}
    manifest.write_text(json.dumps(m,indent=2));print('Snapshot complete:',len(ids),flush=True)
if __name__=='__main__':main()
