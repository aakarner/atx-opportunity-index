import {finite, flags, combination, locate, candidates, trafficScales, trafficColor, escapeHTML as esc} from './logic.mjs';
import {profileLabels, modeLabels, records, basketColor, palette, differenceColors, benefitProfile} from './benefits.mjs';
let benefitData, schools, benefitHex, benefitTracts, benefitSeries, refreshProfile;
const selection={profile:'general',mode:'walk_transit',minutes:30,display:'count'};
const DATA_VERSION='local';
const $=id=>document.getElementById(id), fmt=(v,d=0)=>finite(v)?v.toLocaleString('en-US',{maximumFractionDigits:d}):'Unavailable';
const combinedClasses={
 both:{color:'#8066a9',label:'Both flags'},
 access_only:{color:'#3e8d70',label:'Strong access only'},
 burden_only:{color:'#c7714a',label:'Elevated burden only'},
 neither:{color:'#d9e0e3',label:'Neither flag'},
 unknown:{color:'#a8b4be',label:'Unknown'}
};
const colors={benefit:'#3e8d70',burden:'#c7714a',neutral:'#d9e0e3',unknown:'#a8b4be'};
let map, metadata, tracts, city, hexes, tractLayer, hexLayer, selected, dimension='benefits', controller, searchSequence=0;
let burdenMeasure='rsei';
const geocoder='https://maps.austintexas.gov/arcgis/rest/services/Geocode/COA_Locator/GeocodeServer/findAddressCandidates';
const emptyProfile=$('profile').innerHTML;
function status(text,error=false){$('status').textContent=text;$('status').classList.toggle('error',error);}
function clearSelection(){refreshProfile=null;selected?.clearLayers();$('profile').innerHTML=emptyProfile;}
function cancelSearch(){searchSequence++;controller?.abort();controller=null;$('search').disabled=false;$('results').replaceChildren();}
function profileFrame(title,subtitle,body){$('profile').innerHTML=`<button class="close-profile" aria-label="Close location profile">×</button><span class="eyebrow">${esc(subtitle)}</span><h2>${esc(title)}</h2>${body}`;$('profile').querySelector('.close-profile').addEventListener('click',clearSelection);}
function flagLabel(value,positive,negative){return value===null?'Unknown':value?positive:negative;}
function trafficProfile(row,isHex){
 const distanceLabel=isHex?'H8 center distance':'Mean H8 center distance';
 const overlapLabel=isHex?'H8 area within 300 m':'Mean H8 buffer coverage';
 const coverage=finite(row?.traffic_coverage_share)?fmt(row.traffic_coverage_share*100,1)+'%':'Unavailable';
 return `<section class="metric-block"><div class="metric-label">Burden · Traffic proximity</div><dl class="components"><div><dt>${distanceLabel}</dt><dd>${finite(row?.traffic_distance_ft)?fmt(row.traffic_distance_ft)+' ft':'Unavailable'}</dd></div><div><dt>${overlapLabel}</dt><dd>${finite(row?.traffic_buffer_share)?fmt(row.traffic_buffer_share*100,1)+'%':'Unavailable'}</dd></div>${isHex?'':`<div><dt>Tract area represented</dt><dd>${coverage}</dd></div>`}</dl><p class="small">Roads carrying more than ${fmt(metadata.traffic.threshold_aadt)} vehicles/day. ${isHex?'Distance is measured from the cell center; buffer coverage describes the full hexagon.':'Area-weighted H8 means over covered tract area. Uncovered area is excluded; buffer coverage is an approximate spatial summary.'}</p><p class="small">TxDOT extraction ${esc([].concat(metadata.traffic.extract_dates||[]).join(', '))}. Traffic proximity indicates potential exposure.</p></section>`;
}
function values(row,isHex,point=null){
 const scores=(isHex?benefitHex:benefitTracts).get(row?.id);
 const access=benefitProfile(scores,selection,benefitData.spec,isHex,schools,point,benefitSeries);
 const f=flags(row,metadata.thresholds),t=metadata.thresholds;
 return `${access}<section class="metric-block"><div class="metric-label">Benchmark · Transit job access</div><div class="metric-value">${fmt(row?.jobs_total)}</div><div class="metric-unit">jobs reachable in 45 minutes · walk + transit</div><span class="badge ${f.strong_access?'benefit':''}">${flagLabel(f.strong_access,'Strong access','Not flagged as strong')}</span><p class="small">Strong access: &gt; ${fmt(t.strong_access_above)} jobs</p><dl class="components"><div><dt>Low wage · ≤ $1,250/month</dt><dd>${fmt(row?.jobs_low)}</dd></div><div><dt>Middle · $1,251–$3,333/month</dt><dd>${fmt(row?.jobs_middle)}</dd></div><div><dt>High wage · &gt; $3,333/month</dt><dd>${fmt(row?.jobs_high)}</dd></div></dl><p class="small">Wage groups are components of total access.</p></section>
 <section class="metric-block"><div class="metric-label">Burden · Industrial air releases</div><div class="metric-value">${fmt(row?.rsei,1)}</div><div class="metric-unit">RSEI toxicity-weighted concentration · ToxConc</div><span class="badge ${f.elevated_burden?'burden':''}">${flagLabel(f.elevated_burden,'Elevated burden','Not flagged')}</span><p class="small">Elevated burden: ≥ ${fmt(t.elevated_rsei_at_least)}</p></section>
 ${trafficProfile(row,isHex)}
 <details><summary>Component detail &amp; interpretation</summary><dl class="components"><div><dt>Cancer-weighted concentration</dt><dd>${fmt(row?.rsei_cancer,1)}</dd></div><div><dt>Noncancer-weighted concentration</dt><dd>${fmt(row?.rsei_noncancer,1)}</dd></div><div><dt>RSEI model coverage</dt><dd>${finite(row?.rsei_coverage)?fmt(row.rsei_coverage*100,1)+'%':'Unavailable'}</dd></div></dl><p>Cancer and noncancer measures are separate diagnostics; do not add them to the total. No health or safety determination is made.</p><p>Access method: ${esc(row?.access_method||'Unavailable')}. RSEI: area-weighted ${isHex?'full hexagon':'city-clipped tract'} mean from the native EPA grid.</p><p>2023 jobs · June 2026 routing/transit snapshot · July 13 morning departures · 2022 RSEI v2.3.12. Values are rounded for display; flags use full precision.</p></details><button class="print">Print location profile</button>`;
}
function enablePrint(){ $('profile').querySelector('.print')?.addEventListener('click',()=>window.print());}
function showHex(lon,lat,label,zoom=true,matchType=''){
 clearSelection();document.querySelector('.examples').open=false;document.querySelector('.explorer').scrollTop=0;const result=locate(lon,lat,city,tracts,hexes,h3);
 const boundary=h3.cellToBoundary(result.id);L.polygon(boundary,{color:'#243f50',weight:3,fillOpacity:.08,dashArray:result.row?null:'6 5',interactive:false}).addTo(selected);
 L.marker([lat,lon],{icon:L.divIcon({className:'',html:'<div class="selected-pin"></div>',iconSize:[14,14],iconAnchor:[7,7]}),interactive:false,keyboard:false}).addTo(selected);
 let note=!result.inCity?'Outside the Austin study boundary. No project flags are assigned.':!result.row?'No access origin is available for this hexagon. Component values and flags are unavailable.':null;
 profileFrame(label,'Hexagon profile',`<p class="id">H8 · ${esc(result.id)}</p><p class="small">${lat.toFixed(6)}, ${lon.toFixed(6)}${matchType?' · Locator match: '+esc(matchType):''}</p><p class="small">${result.tract?'Tract '+esc(result.tract.id)+' · approximate boundary lookup':result.inCity?'Tract context unavailable near boundary':'Outside study area'}</p>${note?`<p class="notice">${note}</p>`:''}${values(result.row,true,result.inCity?[lon,lat]:null)}<p class="small">These values describe the containing hexagon, not the parcel. Selected cell is outlined in dark blue.</p>`);
 refreshProfile=()=>showHex(lon,lat,label,false,matchType);
 enablePrint();status(note||'Hexagon selected. The profile shows its component values and flags.',!!note);
 if(zoom)map.setView([lat,lon],14,{animate:false});
 if(window.innerWidth<=700)$('profile').scrollIntoView({behavior:'smooth',block:'start'});
}
function showTract(feature,latlng){
 clearSelection();cancelSearch();status('Tract selected. Search an address for its hexagon profile.');const p=feature.properties;L.geoJSON(feature,{style:{color:'#243f50',weight:3,fillOpacity:.04},interactive:false}).addTo(selected);
 profileFrame('Tract '+p.id,'Tract profile',`${values(p,false)}${p.access_method.includes('fallback')?'<p class="notice">Access uses a fallback aggregation method for this tract. See component detail.</p>':''}<p class="small">City-clipped tract averages can hide neighborhood variation.</p><button id="inspect-point">Inspect hexagon at this point</button>`);
 refreshProfile=()=>showTract(feature,latlng);
 $('inspect-point').addEventListener('click',()=>showHex(latlng.lng,latlng.lat,'Selected map location',false));enablePrint();
 if(window.innerWidth<=700)$('profile').scrollIntoView({behavior:'smooth',block:'start'});
}
function style(row){
 if(dimension==='burdens' && burdenMeasure!=='rsei'){
   return {fillColor:trafficColor(row,burdenMeasure),fillOpacity:.79,color:'#fff',weight:.7};
 }
 if(dimension==='benefits' && selection.display!=='jobs'){
   const score=benefitTracts.get(row.id)||benefitHex.get(row.id);
   return {fillColor:basketColor(score,selection,benefitData.spec),fillOpacity:.79,color:'#fff',weight:.7};
 }
 const value=dimension==='benefits'?row.strong_access:row.elevated_burden;
 const fillColor=dimension==='combined'?combinedClasses[combination(row)].color:
   value===null?colors.unknown:value?(dimension==='benefits'?colors.benefit:colors.burden):colors.neutral;
 return {fillColor,fillOpacity:.73,color:'#fff',weight:.7};
}
function renderMap(){
 const benefit=dimension==='benefits',combined=dimension==='combined',t=metadata.thresholds;
 const traffic=dimension==='burdens' && burdenMeasure!=='rsei';
 $('burden-controls').hidden=dimension!=='burdens';
 for(const view of ['benefits','burdens','combined'])$(view).setAttribute('aria-pressed',String(dimension===view));
 $('legend-title').textContent=combined?'Benefits + burdens':benefit?'Job access':'Industrial air releases';
 $('legend-rule').textContent=combined?`Strong access: > ${fmt(t.strong_access_above)} jobs · Elevated burden: RSEI ≥ ${fmt(t.elevated_rsei_at_least)}`:
   benefit?`Strong access: > ${fmt(t.strong_access_above)} jobs within 45 minutes`:`Elevated burden: RSEI ≥ ${fmt(t.elevated_rsei_at_least)}`;
 if(traffic){
   const scale=trafficScales[burdenMeasure],isHex=$('hex-mode').checked;
   $('legend-title').textContent=scale.title;
   $('legend-rule').textContent=burdenMeasure==='traffic_distance_ft'?
     `${isHex?'H8 center distance':'Area-weighted mean H8 distance'} · roads >50,000 vehicles/day`:
     `${isHex?'Full H8 area':'Mean H8 coverage'} within 300 m · roads >50,000 vehicles/day`;
   const entries=scale.colors.map((color,i)=>[color,scale.labels[i]]);
   entries.push([colors.unknown,'Unavailable']);
   $('legend').innerHTML=entries.map(([color,label])=>`<div class="legend-row"><span class="swatch" style="background:${color}"></span>${esc(label)}</div>`).join('');
   const rows=isHex?[...hexes.values()]:tracts.features.map(f=>f.properties);
   const available=rows.filter(row=>finite(row[burdenMeasure])).length;
   $('map-count').textContent=`${available} of ${rows.length} ${isHex?'hexagons':'tracts'} with values${isHex?'':' · means over covered H8 area'}`;
 }else if(benefit && selection.display!=='jobs'){
   const diff=selection.display==='difference', n=benefitData.spec.profiles[selection.profile].length;
   $('legend-title').textContent=diff?'Profile compared with all eight types':profileLabels[selection.profile];
   $('legend-rule').textContent=modeLabels[selection.mode]+' · '+selection.minutes+' minutes';
   const entries=diff?differenceColors.map((color,i)=>[color,['Smaller share reached','Same share reached','Larger share reached'][i]]):
     palette.map((color,i)=>[color,i===4?'All '+n+' types':`${i*n/4} to <${(i+1)*n/4} types`]);
   entries.push([colors.unknown,'Unavailable']);
   $('legend').innerHTML=entries.map(([c,l])=>`<div class="legend-row"><span class="swatch" style="background:${c}"></span>${esc(l)}</div>`).join('');
   $('map-count').textContent=$('hex-mode').checked?'H8 routing origins':'Resident-weighted tract averages · covered area';
 }else if(combined){
   const counts=Object.fromEntries(Object.keys(combinedClasses).map(key=>[key,0]));
   for(const feature of tracts.features)counts[combination(feature.properties)]++;
   $('legend').innerHTML=Object.entries(combinedClasses).filter(([key])=>key!=='unknown'||counts.unknown>0).map(([key,{color,label}])=>
     `<div class="legend-row"><span class="swatch" style="background:${color}"></span><span>${label}</span><span class="legend-count">${counts[key]} tracts</span></div>`).join('');
   $('map-count').textContent=`${counts.both} of ${metadata.counts.tracts} tracts have both flags · city-clipped averages`;
 }else{
   $('legend').innerHTML=[[benefit?colors.benefit:colors.burden,benefit?'Strong access':'Elevated burden'],[colors.neutral,benefit?'Not flagged as strong':'Not flagged'],[colors.unknown,'Unknown']].map(([c,l])=>`<div class="legend-row"><span class="swatch" style="background:${c}"></span>${l}</div>`).join('');
   $('map-count').textContent=`${benefit?metadata.counts.strong_tract:metadata.counts.elevated_tract} of ${metadata.counts.tracts} tracts flagged · city-clipped averages`;
 }
 $('legend').classList.toggle('combined-legend',combined);
 const filledHex=traffic || (benefit && selection.display!=='jobs');
 tractLayer.setStyle(f=>style(f.properties));hexLayer.setStyle(f=>({...style(f.properties),fillOpacity:filledHex ? .88 : .12,color:'#526f7d',weight:.7}));
 if($('hex-mode').checked){if(!map.hasLayer(hexLayer))hexLayer.addTo(map);tractLayer.setStyle({fillOpacity:filledHex?0:.35});}
 else if(map.hasLayer(hexLayer))map.removeLayer(hexLayer);
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
  const data=await Promise.all(['metadata.json','hexagons.json','tracts.geojson','city.geojson','benefits.json','school-zones.geojson'].map(async f=>{const r=await fetch('assets/'+f+'?v='+DATA_VERSION);if(!r.ok)throw Error('Could not load '+f);return r.json();}));
  [metadata,,tracts,city]=data;hexes=new Map(data[1].map(r=>[r.id,r]));
  benefitData=data[4];schools=data[5];
  benefitHex=new Map(records(benefitData.hex));benefitTracts=new Map(records(benefitData.tract));
  benefitSeries=benefitData.series.field.map((key,i)=>Object.fromEntries(Object.entries(benefitData.series).map(([name,col])=>[name,col[i]])));
  if([...hexes.keys()].some(id=>!benefitHex.has(id))||tracts.features.some(f=>!benefitTracts.has(f.properties.id)))throw Error('Benefit geography mismatch');
  if(metadata.schema_version!==1||typeof L==='undefined'||typeof h3==='undefined')throw Error('Map library or data version unavailable');
  // Fail visibly if exported classifications drift from the configured rules.
  for(const row of [...hexes.values(),...tracts.features.map(f=>f.properties)]){const f=flags(row,metadata.thresholds);if(f.strong_access!==row.strong_access||f.elevated_burden!==row.elevated_burden)throw Error('Classification mismatch');}
  map=L.map('map',{zoomControl:true,minZoom:8,maxZoom:19,zoomSnap:.25});
  let basemap={url:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'};
  try{const r=await fetch('assets/basemap.json');if(r.ok){const configured=await r.json();if(configured.provider==='CARTO Positron' && configured.url.startsWith('https://basemaps.cartocdn.com/'))basemap=configured;}}catch{/* Source-only previews can use OpenStreetMap. */}
  document.body.classList.toggle('osm-basemap',basemap.provider!=='CARTO Positron');
  L.tileLayer(basemap.url,{maxZoom:19,attribution:basemap.attribution}).addTo(map);
  tractLayer=L.geoJSON(tracts,{style:f=>style(f.properties),onEachFeature:(f,l)=>{l.bindTooltip(()=>`Tract ${esc(f.properties.id)}${dimension==='combined'?'<br>'+combinedClasses[combination(f.properties)].label:''}`,{sticky:true});l.on('click',e=>{$('hex-mode').checked?showHex(e.latlng.lng,e.latlng.lat,'Selected map location',false):showTract(f,e.latlng);});}}).addTo(map);
  L.geoJSON(city,{style:{color:'#71868f',weight:1.4,fill:false,dashArray:'4 4'},interactive:false}).addTo(map);
  const hexFeatures=[...hexes.values()].map(row=>({type:'Feature',properties:row,geometry:{type:'Polygon',coordinates:[h3.cellToBoundary(row.id,true)]}}));
  hexLayer=L.geoJSON(hexFeatures,{onEachFeature:(f,l)=>l.on('click',e=>showHex(e.latlng.lng,e.latlng.lat,'Selected map location',false))});
  selected=L.featureGroup().addTo(map);
  const reset=()=>map.fitBounds(tractLayer.getBounds(),{paddingTopLeft:window.innerWidth>700?[360,20]:[15,15],paddingBottomRight:window.innerWidth>700?[340,20]:[15,15]});
  reset();$('reset-view').addEventListener('click',reset);
  map.on('click',e=>{if($('hex-mode').checked)showHex(e.latlng.lng,e.latlng.lat,'Selected map location',false);});
  for(const view of ['benefits','burdens','combined'])$(view).addEventListener('click',()=>{dimension=view;renderMap();});
  $('burden-measure').addEventListener('change',e=>{burdenMeasure=e.target.value;renderMap();});
  $('hex-mode').addEventListener('change',()=>{renderMap();$('map-help').textContent=$('hex-mode').checked?'Click the map to inspect a hexagon. Only source cells have component values.':'Click a tract for its profile. Address searches always select a hexagon.';});
  $('search-form').addEventListener('submit',runSearch);$('address').addEventListener('input',()=>{cancelSearch();clearSelection();status('Enter an Austin address, then select a match.');});
  $('clear').addEventListener('click',()=>{cancelSearch();clearSelection();$('address').value='';status('Selection cleared. Search an address or explore the map.');});
  const examples=[[-97.883274,30.179630,'Southwest Austin example'],[-97.780280,30.167870,'South Austin example'],[-97.666740,30.310930,'East Austin example'],[-97.662190,30.249080,'Dog’s Head example']];
  document.querySelectorAll('[data-example]').forEach(b=>b.addEventListener('click',()=>{cancelSearch();$('address').value='';showHex(...examples[Number(b.dataset.example)]);}));
  $('about-access').textContent=`Strong access is strictly more than ${fmt(metadata.thresholds.strong_access_above)} jobs.`;
  $('about-burden').textContent=`Elevated burden is RSEI ≥ ${fmt(metadata.thresholds.elevated_rsei_at_least)}.`;
  $('traffic-source-note').textContent=`TxDOT extraction ${[].concat(metadata.traffic.extract_dates||[]).join(', ')}. The source does not specify the observation year of each traffic count.`;
  $('boundary-note').textContent=`City of Austin GIS · ${metadata.boundary.snapshot} · full- and limited-purpose limits`;
  $('hex-coverage').textContent=fmt(metadata.boundary.hex_coverage_share*100,1)+'%';
  setupBenefitControls();renderMap();for(const b of document.querySelectorAll('.explorer button,.explorer input'))b.disabled=false;
  status('Search an address, try an example, or click a tract.');
 }catch(error){status('The map data could not be loaded. Reload the page to try again.',true);profileFrame('Map unavailable','Loading error',`<p>${esc(error.message)}</p><p>Serve this site over HTTP or use its GitHub Pages URL.</p>`);console.error(error);}
}
function setupBenefitControls(){
 const spec=benefitData.spec;
 for(const [key,label] of Object.entries(profileLabels))$('basket').add(new Option(label,key));
 function setBudget(){
   $('time-budget').replaceChildren(...spec.budgets[selection.mode].map(v=>new Option(v+' min',v)));
   selection.minutes=spec.defaults[selection.mode];$('time-budget').value=selection.minutes;
 }
 function note(){
   const names=spec.profiles[selection.profile].map(key=>spec.destinations[key]);
   $('group-note').textContent=names.join(' · ')+(selection.profile==='supportive'?'. Partial service inventory.':'')+
     (selection.mode==='walk_transit'?' · Provisional morning transit coverage.':'');
 }
 function update(){
   dimension='benefits';note();renderMap();if(refreshProfile)refreshProfile();
 }
 $('basket').addEventListener('change',e=>{selection.profile=e.target.value;update();});
 $('travel-mode').addEventListener('change',e=>{selection.mode=e.target.value;setBudget();update();});
 $('time-budget').addEventListener('change',e=>{selection.minutes=Number(e.target.value);update();});
 $('benefit-display').addEventListener('change',e=>{selection.display=e.target.value;update();});
 setBudget();note();
}
$('about-open').addEventListener('click',()=>$('about').showModal());$('about-close').addEventListener('click',()=>$('about').close());
init();
