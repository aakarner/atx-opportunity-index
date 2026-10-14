// Pure classification and spatial lookup functions shared by the client and tests.
export const finite = v => typeof v === 'number' && Number.isFinite(v);
export function flags(row, thresholds) {
  return {strong_access: finite(row?.jobs_total) ? row.jobs_total > thresholds.strong_access_above : null,
    elevated_burden: finite(row?.rsei) ? row.rsei >= thresholds.elevated_rsei_at_least : null};
}
// Return 0 outside, 1 inside, 2 on an edge. Coordinates are GeoJSON lon/lat.
function inRing(point, ring) {
  const [x,y] = point; let inside = false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++) {
    const [ax,ay]=ring[j], [bx,by]=ring[i];
    const cross=(x-ax)*(by-ay)-(y-ay)*(bx-ax);
    if(Math.abs(cross)<1e-12 && x>=Math.min(ax,bx)-1e-10 && x<=Math.max(ax,bx)+1e-10 && y>=Math.min(ay,by)-1e-10 && y<=Math.max(ay,by)+1e-10) return 2;
    if((ay>y)!==(by>y) && x<(bx-ax)*(y-ay)/(by-ay)+ax) inside=!inside;
  }
  return inside?1:0;
}
export function contains(geometry, lon, lat) {
  if(!finite(lon)||!finite(lat)||!geometry) return false;
  const polygons=geometry.type==='Polygon'?[geometry.coordinates]:geometry.type==='MultiPolygon'?geometry.coordinates:[];
  return polygons.some(rings=>{
    const outer=inRing([lon,lat],rings[0]); if(!outer)return false;
    return !rings.slice(1).some(r=>inRing([lon,lat],r)===1);
  });
}
export function locate(lon,lat,city,tracts,hexes,h3) {
  if(!finite(lon)||!finite(lat)||Math.abs(lat)>90||Math.abs(lon)>180) throw new Error('Invalid coordinates');
  const id=h3.latLngToCell(lat,lon,8);
  const inCity=city.features.some(f=>contains(f.geometry,lon,lat));
  const tract=inCity ? tracts.features.find(f=>contains(f.geometry,lon,lat))?.properties : null;
  return {id,inCity,tract:tract||null,row:inCity?(hexes.get(id)||null):null};
}
export function candidates(data) {
  const seen=new Set();
  return (Array.isArray(data?.candidates)?data.candidates:[]).filter(c=>{
    if(typeof c.address!=='string'||!c.address.trim()||!finite(c.location?.x)||!finite(c.location?.y)||Math.abs(c.location.x)>180||Math.abs(c.location.y)>90)return false;
    const key=`${c.address}|${c.location.x}|${c.location.y}`;if(seen.has(key))return false;seen.add(key);return true;
  }).slice(0,5);
}
export const escapeHTML = value => String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
