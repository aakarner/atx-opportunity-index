"""Cache the City's regulatory floodplain for the whole study envelope.

No City-boundary clipping: eligibility tests must use complete H3 polygons.
Run from the repository root after h8_geometry and city_boundary exist.
"""
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import subprocess
import urllib.parse
import urllib.request

URL = 'https://maps.austintexas.gov/gis/rest/FloodPro/FloodPro/MapServer/9'
ROOT = pathlib.Path('data/raw/austin_fully_developed_floodplain/2026-11-09')
FIELDS = 'OBJECTID,FLOOD_ZONE,FLOODWAY,SOURCE_CITATION,COUNTY,MODIFIED_DATE,FME_DATE'


def get(path, **params):
    url = URL + path + '?' + urllib.parse.urlencode(dict(f='json', **params))
    request = urllib.request.Request(url, headers={'User-Agent': 'Austin-opportunity-index'})
    with urllib.request.urlopen(request, timeout=60) as response:
        value = json.load(response)
    if 'error' in value or value.get('exceededTransferLimit'):
        raise RuntimeError(value.get('error', 'Incomplete ArcGIS response'))
    return value


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def envelope():
    code = """
    if(dir.exists('.R-library')) .libPaths(c(normalizePath('.R-library'),.libPaths()))
    h<-sf::st_transform(targets::tar_read(h8_geometry),4326)
    c<-sf::st_transform(targets::tar_read(city_boundary),4326)
    cat(paste(as.numeric(sf::st_bbox(c(sf::st_geometry(h),sf::st_geometry(c)))),collapse=','))
    """
    return subprocess.check_output(['Rscript', '-e', code], text=True).strip()


def main():
    bbox = envelope()
    manifest_path = ROOT / 'manifest.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest['query_envelope'] != bbox or manifest['source_url'] != URL:
            raise RuntimeError('Source or study envelope changed; acquire a new dated snapshot.')
        for file in manifest['files']:
            if sha(ROOT / file['path']) != file['sha256']:
                raise RuntimeError('Cached source checksum mismatch: ' + file['path'])
        print('Verified cached fully developed floodplain snapshot.')
        return
    ROOT.mkdir(parents=True, exist_ok=True)
    metadata = get('')
    if metadata['name'] != 'Fully Developed Floodplain' or metadata.get('definitionExpression'):
        raise RuntimeError('Unexpected City layer definition.')
    spatial = dict(where='1=1', geometry=bbox, geometryType='esriGeometryEnvelope',
                   inSR=4326, spatialRel='esriSpatialRelIntersects')
    ids = sorted(get('/query', returnIdsOnly='true', **spatial)['objectIds'])
    if not ids or len(ids) != len(set(ids)):
        raise RuntimeError('Empty or duplicate source object IDs.')
    pages = [ids[i:i + 100] for i in range(0, len(ids), 100)]

    def fetch_page(index_and_ids):
        index, page_ids = index_and_ids
        # f=geojson requires an explicit request, separate from get()'s JSON default.
        params = dict(f='geojson', objectIds=','.join(map(str, page_ids)),
                      outFields=FIELDS, returnGeometry='true', outSR=4326)
        request = urllib.request.Request(URL + '/query?' + urllib.parse.urlencode(params),
                                         headers={'User-Agent': 'Austin-opportunity-index'})
        with urllib.request.urlopen(request, timeout=60) as response:
            value = json.load(response)
        if value.get('error') or value.get('exceededTransferLimit'):
            raise RuntimeError('Incomplete floodplain page.')
        actual = [f['properties']['OBJECTID'] for f in value['features']]
        if sorted(actual) != page_ids or any(f['geometry'] is None for f in value['features']):
            raise RuntimeError('Floodplain page missing IDs or geometry.')
        path = ROOT / f'page_{index:03d}.geojson'
        path.write_text(json.dumps(value, separators=(',', ':')) + '\n')
        return dict(path=path.name, sha256=sha(path), count=len(actual))

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        files = list(pool.map(fetch_page, enumerate(pages)))
    if sorted(get('/query', returnIdsOnly='true', **spatial)['objectIds']) != ids:
        raise RuntimeError('City layer IDs changed during acquisition; retry a fresh snapshot.')
    # The service publishes no edit timestamp. Retain source modification fields
    # for audit; do not claim a transactional snapshot of concurrent attribute edits.
    metadata_path = ROOT / 'metadata.json'
    metadata_path.write_text(json.dumps(metadata, indent=2) + '\n')
    files.append(dict(path=metadata_path.name, sha256=sha(metadata_path)))
    manifest_path.write_text(json.dumps(dict(
        source_url=URL, source_name=metadata['name'], query_envelope=bbox,
        retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        source_ids=ids, files=files), indent=2) + '\n')
    print(f'Cached {len(ids)} City floodplain features in {len(pages)} pages.')


if __name__ == '__main__':
    main()
