import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {indexBurdens,assessBurden,burdenColor,burdenStyle,burdenProfile,burdenLegend,burdenMeasures,tractBurdenValue,tractBurdenProfile,tractBurdenLegend} from '../site/combined-burdens.mjs';
import {columnRows} from '../site/combined-benefits.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const data=read('site/assets/combined-burdens.json'),ids=read('site/assets/hexagons.json').map(r=>r.id);
const html=readFileSync('site/index.html','utf8');
const selector=html.match(/<select id="burden-measure">([\s\S]*?)<\/select>/)[1];
const options=Object.fromEntries([...selector.matchAll(/<option value="([^"]+)">([^<]+)<\/option>/g)].map(m=>[m[1],m[2]]));
assert.deepEqual(options,burdenMeasures);
assert.deepEqual(Object.keys(options).sort(),['combined','flags','heat','industrial','traffic','crash','frontage','heat_quality','industrial_review'].sort());
const benefits=read('site/assets/combined-benefits.json');
const tractIds=read('site/assets/tracts.geojson').features.map(f=>f.properties.id);
const index=indexBurdens(data,ids,tractIds),close=(a,b)=>assert.ok(Number.isFinite(a)&&Number.isFinite(b)&&Math.abs(a-b)<1e-8,`${a} != ${b}`);
assert.deepEqual(data.counts.statuses,{high:184,high_incomplete:1,not_flagged:690,incomplete:154});
assert.equal(data.counts.high,185);assert.equal(data.counts.any_component_high,551);
for(const key of ['primary','quarter_mile']){
 const rows=[...index[key].values()];
 assert.equal(rows.length,1029);
 assert.ok(!('street_safety_score' in data[key]));
 assert.equal(rows.filter(r=>r.combined_burden_score!==null).length,key==='primary'?874:731);
 for(const r of rows){
  close(r.traffic_score,100*r.traffic_buffer_share);
  close(r.industrial_air_score,Math.min(100,100*r.rsei_tox_conc/data.rules.industrial.full_burden_concentration));
  close(r.crash_score,Math.min(100,100*r.annual_ksi_density/data.rules.street.scoring.crash_full_burden_density));
  assert.equal(r.heat_thin_coverage,r.dates_half_land<8);
  assert.equal(r.industrial_air_review_band,r.rsei_tox_conc>=100&&!r.industrial_air_high);
  const a=assessBurden(r,data.policy),b=assessBurden(r,data.policy,{trafficSensitivity:true});
  assert.equal(a.score,b.score); // Traffic sensitivity changes flags, never scores.
  assert.ok(a.high.every(k=>b.high.includes(k)));
  for(const m of Object.keys(burdenMeasures))assert.match(burdenStyle(r,a,m).fillColor,/^#[a-f0-9]{6}$/i);
  if(a.score!==null)close(a.score,r.heat_score/3+(r.crash_score+r.major_frontage_score)/6+r.industrial_air_score/6+r.traffic_score/6);
  if(a.status==='high_incomplete')assert.match(burdenProfile(r,a),/No combined score is assigned/);
 }
}
const complete=[...index.primary.values()].find(r=>r.combined_burden_score!==null);
const synthetic={...complete,heat_score:90,crash_score:0,major_frontage_score:0,industrial_air_score:0,traffic_score:0,heat_high:true,crash_high:false,major_frontage_high:false,industrial_air_high:false,traffic_high:false};
let a=assessBurden(synthetic,data.policy);close(a.score,30);assert.equal(a.status,'not_flagged');assert.equal(a.overallHigh,false);
assert.match(burdenProfile(synthetic,a),/Below overall high-burden threshold/);
assert.match(burdenProfile(synthetic,a),/High components: Heat/);
assert.equal(burdenStyle(synthetic,a,'flags').fillColor,'#dce5e5');
synthetic.major_frontage_score=null;synthetic.major_frontage_high=null;
a=assessBurden(synthetic,data.policy);assert.equal(a.score,null);assert.equal(a.status,'incomplete');assert.equal(a.overallHigh,null);assert.deepEqual(a.high,['heat']);
assert.deepEqual(a.missing,['frontage']);
assert.match(burdenProfile(synthetic,a),/Missing components: Sidewalk gaps on major streets/);
assert.equal(burdenStyle(synthetic,a,'crash').fillColor,burdenColor(0));
assert.equal(burdenStyle(synthetic,a,'frontage').fillColor,burdenColor(null));
assert.equal(burdenStyle(synthetic,a,'combined').dashArray,null);
assert.equal(burdenStyle(synthetic,a,'heat').dashArray,'4 2');
synthetic.industrial_air_high=true;
a=assessBurden(synthetic,data.policy);assert.equal(a.status,'high_incomplete');assert.equal(a.overallHigh,true);
assert.equal(burdenStyle(synthetic,a,'combined').dashArray,'4 2');
const streetOnly={...complete,heat_high:false,industrial_air_high:false,traffic_high:false,crash_high:true,major_frontage_high:true};
assert.equal(assessBurden(streetOnly,data.policy).status,'high');
const absent=assessBurden(null,data.policy);assert.equal(absent.score,null);assert.equal(absent.status,'incomplete');
assert.notEqual(burdenColor(0),burdenColor(null));
const missingContext={...synthetic,traffic_buffer_share:null,observed_area_share:null,major_coverage_pct:null,frontage_status:'no_pedestrian_inventory'};
assert.match(burdenProfile(missingContext,a),/Unavailable% corridor overlap/);
assert.match(burdenProfile(missingContext,a),/Sidewalk coverage is unknown/);
assert.match(burdenProfile(null,absent),/No burden flags can be inferred/);
assert.equal(burdenLegend('flags').entries.length,4);
assert.match(burdenLegend('combined').note,/overall high burden \(2\+ high components\)/);
assert.match(burdenLegend('heat').note,/high component burden/);
for(const key of ['primary','quarter_mile'])for(const trafficSensitivity of [false,true]){
 const rows=[...index[key].values()];
 const outlined=rows.filter(r=>burdenStyle(r,assessBurden(r,data.policy,{trafficSensitivity}),'combined').dashArray!==null);
 assert.equal(outlined.length,key==='primary'?(trafficSensitivity?218:185):(trafficSensitivity?198:163));
}

const componentFields=['heat_high','crash_high','major_frontage_high','industrial_air_high','traffic_high'];
for(let code=0;code<3**5;code++){
 let rest=code;const row={...complete},values=[];
 for(const f of componentFields){const v=[false,true,null][rest%3];rest=Math.floor(rest/3);row[f]=v;values.push(v);}
 row.traffic_sensitivity_high=row.traffic_high;
 const count=values.filter(v=>v===true).length,unknown=values.includes(null);
 const expected=count>=2?(unknown?'high_incomplete':'high'):(unknown?'incomplete':'not_flagged');
 for(const trafficSensitivity of [false,true]){
  const result=assessBurden(row,data.policy,{trafficSensitivity});
  assert.equal(result.status,expected);assert.equal(result.overallHigh,count>=2?true:unknown?null:false);
 }
}
for(const mutation of [x=>x.schema_version=1,x=>x.policy.high_component_minimum=1,x=>delete x.policy.classification_rule,x=>x.primary.overall_high[0]=!x.primary.overall_high[0],x=>x.primary.major_served_m[0]=-1,x=>x.primary.high_component_count[0]=99,x=>x.policy.relative_weights.heat_score=1,x=>x.policy.relative_weights.street_safety_score=2,x=>x.primary.id[0]=x.primary.id[1],x=>x.primary.combined_burden_score[0]=999,x=>x.primary.heat_high[0]=!x.primary.heat_high[0]]){
 const invalid=structuredClone(data);mutation(invalid);assert.throws(()=>indexBurdens(invalid,ids,tractIds));
}
// Independently reproduce both radii from the population overlaps used for tract benefits.
const overlaps=Map.groupBy(columnRows(benefits.tract_weights),r=>r.tract_id);
const components={heat:'heat_score',industrial:'industrial_air_score',crash:'crash_score',frontage:'major_frontage_score',traffic:'traffic_score',combined:'combined_burden_score'};
const flags={heat:'heat_high',industrial:'industrial_air_high',crash:'crash_high',frontage:'major_frontage_high',traffic:'traffic_high'};
function same(actual,expected){if(expected===null)assert.equal(actual,null);else close(actual,expected);}
for(const radius of ['primary','quarter_mile']){
 for(const coverage of columnRows(benefits.tracts)){
  const tract=index.tracts[radius].get(coverage.id);
  const pairs=(overlaps.get(coverage.id)||[]).filter(w=>w.residents>0).map(w=>({w:w.residents,row:index[radius].get(w.id)}));
  const sum=(items,term)=>items.reduce((n,p)=>n+term(p),0);
  const total=sum(pairs,p=>p.w);
  close(tract.resident_weight,total);
  close(tract.area_coverage,coverage.area_coverage);
  close(tract.resident_weight_area_share,coverage.resident_weight_area_share);
  for(const [measure,field] of Object.entries(components)){
   const valid=pairs.filter(p=>p.row[field]!==null),scored=sum(valid,p=>p.w);
   same(tractBurdenValue(tract,measure),scored?sum(valid,p=>p.w*p.row[field])/scored:null);
   same(tract[field+'_coverage_pct'],total?100*scored/total:null);
  }
  function share(predicate){
   if(!pairs.some(p=>predicate(p.row)!==null))return null;
   return 100*sum(pairs.filter(p=>predicate(p.row)===true),p=>p.w)/total;
  }
  for(const field of [...Object.values(flags),'traffic_sensitivity_high']){
   same(tract[field+'_pct'],share(r=>r[field]));
  }
  for(const trafficSensitivity of [false,true]){
   const high=r=>assessBurden(r,data.policy,{trafficSensitivity}).overallHigh;
   same(tractBurdenValue(tract,'flags',{trafficSensitivity}),share(high));
   same(tract[trafficSensitivity?'traffic_sensitivity_overall_unknown_pct':'overall_unknown_pct'],share(r=>high(r)===null));
  }
  same(tractBurdenValue(tract,'heat_quality'),share(r=>r.heat_thin_coverage));
  same(tractBurdenValue(tract,'industrial_review'),share(r=>r.industrial_air_review_band));
 }
}
for(const measure of Object.keys(burdenMeasures))assert.ok(tractBurdenLegend(measure,{}).entries.length);
assert.match(tractBurdenProfile(index.tracts.primary.get(tractIds[0])),/Tract burden components/);
assert.match(tractBurdenProfile(undefined),/Unavailable/);
assert.throws(()=>indexBurdens(data,ids,tractIds.slice(1)),/tract geography/);
console.log('Verified all tract means, resident coverage, classifications and sensitivities against the benefit population weights.');
console.log('Combined burdens: 1,029 origins, R/JS agreement, both radii and traffic flags, fixed weights, missingness, component warnings and display checks passed.');
