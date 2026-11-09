import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {flags,combination,contains,locate,candidates,trafficScales,trafficColor,escapeHTML} from '../site/logic.mjs';
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
assert.equal(combinedCounts.both,meta.counts.both_tract);
assert.equal(combinedCounts.access_only+combinedCounts.both,meta.counts.strong_tract);
assert.equal(combinedCounts.burden_only+combinedCounts.both,meta.counts.elevated_tract);
assert.equal(Object.values(combinedCounts).reduce((a,b)=>a+b,0),meta.counts.tracts);
const dogsHead=locate(-97.66219,30.24908,city,tracts,hexes,h3);
assert.ok(dogsHead.inCity && dogsHead.row && dogsHead.tract,'Dog’s Head must have a city, hex, and tract profile');
assert.equal(city.features[0].properties.boundary_sha256,meta.boundary.sha256);
assert.ok(Number.isFinite(dogsHead.row.traffic_distance_ft));
assert.equal(meta.traffic.buffer_m,300);
assert.equal(meta.traffic.threshold_operator,'>');
for(const row of rows){
 assert.ok(row.traffic_distance_ft>=0);
 assert.ok(row.traffic_buffer_share>=0 && row.traffic_buffer_share<=1);
}
for(const feature of tracts.features){
 const row=feature.properties;
 assert.ok(row.traffic_coverage_share>=0 && row.traffic_coverage_share<=1);
 if(row.traffic_coverage_share===0){assert.equal(row.traffic_distance_ft,null);assert.equal(row.traffic_buffer_share,null);}
}
assert.equal(trafficColor({},'traffic_distance_ft'),'#a8b4be');
assert.equal(trafficColor({traffic_buffer_share:null},'traffic_buffer_share'),'#a8b4be');
assert.equal(trafficColor({traffic_buffer_share:0},'traffic_buffer_share'),trafficScales.traffic_buffer_share.colors[0]);
assert.equal(trafficColor({traffic_buffer_share:.25},'traffic_buffer_share'),trafficScales.traffic_buffer_share.colors[2]);
assert.equal(trafficColor({traffic_buffer_share:1},'traffic_buffer_share'),trafficScales.traffic_buffer_share.colors[4]);
assert.equal(trafficColor({traffic_distance_ft:499.9},'traffic_distance_ft'),trafficScales.traffic_distance_ft.colors[0]);
assert.equal(trafficColor({traffic_distance_ft:500},'traffic_distance_ft'),trafficScales.traffic_distance_ft.colors[1]);
assert.equal(trafficColor({traffic_distance_ft:5000},'traffic_distance_ft'),trafficScales.traffic_distance_ft.colors[4]);
console.log('Traffic map checks passed: ranges, Dog’s Head, missing tracts, zero overlap and legend boundaries.');
console.log('Combined classifications passed: four combinations, missingness, cutoff equality, and tract totals.');

const {records,scoreValue,basketColor,benefitProfile}=await import('../site/benefits.mjs');
const benefits=read('benefits.json'),schools=read('school-zones.geojson');
const benefitCells=new Map(records(benefits.hex)),benefitTracts=new Map(records(benefits.tract));
const selection={profile:'families',mode:'walk_transit',minutes:30,display:'count'};
assert.equal(benefitCells.size,rows.length);
assert.equal(benefitTracts.size,tracts.features.length);
for(const [,row] of benefitCells){
 for(const [mode,budgets] of Object.entries(benefits.spec.budgets)){
  for(const minutes of budgets){
   const key=mode+'_'+minutes+'_';
   for(const [profile,members] of Object.entries(benefits.spec.profiles)){
    const values=members.map(name=>row[key+name]);
    assert.equal(row[key+profile],values.includes(null)?null:values.reduce((a,b)=>a+b,0));
   }
  }
 }
}
const south=benefitCells.get(locate(-97.780280,30.167870,city,tracts,hexes,h3).id);
assert.equal(scoreValue(south,selection),3);
assert.equal(south.walk_transit_30_park,1); // Exactly 30 minutes counts.
const schoolProfile=benefitProfile(south,selection,benefits.spec,true,schools,[-97.780280,30.167870],[]);
assert.match(schoolProfile,/BLAZIER EL/);assert.match(schoolProfile,/Paired accountability record/);
assert.match(benefitProfile(south,selection,benefits.spec,true,schools,[-96.8,32.8],[]),/Outside available elementary/);
for(const [,row] of benefitTracts){
 if(!row.resident_weight)assert.equal(row.walk_transit_30_general,null);
 assert.ok(row.area_coverage>=0 && row.area_coverage<=1);
}
assert.equal(basketColor({},selection,benefits.spec),'#a8b4be');
console.log('Benefit checks passed: complete profile sums, inclusive thresholds, geography, schools and unavailable tracts.');

// Compare browser point assignment with independently exported sf assignments.
const {schoolAssignment}=await import('../site/benefits.mjs');
assert.ok(schools.features.every(f=>f.properties.school_level==='elementary'));
assert.deepEqual([...new Set(schools.features.map(f=>f.properties.district_name))].sort(),['Austin ISD','Del Valle ISD','Manor ISD','Pflugerville ISD','Round Rock ISD']);
const education=benefits.education_origins;
assert.equal(education.site_id.length,rows.length);
for(let i=0;i<education.site_id.length;i++){
 const [lat,lon]=h3.cellToLatLng(education.site_id[i]);
 const actual=schoolAssignment(schools,[lon,lat]);
 assert.equal(actual.status,education.status[i],education.site_id[i]);
 assert.equal(actual.campus_id??null,education.campus_id[i]);
 assert.equal(actual.usable_growth??null,education.overall[i]);
 assert.equal(actual.subgroup_growth??null,education.subgroup[i]);
}
assert.ok(!schoolProfile.includes('Assigned schools · AISD'));
assert.match(schoolProfile,/Under 18/);
console.log('Elementary-only browser assignment matches sf at every H8 origin; both growth measures and child coverage verified.');
