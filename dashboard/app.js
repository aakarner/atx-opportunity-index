const $=id=>document.getElementById(id);
const state={catalog:null,grid:null,scenario:null,mode:'drive',period:'am_peak',series:null,result:null,displaySeries:null,region:'metro',cityBounds:null};
const overlays={};
const destinationFiles={grocery_third_nearest:'groceries.geojson',childcare_fifth_nearest:'childcare.geojson',park_reachable_supply:'parks.geojson',library_nearest:'libraries.geojson',pharmacy_nearest:'pharmacies.geojson',hospital_second_nearest:'hospitals.geojson',urgent_care_third_nearest:'urgent-care.geojson',public_center_nearest:'public-centers.geojson'};
const palette=['#f2e85c','#9bd37f','#43b59f','#2f7c91','#3b437d'];
const lowPalette=[...palette].reverse();
const map=L.map('map',{preferCanvas:true,zoomControl:false}).setView([30.32,-97.7],9);
L.control.zoom({position:'bottomright'}).addTo(map);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap contributors'}).addTo(map);
let gridLayer;

const fmt=(v,u)=>v==null?'Not accessible':u==='minutes'?`${v.toFixed(1)} min`:u==='acres'?`${Math.round(v).toLocaleString()} acres`:u==='jobs'?Math.round(v).toLocaleString():u==='ratio'?`${Math.round(v*100)}%`:`${v.toFixed(2)}`;
const quantile=(a,q)=>{if(!a.length)return null;const p=(a.length-1)*q,b=Math.floor(p),r=p-b;return a[b+1]!==undefined?a[b]+r*(a[b+1]-a[b]):a[b]};
function scenario(){return state.catalog.scenarios.find(s=>s.id===state.scenario)}
function currentSeries(){return state.displaySeries||state.result?.series.find(s=>s.id===state.series)}
function showStatus(t){$('status').textContent=t;$('status').classList.add('show');setTimeout(()=>$('status').classList.remove('show'),1800)}
function setOptions(el,items,value,label=x=>x){el.innerHTML=items.map(x=>`<option value="${x}">${label(x)}</option>`).join('');if(items.includes(value))el.value=value;return el.value}
function updateURL(){const u=new URL(location.href);['scenario','mode','period','series','region'].forEach(k=>u.searchParams.set(k,state[k]));history.replaceState(null,'',u)}

async function loadResult(){
  state.displaySeries=null;
  const s=scenario(); const actualMode=state.mode==='comparison'?'drive':state.mode;
  const file=s.files[`${actualMode}:${state.period}`];
  if(!file){showStatus('This combination is not available');return}
  state.result=await fetch(file).then(r=>r.json());
  const choices=state.result.series.map(x=>x.id);
  state.series=setOptions($('metric'),choices,choices.includes(state.series)?state.series:choices[0],id=>state.result.series.find(x=>x.id===id).label);
  let values=[...currentSeries().values];
  if(state.mode==='comparison'){
    const transitFile=s.files[`walk_transit:${state.period}`];
    if(!transitFile){showStatus('Transit comparison unavailable');return}
    const transit=await fetch(transitFile).then(r=>r.json());
    const tv=transit.series.find(x=>x.id===state.series)?.values||[];
    const direction=currentSeries().direction;
    values=values.map((auto,i)=>{const tr=tv[i];if(auto==null||tr==null||auto===0||tr===0)return null;return direction==='higher'?tr/auto:auto/tr});
    state.displaySeries={id:state.series,label:'Transit access relative to auto',unit:'ratio',direction:'higher',values};
  }
  render(); updateURL();
}

function render(){
  const s=scenario(), ser=currentSeries();
  const active=state.grid.features.map((f,i)=>state.region==='metro'||f.properties.region==='austin'?i:-1).filter(i=>i>=0);
  const allValues=active.map(i=>ser.values[i]).filter(v=>v!=null&&Number.isFinite(v));
  const positive=allValues.filter(v=>v>0).sort((a,b)=>a-b);
  const vals=[...allValues].sort((a,b)=>a-b);
  const cumulative=ser.direction==='higher'&&ser.unit!=='ratio';
  const colors=ser.direction==='lower'?lowPalette:palette;
  const breaks=ser.unit==='ratio'?[.25,.5,.75,1]:cumulative?[.25,.5,.75].map(q=>quantile(positive,q)):[.2,.4,.6,.8].map(q=>quantile(vals,q));
  gridLayer.eachLayer(layer=>{
    const i=layer.feature._i, inRegion=state.region==='metro'||layer.feature.properties.region==='austin', v=ser.values[i];
    if(!inRegion){layer.setStyle({fillOpacity:0,opacity:0});return}
    let c='#c9ced0';
    if(v!=null){
      if(cumulative&&v===0)c='#eee9d2';
      else{let k=breaks.findIndex(b=>v<=b);if(k<0)k=breaks.length;c=colors[cumulative?Math.min(k+1,4):k]}
    }
    layer.setStyle({fillColor:c,fillOpacity:v==null?.28:.76,color:'#fff',opacity:1,weight:.25});
    layer.bindPopup(`<div class="popup"><strong>${fmt(v,ser.unit)}</strong><small>H8 cell ${layer.feature.properties.h3_id}</small></div>`);
  });
  const summaryVals=cumulative?positive:vals;
  const med=quantile(summaryVals,.5), lo=quantile(summaryVals,.05), hi=quantile(summaryVals,.95);
  $('median').textContent=fmt(med,ser.unit);
  const accessible=cumulative?positive.length:vals.length;
  $('reachable').textContent=`${Math.round(100*accessible/active.length)}%`;
  $('range').textContent=summaryVals.length?`${fmt(lo,ser.unit)}–${fmt(hi,ser.unit)}`:'—';
  $('measureTitle').textContent=state.mode==='comparison'?'Transit access relative to auto':ser.label;
  $('measureDescription').textContent=state.mode==='comparison'?'A value of 100% indicates parity with auto. Values below 100% indicate lower transit access.':s.description+(state.mode==='walk_transit'?' Cells without a valid CapMetro walk-and-transit route within 90 minutes are shown as not accessible.':'');
  $('source').textContent=`Source: ${s.source}`;$('unitLabel').textContent=ser.unit;
  const modeLabel=state.mode==='drive'?'Auto':state.mode==='walk_transit'?'Transit + walk':'Transit / auto';
  const periodLabel=state.period==='am_peak'?'Morning peak':'Midday';
  const regionLabel=state.region==='austin'?'City of Austin':'Austin metro';
  $('mapKicker').textContent=`${modeLabel.toUpperCase()} · ${periodLabel.toUpperCase()} · ${regionLabel.toUpperCase()}`;
  $('mapTitle').textContent=state.mode==='comparison'?'How closely does transit match auto access?':ser.label;
  const bins=16,min=summaryVals[0]??0,max=summaryVals.at(-1)??1,counts=Array(bins).fill(0);
  summaryVals.forEach(v=>counts[Math.min(bins-1,Math.floor((v-min)/(max-min||1)*bins))]++);
  const peak=Math.max(...counts,1);$('bars').innerHTML=counts.map(x=>`<i style="height:${Math.max(3,100*x/peak)}%"></i>`).join('');
  let labels=[];
  if(ser.unit==='ratio')labels=[['< 25%',colors[0]],['25–50%',colors[1]],['50–75%',colors[2]],['75–100%',colors[3]],['≥ 100%',colors[4]]];
  else if(cumulative)labels=[['0', '#eee9d2'],[`0–${fmt(breaks[0],ser.unit)}`,colors[1]],[`${fmt(breaks[0],ser.unit)}–${fmt(breaks[1],ser.unit)}`,colors[2]],[`${fmt(breaks[1],ser.unit)}–${fmt(breaks[2],ser.unit)}`,colors[3]],[`> ${fmt(breaks[2],ser.unit)}`,colors[4]]];
  else{const edges=[-Infinity,...breaks,Infinity];labels=colors.map((c,i)=>[i===0?`≤ ${fmt(edges[1],ser.unit)}`:i===4?`> ${fmt(edges[4],ser.unit)}`:`${fmt(edges[i],ser.unit)}–${fmt(edges[i+1],ser.unit)}`,c])}
  $('legend').innerHTML=`<h3>${ser.unit==='ratio'?'Transit / auto':ser.unit}</h3>`+labels.map(([t,c])=>`<div class="legend-row"><i class="swatch" style="background:${c}"></i><span>${t}</span></div>`).join('')+`<div class="legend-row"><i class="swatch" style="background:#c9ced0"></i><span>Not accessible</span></div>`;
  updateDestinationOverlay();
}
async function updateDestinationOverlay(){if(overlays.destination){map.removeLayer(overlays.destination);delete overlays.destination}if(!$('destinationsToggle').checked||!destinationFiles[state.scenario])return;const gj=await fetch(`data/${destinationFiles[state.scenario]}`).then(r=>r.json());overlays.destination=L.geoJSON(gj,{pointToLayer:(f,ll)=>L.circleMarker(ll,{radius:4,fillColor:'#d34949',fillOpacity:.9,color:'#fff',weight:1}),style:{color:'#34865e',weight:1,fillOpacity:.14},onEachFeature:(f,l)=>l.bindPopup(`<strong>${f.properties.name||f.properties.NAME||f.properties.facility_name||'Destination'}</strong>`)}).addTo(map)}
async function toggleOverlay(key,file,style,checked){if(overlays[key]){map.removeLayer(overlays[key]);delete overlays[key]}if(!checked)return;const gj=await fetch(`data/${file}`).then(r=>r.json());overlays[key]=L.geoJSON(gj,{style}).addTo(map);overlays[key].bringToBack()}
async function changeScenario(){const s=scenario();state.period=setOptions($('period'),s.periods,state.period,p=>p==='am_peak'?'Morning peak':'Midday');await loadResult()}
function updateRegion(){
  state.region=$('region').value;
  if(overlays.cityBoundary){map.removeLayer(overlays.cityBoundary);delete overlays.cityBoundary}
  if(state.region==='austin'){
    overlays.cityBoundary=L.geoJSON(state.cityBoundary,{style:{color:'#d2772e',weight:2,fillOpacity:0}}).addTo(map);
    map.fitBounds(overlays.cityBoundary.getBounds(),{padding:[18,18]});
  }else map.fitBounds(gridLayer.getBounds(),{padding:[20,20]});
  render();updateURL();
}

async function init(){
  const [catalog,grid,cityBoundary]=await Promise.all([fetch('data/catalog.json').then(r=>r.json()),fetch('data/h8-grid.geojson').then(r=>r.json()),fetch('data/austin-full-purpose.geojson').then(r=>r.json())]);state.catalog=catalog;state.grid=grid;state.cityBoundary=cityBoundary;grid.features.forEach((f,i)=>f._i=i);
  const q=new URLSearchParams(location.search);state.scenario=q.get('scenario')||'grocery_third_nearest';state.mode=q.get('mode')||'drive';state.period=q.get('period')||'am_peak';state.series=q.get('series');state.region=q.get('region')||'metro';$('region').value=state.region;
  setOptions($('destination'),catalog.scenarios.map(x=>x.id),state.scenario,id=>catalog.scenarios.find(x=>x.id===id).destination);state.scenario=$('destination').value;document.querySelectorAll('.mode-tabs button').forEach(b=>b.classList.toggle('active',b.dataset.mode===state.mode));
  gridLayer=L.geoJSON(grid,{style:{fillColor:'#ddd',fillOpacity:.4,color:'#fff',weight:.25}}).addTo(map);map.fitBounds(gridLayer.getBounds(),{padding:[20,20]});
  await toggleOverlay('counties','county-boundaries.geojson',{color:'#344e5c',weight:1.3,dashArray:'5 4',fillOpacity:0},true);await changeScenario();if(state.region==='austin')updateRegion();$('status').classList.remove('show');
}
$('destination').addEventListener('change',async e=>{state.scenario=e.target.value;state.series=null;await changeScenario()});$('period').addEventListener('change',async e=>{state.period=e.target.value;await loadResult()});$('metric').addEventListener('change',async e=>{state.series=e.target.value;if(state.mode==='comparison')await loadResult();else{state.displaySeries=null;render();updateURL()}});document.querySelectorAll('.mode-tabs button').forEach(b=>b.addEventListener('click',async()=>{state.mode=b.dataset.mode;document.querySelectorAll('.mode-tabs button').forEach(x=>x.classList.toggle('active',x===b));await loadResult()}));
$('region').addEventListener('change',updateRegion);
$('destinationsToggle').addEventListener('change',updateDestinationOverlay);$('countiesToggle').addEventListener('change',e=>toggleOverlay('counties','county-boundaries.geojson',{color:'#344e5c',weight:1.3,dashArray:'5 4',fillOpacity:0},e.target.checked));$('blocksToggle').addEventListener('change',e=>toggleOverlay('blocks','census-block-groups.geojson',{color:'#596b75',weight:.45,fillOpacity:0},e.target.checked));$('shareButton').addEventListener('click',async()=>{await navigator.clipboard.writeText(location.href);showStatus('View link copied')});$('menuButton').addEventListener('click',()=>{$('sidebar').classList.toggle('open')});
init().catch(e=>{console.error(e);$('status').textContent='Unable to load the prototype data';$('status').classList.add('show')});
