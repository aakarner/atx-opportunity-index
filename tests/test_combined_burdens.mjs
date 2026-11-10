import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {indexBurdens,assessBurden,burdenColor,burdenStyle,burdenProfile,burdenLegend,burdenMeasures} from '../site/combined-burdens.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const data=read('site/assets/combined-burdens.json'),ids=read('site/assets/hexagons.json').map(r=>r.id);
const index=indexBurdens(data,ids),close=(a,b)=>assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);
assert.deepEqual(data.counts.statuses,{high:480,high_incomplete:38,not_flagged:400,incomplete:111});
for(const key of ['primary','quarter_mile']){
 const rows=[...index[key].values()];
 assert.equal(rows.length,1029);
 assert.equal(rows.filter(r=>r.combined_burden_score!==null).length,key==='primary'?880:800);
 for(const r of rows){
  close(r.traffic_score,100*r.traffic_buffer_share);
  close(r.industrial_air_score,Math.min(100,100*r.rsei_tox_conc/data.rules.industrial.full_burden_concentration));
  close(r.crash_score,Math.min(100,100*r.annual_ksi_density/data.rules.street.scoring.crash_full_burden_density));
  assert.equal(r.heat_thin_coverage,r.dates_half_land<8);
  assert.equal(r.industrial_air_review_band,r.rsei_tox_conc>=100&&!r.industrial_air_high);
  if(r.pedestrian_gap_score===null)assert.equal(r.street_safety_score,null);
  else close(r.street_safety_score,(r.crash_score+r.pedestrian_gap_score)/2);
  const a=assessBurden(r,data.policy),b=assessBurden(r,data.policy,{trafficSensitivity:true});
  assert.equal(a.score,b.score); // Traffic sensitivity changes flags, never scores.
  assert.ok(a.high.every(k=>b.high.includes(k)));
  for(const m of Object.keys(burdenMeasures))assert.match(burdenStyle(r,a,m).fillColor,/^#[a-f0-9]{6}$/i);
  if(a.score!==null)close(a.score,r.heat_score/3+r.street_safety_score/3+r.industrial_air_score/6+r.traffic_score/6);
  if(a.status==='high_incomplete')assert.match(burdenProfile(r,a),/No combined score is assigned/);
 }
}
const complete=[...index.primary.values()].find(r=>r.combined_burden_score!==null);
const synthetic={...complete,heat_score:90,street_safety_score:0,industrial_air_score:0,traffic_score:0,heat_high:true,crash_high:false,pedestrian_high:false,industrial_air_high:false,traffic_high:false};
let a=assessBurden(synthetic,data.policy);close(a.score,30);assert.equal(a.status,'high');
synthetic.street_safety_score=null;synthetic.pedestrian_gap_score=null;synthetic.pedestrian_high=null;
a=assessBurden(synthetic,data.policy);assert.equal(a.score,null);assert.equal(a.status,'high_incomplete');assert.deepEqual(a.high,['heat']);
assert.equal(burdenStyle(synthetic,a,'combined').dashArray,'4 2');
const absent=assessBurden(null,data.policy);assert.equal(absent.score,null);assert.equal(absent.status,'incomplete');
assert.notEqual(burdenColor(0),burdenColor(null));
const missingContext={...synthetic,traffic_buffer_share:null,observed_area_share:null,denominator_m:null};
assert.match(burdenProfile(missingContext,a),/Unavailable% corridor overlap/);
assert.match(burdenProfile(missingContext,a),/denominator: Unavailable miles/);
assert.match(burdenProfile(null,absent),/No burden flags can be inferred/);
assert.equal(burdenLegend('flags').entries.length,4);
for(const mutation of [x=>x.policy.relative_weights.heat_score=1,x=>x.policy.four_domain_sensitivity=true,x=>x.primary.id[0]=x.primary.id[1],x=>x.primary.combined_burden_score[0]=999,x=>x.primary.heat_high[0]=!x.primary.heat_high[0]]){
 const invalid=structuredClone(data);mutation(invalid);assert.throws(()=>indexBurdens(invalid,ids));
}
console.log('Combined burdens: 1,029 origins, R/JS agreement, both radii and traffic flags, fixed weights, missingness, component warnings and display checks passed.');
