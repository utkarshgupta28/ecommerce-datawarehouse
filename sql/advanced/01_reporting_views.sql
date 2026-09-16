USE DATABASE ecommerce_dw;

CREATE SCHEMA IF NOT EXISTS reporting;

-- Power BI-ready monthly performance view.
-- Demonstrates reusable CTEs, dimensional joins, conditional aggregation,
-- LAG, running totals, ranking, and safe division.
CREATE OR REPLACE VIEW reporting.vw_monthly_sales_performance AS
WITH valid_sales AS (
    SELECT
        DATE_TRUNC('MONTH', fs.date)::DATE AS sales_month,
        COALESCE(sc.sales_channel, 'Unknown') AS sales_channel,
        COALESCE(df.fulfillment, 'Unknown') AS fulfillment,
        fs.orderid,
        COALESCE(fs.qty, 0) AS quantity,
        COALESCE(fs.amount, 0) AS amount
    FROM transformed_data.fact_sales AS fs
    LEFT JOIN transformed_data.dim_sales_channel AS sc
        ON fs.channel_key = sc.channel_key
    LEFT JOIN transformed_data.dim_fulfillment AS df
        ON fs.fulfillment_key = df.fulfillment_key
    WHERE fs.date IS NOT NULL
      AND COALESCE(fs.status, '') NOT ILIKE '%cancel%'
),
monthly_rollup AS (
    SELECT
        sales_month,
        sales_channel,
        fulfillment,
        COUNT(DISTINCT orderid) AS total_orders,
        SUM(quantity) AS units_sold,
        ROUND(SUM(amount), 2) AS revenue,
        ROUND(DIV0(SUM(amount), COUNT(DISTINCT orderid)), 2) AS average_order_value
    FROM valid_sales
    GROUP BY sales_month, sales_channel, fulfillment
),
windowed_metrics AS (
    SELECT
        monthly_rollup.*,
        LAG(revenue) OVER (
            PARTITION BY sales_channel, fulfillment
            ORDER BY sales_month
        ) AS prior_month_revenue,
        SUM(revenue) OVER (
            PARTITION BY sales_channel, fulfillment
            ORDER BY sales_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_revenue,
        DENSE_RANK() OVER (
            PARTITION BY sales_month
            ORDER BY revenue DESC
        ) AS monthly_segment_rank
    FROM monthly_rollup
)
SELECT
    sales_month,
    sales_channel,
    fulfillment,
    total_orders,
    units_sold,
    revenue,
    average_order_value,
    prior_month_revenue,
    ROUND(DIV0(revenue - prior_month_revenue, prior_month_revenue) * 100, 2)
        AS month_over_month_revenue_pct,
    running_revenue,
    monthly_segment_rank
FROM windowed_metrics;


-- Product view pre-aggregates sales and reviews separately to prevent fanout.
CREATE OR REPLACE VIEW reporting.vw_product_performance AS
WITH product_sales AS (
    SELECT
        product_key,
        COUNT(*) AS order_lines,
        COUNT(DISTINCT user_key) AS unique_customers,
        ROUND(SUM(final_price), 2) AS revenue,
        ROUND(AVG(final_price), 2) AS average_selling_price,
        ROUND(AVG(discount), 2) AS average_discount
    FROM transformed_data.fact_ecomm_sales
    GROUP BY product_key
),
product_reviews AS (
    SELECT
        product_key,
        COUNT(*) AS review_count,
        ROUND(AVG(score), 2) AS average_rating,
        ROUND(
            DIV0(
                SUM(helpfulnessnumerator),
                NULLIF(SUM(helpfulnessdenominator), 0)
            ) * 100,
            2
        ) AS helpful_vote_pct
    FROM transformed_data.fact_reviews
    WHERE score IS NOT NULL
    GROUP BY product_key
),
combined AS (
    SELECT
        dp.product_id,
        dp.category,
        COALESCE(ps.order_lines, 0) AS order_lines,
        COALESCE(ps.unique_customers, 0) AS unique_customers,
        COALESCE(ps.revenue, 0) AS revenue,
        ps.average_selling_price,
        ps.average_discount,
        COALESCE(pr.review_count, 0) AS review_count,
        pr.average_rating,
        pr.helpful_vote_pct
    FROM transformed_data.dim_products AS dp
    LEFT JOIN product_sales AS ps
        ON dp.product_key = ps.product_key
    LEFT JOIN product_reviews AS pr
        ON dp.product_key = pr.product_key
)
SELECT
    combined.*,
    ROUND(DIV0(revenue, SUM(revenue) OVER ()) * 100, 2) AS revenue_share_pct,
    DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
    DENSE_RANK() OVER (
        PARTITION BY category
        ORDER BY revenue DESC
    ) AS category_revenue_rank
FROM combined;


-- Customer-value view provides an auditable RFM-style segmentation layer.
CREATE OR REPLACE VIEW reporting.vw_customer_value AS
WITH customer_rollup AS (
    SELECT
        du.user_id,
        MIN(fes.purchase_date) AS first_purchase_date,
        MAX(fes.purchase_date) AS most_recent_purchase_date,
        COUNT(*) AS purchase_count,
        COUNT(DISTINCT fes.product_key) AS distinct_products,
        ROUND(SUM(fes.final_price), 2) AS lifetime_value,
        ROUND(AVG(fes.final_price), 2) AS average_purchase_value
    FROM transformed_data.fact_ecomm_sales AS fes
    INNER JOIN transformed_data.dim_users AS du
        ON fes.user_key = du.user_key
    GROUP BY du.user_id
)
SELECT
    customer_rollup.*,
    DATEDIFF('DAY', most_recent_purchase_date, CURRENT_DATE()) AS recency_days,
    DATEDIFF('DAY', first_purchase_date, most_recent_purchase_date) AS customer_tenure_days,
    NTILE(5) OVER (ORDER BY lifetime_value) AS value_quintile,
    NTILE(5) OVER (ORDER BY most_recent_purchase_date) AS recency_quintile,
    PERCENT_RANK() OVER (ORDER BY lifetime_value) AS lifetime_value_percentile
FROM customer_rollup;

