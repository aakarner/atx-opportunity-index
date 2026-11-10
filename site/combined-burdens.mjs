import {finite,escapeHTML as esc} from './logic.mjs';
export const burdenLabels={high:'High burden identified',high_incomplete:'High burden identified · incomplete assessment',not_flagged:'No high-burden flags identified',incomplete:'Incomplete assessment'};
export const burdenColors={high:'#b94f39',high_incomplete:'#7d343e',not_flagged:'#dce5e5',incomplete:'#a8b4be'};
const names={heat:'Heat',street:'Street safety',industrial:'Industrial air',traffic:'Near-road traffic'};
const flagNames={heat:'Heat',crash:'Fatal / serious-injury crashes',gap:'Pedestrian gaps',industrial:'Industrial air',traffic:'Near-road traffic'};
const fmt=(v,d=1)=>finite(v)?v.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
export const burdenMeasures={combined:'Combined burden score',flags:'High-burden warnings',heat:'Heat score',street:'Street-safety score',industrial:'Industrial-air score',traffic:'Traffic-exposure score',crash:'Crash score',gap:'Pedestrian-gap score',heat_quality:'Heat observation quality',industrial_review:'Industrial-air screening bands'};
export function assessBurden(row,policy,{trafficSensitivity=false}={}){
 const r=row||{},domains={heat:r.heat_score??null,street:r.street_safety_score??null,industrial:r.industrial_air_score??null,traffic:r.traffic_score??null};
 const fields={heat:'heat_score',street:'street_safety_score',industrial:'industrial_air_score',traffic:'traffic_score'};
 const weights=policy.relative_weights,total=Object.values(weights).reduce((a,b)=>a+b,0);
 const missing=Object.keys(domains).filter(k=>!finite(domains[k]));
 const score=missing.length?null:Object.keys(domains).reduce((n,k)=>n+domains[k]*weights[fields[k]]/total,0);
 const flags={heat:r.heat_high??null,crash:r.crash_high??null,gap:r.pedestrian_high??null,industrial:r.industrial_air_high??null,traffic:(trafficSensitivity?r.traffic_sensitivity_high:r.traffic_high)??null};
 const high=Object.keys(flags).filter(k=>flags[k]===true),unknown=Object.values(flags).some(v=>v!==true&&v!==false);
 const status=high.length?(unknown?'high_incomplete':'high'):(unknown?'incomplete':'not_flagged');
 return {score,status,domains,flags,high,missing,weights:Object.fromEntries(Object.keys(domains).map(k=>[k,weights[fields[k]]/total]))};
}
function rows(columns){const ids=columns.id;if(!Array.isArray(ids))throw Error('Missing burden origin IDs');for(const v of Object.values(columns))if(!Array.isArray(v)||v.length!==ids.length)throw Error('Mismatched burden columns');return ids.map((_,i)=>Object.fromEntries(Object.entries(columns).map(([k,v])=>[k,v[i]])));}
export function indexBurdens(data,ids){
 if(data.schema_version!==1||data.policy?.default!=='equal_thirds_by_theme'||data.policy.four_domain_sensitivity!==false)throw Error('Unsupported burden policy');
 const w=data.policy.relative_weights;
 if(w.heat_score!==2||w.street_safety_score!==2||w.industrial_air_score!==1||w.traffic_score!==1)throw Error('Burden weights differ from adopted preset');
 const result={data};
 for(const key of ['primary','quarter_mile']){
  const records=rows(data[key]),map=new Map(records.map(r=>[r.id,r]));
  if(map.size!==records.length||map.size!==ids.length||ids.some(id=>!map.has(id)))throw Error('Burden geography mismatch');
  for(const r of records){
   for(const f of ['heat_score','street_safety_score','industrial_air_score','traffic_score','crash_score','pedestrian_gap_score'])if(r[f]!==null&&(!finite(r[f])||r[f]<0||r[f]>100))throw Error('Invalid burden score');
   const expected={heat_high:finite(r.heat_score)?r.heat_score>=data.rules.heat.high_burden_percentile:null,
    crash_high:finite(r.annual_ksi_density)?r.annual_ksi_density>=data.rules.street.scoring.crash_high_burden_density:null,
    pedestrian_high:finite(r.pedestrian_gap_score)?r.pedestrian_gap_score>=data.rules.street.scoring.pedestrian_high_burden_score:null,
    industrial_air_high:finite(r.industrial_air_score)?r.rsei_tox_conc>=data.rules.industrial.high_burden_concentration:null,
    traffic_high:finite(r.traffic_score)?r.traffic_buffer_share>=data.rules.traffic.high_burden_share:null,
    traffic_sensitivity_high:finite(r.traffic_score)?r.traffic_buffer_share>=data.rules.traffic.sensitivity_high_burden_share:null};
   for(const [k,v] of Object.entries(expected))if(r[k]!==v)throw Error('Burden component flag mismatch: '+k);
   const a=assessBurden(r,data.policy),b=assessBurden(r,data.policy,{trafficSensitivity:true});
   if(a.score===null?r.combined_burden_score!==null:!finite(r.combined_burden_score)||Math.abs(a.score-r.combined_burden_score)>1e-8)throw Error('Combined burden score mismatch');
   if(a.status!==r.burden_status||b.status!==r.traffic_sensitivity_status)throw Error('Combined burden status mismatch');
  }
  result[key]=map;
 }
 return result;
}
export function burdenValue(r,a,measure){return measure==='combined'?a.score:measure==='crash'?r?.crash_score:measure==='gap'?r?.pedestrian_gap_score:a.domains[measure];}
export function burdenColor(value){if(!finite(value))return '#a8b4be';const colors=['#fff0c2','#f2b687','#db7062','#a74771','#502b63'];return colors[Math.min(4,Math.floor(value/20))];}
export function burdenStyle(r,a,measure){
 let color;
 if(measure==='flags')color=burdenColors[a.status];
 else if(measure==='heat_quality')color=r?.heat_thin_coverage===true?'#d5a448':r?.heat_thin_coverage===false?'#73a7a6':'#a8b4be';
 else if(measure==='industrial_review')color=a.flags.industrial===true?'#943958':r?.industrial_air_review_band===true?'#e6a34a':a.flags.industrial===false?'#dce5e5':'#a8b4be';
 else color=burdenColor(burdenValue(r,a,measure));
 const flagged=measure==='combined'?a.high.length>0:measure==='street'?(a.flags.crash===true||a.flags.gap===true):a.flags[measure]===true;
 return {fillColor:color,fillOpacity:.88,color:flagged?'#98422c':'#fff',weight:flagged?1.7:.5,dashArray:flagged?'4 2':null};
}
export function burdenLegend(measure,{quarterMile=false,trafficSensitivity=false}={}){
 const radius=quarterMile?'¼-mile sensitivity':'½-mile neighborhoods';
 let rule='Heat ⅓ · Street safety ⅓ · Air ⅓ (split equally)',entries=[],note='Higher = greater burden. Dashed orange outlines mark high component burden. Gray = unavailable.';
 if(measure==='flags'){rule='Warnings stay separate from the weighted average';entries=Object.entries(burdenLabels).map(([k,l])=>[burdenColors[k],l]);note='Secondary industrial review and limited heat observations are separate badges in profiles.';}
 else if(measure==='heat_quality'){rule='Dates with at least half of hex land observed';entries=[['#d5a448','Fewer than 8 eligible dates'],['#73a7a6','At least 8 eligible dates']];note='Scores are retained when observations are limited.';}
 else if(measure==='industrial_review'){rule='RSEI toxicity-weighted concentration';entries=[['#943958','High burden · ≥351.1'],['#e6a34a','Secondary review · 100 to <351.1'],['#dce5e5','Below review band']];note='Thresholds rounded here; flags use exact frozen values. These are screening bands, not health standards.';}
 else {
  rule={heat:'Relative daytime surface heat · high at percentile 90',street:radius+' · 50% crashes + 50% pedestrian gaps',industrial:'Linear to 100 at ToxConc 622.7 · high at 351.1',traffic:'Percent of full hex within 300 m of >50,000-AADT roads',crash:radius+' · annual KSI crashes / observed square mile',gap:radius+' · planned / (existing + planned) facility length'}[measure]||rule;
  entries=['0–<20','20–<40','40–<60','60–<80','80–100'].map((l,i)=>[burdenColor(i*20),l]);
 }
 if(measure!=='flags')entries.push(['#a8b4be','Unavailable']);
 if(quarterMile||trafficSensitivity)rule+=' · '+[quarterMile?'¼-mile street sensitivity':null,trafficSensitivity?'25% traffic-flag sensitivity':null].filter(Boolean).join(' · ');
 return {title:burdenMeasures[measure],rule,entries,note};
}
export function burdenProfile(r,a,options={}){
 if(!r)return '<section class="combined-score burden-score"><div class="metric-label">Combined burdens</div><p>Unavailable for this location. No burden flags can be inferred.</p></section>';
 const inventoryNote={no_classified_network:'No classified existing or planned pedestrian network is recorded in this window.',unclassified_inventory:'Unclassified pedestrian facilities prevent a reliable gap score.',no_city_observation_area:'No City observation area is available in this window.'}[r.status];
 const warning=a.high.length?`High components: ${a.high.map(k=>flagNames[k]).join(' · ')}.`:'No primary high-burden component is currently identified.';
 const raw={heat:`${fmt(r.dates_half_land,0)} eligible satellite dates · ${fmt(r.quality_hot_pixel_share)}% hot-pixel observations (context only)`,
  street:`${fmt(r.street_radius_miles,2)}-mile windows · crash ${fmt(r.crash_score)} / gaps ${fmt(r.pedestrian_gap_score)} points`,
  industrial:`RSEI ToxConc ${fmt(r.rsei_tox_conc)} · ${r.industrial_air_review_band?'secondary review band':a.flags.industrial===true?'high burden':a.flags.industrial===false?'below review band':'unavailable'}`,
  traffic:`${fmt(finite(r.traffic_buffer_share)?100*r.traffic_buffer_share:null)}% corridor overlap · ${fmt(r.traffic_distance_ft,0)} ft from hex center to nearest qualifying road`};
 return `<section class="combined-score burden-score"><div class="metric-label">Combined burdens · equal thirds by theme</div><div class="metric-value">${fmt(a.score)}${finite(a.score)?' <small>/ 100</small>':''}</div><p class="small">Higher means greater burden. Heat ⅓ · street safety ⅓ · air ⅓, split equally between industrial air and traffic.</p><span class="minimum-status ${a.high.length?'below':a.status==='incomplete'?'incomplete':'neutral'}">${esc(burdenLabels[a.status])}</span><p class="minimum-reason">${esc(warning)}</p>${a.missing.length?`<p class="notice">Missing domains: ${a.missing.map(k=>names[k]).join(', ')}. No combined score is assigned; weights are not redistributed.</p>`:''}
 ${inventoryNote?`<p class="quality-badge">${esc(inventoryNote)}</p>`:''}
 ${options.quarterMile||options.trafficSensitivity?`<p class="notice">Sensitivity active: ${[options.quarterMile?'¼-mile street-safety windows':null,options.trafficSensitivity?'traffic flag at 25% overlap':null].filter(Boolean).join(' · ')}. Default uses ½ mile and a 50% traffic flag.</p>`:''}
 ${r.heat_thin_coverage?'<p class="quality-badge">Limited heat observations: fewer than 8 eligible dates. Score retained.</p>':''}${r.industrial_air_review_band?'<p class="quality-badge">Industrial air: secondary review band. This is separate from a high-burden flag.</p>':''}${r.completion_date_review?'<p class="quality-badge">Pedestrian inventory review: planned facilities carry a past completion date.</p>':''}
 <details class="burden-detail"><summary>Burden components and observations</summary>${Object.entries(a.domains).map(([k,v])=>`<div class="domain-score"><div><strong>${names[k]}</strong><span>${fmt(v)} points · ${fmt(100*a.weights[k])}%</span></div><p>${esc(raw[k])}</p></div>`).join('')}
 <p class="small">Street safety: ${fmt(r.ksi_count,0)} fatal/serious-injury crashes in 2020–2024; ${fmt(r.annual_ksi_density,2)} per year per square mile. Observed City area ${fmt(r.observed_area_sqmi,2)} sq. mi (${fmt(finite(r.observed_area_share)?100*r.observed_area_share:null)}% of the circle). Pedestrian network denominator: ${fmt(finite(r.denominator_m)?r.denominator_m/1609.344:null,2)} miles.</p>
 <p class="small">Heat: 2026 daytime surface temperatures, not air temperature. Industrial air: 2022 RSEI. Traffic: November 2026 extraction; individual count years unspecified. These are neighborhood screening measures, not health-risk estimates. A zero or unflagged result does not establish safety. Road distance is from the hex center, not this address.</p></details><p class="small">Warnings cannot be canceled by a low average. Benefits and flood eligibility remain separate.</p></section>`;
}
