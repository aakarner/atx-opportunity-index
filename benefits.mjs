import {contains, escapeHTML as esc, finite} from './logic.mjs?v=36c8cf2733c4';

export const profileLabels = {
  general:'All eight destinations', families:'Families with children', older:'Older adults',
  single:'Single adults', supportive:'Adult PSH—provisional'
};
export const modeLabels = {drive:'Driving',walk_transit:'Transit + walk'};
export const palette = ['#f4f1df','#cfe6cd','#91c8ac','#509d85','#176956'];
export const differenceColors = ['#a65e43','#e6e5db','#437e91'];
export function records(columns) {
  return columns.id.map((id,i)=>[id,Object.fromEntries(Object.entries(columns).map(([key,col])=>[key,col[i]]))]);
}
export function scoreValue(row,selection) {
  const {mode,minutes,profile}=selection;
  return row?.[`${mode}_${minutes}_${profile}`];
}
export function fractionDifference(row,selection,spec) {
  const count=scoreValue(row,selection), general=scoreValue(row,{...selection,profile:'general'});
  if(!finite(count)||!finite(general)) return null;
  const difference=count/spec.profiles[selection.profile].length-general/spec.profiles.general.length;
  return Math.abs(difference)<1e-12?0:difference;
}
export function basketColor(row,selection,spec) {
  const count=scoreValue(row,selection);
  if(!finite(count)) return '#a8b4be';
  if(selection.display==='difference') {
    const diff=fractionDifference(row,selection,spec);
    return finite(diff)?differenceColors[Math.sign(diff)+1]:'#a8b4be';
  }
  return palette[Math.min(4,Math.floor(4*count/spec.profiles[selection.profile].length))];
}

export function schoolAssignment(zones,point) {
  if(!point) return {status:'No point selected'};
  const matches=zones.features.filter(f=>f.properties.school_level==='elementary' && contains(f.geometry,...point)).map(f=>f.properties);
  const unique=new Set(matches.map(p=>JSON.stringify([p.campus_id,p.campus_name,p.score_status,p.usable_growth,p.subgroup_growth])));
  if(!matches.length) return {status:'Outside available assignment coverage'};
  if(unique.size>1) return {status:'Ambiguous assignment overlap'};
  return {...matches[0],status:matches[0].score_status};
}
export function schoolDetail(zones,point) {
  const p=schoolAssignment(zones,point);
  if(p.status==='No point selected') return '<p>Select an address or map point for its assigned elementary school.</p>';
  if(p.status==='Outside available assignment coverage') return '<p>Outside available elementary assignment coverage</p>';
  if(p.status==='Ambiguous assignment overlap') return '<p>Ambiguous elementary assignment overlap · Scores unavailable</p>';
  return `<p><strong>${esc(p.campus_name)}</strong> · ${esc(p.district_name)}</p>
    <dl class="components"><div><dt>Overall growth</dt><dd>${finite(p.usable_growth)?number(p.usable_growth):esc(p.score_status)}</dd></div>
    <div><dt>Economically disadvantaged growth</dt><dd>${finite(p.subgroup_growth)?number(p.subgroup_growth):esc(p.subgroup_status)}</dd></div></dl>
    ${finite(p.minimum_growth_tests)&&p.minimum_growth_tests<20?'<p class="notice">Small subgroup sample: at least one growth subject has fewer than 20 evaluated tests.</p>':''}
    <p>Current published assignment for 2026–27 · ${esc(p.growth_school_year)} growth. Elementary only; travel time is not scored.</p>
    <details><summary>Attendance boundary source</summary><p>${esc(p.source_layer_label)} · ${esc(p.boundary_year_basis)}</p></details>`;
}
function educationCoverage(spec) {
  const c=spec.education?.coverage;
  if(!c?.scenario) return '';
  const value=(scenario,group)=>{
    const i=c.scenario.findIndex((s,i)=>s===scenario && c.population_group[i]===group);
    return i<0?'Unavailable':number(100*c.population_coverage[i])+'%';
  };
  const items=[['Five-district elementary assignment','Assigned elementary'],['Overall growth available','Overall growth'],['Subgroup growth; minimum 1 tests per subject','Subgroup growth']];
  return `<details><summary>Education coverage · residents and children</summary>
    <table class="education-coverage"><thead><tr><th>Coverage</th><th>Residents</th><th>Under 18</th></tr></thead><tbody>${items.map(([key,label])=>`<tr><td>${label}</td><td>${value(key,'total_population')}</td><td>${value(key,'children_under_18')}</td></tr>`).join('')}</tbody></table>
    <p>Shares of known population weights in the prototype hexes. Children are residents under 18, not enrolled students. ${c.missing_weight_origins[0]} origins have missing population weights and are excluded from these denominators. Small-sample scores are flagged, not discarded.</p></details>`;
}
const number=(v,d=1)=>finite(v)?v.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
export function benefitProfile(row,selection,spec,isHex,zones,point,series,jobBenchmark=null) {
  const {mode,minutes,profile}=selection, names=spec.profiles[profile];
  const prefix=`${mode}_${minutes}_`, count=scoreValue(row,selection);
  const components=names.map(name=>{
    const reached=row?.[prefix+name], key=`${mode}__${name}_nearest__${name==='park'?'park':'facility'}_count__1`;
    let label=finite(reached)?number(reached*100)+'% of represented residents within budget':'Unavailable';
    if(isHex) {
      const status=row?.[`${mode}_${name}_status`];
      label=finite(row?.[key])?`${number(row[key])} min · ${reached?'within':'over'}`:
        status==='not_reached_within_model'?'Unreached in model':'Unknown';
    }
    return `<div><dt>${esc(spec.destinations[name])}</dt><dd>${label}</dd></div>`;
  }).join('');
  const details=series.filter(s=>s.mode===mode && (s.scenario==='jobs_cumulative' ||
    (isHex && (s.scenario.includes('_nearest') && !s.measure_id.endsWith('__1') || s.unit==='acres'))));
  const fields=details.map(s=>`<div><dt>${esc(s.label)}</dt><dd>${number(row?.[s.field])} ${esc(s.unit)}</dd></div>`).join('');
  const jobMinutes=mode==='drive'?15:45;
  const totalJobs=mode==='drive'?row?.drive__jobs_cumulative__total_jobs__15:jobBenchmark?.jobs_total;
  const lowWageJobs=mode==='drive'?row?.drive__jobs_cumulative__low_wage_jobs__15:jobBenchmark?.jobs_low;
  return `<section class="metric-block"><div class="metric-label">${esc(profileLabels[profile])} · ${esc(modeLabels[mode])}</div>
    <div class="metric-value">${number(count)} / ${names.length}</div><div class="metric-unit">${isHex?'Destination types reached':'Resident-weighted mean types reached'} within ${minutes} minutes</div>
    <dl class="components">${components}</dl>
    ${isHex?'':`<p class="small">H8 cells cover ${number(row?.area_coverage*100)}% of the clipped tract area. Resident weights cover ${number(row?.resident_weight_area_share*100)}% of tract area. Estimated resident weight: ${number(row?.resident_weight,0)}. Zero weight gives an unavailable mean.</p>`}
    ${profile==='supportive'?'<p class="notice">Partial basket. Behavioral health, supportive services and on-site supports require separate review.</p>':''}
    ${mode==='walk_transit'?'<p class="small">Provisional July morning routing. An unreached trip can reflect service coverage or model limits.</p>':''}
    ${profile==='families'?`<h3>Assigned elementary school</h3><div class="small">Austin, Round Rock, Pflugerville, Del Valle and Manor${schoolDetail(zones,point)}${educationCoverage(spec)}</div>`:''}
    ${isHex?`<p class="small">Mean trip to the nearest facility across this basket: ${number(row?.[`${mode}_${profile}_mean_minutes`])}${finite(row?.[`${mode}_${profile}_mean_minutes`])?' min':' (requires a time for every type)'}.</p>`:''}
    ${['families','single'].includes(profile)?`<h3>Access to employment</h3><p class="small">${number(lowWageJobs,0)} low-wage jobs of ${number(totalJobs,0)} total within ${jobMinutes} minutes by ${esc(modeLabels[mode].toLowerCase())}.</p>`:''}
    <details><summary>Jobs${isHex?', destination choice and park acreage':''} · ${esc(modeLabels[mode])}</summary>
    <dl class="components">${fields}</dl>${isHex?'':`<p class="small">DAM jobs: ${esc(row?.job_method||'Unavailable')}.</p>`}</details></section>`;
}
