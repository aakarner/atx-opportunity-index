import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {assessBenefits, columnRows} from '../site/combined-benefits.mjs';
import {assessBurden} from '../site/combined-burdens.mjs';
import {medianScore, scoreGroup, thresholdFlags} from '../site/score-comparison.mjs';

const scores = values => values.map(score => ({score}));
assert.equal(medianScore(scores([null, 10, 0, 12, 3])), 6.5);
assert.equal(medianScore(scores([5, 0, 0, null])), 0);
assert.equal(medianScore(scores([null, NaN])), null);
assert.equal(scoreGroup(0, 0, 0, 0), 'highHigh');
assert.equal(scoreGroup(0, 100, 100, 100), 'lowHigh');
assert.equal(scoreGroup(100, 0, 100, 100), 'highLow');
assert.equal(scoreGroup(49.9999, 49.9999, 50, 50), 'lowLow');
for (let i = 0; i < 4; i++) {
  const inputs = [0, 0, 0, 0];
  inputs[i] = null;
  assert.equal(scoreGroup(...inputs), 'incomplete');
}

const asset = file => JSON.parse(readFileSync(new URL('../site/assets/' + file, import.meta.url)));
const missedJobs = {status: 'incomplete', failed: ['jobs'], score: null};
const unknownBurden = {overallHigh: null, high: ['heat'], score: null};
const confirmedBurden = {overallHigh: true, high: ['heat', 'crash'], score: null};
assert.equal(thresholdFlags(undefined, unknownBurden).flagged, false);
assert.equal(thresholdFlags({status:'meets', failed:[]}, {overallHigh:false, high:['heat']}).flagged, false);
assert.deepEqual(thresholdFlags(missedJobs, unknownBurden), {flagged:true, missedMinimums:['jobs'], highBurdens:[]});
assert.deepEqual(thresholdFlags(undefined, confirmedBurden), {flagged:true, missedMinimums:[], highBurdens:['heat','crash']});
assert.deepEqual(thresholdFlags(missedJobs, confirmedBurden), {flagged:true, missedMinimums:['jobs'], highBurdens:['heat','crash']});
const benefits = asset('combined-benefits.json'), baskets = asset('benefits.json').spec;
const origins = columnRows(benefits.origins);
const burdens = asset('combined-burdens.json');
const burdenById = new Map(columnRows(burdens.primary).map(row => [row.id, assessBurden(row, burdens.policy)]));
const burdenCut = medianScore(burdenById);
assert.ok(Math.abs(burdenCut - 34.5597378136315) < 1e-10);

// Counts from the project's independent R median-split analysis, including flood exclusions.
// Columns are high/high, low/high, high/low, low/low, and missing.
const expected = {
  families:    {drive: [282,133,189,221,204], transit: [297,118,185,225,204]},
  older:       {drive: [305,132,194,243,155], transit: [318,119,193,244,155]},
  single:      {drive: [298,139,203,234,155], transit: [326,111,186,251,155]},
  supportive:  {drive: [294,143,205,232,155], transit: [325,112,186,251,155]}
};
for (const [profile, scenarios] of Object.entries(expected)) {
  for (const [scenario, reference] of Object.entries(scenarios)) {
    const assessments = origins.map(row => assessBenefits(row, profile, scenario, benefits.spec, baskets));
    const benefitCut = medianScore(assessments);
    const counts = {highHigh: 0, lowHigh: 0, highLow: 0, lowLow: 0, incomplete: 0};
    for (const [i, benefit] of assessments.entries()) {
      const burden = burdenById.get(origins[i].id);
      counts[scoreGroup(benefit.score, burden.score, benefitCut, burdenCut)]++;
    }
    assert.deepEqual(Object.values(counts), reference, `${profile}/${scenario}`);
  }
}
console.log('Score comparison passed for medians, ties, custom cuts, missing scores, and all eight reference maps.');
