import {finite,escapeHTML as esc} from './logic.mjs?v=36c8cf2733c4';
export const domainLabels={destinations:'Everyday destinations',jobs:'Jobs',education:'Education'};
export const statusLabels={meets:'Meets all minimums',below:'Below minimum',incomplete:'Incomplete'};
export const statusColors={meets:'#26765d',below:'#b65c2e',incomplete:'#87949c'};
const fmt=(n,d=1)=>finite(n)?n.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
const percent=n=>finite(n)?fmt(n)+'%':'Unavailable';
export function columnRows(columns){return columns[Object.keys(columns)[0]].map((_,i)=>Object.fromEntries(Object.entries(columns).map(([k,v])=>[k,v[i]])));}
export function requiredDomains(profile){return profile==='families'?['destinations','jobs','education']:['destinations','jobs'];}
export function normalizedWeights(profile,weights,spec){
 const names=requiredDomains(profile),raw=weights||spec.presets[profile];
 if(!raw||names.some(k=>!finite(raw[k])||raw[k]<0))return null;
 const total=names.reduce((n,k)=>n+raw[k],0);
 return total>0?Object.fromEntries(names.map(k=>[k,raw[k]/total])):null;
}
export function jobRule(scenario,spec){return scenario==='transit'?spec.transit:scenario==='drive30'?spec.driving.sensitivity:spec.driving.default;}
export function assessBenefits(origin,profile,scenario,spec,baskets,weights=null,school=null){
 const row=origin||{},mode=scenario==='transit'?'transit':'drive',rule=jobRule(scenario,spec);
 const count=row[`${mode}_${profile}`],grocery=row[`${mode}_grocery`],jobs=row[`jobs_${scenario}`];
 const growth=school===null?row.education_growth:(school.status==='Available'?school.subgroup_growth:null);
 const sample=school===null?row.education_sample:school.minimum_growth_tests;
 const domains={
  destinations:{value:count,points:finite(count)?100*count/baskets.profiles[profile].length:null,
   missing:!finite(count)||!finite(grocery),passes:finite(count)&&finite(grocery)&&count>=spec.destination_minimums[profile]&&grocery===1,
   detail:`${fmt(count,0)} of ${baskets.profiles[profile].length} types; grocery ${!finite(grocery)?'unknown':grocery===1?'reached':'not reached'}`,
   minimum:`At least ${spec.destination_minimums[profile]} types, including grocery`},
  jobs:{value:jobs,points:finite(jobs)?100*Math.min(jobs/rule.full_credit_jobs,1):null,missing:!finite(jobs),
   passes:finite(jobs)&&jobs>=rule.full_credit_jobs*spec.jobs.minimum_fraction,
   detail:`${fmt(jobs,0)} jobs within ${rule.minutes} minutes`,
   minimum:`Minimum ${fmt(rule.full_credit_jobs*spec.jobs.minimum_fraction,0)}; full credit ${fmt(rule.full_credit_jobs,0)}`}
 };
 if(profile==='families')domains.education={value:growth,points:finite(growth)?100*Math.min(growth/spec.education.full_credit_growth,1):null,
  missing:!finite(growth),passes:finite(growth)&&growth>=spec.education.minimum_growth,
  detail:`Economically disadvantaged growth: ${fmt(growth,0)}`,
  minimum:`Minimum ${spec.education.minimum_growth}; full credit ${spec.education.full_credit_growth}`,
  smallSample:finite(growth)&&finite(sample)&&sample<spec.education.small_sample_tests_each_subject};
 const required=requiredDomains(profile),normalized=normalizedWeights(profile,weights,spec);
 const missing=required.filter(k=>domains[k].missing),failed=required.filter(k=>!domains[k].missing&&!domains[k].passes);
 const status=missing.length||!normalized?'incomplete':failed.length?'below':'meets';
 const score=missing.length||!normalized?null:required.reduce((n,k)=>n+domains[k].points*normalized[k],0);
 return {score,status,missing,failed,domains,weights:normalized,invalidWeights:!normalized};
}
export function aggregateTract(entries,assessments,coverage={}){
 let known=0,complete=0,weighted=0,meets=0,below=0,incomplete=0,unknownArea=0;
 for(const e of entries||[]){
  if(!finite(e.residents)){unknownArea+=e.area;continue;}
  const w=e.residents;if(w<=0)continue;known+=w;
  const a=assessments.get(e.id);
  if(!a||a.status==='incomplete'){incomplete+=w;continue;}
  complete+=w;weighted+=w*a.score;
  if(a.status==='meets')meets+=w;else below+=w;
 }
 return {score:complete>0?weighted/complete:null,known,complete,
  meets:known>0?100*meets/known:null,below:known>0?100*below/known:null,
  incomplete:known>0?100*incomplete/known:null,completeShare:known>0?100*complete/known:null,
  unknownArea,...coverage};
}
export function scoreColor(score){
 if(!finite(score))return '#a8b4be';
 const t=Math.max(0,Math.min(1,score/100)),a=[238,243,240],b=[23,105,86];
 return `rgb(${a.map((v,i)=>Math.round(v+(b[i]-v)*t)).join(',')})`;
}
export function combinedStyle(result,display='combined',tract=false){
 if(tract)return {fillColor:scoreColor(display==='minimums'?result?.meets:result?.score),color:'#607b80',weight:.7,dashArray:null,fillOpacity:.82};
 const status=result?.status||'incomplete';
 return {fillColor:display==='minimums'?statusColors[status]:scoreColor(result?.score),
  color:status==='below'?statusColors.below:status==='incomplete'?'#65747b':'#4d766a',
  weight:status==='below'?1.8:.6,dashArray:status==='below'?'3 2':null,fillOpacity:.88};
}
export function combinedProfile(a,profile,scenario,custom=false){
 if(!a)return '';
 return `<section class="combined-score" aria-label="Combined benefits assessment">
  <div class="metric-label">Combined benefits · ${custom?'Custom weights':'Preset weights'}</div>
  <div class="metric-value">${finite(a.score)?fmt(a.score)+' <small>/ 100</small>':'Unavailable'}</div>
  <div class="minimum-status ${a.status}">${statusLabels[a.status]}</div>
  <p class="small">${scenario==='transit'?'45-minute transit/walking':scenario==='drive'?'15-minute driving':'Driving job sensitivity'} assessment. Destination explorer controls do not change this score.</p>
  ${a.invalidWeights?'<p class="notice">Enter a positive weight for at least one applicable domain.</p>':''}
  ${a.failed.length?`<p class="minimum-reason">Below minimum: ${a.failed.map(k=>domainLabels[k]).join(', ')}.</p>`:''}
  ${a.missing.length?`<p class="minimum-reason">Missing required data: ${a.missing.map(k=>domainLabels[k]).join(', ')}. No combined score is assigned.</p>`:''}
  ${scenario==='drive30'?'<p class="notice">Job sensitivity: 30-minute driving access, full credit at 1 million jobs. Destinations retain the 15-minute budget. This does not override the default assessment.</p>':''}
  <div class="domain-scores">${Object.entries(a.domains).map(([k,d])=>`<div class="domain-score"><div><strong>${domainLabels[k]}</strong><span>${fmt(d.points)} points · ${a.weights?fmt(100*a.weights[k])+'%':'—'}</span></div>
   <p>${esc(d.detail)}</p><p class="small">${esc(d.minimum)} · <strong>${d.missing?'Unavailable':d.passes?'Meets minimum':'Below minimum'}</strong></p>
   ${d.smallSample?'<p class="notice">Small sample: fewer than 20 evaluated tests in at least one subject. Score retained.</p>':''}</div>`).join('')}</div>
  ${profile==='supportive'?'<p class="notice">Adult PSH—provisional. The destination basket does not include all supportive services. Family-serving PSH requires an education assessment.</p>':''}
  <p class="small">Required minimums stay fixed when weights change. Benefits and environmental burdens are assessed separately.</p></section>`;
}
export function tractCombinedProfile(a){
 return `<section class="combined-score"><div class="metric-label">Combined benefits · Tract population summary</div>
  <div class="metric-value">${fmt(a?.score)}${finite(a?.score)?' <small>/ 100</small>':''}</div>
  <p class="small">Resident-weighted mean among complete locations. Minimums are evaluated at each origin before aggregation.</p>
  <dl class="components"><div><dt>Residents meeting all minimums</dt><dd>${percent(a?.meets)}</dd></div>
  <div><dt>Residents below a minimum</dt><dd>${percent(a?.below)}</dd></div><div><dt>Residents with incomplete assessments</dt><dd>${percent(a?.incomplete)}</dd></div>
  <div><dt>Known resident weight</dt><dd>${fmt(a?.known,0)}</dd></div><div><dt>Tract area with known population weights</dt><dd>${percent(a?.resident_weight_area_share*100)}</dd></div>
  <div><dt>Tract area covered by origins</dt><dd>${percent(a?.area_coverage*100)}</dd></div></dl>
  <p class="small">Shares use known resident weights within covered hexagon overlaps. Unknown population is excluded; no population is inferred for uncovered areas. The tract mean does not determine whether individual locations meet minimums.</p></section>`;
}
