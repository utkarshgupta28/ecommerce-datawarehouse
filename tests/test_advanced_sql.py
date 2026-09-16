from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql" / "advanced"


def read_sql(filename: str) -> str:
    return (SQL_DIR / filename).read_text(encoding="utf-8").upper()


class AdvancedSqlContractTests(unittest.TestCase):
    def test_reporting_views_cover_advanced_sql_constructs(self) -> None:
        sql = read_sql("01_reporting_views.sql")
        expected = {
            "CREATE OR REPLACE VIEW REPORTING.VW_MONTHLY_SALES_PERFORMANCE",
            "CREATE OR REPLACE VIEW REPORTING.VW_PRODUCT_PERFORMANCE",
            "CREATE OR REPLACE VIEW REPORTING.VW_CUSTOMER_VALUE",
            "WITH VALID_SALES AS",
            "LAG(REVENUE) OVER",
            "DENSE_RANK() OVER",
            "NTILE(5) OVER",
            "PERCENT_RANK() OVER",
        }
        for token in expected:
            self.assertIn(token, sql)

    def test_refresh_procedure_is_auditable_and_incremental(self) -> None:
        sql = read_sql("02_refresh_procedure.sql")
        expected = {
            "CREATE OR REPLACE PROCEDURE REPORTING.SP_REFRESH_MONTHLY_SALES",
            "DEFAULT 90",
            "MERGE INTO REPORTING.MART_MONTHLY_SALES",
            "WHEN MATCHED THEN UPDATE",
            "WHEN NOT MATCHED THEN INSERT",
            "V_ROWS_AFFECTED := SQLROWCOUNT",
            "V_MERGE_QUERY_ID := SQLID",
            "STATUS = 'SUCCEEDED'",
            "STATUS = 'FAILED'",
            "RAISE;",
        }
        for token in expected:
            self.assertIn(token, sql)

    def test_quality_checks_cover_required_failure_modes(self) -> None:
        sql = read_sql("03_data_quality_checks.sql")
        for token in (
            "FACT_SALES_REQUIRED_FIELDS",
            "FACT_SALES_NONNEGATIVE_AMOUNT",
            "FACT_SALES_CHANNEL_FK",
            "FACT_ECOMM_USER_FK",
            "FACT_ECOMM_PRODUCT_FK",
            "FACT_ECOMM_PAYMENT_FK",
            "QUALIFY DUPLICATE_SEQUENCE > 1",
        ):
            self.assertIn(token, sql)

    def test_benchmark_uses_uncached_same_session_query_history(self) -> None:
        sql = read_sql("04_performance_benchmark.sql")
        expected = {
            "USE_CACHED_RESULT = FALSE",
            "ECOMMERCE_DW_MONTHLY_SALES_BASELINE",
            "ECOMMERCE_DW_MONTHLY_SALES_OPTIMIZED",
            "QUERY_HISTORY_BY_SESSION",
            "TOTAL_ELAPSED_TIME",
            "BYTES_SCANNED",
            "ELAPSED_TIME_REDUCTION_PCT",
            "BYTES_SCANNED_REDUCTION_PCT",
        }
        for token in expected:
            self.assertIn(token, sql)
        self.assertNotIn("PARTITIONS_SCANNED", sql)

    def test_package_contains_no_placeholders(self) -> None:
        combined = "\n".join(path.read_text(encoding="utf-8") for path in SQL_DIR.glob("*.sql"))
        for token in ("TODO", "PLACEHOLDER", "REPLACE_ME"):
            self.assertNotIn(token, combined.upper())


if __name__ == "__main__":
    unittest.main()

