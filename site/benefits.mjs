import {contains, escapeHTML as esc, finite} from './logic.mjs';

export const profileLabels = {
  general:'All eight destinations', families:'Families with children', older:'Older adults',
  single:'Single adults', supportive:'Permanent supportive housing'
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

function schoolDetail(zones,point) {
  if(!point) return '<p>Select an address or map point for its assigned schools.</p>';
  const hits=zones.features.filter(f=>contains(f.geometry,...point)).map(f=>f.properties);
  return ['elementary','middle','high'].map(level=>{
    const matches=hits.filter(p=>p.school_level===level);
    const unique=new Set(matches.map(p=>JSON.stringify([p.campus_id,p.score_status,p.usable_growth])));
    if(!matches.length) return `<p>${level} · Outside available AISD assignment coverage</p>`;
    if(unique.size>1) return `<p>${level} · Ambiguous assignment</p>`;
    const p=matches[0];
    return `<p>${esc(p.campus_name)} · ${esc(level)} · ${finite(p.usable_growth)?'growth '+p.usable_growth:esc(p.score_status)}</p>`;
  }).join('');
}
const number=(v,d=1)=>finite(v)?v.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
export function benefitProfile(row,selection,spec,isHex,zones,point,series) {
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
  return `<section class="metric-block"><div class="metric-label">${esc(profileLabels[profile])} · ${esc(modeLabels[mode])}</div>
    <div class="metric-value">${number(count)} / ${names.length}</div><div class="metric-unit">${isHex?'Destination types reached':'Resident-weighted mean types reached'} within ${minutes} minutes</div>
    <dl class="components">${components}</dl>
    ${isHex?'':`<p class="small">H8 cells cover ${number(row?.area_coverage*100)}% of the clipped tract area. Resident weights cover ${number(row?.resident_weight_area_share*100)}% of tract area. Estimated resident weight: ${number(row?.resident_weight,0)}. Zero weight gives an unavailable mean.</p>`}
    ${profile==='supportive'?'<p class="notice">Partial basket. Behavioral health, supportive services and on-site supports require separate review.</p>':''}
    ${mode==='walk_transit'?'<p class="small">Provisional July morning routing. An unreached trip can reflect service coverage or model limits.</p>':''}
    ${profile==='families'?`<h3>Assigned schools · AISD</h3><div class="small">2025–26 campus academic growth${schoolDetail(zones,point)}</div>`:''}
    ${isHex?`<p class="small">Mean trip to the nearest facility across this basket: ${number(row?.[`${mode}_${profile}_mean_minutes`])}${finite(row?.[`${mode}_${profile}_mean_minutes`])?' min':' (requires a time for every type)'}.</p>`:''}
    ${['families','single'].includes(profile)?`<h3>Access to employment</h3><p class="small">${number(row?.[`${mode}__jobs_cumulative__low_wage_jobs__30`],0)} low-wage jobs of ${number(row?.[`${mode}__jobs_cumulative__total_jobs__30`],0)} total within 30 minutes by ${esc(modeLabels[mode].toLowerCase())}.</p>`:''}
    <details><summary>Jobs${isHex?', destination choice and park acreage':''} · ${esc(modeLabels[mode])}</summary>
    <dl class="components">${fields}</dl>${isHex?'':`<p class="small">DAM jobs: ${esc(row?.job_method||'Unavailable')}.</p>`}</details></section>`;
}
