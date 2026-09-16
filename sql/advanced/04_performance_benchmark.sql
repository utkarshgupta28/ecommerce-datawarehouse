USE DATABASE ecommerce_dw;

CREATE SCHEMA IF NOT EXISTS reporting;

CREATE TABLE IF NOT EXISTS reporting.query_benchmark_results (
    benchmark_run_id VARCHAR NOT NULL,
    benchmark_name VARCHAR NOT NULL,
    query_variant VARCHAR NOT NULL,
    query_id VARCHAR NOT NULL,
    warehouse_name VARCHAR,
    warehouse_size VARCHAR,
    total_elapsed_ms NUMBER,
    execution_ms NUMBER,
    compilation_ms NUMBER,
    bytes_scanned NUMBER,
    rows_produced NUMBER,
    recorded_at TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- Disable result-cache reuse so the baseline and mart query are comparable.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SET benchmark_run_id = UUID_STRING();

-- Baseline: repeat dimensional joins and aggregation at report runtime.
ALTER SESSION SET QUERY_TAG = 'ecommerce_dw_monthly_sales_baseline';
SELECT
    DATE_TRUNC('MONTH', fs.date)::DATE AS sales_month,
    COALESCE(sc.sales_channel, 'Unknown') AS sales_channel,
    COALESCE(df.fulfillment, 'Unknown') AS fulfillment,
    COUNT(DISTINCT fs.orderid) AS total_orders,
    SUM(COALESCE(fs.qty, 0)) AS units_sold,
    ROUND(SUM(COALESCE(fs.amount, 0)), 2) AS revenue,
    ROUND(DIV0(SUM(COALESCE(fs.amount, 0)), COUNT(DISTINCT fs.orderid)), 2)
        AS average_order_value
FROM transformed_data.fact_sales AS fs
LEFT JOIN transformed_data.dim_sales_channel AS sc
    ON fs.channel_key = sc.channel_key
LEFT JOIN transformed_data.dim_fulfillment AS df
    ON fs.fulfillment_key = df.fulfillment_key
WHERE fs.date IS NOT NULL
  AND COALESCE(fs.status, '') NOT ILIKE '%cancel%'
GROUP BY sales_month, sales_channel, fulfillment
ORDER BY sales_month, sales_channel, fulfillment;
SET baseline_query_id = LAST_QUERY_ID();

-- Optimized: query the incrementally refreshed, Power BI-facing mart.
ALTER SESSION SET QUERY_TAG = 'ecommerce_dw_monthly_sales_optimized';
SELECT
    sales_month,
    sales_channel,
    fulfillment,
    total_orders,
    units_sold,
    revenue,
    average_order_value
FROM reporting.mart_monthly_sales
ORDER BY sales_month, sales_channel, fulfillment;
SET optimized_query_id = LAST_QUERY_ID();

INSERT INTO reporting.query_benchmark_results (
    benchmark_run_id,
    benchmark_name,
    query_variant,
    query_id,
    warehouse_name,
    warehouse_size,
    total_elapsed_ms,
    execution_ms,
    compilation_ms,
    bytes_scanned,
    rows_produced
)
SELECT
    $benchmark_run_id,
    'monthly_sales_power_bi',
    IFF(query_id = $baseline_query_id, 'BASELINE', 'OPTIMIZED'),
    query_id,
    warehouse_name,
    warehouse_size,
    total_elapsed_time,
    execution_time,
    compilation_time,
    bytes_scanned,
    rows_produced
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        END_TIME_RANGE_START => DATEADD('MINUTE', -10, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 100
    )
)
WHERE query_id IN ($baseline_query_id, $optimized_query_id);

-- Produces the before/after numbers that can be cited in documentation.
WITH latest_run AS (
    SELECT *
    FROM reporting.query_benchmark_results
    WHERE benchmark_run_id = $benchmark_run_id
),
pivoted AS (
    SELECT
        MAX(IFF(query_variant = 'BASELINE', total_elapsed_ms, NULL)) AS baseline_elapsed_ms,
        MAX(IFF(query_variant = 'OPTIMIZED', total_elapsed_ms, NULL)) AS optimized_elapsed_ms,
        MAX(IFF(query_variant = 'BASELINE', bytes_scanned, NULL)) AS baseline_bytes_scanned,
        MAX(IFF(query_variant = 'OPTIMIZED', bytes_scanned, NULL)) AS optimized_bytes_scanned
    FROM latest_run
)
SELECT
    $benchmark_run_id AS benchmark_run_id,
    baseline_elapsed_ms,
    optimized_elapsed_ms,
    ROUND(
        DIV0(baseline_elapsed_ms - optimized_elapsed_ms, baseline_elapsed_ms) * 100,
        2
    ) AS elapsed_time_reduction_pct,
    baseline_bytes_scanned,
    optimized_bytes_scanned,
    ROUND(
        DIV0(baseline_bytes_scanned - optimized_bytes_scanned, baseline_bytes_scanned) * 100,
        2
    ) AS bytes_scanned_reduction_pct
FROM pivoted;

ALTER SESSION UNSET QUERY_TAG;
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
