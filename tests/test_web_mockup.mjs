import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {contains,locate,candidates,escapeHTML} from '../site/logic.mjs';
const require=createRequire(import.meta.url),h3=require('../site/vendor/h3-js.umd.js');
const read=f=>JSON.parse(readFileSync(new URL('../site/assets/'+f,import.meta.url)));
const meta=read('metadata.json'), rows=read('hexagons.json'), tracts=read('tracts.geojson'),city=read('city.geojson'),hexes=new Map(rows.map(r=>[r.id,r]));
assert.equal(meta.schema_version,2);
assert.ok(!('thresholds' in meta));
for(const r of [...rows,...tracts.features.map(f=>f.properties)]){
 assert.ok(!('strong_access' in r || 'elevated_burden' in r));
}
for(const row of rows){assert.equal(h3.getResolution(row.id),8);const [lat,lon]=h3.cellToLatLng(row.id);assert.equal(locate(lon,lat,city,tracts,hexes,h3).row?.id,row.id);}
const example=locate(-97.666740,30.310930,city,tracts,hexes,h3);assert.equal(example.id,'88489e22c1fffff');assert.equal(example.row.jobs_total,87732);assert.ok(example.tract);
assert.equal(locate(-96.8,32.8,city,tracts,hexes,h3).row,null);
assert.equal(locate(-97.666740,30.310930,city,tracts,new Map(),h3).row,null);
const polygon={type:'Polygon',coordinates:[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[2,2],[3,2],[3,3],[2,3],[2,2]]]};
assert.equal(contains(polygon,1,1),true);assert.equal(contains(polygon,2.5,2.5),false);assert.equal(contains(polygon,0,4),true);assert.equal(contains(polygon,11,4),false);
assert.equal(contains({type:'MultiPolygon',coordinates:[polygon.coordinates]},1,1),true);
assert.throws(()=>locate(NaN,30,city,tracts,hexes,h3));
assert.equal(escapeHTML('<img onerror="x">'),'&lt;img onerror=&quot;x&quot;&gt;');
assert.equal(candidates({candidates:[{address:'A',location:{x:-97,y:30}},{address:'A',location:{x:-97,y:30}},{address:'B',location:{x:'bad',y:30}},{address:'C',location:{x:200,y:30}}]}).length,1);
assert.equal(rows.length,meta.counts.hexagons);assert.equal(tracts.features.length,meta.counts.tracts);
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
console.log('Website checks passed: geography, source values, traffic ranges, missing coverage and address lookup.');

const {records,scoreValue,basketColor,benefitProfile}=await import('../site/benefits.mjs');
const benefits=read('benefits.json'),schools=read('school-zones.geojson');
const benefitCells=new Map(records(benefits.hex)),benefitTracts=new Map(records(benefits.tract));
const selection={profile:'families',mode:'walk_transit',minutes:30,display:'count'};
// At this origin the historical clinic and pooled center took 53 and 19 minutes.
const centerClinicOrigin=benefitCells.get('88489e2211fffff');
const transitDetail=profile=>benefitProfile(centerClinicOrigin,{...selection,profile,minutes:45},
 benefits.spec,true,schools,null,[]);
const singleDetail=transitDetail('single');
assert.ok(singleDetail.includes('<dt>Urgent care/clinics</dt><dd>41 min · within</dd>'));
assert.ok(singleDetail.includes('<dt>Community/social/recreation centers</dt><dd>16 min · within</dd>'));
assert.ok(transitDetail('older').includes('<dt>Senior centers</dt><dd>57 min · over</dd>'));
assert.equal(benefits.spec.profiles.general.length,9);
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
assert.deepEqual([...new Set(schools.features.map(f=>f.properties.district_name))].sort(),
 ['Austin ISD','Del Valle ISD','Eanes ISD','Hays CISD','Lake Travis ISD','Leander ISD','Manor ISD','Pflugerville ISD','Round Rock ISD']);
assert.equal(benefits.spec.education.districts.length,9);
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
for(const prefix of ['227909','246913','105906','227913']) {
 const i=education.campus_id.findIndex(id=>id?.startsWith(prefix));
 assert.ok(i>=0,`New district ${prefix} must serve a mapped origin`);
 const [lat,lon]=h3.cellToLatLng(education.site_id[i]);
 const profile=benefitProfile(benefitCells.get(education.site_id[i]),selection,benefits.spec,true,schools,[lon,lat],[]);
 assert.ok(profile.includes(schoolAssignment(schools,[lon,lat]).campus_name));
 if(prefix==='227913')assert.match(profile,/Approximate attendance boundary/);
}
console.log('Elementary-only browser assignment matches sf at every H8 origin; both growth measures and child coverage verified.');

// Default destination budgets match the selected job-access budgets. The job
// summary must use the independent 45-minute transit source, not DAM's 30-minute series.
assert.deepEqual(benefits.spec.defaults,{drive:15,walk_transit:45});
for(const mode of ['drive','walk_transit']) {
 const chosen={...selection,mode,minutes:benefits.spec.defaults[mode]};
 const source=benefitCells.get(example.id);
 const detail=benefitProfile(source,chosen,benefits.spec,true,schools,[-97.666740,30.310930],[],example.row);
 const expectedJobs=mode==='drive'?source.drive__jobs_cumulative__total_jobs__15:example.row.jobs_total;
 assert.ok(detail.includes(`${expectedJobs.toLocaleString('en-US',{maximumFractionDigits:0})} total within ${chosen.minutes} minutes`));
}
console.log('Aligned 15-minute driving / 45-minute transit defaults and job summary sources verified.');
