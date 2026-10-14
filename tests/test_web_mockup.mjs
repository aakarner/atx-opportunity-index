import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {flags,combination,contains,locate,candidates,escapeHTML} from '../site/logic.mjs';
const require=createRequire(import.meta.url),h3=require('../site/vendor/h3-js.umd.js');
const read=f=>JSON.parse(readFileSync(new URL('../site/assets/'+f,import.meta.url)));
const meta=read('metadata.json'), rows=read('hexagons.json'), tracts=read('tracts.geojson'),city=read('city.geojson'),hexes=new Map(rows.map(r=>[r.id,r]));
assert.deepEqual(flags({jobs_total:50000,rsei:100},meta.thresholds),{strong_access:false,elevated_burden:true});
assert.deepEqual(flags({jobs_total:50000.01,rsei:99.99},meta.thresholds),{strong_access:true,elevated_burden:false});
assert.deepEqual(flags({jobs_total:null,rsei:NaN},meta.thresholds),{strong_access:null,elevated_burden:null});
for(const r of [...rows,...tracts.features.map(f=>f.properties)]){const f=flags(r,meta.thresholds);assert.equal(r.strong_access,f.strong_access);assert.equal(r.elevated_burden,f.elevated_burden);}
for(const row of rows){assert.equal(h3.getResolution(row.id),8);const [lat,lon]=h3.cellToLatLng(row.id);assert.equal(locate(lon,lat,city,tracts,hexes,h3).row?.id,row.id);}
const example=locate(-97.666740,30.310930,city,tracts,hexes,h3);assert.equal(example.id,'88489e22c1fffff');assert.equal(example.row.jobs_total,87732);assert.equal(example.row.strong_access,true);assert.equal(example.row.elevated_burden,true);assert.ok(example.tract);
assert.equal(locate(-96.8,32.8,city,tracts,hexes,h3).row,null);
assert.equal(locate(-97.666740,30.310930,city,tracts,new Map(),h3).row,null);
const polygon={type:'Polygon',coordinates:[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[2,2],[3,2],[3,3],[2,3],[2,2]]]};
assert.equal(contains(polygon,1,1),true);assert.equal(contains(polygon,2.5,2.5),false);assert.equal(contains(polygon,0,4),true);assert.equal(contains(polygon,11,4),false);
assert.equal(contains({type:'MultiPolygon',coordinates:[polygon.coordinates]},1,1),true);
assert.throws(()=>locate(NaN,30,city,tracts,hexes,h3));
assert.equal(escapeHTML('<img onerror="x">'),'&lt;img onerror=&quot;x&quot;&gt;');
assert.equal(candidates({candidates:[{address:'A',location:{x:-97,y:30}},{address:'A',location:{x:-97,y:30}},{address:'B',location:{x:'bad',y:30}},{address:'C',location:{x:200,y:30}}]}).length,1);
assert.equal(rows.length,meta.counts.hexagons);assert.equal(tracts.features.length,meta.counts.tracts);
assert.equal(rows.filter(r=>r.strong_access).length,meta.counts.strong_hex);assert.equal(rows.filter(r=>r.elevated_burden).length,meta.counts.elevated_hex);
console.log('Website checks passed: thresholds, all H8 origins, example profile, outside/missing coverage, polygon holes and edges, safe locator results, exported flags.');

for(const [access,burden,expected] of [[true,true,'both'],[true,false,'access_only'],[false,true,'burden_only'],[false,false,'neither'],[null,false,'unknown'],[true,null,'unknown'],[null,null,'unknown']]){
 assert.equal(combination({strong_access:access,elevated_burden:burden}),expected);
}
assert.equal(combination({}),'unknown');
assert.equal(combination(flags({jobs_total:50000,rsei:100},meta.thresholds)),'burden_only');
const combinedCounts={both:0,access_only:0,burden_only:0,neither:0,unknown:0};
for(const f of tracts.features)combinedCounts[combination(f.properties)]++;
assert.deepEqual(combinedCounts,{both:29,access_only:51,burden_only:58,neither:137,unknown:0});
console.log('Combined classifications passed: four combinations, missingness, cutoff equality, and tract totals.');
