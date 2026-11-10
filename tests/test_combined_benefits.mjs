import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {columnRows,assessBenefits,aggregateTract,normalizedWeights,combinedStyle} from '../site/combined-benefits.mjs';
const read=f=>JSON.parse(readFileSync(new URL('../site/assets/'+f,import.meta.url)));
const data=read('combined-benefits.json'),baskets=read('benefits.json').spec,spec=data.spec;
const origins=new Map(columnRows(data.origins).map(r=>[r.id,r]));
let compared=0;
for(const r of columnRows(data.reference)){
 const a=assessBenefits(origins.get(r.id),r.profile,r.scenario,spec,baskets);
 assert.equal(a.status,r.status,`${r.id}/${r.profile}/${r.scenario}`);
 if(r.score===null)assert.equal(a.score,null);else assert.ok(Math.abs(a.score-r.score)<1e-10);
 compared++;
}
assert.equal(compared,origins.size*4*3);
const base={drive_families:3,drive_older:5,drive_single:3,drive_supportive:2,drive_grocery:1,
 transit_families:3,transit_grocery:1,jobs_drive:125000,jobs_transit:25000,jobs_drive30:500000,
 education_growth:50,education_sample:10};
const score=(r,p='families',s='drive',w=null,school=null)=>assessBenefits(r,p,s,spec,baskets,w,school);
assert.equal(score(base).status,'meets');
assert.equal(score(base).domains.education.smallSample,true);
assert.equal(score({...base,education_growth:49}).status,'below');
assert.equal(score({...base,jobs_drive:124999}).status,'below');
assert.equal(score({...base,jobs_transit:24999},'families','transit').status,'below');
assert.equal(score({...base,jobs_drive30:499999},'families','drive30').status,'below');
assert.equal(score({...base,drive_grocery:0}).status,'below');
assert.equal(score({...base,drive_families:2}).status,'below');
assert.equal(score({...base,drive_supportive:2},'supportive').status,'meets');
assert.equal(score({...base,education_growth:null},'older').status,'meets');
const zeroJobs={destinations:75,jobs:0,education:25};
assert.equal(score({...base,jobs_drive:0},'families','drive',zeroJobs).status,'below');
assert.equal(score({...base,jobs_drive:null},'families','drive',zeroJobs).score,null);
assert.equal(score({...base,education_growth:null},'families','drive',{destinations:50,jobs:50,education:0}).score,null);
assert.equal(score(base,'families','drive',{destinations:0,jobs:0,education:0}).invalidWeights,true);
assert.equal(normalizedWeights('families',{destinations:-1,jobs:1,education:1},spec),null);
assert.ok(Math.abs(score({...base,jobs_drive:250000,drive_families:4,education_growth:99}).score-100)<1e-10);
assert.equal(score({...base,education_growth:99},'families','drive',null,{status:'Outside available assignment coverage'}).score,null);
assert.equal(score(base,'families','drive',null,{status:'Available',subgroup_growth:49,minimum_growth_tests:30}).status,'below');
// Missing, zero-weight, and failed locations never become passing through aggregation.
const a=new Map([['a',{score:100,status:'meets'}],['b',{score:80,status:'below'}],['c',{score:null,status:'incomplete'}]]);
const entries=[{id:'a',residents:20,area:10},{id:'b',residents:30,area:10},{id:'c',residents:50,area:10},{id:'a',residents:null,area:7},{id:'a',residents:0,area:2}];
const tract=aggregateTract(entries,a);
assert.equal(tract.score,88);assert.equal(tract.meets,20);assert.equal(tract.below,30);assert.equal(tract.incomplete,50);
assert.equal(tract.completeShare,50);assert.equal(tract.unknownArea,7);
assert.equal(aggregateTract([],a).score,null);assert.equal(aggregateTract([],a).meets,null);
assert.equal(combinedStyle({score:99,status:'below'}).color,'#b65c2e');
// All tracts exhaust the known-resident denominator; custom weights leave classifications fixed.
const groups=new Map();for(const e of columnRows(data.tract_weights)){if(!groups.has(e.tract_id))groups.set(e.tract_id,[]);groups.get(e.tract_id).push(e);}
for(const p of Object.keys(spec.presets))for(const s of ['drive','transit','drive30']){
 const scores=new Map([...origins].map(([id,r])=>[id,score(r,p,s)]));
 const custom={destinations:9,jobs:1,education:0};
 for(const [id,r] of origins)assert.equal(score(r,p,s,custom).status,scores.get(id).status);
 for(const entries of groups.values()){
  const t=aggregateTract(entries,scores);
  if(t.known>0)assert.ok(Math.abs(t.meets+t.below+t.incomplete-100)<1e-9);
  if(t.score!==null)assert.ok(t.score>=0&&t.score<=100+1e-10);
 }
}
console.log(`Combined benefits: ${compared} R/browser results agree; cutoff equality, fixed minimums, missing data, small samples, custom weights, point assignments and tract aggregation pass.`);
