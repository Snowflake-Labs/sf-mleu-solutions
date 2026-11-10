-- =============================================================================
-- Optional: use Snowflake Public Data (Free) for the macro indicators
-- =============================================================================
-- By default the CHP_OPS.MACRO_* views read the synthetic monthly series in
-- CHP_ATOMIC.MACRO_INDICATOR. This script re-points them to public US CPI and
-- industrial-production series from the free "Snowflake Public Data (Free)"
-- Marketplace listing.
--
-- Before running:
--   1. In Snowsight, open Data Products > Marketplace, find "Snowflake Public Data (Free)"
--      and select Get. Keep the default database name SNOWFLAKE_PUBLIC_DATA_FREE, or
--      replace it below. Review the listing's terms before using the data.
--   2. Run: snow sql -f marketplace/use_public_data.sql --enable-templating NONE
--   3. Re-run the ML pipeline: CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();
--
-- To switch back to the synthetic series, re-run ddl/core/005_CHEMICAL_OPS_MART.sql.
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

-- Fails here, before changing anything, if the listing is not installed
SELECT COUNT(*) AS public_rows
FROM SNOWFLAKE_PUBLIC_DATA_FREE.PUBLIC_DATA_FREE.FINANCIAL_ECONOMIC_INDICATORS_TIMESERIES
WHERE VARIABLE = 'CUSRSEHE01E011982-84.M';

CREATE OR REPLACE VIEW CHP_OPS.MACRO_FUEL_OIL_CPI AS
SELECT
    date AS price_date,
    'FUEL_OIL_CPI' AS index_code,
    value AS index_value,
    unit,
    'SNOWFLAKE_PUBLIC_DATA_FREE' AS data_source
FROM SNOWFLAKE_PUBLIC_DATA_FREE.PUBLIC_DATA_FREE.FINANCIAL_ECONOMIC_INDICATORS_TIMESERIES
WHERE variable = 'CUSRSEHE01E011982-84.M'
  AND date >= DATEADD(YEAR, -3, CURRENT_DATE());

CREATE OR REPLACE VIEW CHP_OPS.MACRO_CORE_CPI AS
SELECT
    date AS price_date,
    'CORE_CPI' AS index_code,
    value AS index_value,
    unit,
    'SNOWFLAKE_PUBLIC_DATA_FREE' AS data_source
FROM SNOWFLAKE_PUBLIC_DATA_FREE.PUBLIC_DATA_FREE.FINANCIAL_ECONOMIC_INDICATORS_TIMESERIES
WHERE variable = 'CUSRSA0L1EL1E1982-84.M'
  AND date >= DATEADD(YEAR, -3, CURRENT_DATE());

CREATE OR REPLACE VIEW CHP_OPS.MACRO_INDUSTRIAL_PRODUCTION AS
SELECT
    date AS price_date,
    'INDUSTRIAL_PRODUCTION' AS index_code,
    value AS index_value,
    unit,
    'SNOWFLAKE_PUBLIC_DATA_FREE' AS data_source
FROM SNOWFLAKE_PUBLIC_DATA_FREE.PUBLIC_DATA_FREE.FINANCIAL_ECONOMIC_INDICATORS_TIMESERIES
WHERE variable = 'G17_IP.N32411D.S_SA'  -- Industrial Production: Distillate fuel oil (SA)
  AND date >= DATEADD(YEAR, -3, CURRENT_DATE());

SELECT index_code, data_source, COUNT(*) AS months, MIN(price_date) AS first_month, MAX(price_date) AS last_month
FROM CHP_OPS.MACRO_ECONOMIC_INDICATORS
GROUP BY index_code, data_source
ORDER BY index_code;
