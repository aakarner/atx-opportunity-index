import {indexBurdens,assessBurden,burdenStyle,burdenColor,burdenLegend,burdenMeasures,burdenProfile,tractShareLabels,tractBurdenValue,tractBurdenLegend,tractBurdenProfile} from './combined-burdens.mjs';
import {indexFlood,floodProfile,floodColors} from './flood-eligibility.mjs';
import {medianScore,scoreGroup,scoreGroups} from './score-comparison.mjs';
import {columnRows,assessBenefits,aggregateTract,normalizedWeights,requiredDomains,combinedStyle,combinedProfile,tractCombinedProfile,statusLabels,statusColors} from './combined-benefits.mjs';
import {finite, locate, candidates, escapeHTML as esc} from './logic.mjs';
import {profileLabels, modeLabels, records, basketColor, palette, differenceColors, benefitProfile, schoolAssignment} from './benefits.mjs';
let benefitData, schools, benefitHex, benefitTracts, benefitSeries, refreshProfile;
let combinedData, combinedOrigins, tractWeights, tractCoverage, assessments=new Map(), tractAssessments=new Map();
const selection={profile:'families',mode:'walk_transit',minutes:45,display:'combined',weights:null,jobSensitivity:false};
const DATA_VERSION='local';
const $=id=>document.getElementById(id), fmt=(v,d=0)=>finite(v)?v.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
const mapViews=['benefits','burdens','combined'];
let map, metadata, tracts, city, hexes, tractLayer, hexLayer, selected, controller, searchSequence=0;
let dimension=mapViews.includes(location.hash.slice(1))?location.hash.slice(1):'benefits';
let floodIndex, excludedLayer, floodplainLayer;
const floodplainColor='#1673b8';
let burdenMeasure='combined', burdenIndex, burdenAssessments=new Map();
const burdenOptions={quarterMile:false,trafficSensitivity:false};
const medians={benefit:null,burden:null}, customCuts={benefit:null,burden:null};
const breakpoint=axis=>medians[axis]===null?null:(customCuts[axis]??medians[axis]);
const currentBurdenRows=()=>burdenOptions.quarterMile?burdenIndex.quarter_mile:burdenIndex.primary;
const currentTractBurdens=()=>burdenIndex.tracts[burdenOptions.quarterMile?'quarter_mile':'primary'];
const benefitFor=id=>(tractCoverage.has(id)?tractAssessments:assessments).get(id)?.score;
const burdenFor=id=>tractCoverage.has(id)?currentTractBurdens().get(id)?.combined_burden_score:burdenAssessments.get(id)?.score;
const groupFor=id=>scoreGroup(benefitFor(id),burdenFor(id),breakpoint('benefit'),breakpoint('burden'));
function refreshBurdenAssessments(){
 burdenAssessments=new Map([...currentBurdenRows()].map(([id,r])=>[id,assessBurden(r,burdenIndex.data.policy,burdenOptions)]));
}
const geocoder='https://maps.austintexas.gov/arcgis/rest/services/Geocode/COA_Locator/GeocodeServer/findAddressCandidates';
const emptyProfile=$('profile').innerHTML;
const combinedView=()=>['combined','minimums'].includes(selection.display);
const jobScenario=()=>selection.mode==='walk_transit'?'transit':selection.jobSensitivity?'drive30':'drive';
function refreshAssessments(){
 assessments=new Map();tractAssessments=new Map();
 if(combinedData.spec.presets[selection.profile]){
   for(const [id,row] of combinedOrigins)assessments.set(id,assessBenefits(row,selection.profile,jobScenario(),combinedData.spec,benefitData.spec,selection.weights));
 }
 if(!assessments.size)return;
 for(const [id,coverage] of tractCoverage)tractAssessments.set(id,aggregateTract(tractWeights.get(id),assessments,coverage));
}

function status(text,error=false){$('status').textContent=text;$('status').classList.toggle('error',error);}
function clearSelection(){refreshProfile=null;selected?.clearLayers();$('profile').innerHTML=emptyProfile;}
function cancelSearch(){searchSequence++;controller?.abort();controller=null;$('search').disabled=false;$('results').replaceChildren();}
function profileFrame(title,subtitle,body){$('profile').innerHTML=`<button class="close-profile" aria-label="Close location profile">×</button><span class="eyebrow">${esc(subtitle)}</span><h2>${esc(title)}</h2>${body}`;$('profile').querySelector('.close-profile').addEventListener('click',clearSelection);}
function comparisonProfile(id){
 const tract=tractCoverage.has(id),unit=tract?'tract':'hexagon';
 const group=scoreGroups[groupFor(id)];
 const rule=group===scoreGroups.incomplete?'Both scores are required to classify this '+unit+'.':
   `High starts at ${fmt(breakpoint('benefit'),2)} for benefits and ${fmt(breakpoint('burden'),2)} for burdens. Values shown are rounded.`;
 return `<div class="metric-label">Mapped ${unit} · benefits and burdens</div>
 <h3 class="comparison-result"><span class="swatch" style="background:${group.color}"></span>${group.label}</h3>
 <dl class="components"><div><dt>${tract?'Tract mean benefit score':'Origin benefit score'}</dt><dd>${fmt(benefitFor(id),2)}</dd></div>
 <div><dt>${tract?'Tract mean burden score':'Burden score'}</dt><dd>${fmt(burdenFor(id),2)}</dd></div></dl>
 <p class="small">${rule}</p>`;
}
function values(row,isHex,point=null,comparisonId=row?.id){
 const scores=(isHex?benefitHex:benefitTracts).get(row?.id);
 const accessSelection=dimension==='combined'?{...selection,minutes:benefitData.spec.defaults[selection.mode]}:selection;
 const access=benefitProfile(scores,accessSelection,benefitData.spec,isHex,schools,point,benefitSeries,row);
 const canScore=!!combinedData.spec.presets[selection.profile];
 const assessment=canScore&&isHex?assessBenefits(combinedOrigins.get(row?.id),selection.profile,jobScenario(),combinedData.spec,benefitData.spec,selection.weights,point?schoolAssignment(schools,point):null):null;
 const score=canScore?(isHex?combinedProfile(assessment,selection.profile,jobScenario(),!!selection.weights):tractCombinedProfile(tractAssessments.get(row?.id))):'';
 const burden=isHex?burdenProfile(currentBurdenRows().get(row?.id),burdenAssessments.get(row?.id),burdenOptions):tractBurdenProfile(currentTractBurdens().get(row.id),burdenOptions);
 const benefits=`${score}<details><summary>Destination and school detail</summary>${access}</details>`;
 const comparison=dimension==='combined'&&comparisonId?`<section class="metric-block" id="score-comparison" data-id="${esc(comparisonId)}">${comparisonProfile(comparisonId)}</section>`:'';
 return `${floodProfile(floodIndex,row?.id,isHex,point)}${comparison}${dimension==='burdens'?burden+'<details><summary>Benefits at this location</summary>'+benefits+'</details>':benefits+burden}
 <details><summary>Additional source context</summary><dl class="components"><div><dt>Cancer-weighted concentration</dt><dd>${fmt(row?.rsei_cancer,1)}</dd></div><div><dt>Noncancer-weighted concentration</dt><dd>${fmt(row?.rsei_noncancer,1)}</dd></div><div><dt>RSEI model coverage</dt><dd>${finite(row?.rsei_coverage)?fmt(row.rsei_coverage*100,1)+'%':'Unavailable'}</dd></div></dl><p>Cancer and noncancer measures are separate diagnostics; do not add them to the total. No health or safety determination is made.</p><p>Access method: ${esc(row?.access_method||'Unavailable')}. RSEI: area-weighted ${isHex?'full hexagon':'city-clipped tract'} mean from the native EPA grid.</p><p>2023 jobs · June 2026 routing/transit snapshot · July 13 morning departures · 2022 RSEI v2.3.12. Values are rounded for display; flags use full precision.</p></details><button class="print">Print location profile</button>`;
}
function enablePrint(){ $('profile').querySelector('.print')?.addEventListener('click',()=>window.print());}
function showHex(lon,lat,label,zoom=true,matchType=''){
 clearSelection();document.querySelector('.examples').open=false;document.querySelector('.explorer').scrollTop=0;const result=locate(lon,lat,city,tracts,hexes,h3);
 const boundary=h3.cellToBoundary(result.id);L.polygon(boundary,{pane:'selection',color:'#243f50',weight:3,fillOpacity:.08,dashArray:result.row?null:'6 5',interactive:false}).addTo(selected);
 L.marker([lat,lon],{icon:L.divIcon({className:'',html:'<div class="selected-pin"></div>',iconSize:[14,14],iconAnchor:[7,7]}),interactive:false,keyboard:false}).addTo(selected);
 let note=!result.inCity?'Outside the Austin study boundary. No project flags are assigned.':!result.row?'No access origin is available for this hexagon. Component values and flags are unavailable.':null;
 refreshProfile=()=>{
   const comparisonId=($('hex-mode').checked?result.row?.id:result.tract?.id)??null;
   profileFrame(label,'Hexagon profile',`<p class="id">H8 · ${esc(result.id)}</p><p class="small">${lat.toFixed(6)}, ${lon.toFixed(6)}${matchType?' · Locator match: '+esc(matchType):''}</p><p class="small">${result.tract?'Tract '+esc(result.tract.id)+' · approximate boundary lookup':result.inCity?'Tract context unavailable near boundary':'Outside study area'}</p>${note?`<p class="notice">${note}</p>`:''}${values(result.row,true,result.inCity?[lon,lat]:null,comparisonId)}<p class="small">Access describes the containing hexagon. Elementary assignment uses the selected point; map scores use each hexagon’s origin, so school-boundary locations may differ. Selected cell is outlined in dark blue.</p>`);
   enablePrint();
 };
 refreshProfile();status(note||'Hexagon selected. The profile shows its component values and flags.',!!note);
 if(zoom)map.setView([lat,lon],14,{animate:false});
 if(window.innerWidth<=1000)$('profile').scrollIntoView({behavior:'smooth',block:'start'});
}
function showTract(feature,latlng){
 clearSelection();cancelSearch();status('Tract selected. Search an address for its hexagon profile.');const p=feature.properties;L.geoJSON(feature,{style:{color:'#243f50',weight:3,fillOpacity:.04},interactive:false}).addTo(selected);
 profileFrame('Tract '+p.id,'Tract profile',`${values(p,false)}${p.access_method.includes('fallback')?'<p class="notice">Access uses a fallback aggregation method for this tract. See component detail.</p>':''}<p class="small">Values can vary within the city-clipped tract.</p><button id="inspect-point">Inspect hexagon at this point</button>`);
 refreshProfile=()=>showTract(feature,latlng);
 $('inspect-point').addEventListener('click',()=>showHex(latlng.lng,latlng.lat,'Selected map location',false));enablePrint();
 if(window.innerWidth<=1000)$('profile').scrollIntoView({behavior:'smooth',block:'start'});
}
function style(row){
 const floodRow=floodIndex?.rows.get(row.id);
 if(floodRow?.excluded)return {fillColor:floodColors.ineligible,fillOpacity:.9,color:'#142534',weight:1.5};
 if(dimension==='combined')return {fillColor:scoreGroups[groupFor(row.id)].color,fillOpacity:.82,color:'#fff',weight:.6,dashArray:null};
 if(dimension==='benefits' && combinedView()){
   const tract=tractAssessments.has(row.id);
   return combinedStyle(tract?tractAssessments.get(row.id):assessments.get(row.id),selection.display,tract);
 }

 if(dimension==='burdens'){
   if(tractCoverage.has(row.id))return {fillColor:burdenColor(tractBurdenValue(currentTractBurdens().get(row.id),burdenMeasure,burdenOptions)),color:'#607b80',weight:.7,dashArray:null,fillOpacity:.82};
   const r=currentBurdenRows().get(row.id),a=burdenAssessments.get(row.id)||assessBurden(null,burdenIndex.data.policy);
   return burdenStyle(r,a,burdenMeasure);
 }
 if(dimension==='benefits'){
   const score=benefitTracts.get(row.id)||benefitHex.get(row.id);
   return {fillColor:basketColor(score,selection,benefitData.spec),fillOpacity:.79,color:'#fff',weight:.7};
 }

}
function renderComparison(){
 const isHex=$('hex-mode').checked,units=isHex?'hexagons':'tracts',geography=isHex?hexes:tractCoverage;
 medians.benefit=medianScore(isHex?assessments:tractAssessments);
 medians.burden=isHex?medianScore(burdenAssessments):medianScore(currentTractBurdens(),r=>r.combined_burden_score);
 for(const axis of ['benefit','burden']){
   const slider=$(axis+'-cut'), value=breakpoint(axis);
   const description=finite(medians[axis])?`${fmt(value,2)} · ${customCuts[axis]===null?'median':'custom'}`:'Unavailable';
   slider.disabled=!finite(medians[axis]);
   slider.value=value??0;
   slider.setAttribute('aria-valuetext',description);
   $(axis+'-cut-value').value=description;
 }
 const counts=Object.fromEntries(Object.keys(scoreGroups).map(key=>[key,0]));
 for(const id of geography.keys())counts[groupFor(id)]++;
 function cell(key){
   return `<td><span class="swatch" style="background:${scoreGroups[key].color}"></span>${fmt(counts[key])}</td>`;
 }
 $('comparison-legend').innerHTML=`<table aria-label="${isHex?'Hexagons':'Tracts'} by benefit and burden score"><thead><tr><td></td><th scope="col">Low benefits</th><th scope="col">High benefits</th></tr></thead>
   <tbody><tr><th scope="row">High burdens</th>${cell('lowHigh')}${cell('highHigh')}</tr>
   <tr><th scope="row">Low burdens</th>${cell('lowLow')}${cell('highLow')}</tr></tbody></table>
   <div class="legend-row"><span class="swatch" style="background:${scoreGroups.incomplete.color}"></span>Missing score · ${fmt(counts.incomplete)}</div>`;
 $('legend-rule').textContent=selection.profile==='general'?'Choose a housing profile to compare scores. The general basket shows destination counts.':
   medians.benefit===null?'A benefit score requires a positive weight for at least one applicable domain.':
   `Each slider starts at the median across ${units} with an available score. Scores at or above the breakpoint are high.`;
 $('map-count').textContent=`${fmt(geography.size-counts.incomplete)} of ${fmt(geography.size)} ${units} have both scores.`+(isHex?' Counts include flood exclusions.':' Each tract mean uses the residents with data for that score.');
}
function applyBreakpoints(){
 renderComparison();
 const layerGroup=$('hex-mode').checked?hexLayer:tractLayer;
 layerGroup.eachLayer(layer=>{
   const id=layer.feature.properties.id;
   if(floodIndex.rows.get(id)?.excluded)return;
   const color=scoreGroups[groupFor(id)].color;
   if(layer.options.fillColor!==color)layer.setStyle({fillColor:color});
 });
 const profile=$('score-comparison');
 if(profile)profile.innerHTML=comparisonProfile(profile.dataset.id);
}
function renderMap(){
 const benefit=dimension==='benefits',burden=dimension==='burdens',compare=dimension==='combined';
 document.querySelector('.group-preview').hidden=burden;
 $('benefit-display-control').hidden=compare;
 const fixedBudget=compare||combinedView();
 $('time-budget-label').hidden=fixedBudget;
 $('budget-note').hidden=!fixedBudget;
 $('job-sensitivity-label').hidden=selection.mode!=='drive'||!fixedBudget;
 $('burden-controls').hidden=benefit;
 $('burden-measure-control').hidden=!burden;
 $('comparison-controls').hidden=!compare;
 $('comparison-legend').hidden=!compare;
 const isHex=$('hex-mode').checked;
 $('map-help').textContent=isHex?'Click a hexagon for its assessment. Turn off hexagons to inspect tract population summaries.':'Click a tract for its population summary. Address searches show the containing hexagon.';
 for(const view of mapViews)$(view).setAttribute('aria-pressed',String(dimension===view));
 if(compare){
   $('legend-title').textContent=isHex?'Hexagons by score':'Tracts by score';
   $('legend').replaceChildren();
   renderComparison();
 }else if(burden){
   for(const option of $('burden-measure').options){
     option.textContent=(!isHex && tractShareLabels[option.value]) || burdenMeasures[option.value];
   }
   const legend=isHex?burdenLegend(burdenMeasure,burdenOptions):tractBurdenLegend(burdenMeasure,burdenOptions);
   $('legend-title').textContent=legend.title;$('legend-rule').textContent=legend.rule;
   $('legend').innerHTML=legend.entries.map(([c,l])=>`<div class="legend-row"><span class="swatch" style="background:${c}"></span>${esc(l)}</div>`).join('')+`<p class="small">${esc(legend.note)}</p>`;
   const results=[...burdenAssessments.values()],scored=results.filter(a=>finite(a.score)).length,high=results.filter(a=>a.overallHigh===true).length;
   if(!isHex){
    const rows=[...currentTractBurdens().values()];
    const available=rows.filter(r=>finite(tractBurdenValue(r,burdenMeasure,burdenOptions))).length;
    $('map-count').textContent=`${available} of ${rows.length} tracts have an estimate for this measure.`;
   }else if(burdenMeasure==='frontage'){
    const rows=[...currentBurdenRows().values()],available=rows.filter(r=>r.frontage_status==='available').length;
    $('map-count').textContent=`${available} of ${rows.length} sidewalk gap scores · ${rows.filter(r=>r.major_frontage_high===true).length} high · ${rows.length-available} unavailable`;
   }else {
    $('map-count').textContent=`${scored} of ${results.length} complete combined scores · ${high} classified overall high burden (2+ high components) · ${results.length-scored} incomplete scores`;
   }
 }else if(benefit && combinedView()){
   const isHex=$('hex-mode').checked,minimums=selection.display==='minimums';
   $('legend-title').textContent=minimums?(isHex?'Minimum status':'Residents meeting all minimums'):'Combined benefits score';
   $('legend-rule').textContent=profileLabels[selection.profile]+' · '+modeLabels[selection.mode]+' · '+selection.minutes+' minutes'+(selection.mode==='drive'&&selection.jobSensitivity?' · jobs: 30-minute sensitivity':'');
   $('legend').innerHTML=minimums&&isHex?Object.entries(statusLabels).map(([key,label])=>`<div class="legend-row"><span class="swatch" style="background:${statusColors[key]}"></span>${label}</div>`).join(''):
     `<div class="score-gradient" aria-label="Continuous scale from 0 to 100"></div><div class="gradient-labels"><span>0${minimums?'%':''}</span><span>50${minimums?'%':''}</span><span>100${minimums?'%':''}</span></div>`+
     (isHex?'<p class="small">Orange dashed outline: below a minimum. Gray: incomplete. Color shows the score; it does not establish that minimums are met.</p>':'<p class="small">Tract means use complete locations only. Inspect a tract for complete, below-minimum and missing-data shares.</p>');
   const results=[...assessments.values()],counts={meets:0,below:0,incomplete:0};
   for(const a of results)counts[a.status]++;
   $('map-count').textContent=isHex?`${counts.meets} meet all minimums · ${counts.below} below · ${counts.incomplete} incomplete hexagons`:'Population summaries over covered areas; no minimum is applied to a tract average.';
 }else if(benefit){
   const diff=selection.display==='difference', n=benefitData.spec.profiles[selection.profile].length;
   $('legend-title').textContent=diff?'Profile compared with all destination types':profileLabels[selection.profile];
   $('legend-rule').textContent=modeLabels[selection.mode]+' · '+selection.minutes+' minutes';
   const entries=diff?differenceColors.map((color,i)=>[color,['Smaller share reached','Same share reached','Larger share reached'][i]]):
     palette.map((color,i)=>[color,i===4?'All '+n+' types':`${i*n/4} to <${(i+1)*n/4} types`]);
   entries.push(['#a8b4be','Unavailable']);
   $('legend').innerHTML=entries.map(([c,l])=>`<div class="legend-row"><span class="swatch" style="background:${c}"></span>${esc(l)}</div>`).join('');
   $('map-count').textContent=$('hex-mode').checked?'H8 routing origins':'Resident-weighted tract averages · covered area';
 }
 $('legend').insertAdjacentHTML('beforeend',`<div class="legend-row"><span class="swatch" style="background:${floodColors.ineligible}"></span>Flood exclusion · overrides map color</div>`);
 if($('floodplain-overlay').checked)$('legend').insertAdjacentHTML('beforeend',`<div class="legend-row"><span class="swatch" style="background:${floodplainColor}"></span>Actual floodplain · within study hexes</div>`);
 tractLayer.setStyle(f=>style(f.properties));hexLayer.setStyle(f=>({...style(f.properties),fillOpacity:floodIndex.rows.get(f.properties.id)?.excluded ? .9 : .88}));
 if($('hex-mode').checked){if(!map.hasLayer(hexLayer))hexLayer.addTo(map);tractLayer.setStyle({fillOpacity:0});}
 else if(map.hasLayer(hexLayer))map.removeLayer(hexLayer);
 if($('floodplain-overlay').checked){if(!map.hasLayer(floodplainLayer))floodplainLayer.addTo(map);}else if(map.hasLayer(floodplainLayer))map.removeLayer(floodplainLayer);
 selected.bringToFront();
}
async function runSearch(e){
 e.preventDefault();const query=$('address').value.trim();if(!query)return;
 cancelSearch();clearSelection();const sequence=searchSequence;controller=new AbortController();const ownController=controller;
 $('search').disabled=true;status('Searching the City of Austin address locator…');let timedOut=false;
 const timeout=setTimeout(()=>{timedOut=true;ownController.abort();},15000);
 try{
  const params=new URLSearchParams({f:'json',SingleLine:query,outSR:'4326',outFields:'Match_addr,Addr_type',maxLocations:'5'});
  const response=await fetch(`${geocoder}?${params}`,{signal:ownController.signal,credentials:'omit'});if(!response.ok)throw Error('Locator unavailable');
  const data=await response.json();if(data.error)throw Error('Locator error');if(sequence!==searchSequence)return;
  const matches=candidates(data);status(matches.length?'Choose a matching address below.':'No matching address found. Try a full street address with Austin and ZIP code.',!matches.length);
  for(const c of matches){const li=document.createElement('li'),button=document.createElement('button');button.textContent=c.address;button.addEventListener('click',()=>{$('results').replaceChildren();showHex(c.location.x,c.location.y,c.address,true,c.attributes?.Addr_type||'');});li.append(button);$('results').append(li);}
 }catch(error){if(sequence===searchSequence && (error.name!=='AbortError'||timedOut))status('Address search is unavailable. Try again, select an example, or inspect a hexagon on the map.',true);}
 finally{clearTimeout(timeout);if(sequence===searchSequence){$('search').disabled=false;controller=null;}}
}
async function init(){
 for(const b of document.querySelectorAll('.explorer button,.explorer input'))b.disabled=true;
 try{
  const data=await Promise.all(['metadata.json','hexagons.json','tracts.geojson','city.geojson','benefits.json','school-zones.geojson','combined-benefits.json','flood-eligibility.json','flood-geometry.geojson','combined-burdens.json'].map(async f=>{const r=await fetch('assets/'+f+'?v='+DATA_VERSION);if(!r.ok)throw Error('Could not load '+f);return r.json();}));
  [metadata,,tracts,city]=data;hexes=new Map(data[1].map(r=>[r.id,r]));
  benefitData=data[4];schools=data[5];combinedData=data[6];
  floodIndex=indexFlood({...data[7],flood_by_hex:data[8]},[...hexes.keys()]);
  burdenIndex=indexBurdens(data[9],[...hexes.keys()],tracts.features.map(f=>f.properties.id));refreshBurdenAssessments();
  combinedOrigins=new Map(columnRows(combinedData.origins).map(r=>[r.id,r]));
  if(combinedData.schema_version!==1||combinedOrigins.size!==hexes.size||[...hexes.keys()].some(id=>!combinedOrigins.has(id)))throw Error('Combined benefit geography mismatch');
  tractCoverage=new Map(columnRows(combinedData.tracts).map(r=>[r.id,r]));tractWeights=new Map();
  for(const r of columnRows(combinedData.tract_weights)){if(!tractWeights.has(r.tract_id))tractWeights.set(r.tract_id,[]);tractWeights.get(r.tract_id).push(r);}
  refreshAssessments();
  benefitHex=new Map(records(benefitData.hex));benefitTracts=new Map(records(benefitData.tract));
  benefitSeries=benefitData.series.field.map((key,i)=>Object.fromEntries(Object.entries(benefitData.series).map(([name,col])=>[name,col[i]])));
  if([...hexes.keys()].some(id=>!benefitHex.has(id))||tracts.features.some(f=>!benefitTracts.has(f.properties.id)))throw Error('Benefit geography mismatch');
  if(metadata.schema_version!==2||typeof L==='undefined'||typeof h3==='undefined')throw Error('Map library or data version unavailable');
  map=L.map('map',{zoomControl:true,minZoom:8,maxZoom:19,zoomSnap:.25});
  for(const [name,z] of [['floodplain',450],['exclusions',460],['selection',470]]){const pane=map.createPane(name);pane.style.zIndex=z;pane.style.pointerEvents='none';}
  let basemap={url:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'};
  try{const r=await fetch('assets/basemap.json');if(r.ok){const configured=await r.json();if(configured.provider==='CARTO Positron' && configured.url.startsWith('https://basemaps.cartocdn.com/'))basemap=configured;}}catch{/* Source-only previews can use OpenStreetMap. */}
  document.body.classList.toggle('osm-basemap',basemap.provider!=='CARTO Positron');
  L.tileLayer(basemap.url,{maxZoom:19,attribution:basemap.attribution}).addTo(map);
  tractLayer=L.geoJSON(tracts,{style:f=>style(f.properties),onEachFeature:(f,l)=>{l.bindTooltip(()=>`Tract ${esc(f.properties.id)}`,{sticky:true});l.on('click',e=>{$('hex-mode').checked?showHex(e.latlng.lng,e.latlng.lat,'Selected map location',false):showTract(f,e.latlng);});}}).addTo(map);
  L.geoJSON(city,{style:{color:'#71868f',weight:1.4,fill:false,dashArray:'4 4'},interactive:false}).addTo(map);
  const hexFeatures=[...hexes.values()].map(row=>({type:'Feature',properties:row,geometry:{type:'Polygon',coordinates:[h3.cellToBoundary(row.id,true)]}}));
  hexLayer=L.geoJSON(hexFeatures,{onEachFeature:(f,l)=>l.on('click',e=>showHex(e.latlng.lng,e.latlng.lat,'Selected map location',false))});
  floodplainLayer=L.geoJSON(data[8],{pane:'floodplain',renderer:L.canvas({pane:'floodplain',padding:.5}),style:{fillColor:floodplainColor,fillOpacity:.65,stroke:false},interactive:false});
  excludedLayer=L.geoJSON(hexFeatures.filter(f=>floodIndex.rows.get(f.properties.id).excluded),{pane:'exclusions',style:{fillColor:floodColors.ineligible,fillOpacity:.9,color:'#142534',weight:1.5},interactive:false}).addTo(map);
  selected=L.featureGroup().addTo(map);
  const reset=()=>map.fitBounds(tractLayer.getBounds(),{paddingTopLeft:window.innerWidth>1000?[360,20]:[15,15],paddingBottomRight:window.innerWidth>1000?[340,20]:[15,15]});
  reset();$('reset-view').addEventListener('click',reset);
  map.on('click',e=>{if($('hex-mode').checked)showHex(e.latlng.lng,e.latlng.lat,'Selected map location',false);});
  for(const view of mapViews)$(view).addEventListener('click',()=>{dimension=view;renderMap();refreshProfile?.();});
  for(const axis of ['benefit','burden'])$(axis+'-cut').addEventListener('input',e=>{
    customCuts[axis]=e.target.valueAsNumber;
    applyBreakpoints();
  });
  $('reset-cuts').addEventListener('click',()=>{customCuts.benefit=null;customCuts.burden=null;applyBreakpoints();});
  $('floodplain-overlay').addEventListener('change',renderMap);
  $('burden-measure').addEventListener('change',e=>{burdenMeasure=e.target.value;renderMap();});
  for(const [id,key] of [['street-sensitivity','quarterMile'],['traffic-sensitivity','trafficSensitivity']])$(id).addEventListener('change',e=>{burdenOptions[key]=e.target.checked;refreshBurdenAssessments();renderMap();refreshProfile?.();});
  $('hex-mode').addEventListener('change',()=>{clearSelection();renderMap();status($('map-help').textContent);});
  $('search-form').addEventListener('submit',runSearch);$('address').addEventListener('input',()=>{cancelSearch();clearSelection();status('Enter an Austin address, then select a match.');});
  $('clear').addEventListener('click',()=>{cancelSearch();clearSelection();$('address').value='';status('Selection cleared. Search an address or explore the map.');});
  const examples=[[-97.883274,30.179630,'Southwest Austin example'],[-97.780280,30.167870,'South Austin example'],[-97.666740,30.310930,'East Austin example'],[-97.662190,30.249080,'Dog’s Head example']];
  document.querySelectorAll('[data-example]').forEach(b=>b.addEventListener('click',()=>{cancelSearch();$('address').value='';showHex(...examples[Number(b.dataset.example)]);}));
  $('traffic-source-note').textContent=`TxDOT extraction ${[].concat(metadata.traffic.extract_dates||[]).join(', ')}. The source does not specify the observation year of each traffic count.`;
  $('boundary-note').textContent=`City of Austin GIS · ${metadata.boundary.snapshot} · full- and limited-purpose limits`;
  $('hex-coverage').textContent=fmt(metadata.boundary.hex_coverage_share*100,1)+'%';
  setupBenefitControls();for(const b of document.querySelectorAll('.explorer button,.explorer input'))b.disabled=false;
  renderMap();status('Search an address, try an example, or click a hexagon.');
 }catch(error){status('The map data could not be loaded. Reload the page to try again.',true);profileFrame('Map unavailable','Loading error',`<p>${esc(error.message)}</p><p>Serve this site over HTTP or use its GitHub Pages URL.</p>`);console.error(error);}
}
function setupBenefitControls(){
 const spec=benefitData.spec;
 for(const [key,label] of Object.entries(profileLabels))$('basket').add(new Option(key==='supportive'?'Adult PSH—provisional':label,key));
 $('basket').value=selection.profile;
 function setBudget(){
   $('time-budget').replaceChildren(...spec.budgets[selection.mode].map(v=>new Option(v+' min',v)));
   selection.minutes=spec.defaults[selection.mode];$('time-budget').value=selection.minutes;
 }
 function weightsUI(){
   const preset=combinedData.spec.presets[selection.profile],raw=selection.weights||preset;
   $('weights-section').hidden=!preset;
   if(!preset)return;
   const normalized=normalizedWeights(selection.profile,raw,combinedData.spec);
   for(const k of ['destinations','jobs','education']){
     const input=$('weight-'+k);input.value=raw[k]||0;input.disabled=!requiredDomains(selection.profile).includes(k);
     $('effective-'+k).textContent=normalized&&k in normalized?fmt(100*normalized[k],1)+'%':'0%';
   }
   $('weights-label').textContent=selection.weights?'Custom weights':'Preset weights';
   $('weight-error').hidden=!!normalized;
 }
 function note(){
   const names=spec.profiles[selection.profile].map(key=>spec.destinations[key]);
   $('group-note').textContent=names.join(' · ')+(selection.profile==='supportive'?'. Partial service inventory.':'')+
     (selection.mode==='walk_transit'?' · Morning transit coverage.':'');
   $('budget-note').textContent=`Destinations and jobs: ${spec.defaults[selection.mode]} minutes ${modeLabels[selection.mode].toLowerCase()}.`;
 }
 function update(){
   note();weightsUI();refreshAssessments();renderMap();if(refreshProfile)refreshProfile();
 }
 $('basket').addEventListener('change',e=>{
   selection.profile=e.target.value;selection.weights=null;
   if(selection.profile==='general'&&combinedView()){selection.display='count';$('benefit-display').value='count';}
   update();
 });
 $('travel-mode').addEventListener('change',e=>{selection.mode=e.target.value;setBudget();update();});
 $('time-budget').addEventListener('change',e=>{selection.minutes=Number(e.target.value);update();});
 $('benefit-display').addEventListener('change',e=>{
   selection.display=e.target.value;
   if(combinedView()){
     if(selection.profile==='general'){selection.profile='families';$('basket').value='families';selection.weights=null;}
     setBudget();
   }
   update();
 });
 $('job-sensitivity').addEventListener('change',e=>{selection.jobSensitivity=e.target.checked;update();});
 for(const k of ['destinations','jobs','education'])$('weight-'+k).addEventListener('change',()=>{
   selection.weights=Object.fromEntries(['destinations','jobs','education'].map(n=>{
     const value=Number($('weight-'+n).value);return [n,Number.isFinite(value)?Math.max(0,Math.min(100,value)):0];
   }));update();
 });
 $('reset-weights').addEventListener('click',()=>{selection.weights=null;update();});
 setBudget();weightsUI();note();
}
$('about-open').addEventListener('click',()=>$('about').showModal());$('about-close').addEventListener('click',()=>$('about').close());
init();
