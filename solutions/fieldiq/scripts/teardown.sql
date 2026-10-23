-- =============================================================================
-- Solution: FieldIQ - teardown
-- Drops the FIQ schemas and the optional web-app and voice add-on objects.
-- Never drops the shared SF_SOLUTIONS database or SF_SOLUTIONS_WH warehouse.
-- Idempotent: safe to run more than once.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
USE DATABASE SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Optional add-ons (app/setup_app.sql, app/setup_voice.sql)
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.FIQ_CORTEX;
DROP SERVICE IF EXISTS SF_SOLUTIONS.FIQ_CORTEX.FIQ_APP_SERVICE;
DROP SERVICE IF EXISTS SF_SOLUTIONS.FIQ_CORTEX.FIQ_VOICE_SERVICE;
DROP COMPUTE POOL IF EXISTS SF_SOLUTIONS_FIQ_APP_POOL;
DROP COMPUTE POOL IF EXISTS SF_SOLUTIONS_FIQ_VOICE_POOL;

-- Solution schemas (includes procedures, stages, search service, semantic view and agent)
DROP SCHEMA IF EXISTS SF_SOLUTIONS.FIQ_ATOMIC;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.FIQ_ANALYTICS;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.FIQ_CORTEX;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.FIQ_ACTIONS;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.FIQ_STAGES;

SELECT 'FieldIQ teardown complete' AS STATUS;
