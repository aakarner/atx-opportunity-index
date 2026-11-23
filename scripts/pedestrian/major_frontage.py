"""Measure mapped sidewalk and parallel-path frontage on eligible Austin streets."""
import argparse
from pathlib import Path
import re

import geopandas as gpd
import numpy as np
import pandas as pd
import shapely as sh

CRS = 26914
ABBR = {'ROAD':'RD','STREET':'ST','DRIVE':'DR','AVENUE':'AVE','LANE':'LN','BOULEVARD':'BLVD','COURT':'CT','PARKWAY':'PKWY','CIRCLE':'CIR','TRAIL':'TRL','PLACE':'PL','TERRACE':'TER','NORTH':'N','SOUTH':'S','EAST':'E','WEST':'W','HIGHWAY':'HWY','PASS':'PASS'}


def normal(value):
    words = re.sub(r"[^A-Z0-9 ]", "", str(value).upper()).split()
    return ' '.join(ABBR.get(w,w) for w in words)


def read_pages(directory, pattern, columns=None):
    return pd.concat([gpd.read_file(p, columns=columns) for p in sorted(directory.glob(pattern))],
                     ignore_index=True).to_crs(CRS)


def streets(directory, city):
    r = pd.concat([read_pages(directory, "roads_*.geojson"),read_pages(directory, "other_roads_*.geojson")],ignore_index=True)
    assert r.OBJECTID_1.is_unique
    r = r.loc[r.geometry.notna()].explode(index_parts=False).reset_index(drop=True)
    # Retain nearby geometry for matching roads and facilities along the city edge.
    r = r.loc[r.intersects(city.buffer(900)) & (r.length>0) &
              (r.CTM_BUILT_STATUS.isin([1,2]) | r.BUILT_STATUS.eq("Existing"))].copy()
    r["name"] = r.FULL_STREET_NAME.fillna("").map(normal)
    by_class = r.ROAD_CLASS.isin([2,4,5,6,8,14])
    by_level = (r.ROAD_CLASS.isna() | r.ROAD_CLASS.eq(0)) & r.STREET_LEVEL.isin([1,2,3,4,101,102,103,104])
    frontage = r.name.str.contains(r"\bSVRD (?:NB|SB|EB|WB)$") & ~r.ROAD_CLASS.isin([10,12,15,16])
    r["public"] = (by_class|by_level|frontage) & ~r.STREET_LEVEL.eq(5) & ~r.MAINTENANCE_AGENCY.isin(["Private","Not Built"])
    r["major"] = (r.STREET_LEVEL.isin([2,3,4,102,103,104]) | r.ROAD_CLASS.isin([2,4,5,8]) |
                  r.name.str.contains(r"\bSVRD\b")) & r.public
    r["local"] = r.public & ~r.major & (r.STREET_LEVEL.isin([1,101]) | r.ROAD_CLASS.isin([6,14]))
    return r.reset_index(drop=True)


def facilities(f, city):
    f = f.loc[f.geometry.notna() & f.PEDESTRIAN_FACILITY_TYPE.isin(["EXISTING_SIDEWALK","DRIVEWAY","SHARED_USE_PATH","PROTECTED_STREET_PATH","SHARED_STREET"])].copy()
    f = f.explode(index_parts=False).reset_index(drop=True)
    f = f.loc[(f.length>0) & f.intersects(city.buffer(900))].copy()
    f["kind"] = f.PEDESTRIAN_FACILITY_TYPE
    f["name"] = f.FULL_STREET_NAME.fillna("").map(normal)
    # Count driveway crossings that connect to an existing facility at both ends.
    drives = f.kind.eq("DRIVEWAY")
    sidewalk = f.loc[~drives & ~f.kind.eq("SHARED_STREET")].geometry.to_numpy()
    tree = sh.STRtree(sidewalk)
    dg = f.loc[drives].geometry.to_numpy()
    keep = np.ones(len(dg),dtype=bool)
    for side in (0,-1):
        idx, _ = tree.query(sh.get_point(dg,side),predicate="dwithin",distance=2.5)
        keep &= np.isin(np.arange(len(dg)),idx)
    mask = ~drives.to_numpy()
    mask[np.flatnonzero(drives)] = keep
    return f.loc[mask, ["kind", "name", "geometry"]]


def segment_arrays(lines, spacing):
    """Split lines into short straight chords, preserving their true polyline length."""
    coords, owner = sh.get_coordinates(sh.segmentize(lines,spacing), return_index=True)
    d = coords[1:] - coords[:-1]
    length = np.hypot(d[:,0],d[:,1])
    ok = (owner[:-1]==owner[1:]) & (length>0)
    return coords[:-1][ok], coords[1:][ok], length[ok], owner[:-1][ok]


def adjacent_facilities(r,f,mid,u,owner):
    """Assign parallel mapped facilities to the same street and signed street side."""
    tree=sh.STRtree(f.geometry.to_numpy())
    geoms=f.geometry.to_numpy()
    names=f.name.to_numpy()
    kinds=f.kind.to_numpy()
    lens=sh.length(geoms)
    roadname=r.name.to_numpy()
    major=r.major.to_numpy()
    width=r.PAVEMENT_WIDTH.fillna(0).to_numpy(float)
    lim=np.clip(np.maximum(np.where(major,22.,14.),width*0.3048/2+7),0,35)
    flags=np.zeros((len(mid),7),bool)
    for start in range(0,len(mid),22000):
        sub=slice(start,start+22000)
        pts=sh.points(mid[sub])
        i,j=tree.query(pts,predicate="dwithin",distance=lim[owner[sub]])
        if not len(i):continue
        pos=sh.line_locate_point(geoms[j],pts[i])
        on=sh.get_coordinates(sh.line_interpolate_point(geoms[j],pos))
        v=sh.get_coordinates(sh.line_interpolate_point(geoms[j],np.minimum(lens[j],pos+1))) - sh.get_coordinates(sh.line_interpolate_point(geoms[j],np.maximum(0,pos-1)))
        vlen=np.linalg.norm(v,axis=1)
        heading=np.abs(np.sum(v*u[sub][i],axis=1))/np.maximum(vlen,.00001)
        delta=on-mid[sub][i]
        parallel=np.abs(np.sum(delta*u[sub][i],axis=1))
        side=u[sub][i,0]*delta[:,1]-u[sub][i,1]*delta[:,0]
        # A bounded along-street distance prevents points past the end of a sidewalk getting credit.
        agree=names[j]==roadname[owner[sub][i]]
        unnamed=(names[j]=="") | (roadname[owner[sub][i]]=="")
        path=np.isin(kinds[j],["PROTECTED_STREET_PATH","SHARED_USE_PATH"])
        accept=(heading>=.75)&(parallel<=4)&(agree | ((unnamed|path)&(np.abs(side)<=14)&(heading>=.9)))
        for idx,category in enumerate([kinds[j]=="EXISTING_SIDEWALK",kinds[j]=="DRIVEWAY",path]):
            for s,which in enumerate([side>=0,side<0]):
                flags[i[accept&category&which]+start,2*idx+s]=True
        flags[i[accept&(kinds[j]=="SHARED_STREET")]+start,6]=True
    return flags


def opposing(r,mid,u,owner):
    """Collapse adjacent parallel representations of the same divided road."""
    which=np.flatnonzero(r.ONE_WAY.eq("Y").to_numpy()[owner])
    other=np.full(len(mid),-1,int)
    toward_left=np.zeros(len(mid),bool)
    if not len(which):return other,toward_left
    names=r.name.str.replace(r" (NB|SB|EB|WB)$","",regex=True).to_numpy()
    tree=sh.STRtree(sh.points(mid[which]))
    i,j=tree.query(sh.points(mid[which]),predicate="dwithin",distance=32.)
    a,b=which[i],which[j]
    dx=mid[b]-mid[a]
    lateral=u[a,0]*dx[:,1]-u[a,1]*dx[:,0]
    ok=(owner[a]!=owner[b]) & (names[owner[a]]==names[owner[b]]) & (names[owner[a]]!="") & (np.abs(lateral)>4) & (np.abs(np.sum(u[a]*dx,axis=1))<5) & (np.abs(np.sum(u[a]*u[b],axis=1))>.94)
    a,b,lat,d=a[ok],b[ok],lateral[ok],np.linalg.norm(dx[ok],axis=1)
    ix=np.lexsort((d,a))
    pick=ix[np.r_[True,np.diff(a[ix])!=0]] if len(ix) else ix
    other[a[pick]]=b[pick]
    toward_left[a[pick]]=lat[pick]>0
    return other,toward_left



def frontage_samples(roads, facilities):
    a, b, length, owner = segment_arrays(roads.geometry.to_numpy(), 8)
    mid = (a + b) / 2
    direction = (b - a) / length[:, None]
    matches = adjacent_facilities(roads, facilities, mid, direction, owner)
    sides = matches[:, :2] | matches[:, 2:4] | matches[:, 4:6]
    partner, median_left = opposing(roads, mid, direction, owner)
    paired = partner >= 0
    # Left is column 0 and right is column 1. Keep only the outside of a paired carriageway.
    outside_served = sides[np.arange(len(mid)), median_left.astype(int)]
    major = roads.major.to_numpy()[owner]
    total = np.where(paired, 1, 2) * length
    served = np.where(paired, outside_served, sides.sum(axis=1)) * length
    return sh.points(mid[major]), total[major], served[major]


def measure(inventory_dir, transport_dir, windows_path, output):
    city = gpd.read_file(windows_path, layer="city").to_crs(CRS).geometry.union_all()
    roads = streets(transport_dir, city)
    public = roads.loc[roads.public].reset_index(drop=True)
    inventory = read_pages(inventory_dir, "page-*.geojson", ["PEDESTRIAN_FACILITY_TYPE", "FULL_STREET_NAME"])
    observed = inventory.geometry[inventory.geometry.notna() & (inventory.length > 0)].to_numpy()
    observation_tree = sh.STRtree(observed)
    trails = read_pages(transport_dir, "trails_*.geojson").explode(index_parts=False)
    trails["name"] = ""
    trails["kind"] = "SHARED_USE_PATH"
    mapped = pd.concat([facilities(inventory, city), trails[["name", "kind", "geometry"]]], ignore_index=True)
    points, total, served = frontage_samples(public, mapped)
    tree = sh.STRtree(points)
    results = []
    for scenario in ("primary", "sensitivity"):
        windows = gpd.read_file(windows_path, layer=scenario).to_crs(CRS)
        polygons = windows.geometry.to_numpy()
        i, j = tree.query(polygons, predicate="intersects")
        # A line touching only the edge of a window supplies no observed length.
        # For line/polygon intersection, T******** means the interiors intersect.
        wi, fi = observation_tree.query(polygons, predicate="intersects")
        interior = sh.relate_pattern(observed[fi], polygons[wi], "T********")
        results.append(pd.DataFrame({
            "h3_id": windows.h3_id, "scenario": scenario,
            "major_frontage_m": np.bincount(i, weights=total[j], minlength=len(windows)),
            "major_served_m": np.bincount(i, weights=served[j], minlength=len(windows)),
            "inventory_observed": np.isin(np.arange(len(windows)), wi[interior])
        }))
    pd.concat(results, ignore_index=True).to_csv(output, index=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("inventory_dir", "transport_dir", "windows", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    measure(args.inventory_dir, args.transport_dir, args.windows, args.output)
