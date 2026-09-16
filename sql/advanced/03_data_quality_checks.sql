USE DATABASE ecommerce_dw;

CREATE SCHEMA IF NOT EXISTS reporting;

-- Centralized test results suitable for monitoring or CI assertions.
CREATE OR REPLACE VIEW reporting.vw_data_quality_results AS
WITH test_results AS (
    SELECT
        'fact_sales_required_fields' AS test_name,
        'ERROR' AS severity,
        COUNT_IF(orderid IS NULL OR date IS NULL OR amount IS NULL) AS failure_count,
        'orderid, date, and amount must be populated' AS test_description
    FROM transformed_data.fact_sales

    UNION ALL

    SELECT
        'fact_sales_nonnegative_amount',
        'ERROR',
        COUNT_IF(amount < 0),
        'sales amount must not be negative'
    FROM transformed_data.fact_sales

    UNION ALL

    SELECT
        'fact_sales_channel_fk',
        'ERROR',
        COUNT_IF(sc.channel_key IS NULL),
        'every fact_sales channel_key must resolve to dim_sales_channel'
    FROM transformed_data.fact_sales AS fs
    LEFT JOIN transformed_data.dim_sales_channel AS sc
        ON fs.channel_key = sc.channel_key

    UNION ALL

    SELECT
        'fact_sales_fulfillment_fk',
        'ERROR',
        COUNT_IF(df.fulfillment_key IS NULL),
        'every fact_sales fulfillment_key must resolve to dim_fulfillment'
    FROM transformed_data.fact_sales AS fs
    LEFT JOIN transformed_data.dim_fulfillment AS df
        ON fs.fulfillment_key = df.fulfillment_key

    UNION ALL

    SELECT
        'fact_ecomm_user_fk',
        'ERROR',
        COUNT_IF(du.user_key IS NULL),
        'every fact_ecomm_sales user_key must resolve to dim_users'
    FROM transformed_data.fact_ecomm_sales AS fes
    LEFT JOIN transformed_data.dim_users AS du
        ON fes.user_key = du.user_key

    UNION ALL

    SELECT
        'fact_ecomm_product_fk',
        'ERROR',
        COUNT_IF(dp.product_key IS NULL),
        'every fact_ecomm_sales product_key must resolve to dim_products'
    FROM transformed_data.fact_ecomm_sales AS fes
    LEFT JOIN transformed_data.dim_products AS dp
        ON fes.product_key = dp.product_key

    UNION ALL

    SELECT
        'fact_ecomm_payment_fk',
        'ERROR',
        COUNT_IF(dpm.payment_key IS NULL),
        'every fact_ecomm_sales payment_key must resolve to dim_payment_methods'
    FROM transformed_data.fact_ecomm_sales AS fes
    LEFT JOIN transformed_data.dim_payment_methods AS dpm
        ON fes.payment_key = dpm.payment_key
)
SELECT
    test_name,
    severity,
    failure_count,
    IFF(failure_count = 0, 'PASS', 'FAIL') AS test_status,
    test_description,
    CURRENT_TIMESTAMP() AS evaluated_at
FROM test_results;


-- Duplicate detector uses a natural-row signature and QUALIFY.
CREATE OR REPLACE VIEW reporting.vw_duplicate_ecomm_rows AS
SELECT
    sales_id,
    user_key,
    product_key,
    payment_key,
    purchase_date,
    final_price,
    ROW_NUMBER() OVER (
        PARTITION BY
            user_key,
            product_key,
            payment_key,
            purchase_date,
            final_price
        ORDER BY sales_id
    ) AS duplicate_sequence
FROM transformed_data.fact_ecomm_sales
QUALIFY duplicate_sequence > 1;


-- A deployment or orchestration job should fail when this returns rows.
SELECT *
FROM reporting.vw_data_quality_results
WHERE test_status = 'FAIL'
ORDER BY severity, test_name;

