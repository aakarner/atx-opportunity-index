import {finite,escapeHTML as esc} from './logic.mjs?v=e2b7c16e95d7';
export const burdenLabels={high:'Overall high burden · 2+ high components',high_incomplete:'Overall high burden · incomplete assessment',not_flagged:'Below overall high-burden threshold',incomplete:'Incomplete assessment'};
export const burdenColors={high:'#b94f39',high_incomplete:'#7d343e',not_flagged:'#dce5e5',incomplete:'#a8b4be'};
const names={heat:'Heat',crash:'Fatal / serious-injury crashes',frontage:'Sidewalk gaps on major streets',industrial:'Industrial air',traffic:'Near-road traffic'};
const scoreFields={heat:'heat_score',crash:'crash_score',frontage:'major_frontage_score',industrial:'industrial_air_score',traffic:'traffic_score'};
const fmt=(v,d=1)=>finite(v)?v.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
export const burdenMeasures={combined:'Combined burden score',flags:'Overall high-burden classification',heat:'Heat score',industrial:'Industrial-air score',traffic:'Traffic-exposure score',crash:'Crash score',frontage:'Sidewalk gaps on major streets',heat_quality:'Heat observation quality',industrial_review:'Industrial-air screening bands'};
export function assessBurden(row,policy,{trafficSensitivity=false}={}){
 if(policy.classification_rule!=='at_least_two_primary_components_high_independent_of_score'||policy.high_component_minimum!==2)throw Error('Unsupported overall burden classification');
 const r=row||{};
 const domains=Object.fromEntries(Object.entries(scoreFields).map(([key,field])=>[key,r[field]??null]));
 const weights=policy.relative_weights,total=Object.values(weights).reduce((a,b)=>a+b,0);
 const missing=Object.keys(domains).filter(k=>!finite(domains[k]));
 const score=missing.length?null:Object.keys(domains).reduce((n,k)=>n+domains[k]*weights[scoreFields[k]]/total,0);
 const flags={heat:r.heat_high??null,crash:r.crash_high??null,frontage:r.major_frontage_high??null,industrial:r.industrial_air_high??null,traffic:(trafficSensitivity?r.traffic_sensitivity_high:r.traffic_high)??null};
 const high=Object.keys(flags).filter(k=>flags[k]===true),unknown=Object.values(flags).some(v=>v!==true&&v!==false);
 const overallHigh=high.length>=policy.high_component_minimum?true:unknown?null:false;
 const status=overallHigh===true?(unknown?'high_incomplete':'high'):(unknown?'incomplete':'not_flagged');
 return {score,status,overallHigh,domains,flags,high,missing,weights:Object.fromEntries(Object.keys(domains).map(k=>[k,weights[scoreFields[k]]/total]))};
}
function rows(columns){const ids=columns.id;if(!Array.isArray(ids))throw Error('Missing burden origin IDs');for(const v of Object.values(columns))if(!Array.isArray(v)||v.length!==ids.length)throw Error('Mismatched burden columns');return ids.map((_,i)=>Object.fromEntries(Object.entries(columns).map(([k,v])=>[k,v[i]])));}
export function indexBurdens(data,ids,tractIds=data.tracts?.primary?.id){
 if(data.schema_version!==5||data.policy?.default!=='equal_thirds_by_theme')throw Error('Unsupported burden policy');
 const w=data.policy.relative_weights;
 if(Object.keys(w).length!==5||w.heat_score!==2||w.crash_score!==1||w.major_frontage_score!==1||w.industrial_air_score!==1||w.traffic_score!==1)throw Error('Burden weights differ from adopted preset');
 const result={data,tracts:{}};
 for(const key of ['primary','quarter_mile']){
  const records=rows(data[key]),map=new Map(records.map(r=>[r.id,r]));
  if(map.size!==records.length||map.size!==ids.length||ids.some(id=>!map.has(id)))throw Error('Burden geography mismatch');
  for(const r of records){
   for(const f of Object.values(scoreFields))if(r[f]!==null&&(!finite(r[f])||r[f]<0||r[f]>100))throw Error('Invalid burden score');
   const total=r.major_frontage_m,served=r.major_served_m,coverage=r.major_coverage_pct;
   const status=total===null?'no_city_observation_area':total===0?'no_major_street':served===0 && !r.inventory_observed?'no_pedestrian_inventory':'available';
   if((total===null)!==(served===null) || (total!==null && (!finite(total)||!finite(served)||served<0||served>total||typeof r.inventory_observed!=='boolean')) || r.frontage_status!==status)
    throw Error('Invalid major-street frontage observations');
   if(status==='available' ? !finite(coverage)||!finite(r.major_frontage_score)||Math.abs(coverage-100*served/total)>1e-8||Math.abs(r.major_frontage_score+coverage-100)>1e-8 : coverage!==null||r.major_frontage_score!==null)
    throw Error('Invalid major-street coverage or burden');
   const expected={heat_high:finite(r.heat_score)?r.heat_score>=data.rules.heat.high_burden_percentile:null,
    crash_high:finite(r.annual_ksi_density)?r.annual_ksi_density>=data.rules.street.scoring.crash_high_burden_density:null,
    major_frontage_high:finite(r.major_frontage_score)?r.major_frontage_score>=data.rules.street.scoring.major_frontage_high_burden_score:null,
    industrial_air_high:finite(r.industrial_air_score)?r.rsei_tox_conc>=data.rules.industrial.high_burden_concentration:null,
    traffic_high:finite(r.traffic_score)?r.traffic_buffer_share>=data.rules.traffic.high_burden_share:null,
    traffic_sensitivity_high:finite(r.traffic_score)?r.traffic_buffer_share>=data.rules.traffic.sensitivity_high_burden_share:null};
   for(const [k,v] of Object.entries(expected))if(r[k]!==v)throw Error('Burden component flag mismatch: '+k);
   const a=assessBurden(r,data.policy),b=assessBurden(r,data.policy,{trafficSensitivity:true});
   if(a.score===null?r.combined_burden_score!==null:!finite(r.combined_burden_score)||Math.abs(a.score-r.combined_burden_score)>1e-8)throw Error('Combined burden score mismatch');
   if(a.high.length!==r.high_component_count||a.overallHigh!==r.overall_high)throw Error('Combined burden classification mismatch');
   if((a.high.length?true:Object.values(a.flags).some(v=>v===null)?null:false)!==r.any_high)throw Error('Combined burden warning mismatch');
   if(a.status!==r.burden_status||b.status!==r.traffic_sensitivity_status)throw Error('Combined burden status mismatch');
  }
  result[key]=map;
  const estimates=rows(data.tracts[key]);
  const byTract=new Map(estimates.map(r=>[r.id,r]));
  if(byTract.size!==estimates.length || byTract.size!==tractIds.length || tractIds.some(id=>!byTract.has(id)))throw Error('Burden tract geography mismatch');
  result.tracts[key]=byTract;
 }
 return result;
}
export function burdenColor(value){if(!finite(value))return '#a8b4be';const colors=['#fff0c2','#f2b687','#db7062','#a74771','#502b63'];return colors[Math.min(4,Math.floor(value/20))];}
export function burdenStyle(r,a,measure){
 let color;
 if(measure==='flags')color=burdenColors[a.status];
 else if(measure==='heat_quality')color=r?.heat_thin_coverage===true?'#d5a448':r?.heat_thin_coverage===false?'#73a7a6':'#a8b4be';
 else if(measure==='industrial_review')color=a.flags.industrial===true?'#943958':r?.industrial_air_review_band===true?'#e6a34a':a.flags.industrial===false?'#dce5e5':'#a8b4be';
 else color=burdenColor(measure==='combined'?a.score:a.domains[measure]);
 const flagged=measure==='combined'?a.overallHigh===true:a.flags[measure]===true;
 return {fillColor:color,fillOpacity:.88,color:flagged?'#98422c':'#fff',weight:flagged?1.7:.5,dashArray:flagged?'4 2':null};
}
export function burdenLegend(measure,{quarterMile=false,trafficSensitivity=false}={}){
 const radius=quarterMile?'¼-mile windows':'½-mile windows';
 let rule='Heat ⅓ · Crashes, sidewalk gaps on major streets, industrial air and traffic ⅙ each',entries=[],note='Higher = greater burden. Dashed orange outlines mark high component burden. Gray = unavailable.';
 if(measure==='combined')note='Higher = greater burden. Dashed orange outlines mark overall high burden (2+ high components). Gray = unavailable score; a known overall high burden still receives an outline.';
 if(measure==='flags'){rule='Overall high burden requires at least 2 high components';entries=Object.entries(burdenLabels).map(([k,l])=>[burdenColors[k],l]);note='Crashes and sidewalk gaps on major streets count separately. Individual component warnings remain visible in profiles; secondary industrial review and limited heat observations do not count.';}
 else if(measure==='heat_quality'){rule='Dates with at least half of hex land observed';entries=[['#d5a448','Fewer than 8 eligible dates'],['#73a7a6','At least 8 eligible dates']];note='Scores are retained when observations are limited.';}
 else if(measure==='industrial_review'){rule='RSEI toxicity-weighted concentration';entries=[['#943958','High burden · ≥351.1'],['#e6a34a','Secondary review · 100 to <351.1'],['#dce5e5','Below review band']];note='Thresholds rounded here; flags use exact frozen values. These are screening bands, not health standards.';}
 else {
  rule={heat:'Relative daytime surface heat · high at percentile 90',industrial:'Linear to 100 at ToxConc 622.7 · high at 351.1',traffic:'Percent of full hex within 300 m of >50,000-AADT roads',crash:radius+' · annual KSI crashes / observed square mile',frontage:radius+' · Percentage of major-street length without a mapped sidewalk or parallel path, counting each side separately · high at 50%'}[measure]||rule;
  entries=['0–<20','20–<40','40–<60','60–<80','80–100'].map((l,i)=>[burdenColor(i*20),l]);
 }
 if(measure==='frontage')note='Gray indicates no eligible major street or unknown coverage. Select a hexagon for the reason.';
 if(measure!=='flags')entries.push(['#a8b4be','Unavailable']);
 if(quarterMile||trafficSensitivity)rule+=' · '+[quarterMile?'¼-mile windows for crashes and sidewalk gaps':null,trafficSensitivity?'25% traffic-flag sensitivity':null].filter(Boolean).join(' · ');
 return {title:burdenMeasures[measure],rule,entries,note};
}
export const tractShareLabels={
 flags:'Residents in hexagons with confirmed overall high burden',
 heat_quality:'Residents in hexagons with limited heat observations',
 industrial_review:'Residents in the secondary industrial-air review band'
};
function overallField(options){
 return options.trafficSensitivity?'traffic_sensitivity_overall':'overall';
}
export function tractBurdenValue(row,measure,options={}){
 const fields={...scoreFields,combined:'combined_burden_score',flags:overallField(options)+'_high_pct',
  heat_quality:'heat_thin_coverage_pct',industrial_review:'industrial_air_review_band_pct'};
 return row?.[fields[measure]]??null;
}
export function tractBurdenLegend(measure,options){
 const share=tractShareLabels[measure];
 const labels=['0–<20','20–<40','40–<60','60–<80','80–100'];
 const entries=labels.map((label,i)=>[burdenColor(20*i),label+(share?'%':' points')]);
 entries.push(['#a8b4be','Unavailable']);
 const rule=share?'Percent of represented residents. Flags are evaluated at each hexagon.':'Resident-weighted mean of available hexagon scores.';
 const notes=[options.quarterMile?'¼-mile street windows':'½-mile street windows',
  options.trafficSensitivity?'25% traffic flag':'50% traffic flag'];
 return {title:share||('Tract mean · '+burdenMeasures[measure]),rule,entries,
  note:notes.join(' · ')+'. Select a tract for population and area coverage.'};
}
const percent=value=>finite(value)?fmt(value)+'%':'Unavailable';
export function tractBurdenProfile(row,options={}){
 const overall=overallField(options);
 const highFields={heat:'heat_high_pct',crash:'crash_high_pct',frontage:'major_frontage_high_pct',
  industrial:'industrial_air_high_pct',traffic:options.trafficSensitivity?'traffic_sensitivity_high_pct':'traffic_high_pct'};
 const components=Object.entries(scoreFields).map(([key,field])=>
  `<tr><th scope="row">${names[key]}</th><td>${fmt(row?.[field])}</td><td>${percent(row?.[highFields[key]])}</td><td>${percent(row?.[field+'_coverage_pct'])}</td></tr>`
 ).join('');
 return `<section class="combined-score burden-score"><div class="metric-label">Combined burdens · Tract population summary</div>
  <div class="metric-value">${fmt(row?.combined_burden_score)}${finite(row?.combined_burden_score)?' <small>/ 100</small>':''}</div>
  <p class="small">Resident-weighted mean for hexagons with all five scores. Each component mean uses the residents with data for that component.</p>
  <dl class="components"><div><dt>Residents with a complete score</dt><dd>${percent(row?.combined_burden_score_coverage_pct)}</dd></div>
  <div><dt>Residents in hexagons with confirmed overall high burden</dt><dd>${percent(row?.[overall+'_high_pct'])}</dd></div>
  <div><dt>Residents with unknown overall classification</dt><dd>${percent(row?.[overall+'_unknown_pct'])}</dd></div>
  <div><dt>Estimated residents represented</dt><dd>${fmt(row?.resident_weight,0)}</dd></div>
  <div><dt>Tract area covered by hexagons</dt><dd>${percent(row?.area_coverage*100)}</dd></div>
  <div><dt>Tract area with known population weights</dt><dd>${percent(row?.resident_weight_area_share*100)}</dd></div></dl>
  <details><summary>Tract burden components</summary><table class="tract-burden-table"><thead><tr><th>Measure</th><th>Mean score</th><th>Residents in high-burden hexagons</th><th>Residents with scores</th></tr></thead><tbody>${components}</tbody></table>
  <dl class="components"><div><dt>${tractShareLabels.heat_quality}</dt><dd>${percent(row?.heat_thin_coverage_pct)}</dd></div>
  <div><dt>${tractShareLabels.industrial_review}</dt><dd>${percent(row?.industrial_air_review_band_pct)}</dd></div></dl></details>
  <p class="small">Resident shares use the known population in overlapping hexagons. Overall high burden starts at two high components in the same hexagon. Street windows use ${options.quarterMile?'¼':'½'} mile. The traffic flag starts at ${options.trafficSensitivity?25:50}% overlap.</p></section>`;
}
export function burdenProfile(r,a,options={}){
 if(!r)return '<section class="combined-score burden-score"><div class="metric-label">Combined burdens</div><p>Unavailable for this location. No burden flags can be inferred.</p></section>';
 const inventoryNote={no_major_street:'No eligible major street in this window.',no_pedestrian_inventory:'Sidewalk coverage is unknown. This window contains major streets, but has no pedestrian inventory or mapped parallel path.',no_city_observation_area:'The window has no area inside Austin.'}[r.frontage_status];
 const warning=a.high.length?`High components: ${a.high.map(k=>names[k]).join(' · ')}.`:'No primary high-burden component is currently identified.';
 const raw={heat:`${fmt(r.dates_half_land,0)} eligible satellite dates · ${fmt(r.quality_hot_pixel_share)}% hot-pixel observations (context only)`,
  crash:`${fmt(r.ksi_count,0)} fatal or serious-injury crashes in 2020–2024 · ${fmt(r.annual_ksi_density,2)} per year per observed square mile`,
  frontage:finite(r.major_coverage_pct)
   ? `${fmt(r.major_coverage_pct)}% served · ${fmt(r.major_frontage_score)}% unserved · ${fmt(r.major_served_m/1609.344,2)} of ${fmt(r.major_frontage_m/1609.344,2)} miles have a mapped sidewalk or parallel path, counting each side separately`
   : (inventoryNote || 'Sidewalk coverage unavailable'),
  industrial:`RSEI ToxConc ${fmt(r.rsei_tox_conc)} · ${r.industrial_air_review_band?'secondary review band':a.flags.industrial===true?'high burden':a.flags.industrial===false?'below review band':'unavailable'}`,
  traffic:`${fmt(finite(r.traffic_buffer_share)?100*r.traffic_buffer_share:null)}% corridor overlap · ${fmt(r.traffic_distance_ft,0)} ft from hex center to nearest qualifying road`};
 return `<section class="combined-score burden-score"><div class="metric-label">Combined burdens · equal thirds by theme</div><div class="metric-value">${fmt(a.score)}${finite(a.score)?' <small>/ 100</small>':''}</div><p class="small">Higher means greater burden. Heat contributes one third. Crashes, sidewalk gaps on major streets, industrial air and traffic each contribute one sixth.</p><span class="minimum-status ${a.overallHigh===true?'below':a.status==='incomplete'?'incomplete':'neutral'}">${esc(burdenLabels[a.status])}</span><p class="minimum-reason">${esc(warning)} ${a.high.length} known high component${a.high.length===1?'':'s'}; overall high burden requires at least 2. Crashes and sidewalk gaps on major streets count separately.</p>${a.missing.length?`<p class="notice">Missing components: ${a.missing.map(k=>names[k]).join(', ')}. No combined score is assigned; weights are not redistributed.</p>`:''}
 ${inventoryNote?`<p class="quality-badge">${esc(inventoryNote)}</p>`:''}
 ${options.quarterMile||options.trafficSensitivity?`<p class="notice">Sensitivity active: ${[options.quarterMile?'¼-mile windows for crashes and sidewalk gaps':null,options.trafficSensitivity?'traffic flag at 25% overlap':null].filter(Boolean).join(' · ')}. Default uses ½ mile and a 50% traffic flag.</p>`:''}
 ${r.heat_thin_coverage?'<p class="quality-badge">Limited heat observations: fewer than 8 eligible dates. Score retained.</p>':''}${r.industrial_air_review_band?'<p class="quality-badge">Industrial air: secondary review band. This is separate from a high-burden flag.</p>':''}
 <details class="burden-detail"><summary>Burden components and observations</summary>${Object.entries(a.domains).map(([k,v])=>`<div class="domain-score"><div><strong>${names[k]}</strong><span>${fmt(v)} points · ${fmt(100*a.weights[k])}%</span></div><p>${esc(raw[k])}</p></div>`).join('')}
 <p class="small">Crash and sidewalk gap measures use ${fmt(r.street_radius_miles,2)}-mile windows. Observed City area ${fmt(r.observed_area_sqmi,2)} sq. mi (${fmt(finite(r.observed_area_share)?100*r.observed_area_share:null)}% of the circle).</p>
 <p class="small">Heat: 2026 daytime surface temperatures, not air temperature. Industrial air: 2022 RSEI. Traffic: November 2026 extraction; individual count years unspecified. These measures describe conditions at the hexagon scale. A zero or unflagged result does not establish safety. Road distance is from the hex center, not this address.</p></details><p class="small">Warnings cannot be canceled by a low average. Benefits and flood eligibility remain separate.</p></section>`;
}
