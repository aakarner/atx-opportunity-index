"""Extract a package-ready OD subset from a large prepared Parquet matrix.

This script performs file-backed filtering only. Accessibility measures are
calculated in R with the accessibility package.
"""

import json
import sys

import duckdb


def main(config_path: str) -> None:
    with open(config_path, encoding="utf-8") as stream:
        cfg = json.load(stream)

    con = duckdb.connect()
    con.execute("SET memory_limit='2GB'")
    con.execute("SET threads=4")
    con.execute("CREATE TABLE origins AS SELECT * FROM read_csv_auto(?)", [cfg["origins"]])
    con.execute("CREATE TABLE destinations AS SELECT * FROM read_csv_auto(?)", [cfg["destinations"]])
    matrix_path = cfg["matrix"].replace("'", "''")
    con.execute(f"CREATE VIEW matrix AS SELECT * FROM read_parquet('{matrix_path}')")
    output_path = cfg["output"].replace("'", "''")
    con.execute(
        f"""
        COPY (
          SELECT
            matrix.origin_h3 AS from_id,
            matrix.destination_h3 AS to_id,
            matrix.travel_time_mean_minutes AS travel_time
          FROM matrix
          INNER JOIN origins ON matrix.origin_h3 = origins.id
          INNER JOIN destinations ON matrix.destination_h3 = destinations.id
          WHERE matrix.h3_resolution = ?
            AND matrix.samples_observed = matrix.samples_requested
            AND matrix.travel_time_mean_minutes <= ?
          ORDER BY from_id, to_id
        ) TO '{output_path}' (FORMAT CSV, HEADER TRUE, DELIMITER ',')
        """,
        [
            cfg.get("h3_resolution", 8),
            cfg.get("maximum_minutes", 60),
        ],
    )


if __name__ == "__main__":
    main(sys.argv[1])
