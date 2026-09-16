USE DATABASE ecommerce_dw;

CREATE SCHEMA IF NOT EXISTS reporting;

CREATE TABLE IF NOT EXISTS reporting.mart_monthly_sales (
    sales_month DATE NOT NULL,
    sales_channel VARCHAR NOT NULL,
    fulfillment VARCHAR NOT NULL,
    total_orders NUMBER NOT NULL,
    units_sold NUMBER NOT NULL,
    revenue NUMBER(38, 2) NOT NULL,
    average_order_value NUMBER(38, 2) NOT NULL,
    prior_month_revenue NUMBER(38, 2),
    month_over_month_revenue_pct NUMBER(18, 2),
    running_revenue NUMBER(38, 2),
    monthly_segment_rank NUMBER,
    refreshed_at TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT uq_mart_monthly_sales UNIQUE (sales_month, sales_channel, fulfillment)
);

CREATE TABLE IF NOT EXISTS reporting.etl_run_log (
    run_id VARCHAR NOT NULL,
    procedure_name VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    started_at TIMESTAMP_LTZ NOT NULL,
    completed_at TIMESTAMP_LTZ,
    cutoff_date DATE,
    source_rows NUMBER,
    invalid_rows NUMBER,
    rows_affected NUMBER,
    merge_query_id VARCHAR,
    error_code VARCHAR,
    error_message VARCHAR
);

-- Incrementally refreshes the Power BI-facing mart and records each run.
-- Call with CALL reporting.sp_refresh_monthly_sales(90);
CREATE OR REPLACE PROCEDURE reporting.sp_refresh_monthly_sales(
    p_lookback_days INTEGER DEFAULT 90
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_run_id VARCHAR DEFAULT UUID_STRING();
    v_started_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP();
    v_cutoff_date DATE DEFAULT DATEADD('DAY', -p_lookback_days, CURRENT_DATE());
    v_source_rows NUMBER DEFAULT 0;
    v_invalid_rows NUMBER DEFAULT 0;
    v_rows_affected NUMBER DEFAULT 0;
    v_merge_query_id VARCHAR;
    e_data_quality EXCEPTION (-20001, 'Required sales fields failed validation.');
BEGIN
    INSERT INTO reporting.etl_run_log (
        run_id,
        procedure_name,
        status,
        started_at,
        cutoff_date
    )
    SELECT
        :v_run_id,
        'reporting.sp_refresh_monthly_sales',
        'STARTED',
        :v_started_at,
        :v_cutoff_date;

    SELECT
        COUNT(*),
        COUNT_IF(
            fs.orderid IS NULL
            OR fs.date IS NULL
            OR fs.amount IS NULL
            OR fs.amount < 0
        )
    INTO :v_source_rows, :v_invalid_rows
    FROM transformed_data.fact_sales AS fs
    WHERE fs.date >= :v_cutoff_date;

    IF (v_invalid_rows > 0) THEN
        RAISE e_data_quality;
    END IF;

    MERGE INTO reporting.mart_monthly_sales AS target
    USING (
        SELECT
            sales_month,
            sales_channel,
            fulfillment,
            total_orders,
            units_sold,
            revenue,
            average_order_value,
            prior_month_revenue,
            month_over_month_revenue_pct,
            running_revenue,
            monthly_segment_rank
        FROM reporting.vw_monthly_sales_performance
        WHERE sales_month >= DATE_TRUNC('MONTH', :v_cutoff_date)::DATE
    ) AS source
        ON target.sales_month = source.sales_month
       AND target.sales_channel = source.sales_channel
       AND target.fulfillment = source.fulfillment
    WHEN MATCHED THEN UPDATE SET
        target.total_orders = source.total_orders,
        target.units_sold = source.units_sold,
        target.revenue = source.revenue,
        target.average_order_value = source.average_order_value,
        target.prior_month_revenue = source.prior_month_revenue,
        target.month_over_month_revenue_pct = source.month_over_month_revenue_pct,
        target.running_revenue = source.running_revenue,
        target.monthly_segment_rank = source.monthly_segment_rank,
        target.refreshed_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        sales_month,
        sales_channel,
        fulfillment,
        total_orders,
        units_sold,
        revenue,
        average_order_value,
        prior_month_revenue,
        month_over_month_revenue_pct,
        running_revenue,
        monthly_segment_rank,
        refreshed_at
    ) VALUES (
        source.sales_month,
        source.sales_channel,
        source.fulfillment,
        source.total_orders,
        source.units_sold,
        source.revenue,
        source.average_order_value,
        source.prior_month_revenue,
        source.month_over_month_revenue_pct,
        source.running_revenue,
        source.monthly_segment_rank,
        CURRENT_TIMESTAMP()
    );

    v_rows_affected := SQLROWCOUNT;
    v_merge_query_id := SQLID;

    UPDATE reporting.etl_run_log
    SET
        status = 'SUCCEEDED',
        completed_at = CURRENT_TIMESTAMP(),
        source_rows = :v_source_rows,
        invalid_rows = :v_invalid_rows,
        rows_affected = :v_rows_affected,
        merge_query_id = :v_merge_query_id
    WHERE run_id = :v_run_id;

    RETURN OBJECT_CONSTRUCT(
        'run_id', v_run_id,
        'status', 'SUCCEEDED',
        'cutoff_date', v_cutoff_date,
        'source_rows', v_source_rows,
        'rows_affected', v_rows_affected,
        'merge_query_id', v_merge_query_id
    );

EXCEPTION
    WHEN OTHER THEN
        UPDATE reporting.etl_run_log
        SET
            status = 'FAILED',
            completed_at = CURRENT_TIMESTAMP(),
            source_rows = :v_source_rows,
            invalid_rows = :v_invalid_rows,
            error_code = :sqlstate,
            error_message = :sqlerrm
        WHERE run_id = :v_run_id;

        RAISE;
END;
$$;
