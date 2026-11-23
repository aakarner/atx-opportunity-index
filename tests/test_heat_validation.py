"""Independent checks of the exported heat analysis (run after validation/report)."""
import csv
import math
from collections import defaultdict
from pathlib import Path

ROOT = Path('output/components/heat-validation')


def read(name):
    return list(csv.DictReader((ROOT / f'{name}.csv').open()))


def close(a, b, tolerance=1e-7):
    assert math.isclose(float(a), float(b), rel_tol=tolerance, abs_tol=tolerance), (a, b)


def percentiles(values):
    ordered = sorted(values.values())
    # Empirical CDF: all ties get the upper rank, independently of R implementation.
    import bisect
    return {key: 100 * bisect.bisect_right(ordered, value) / len(ordered)
            for key, value in values.items()}


origins = read('comparison_origins')
assert len(origins) == len({r['h3_id'] for r in origins}) == 1029
daily = read('current_daily_values')
assert len(daily) == len({(r['h3_id'], r['date']) for r in daily}) == 1029 * 17
by_origin, by_date = defaultdict(list), defaultdict(dict)
for r in daily:
    valid, hot = float(r['valid_pixel_equivalents']), float(r['hot_pixel_equivalents'])
    assert 0 <= hot <= valid + 1e-8
    if float(r['land_coverage']) >= .5:
        by_origin[r['h3_id']].append(r)
        by_date[r['date']][r['h3_id']] = float(r['mean_F'])
daily_ranks = defaultdict(list)
for rows in by_date.values():
    for h3, rank in percentiles(rows).items():
        daily_ranks[h3].append(rank)
expected_ranks = percentiles({h3: sum(ranks) / len(ranks) for h3, ranks in daily_ranks.items()})
for r in origins:
    h3 = r['h3_id']
    rows = by_origin[h3]
    assert len(rows) == int(r['dates_half_land'])
    close(r['quality_hot_pixel_share'],
          100 * sum(float(a['hot_pixel_equivalents']) for a in rows) /
          sum(float(a['valid_pixel_equivalents']) for a in rows))
    close(r['quality_relative_rank'], expected_ranks[h3])
    assert (r['thin_coverage_flag'] == 'TRUE') == (len(rows) < 8)
    close(r['raster_extent_land_coverage'], 1, tolerance=1e-5)

for r in read('peter_reconciliation'):
    close(r['saved_hot_share'], r['reconstructed_hot_share'], tolerance=1e-4)
    close(r['saved_rank'], r['historical_rank'])
    assert r['saved_date_count'] == r['historical_date_count']
for r in read('threshold_comparison'):
    group = r['weighting']
    population = [float(o[group]) for o in origins if o[group]] if group != 'equal_hex' else [1] * len(origins)
    close(r['all_known_weight'], sum(population))
    close(r['percent_of_all_known'], 100 * float(r['flagged_weight']) / sum(population))

assert sum(r['peter_grid_match'] == 'FALSE' for r in origins) == 7
assert sum(r['thin_coverage_flag'] == 'TRUE' for r in origins) == 257
assert sum(not r['total_population'] for r in origins) == 71
assert sum(int(r['current_hexes_any']) > 0 for r in read('scene_coverage')) == 14
print('Passed: unique/current geography, 17-date coverage, independent rank and pooled-share reconstruction, source reconciliation, population denominators and coverage flags.')
