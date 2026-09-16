# Advanced SQL reporting layer

This package adds production-style SQL evidence to the existing Snowflake warehouse without changing the raw or transformed schemas.

Run the dependency-free contract tests before deployment:

```bash
python -m unittest tests/test_advanced_sql.py
```

The same tests run automatically in GitHub Actions whenever the advanced SQL package changes.

## What is included

- `01_reporting_views.sql`: Three reusable reporting views using CTEs, dimensional joins, conditional aggregation, `LAG`, running totals, ranking, `NTILE`, `PERCENT_RANK`, and `QUALIFY`.
- `02_refresh_procedure.sql`: An incremental SQL stored procedure that refreshes a Power BI-facing mart, validates required fields, writes an audit log, captures the merge query ID, and rolls back failures.
- `03_data_quality_checks.sql`: Referential-integrity, required-field, negative-value, and duplicate checks exposed through monitorable views.
- `04_performance_benchmark.sql`: A cold-cache baseline-versus-mart benchmark that records Snowflake query-history metrics, including elapsed time, bytes scanned, compilation time, execution time, and rows produced.

## Deployment order

Run these files in order with a role that can create objects in `ECOMMERCE_DW`:

```sql
-- 1. Create the reporting views.
!source sql/advanced/01_reporting_views.sql

-- 2. Create the mart, audit table, and stored procedure.
!source sql/advanced/02_refresh_procedure.sql

-- 3. Create the data-quality monitoring views.
!source sql/advanced/03_data_quality_checks.sql

-- 4. Populate the mart.
CALL reporting.sp_refresh_monthly_sales(3650);

-- 5. Confirm that no ERROR-level checks fail.
SELECT *
FROM reporting.vw_data_quality_results
WHERE test_status = 'FAIL';

-- 6. Run and record the benchmark.
!source sql/advanced/04_performance_benchmark.sql
```

`!source` is a SnowSQL command. In Snowsight, open each file and run its statements in the same order.

## Benchmark integrity

The benchmark disables result-cache reuse, executes the baseline and optimized queries in the same session and warehouse, captures both query IDs, and persists the corresponding query-history metrics. Run it at least three times on the same warehouse size and report the median result.

Do not put an optimization percentage on a resume until the recorded rows in `reporting.query_benchmark_results` support it.

Use this query to summarize multiple runs:

```sql
WITH paired_runs AS (
    SELECT
        benchmark_run_id,
        MAX(IFF(query_variant = 'BASELINE', total_elapsed_ms, NULL)) AS baseline_ms,
        MAX(IFF(query_variant = 'OPTIMIZED', total_elapsed_ms, NULL)) AS optimized_ms,
        MAX(IFF(query_variant = 'BASELINE', bytes_scanned, NULL)) AS baseline_bytes,
        MAX(IFF(query_variant = 'OPTIMIZED', bytes_scanned, NULL)) AS optimized_bytes
    FROM reporting.query_benchmark_results
    WHERE benchmark_name = 'monthly_sales_power_bi'
    GROUP BY benchmark_run_id
)
SELECT
    MEDIAN(DIV0(baseline_ms - optimized_ms, baseline_ms) * 100)
        AS median_elapsed_time_reduction_pct,
    MEDIAN(DIV0(baseline_bytes - optimized_bytes, baseline_bytes) * 100)
        AS median_bytes_scanned_reduction_pct
FROM paired_runs;
```

## Resume evidence after execution

The code itself supports claims about complex views, a SQL stored procedure, window functions, incremental `MERGE`, audit logging, data-quality validation, and a repeatable performance benchmark. Only add measured performance numbers after the benchmark has been run in Snowflake and the results have been reviewed.
