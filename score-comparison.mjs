import {finite} from './logic.mjs?v=e2b7c16e95d7';

export const scoreGroups = {
  highHigh: {label: 'High benefits / high burdens', color: '#9968a4'},
  lowHigh:  {label: 'Low benefits / high burdens', color: '#b44949'},
  highLow:  {label: 'High benefits / low burdens', color: '#21847b'},
  lowLow:   {label: 'Low benefits / low burdens', color: '#b68b36'},
  incomplete: {label: 'Missing score', color: '#b9bec3'}
};

export function medianScore(assessments, value = assessment => assessment.score) {
  const scores = Array.from(assessments.values(), value)
    .filter(finite).sort((a, b) => a - b);
  if (!scores.length) return null;
  const middle = Math.floor(scores.length / 2);
  return scores.length % 2 ? scores[middle] : (scores[middle - 1] + scores[middle]) / 2;
}

export function scoreGroup(benefit, burden, benefitCut, burdenCut) {
  if (![benefit, burden, benefitCut, burdenCut].every(finite)) return 'incomplete';
  if (benefit >= benefitCut) return burden >= burdenCut ? 'highHigh' : 'highLow';
  return burden >= burdenCut ? 'lowHigh' : 'lowLow';
}
