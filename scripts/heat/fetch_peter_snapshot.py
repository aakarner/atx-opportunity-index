"""Cache selected public heat artifacts at a pinned GitHub commit; verify Git blob hashes."""
import concurrent.futures, hashlib, json, pathlib, urllib.request, urllib.parse
COMMIT = 'd90d74f38a70472418e59666ac86e9d5736efab5'
REPO = 'aakarner/atx-opportunity-index'
PREFIX = 'scripts/prepare/surface_temp/'
ROOT = pathlib.Path('data/raw/peter_heat') / COMMIT[:10]
WATER_ROOT = pathlib.Path('data/raw/heat_validation_water_2024')
# Pin the water snapshot as well as the heat source for reproducible land masks.
WATER_HASHES = {
    '48453': '047c7156eca21cf67f0eefd5c3bdae3eada875944b2576b2852179e39e35eb92',
    '48491': 'a975a07210eb9c41dfcfacad16d42b2a2e3714071c657484da04426d681f2df6',
    '48209': '0d8ec6d0de5a4d4f3a706b96566ecf94dae51f6e708590082df248fd0ffb3fb5',
}
def get(url):
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'opportunity-index-heat-validation'}),timeout=120) as response:
        return response.read()
def blob_sha(data):
    return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
def fetch_water():
    WATER_ROOT.mkdir(parents=True, exist_ok=True)
    files = []
    for county, expected in WATER_HASHES.items():
        name = f'tl_2024_{county}_areawater.zip'
        path = WATER_ROOT / name
        url = 'https://www2.census.gov/geo/tiger/TIGER2024/AREAWATER/' + name
        raw = path.read_bytes() if path.exists() else get(url)
        actual = hashlib.sha256(raw).hexdigest()
        if actual != expected:
            raise RuntimeError(f'Census water snapshot changed: {name}')
        if not path.exists():
            path.write_bytes(raw)
        files.append(dict(file=name, url=url, sha256=actual, bytes=len(raw)))
    (WATER_ROOT / 'manifest.json').write_text(json.dumps(files, indent=2) + '\n')
def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    tree=json.loads(get(f'https://api.github.com/repos/{REPO}/git/trees/{COMMIT}?recursive=1'))
    if tree.get('truncated'): raise RuntimeError('Incomplete repository tree')
    selected=[x for x in tree['tree'] if x['type']=='blob' and x['path'].startswith(PREFIX) and
      (x['path'].endswith(('.R','.tif','.docx')) or pathlib.Path(x['path']).name in ('hex_8.gpkg','hex_8_temps.gpkg','hex_8_hot_pixels.gpkg'))]
    def fetch(item):
        relative=item['path'][len(PREFIX):];path=ROOT/relative
        url=f'https://raw.githubusercontent.com/{REPO}/{COMMIT}/'+urllib.parse.quote(item['path'])
        raw=path.read_bytes() if path.exists() else get(url)
        if blob_sha(raw)!=item['sha']: raise RuntimeError(f'Git blob mismatch: {relative}')
        path.parent.mkdir(parents=True,exist_ok=True)
        if not path.exists(): path.write_bytes(raw)
        return dict(path=relative,bytes=len(raw),git_blob_sha=item['sha'],sha256=hashlib.sha256(raw).hexdigest(),url=url)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        files=list(pool.map(fetch,selected))
    (ROOT/'manifest.json').write_text(json.dumps(dict(repository=REPO,commit=COMMIT,files=files),indent=2)+'\n')
    print(f'Verified {len(files)} files, {sum(x["bytes"] for x in files)/1e6:.1f} MB at {ROOT}')
    fetch_water()
if __name__=='__main__': main()
