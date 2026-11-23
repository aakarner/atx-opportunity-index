import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {floodContains,indexFlood,floodStatus,floodProfile} from '../site/flood-eligibility.mjs';
const polygon={type:'Polygon',coordinates:[[[0,0],[4,0],[4,4],[0,4],[0,0]],[[1,1],[2,1],[2,2],[1,2],[1,1]]]};
assert.equal(floodContains(polygon,[.5,.5]),true);
assert.equal(floodContains(polygon,[0,2]),true);
assert.equal(floodContains(polygon,[1.5,1.5]),false);
assert.equal(floodContains(polygon,[1,1.5]),true);
assert.equal(floodContains(polygon,[5,5]),false);
assert.equal(floodContains(polygon,[NaN,1]),false);
assert.equal(floodContains({type:'MultiPolygon',coordinates:[polygon.coordinates]},[3,3]),true);
const read=p=>JSON.parse(fs.readFileSync(new URL(p,import.meta.url),'utf8'));
const data=read('../site/assets/flood-eligibility.json'),hex=read('../site/assets/hexagons.json');
data.flood_by_hex=read('../site/assets/flood-geometry.geojson');
assert.equal(createHash('sha256').update(fs.readFileSync(new URL('../site/assets/flood-geometry.geojson',import.meta.url))).digest('hex'),data.geometry_sha256);
const index=indexFlood(data,hex.map(r=>r.id));
assert.equal(index.rows.size,1029);
assert.equal(floodStatus(index,'missing'), 'unknown');
assert.equal(floodStatus(index,hex[0].id,[NaN,0]), 'unknown');
for(const row of data.hex){
 assert.equal(floodStatus(index,row.id),row.status);
 assert.equal(row.excluded,row.status==='ineligible');
 if(row.excluded)assert.ok(row.overlap_share>1-1e-8);
 if(row.status==='not_excluded')assert.equal(row.overlap_share,0);
}
const checks=read('./fixtures/flood-point-checks.json');
let inPartial=0,outPartial=0;
for(const point of checks){
 const actual=floodStatus(index,point.id,[point.longitude,point.latitude]);
 assert.equal(actual,point.ineligible?'ineligible':'not_excluded',JSON.stringify(point));
 if(index.rows.get(point.id).status==='address_check_required')point.ineligible?inPartial++:outPartial++;
}
assert.ok(inPartial>0&&outPartial>0,'Actual points distinguish flooded and dry portions of partial cells');
const partial=data.hex.find(r=>r.status==='address_check_required');
assert.match(floodProfile(index,partial.id,true),/check the address/);
assert.throws(()=>indexFlood({...data,hex:data.hex.slice(1)},hex.map(r=>r.id)),/geography/);
assert.throws(()=>indexFlood({...data,flood_by_hex:{features:[]}},hex.map(r=>r.id)),/missing/);
console.log(`Passed ${checks.length} independent sf/browser point comparisons, including wet and dry points in partial cells; geometry, missingness, boundaries and holes also passed.`);
