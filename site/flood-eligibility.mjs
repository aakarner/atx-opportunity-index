import {finite,escapeHTML as esc} from './logic.mjs';

export const floodLabels={ineligible:'Ineligible for development',address_check_required:'Partial overlap — check the address',not_excluded:'Not excluded by flood rule',unknown:'Flood eligibility unavailable'};
export const floodColors={ineligible:'#384452',address_check_required:'#80bdd6',not_excluded:'#e5ecec',unknown:'#b3bbc0'};

// Boundary-inclusive point/polygon test, retaining holes. Coordinates are the
// unsimplified, per-hex intersections exported at ten decimal places.
function ringPosition([x,y],ring){
 let inside=false;
 for(let i=0,j=ring.length-1;i<ring.length;j=i++){
  const [ax,ay]=ring[j],[bx,by]=ring[i],dx=bx-ax,dy=by-ay,len=Math.hypot(dx,dy);
  if(len>0 && Math.abs((x-ax)*dy-(y-ay)*dx)<=1e-11*len &&
     x>=Math.min(ax,bx)-1e-11 && x<=Math.max(ax,bx)+1e-11 && y>=Math.min(ay,by)-1e-11 && y<=Math.max(ay,by)+1e-11)return 2;
  if((ay>y)!==(by>y)&&x<(bx-ax)*(y-ay)/(by-ay)+ax)inside=!inside;
 }
 return inside?1:0;
}
export function floodContains(geometry,point){
 if(!geometry||!Array.isArray(point)||point.length!==2||!point.every(finite))return false;
 const polygons=geometry.type==='Polygon'?[geometry.coordinates]:geometry.type==='MultiPolygon'?geometry.coordinates:[];
 return polygons.some(rings=>ringPosition(point,rings[0])>0&&!rings.slice(1).some(r=>ringPosition(point,r)===1));
}
export function indexFlood(data,expectedIds){
 if(data?.schema_version!==1||data.metadata?.role!=='eligibility_constraint'||data.metadata.contributes_to_burden_score!==false)throw Error('Flood eligibility schema mismatch');
 const rows=new Map(data.hex.map(r=>[r.id,r])),geometry=new Map();
 if(rows.size!==data.hex.length||rows.size!==expectedIds.length||expectedIds.some(id=>!rows.has(id)))throw Error('Flood eligibility geography mismatch');
 for(const f of data.flood_by_hex.features){
  const id=f.properties.h3_id;
  if(!rows.has(id)||!['Polygon','MultiPolygon'].includes(f.geometry?.type))throw Error('Invalid flood polygon');
  if(!geometry.has(id))geometry.set(id,[]);geometry.get(id).push(f.geometry);
 }
 for(const row of rows.values()){
  if(!finite(row.overlap_share)||row.overlap_share<0||row.overlap_share>1||!['ineligible','address_check_required','not_excluded'].includes(row.status)||row.excluded!==(row.status==='ineligible'))throw Error('Invalid flood screen');
  if(row.overlap_share>0&&!geometry.has(row.id))throw Error('Flood polygons missing for affected hexagon');
 }
 return {rows,geometry,tracts:new Map(data.tract.map(r=>[r.id,r])),metadata:data.metadata};
}
export function floodStatus(index,id,point=null){
 const row=index?.rows.get(id);
 if(!row)return 'unknown';
 if(point===null)return row.status;
 if(!Array.isArray(point)||point.length!==2||!point.every(finite))return 'unknown';
 return row.excluded||(index.geometry.get(id)||[]).some(g=>floodContains(g,point))?'ineligible':'not_excluded';
}
export function floodProfile(index,id,isHex,point=null){
 const row=(isHex?index?.rows:index?.tracts)?.get(id);
 const share=row?.overlap_share;
 let area=finite(share)?(share*100).toFixed(1)+'%':'Unavailable';
 if(isHex&&row?.status==='address_check_required'&&area==='100.0%')area='<100%';
 if(finite(share)&&share>0&&area==='0.0%')area='<0.1%';
 const state=isHex?floodStatus(index,id,point):null;
 const label=isHex?floodLabels[state]:'Address-level flood check required';
 const explanation=!isHex?'Tract overlap describes area, not the eligibility of every address.':
  point?'The selected address or map point is checked against the floodplain itself.':
  state==='ineligible'?'The entire full hexagon is covered by the mapped floodplain.':
  state==='address_check_required'?'Only part of this hexagon overlaps. Check the actual development address.':
  state==='unknown'?'No verified flood eligibility result is available.':'No mapped floodplain area overlaps this hexagon.';
 return `<section class="metric-block flood-screen ${state==='ineligible'?'flood-excluded':''}"><div class="metric-label">Development eligibility · Flood constraint</div><strong>${esc(label)}</strong><p>${esc(explanation)}</p><p class="small">${isHex?'Full hexagon':'City-clipped tract'} overlap: ${esc(area)}. City fully developed floodplain. This constraint cannot be offset by benefits, weights, or lower burdens.</p><p class="small">Project eligibility rule; not a permit determination. “Not excluded” applies only to this flood rule.</p></section>`;
}
