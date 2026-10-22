-- =============================================================================
-- Solution: Customer Quality Command (CQC) - teardown
-- Drops the CQC schemas and the optional app add-on objects.
-- Never drops the shared SF_SOLUTIONS database or SF_SOLUTIONS_WH warehouse.
-- Idempotent: safe to run more than once.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
USE DATABASE SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Optional app add-on (app/setup_app.sql, app/create_service.sql)
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CQC_ML;
DROP SERVICE IF EXISTS SF_SOLUTIONS.CQC_ML.CQC_APP_SERVICE;
DROP COMPUTE POOL IF EXISTS SF_SOLUTIONS_CQC_POOL;

-- Solution schemas (includes models, tasks, search services, semantic view and agent)
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_RAW;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_STAGING;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_ATOMIC;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_FEATURE_STORE;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_ML;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_ANALYTICS;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_INSIGHTS;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_ACTION;
DROP SCHEMA IF EXISTS SF_SOLUTIONS.CQC_DOCS;

SELECT 'CQC teardown complete' AS STATUS;
