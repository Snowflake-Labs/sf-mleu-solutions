-- =============================================================================
-- Solution: FieldIQ - data
-- Database: SF_SOLUTIONS
-- Schemas:  FIQ_ATOMIC, FIQ_ANALYTICS, FIQ_CORTEX, FIQ_ACTIONS, FIQ_STAGES
-- Generates the synthetic CRM/ERP data, 262 engineering documents and the search chunks.
-- Run after setup.sql. Approx. 3-5 min on a LARGE warehouse.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

CALL SF_SOLUTIONS.FIQ_ATOMIC.SP_GENERATE_DATA();

SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('FIQ_ATOMIC', 'FIQ_CORTEX') AND TABLE_TYPE = 'BASE TABLE'
ORDER BY 1, 2;

ALTER STAGE SF_SOLUTIONS.FIQ_STAGES.DOCS REFRESH;
SELECT COUNT(*) AS STAGED_DOCUMENTS FROM DIRECTORY(@SF_SOLUTIONS.FIQ_STAGES.DOCS);

SELECT 'FieldIQ data load complete. Next: run scripts/pipeline.sql' AS STATUS;
