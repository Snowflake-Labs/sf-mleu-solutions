-- =============================================================================
-- Solution: Chemicals Pricing & Margin Intelligence - teardown
-- Drops the CHP schemas (tables, views, procedures, stages, semantic view, search
-- service, agent and Streamlit app). Never drops the shared SF_SOLUTIONS database or
-- SF_SOLUTIONS_WH warehouse. Idempotent: safe to run more than once.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed by the terms in
-- LICENSE, unless expressly agreed to in writing. You use this application at your own
-- risk, and Snowflake has no obligation to support your use of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

DROP SCHEMA IF EXISTS SF_SOLUTIONS.CHP_OPS;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CHP_ATOMIC;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CHP_RAW;

SELECT 'Chemicals Pricing teardown complete' AS STATUS;
