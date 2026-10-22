-- =============================================================================
-- Solution: Customer Quality Command (CQC) - optional app add-on (SPCS)
-- Not available on trial accounts (compute pools).
-- Step 1 of 2: run after scripts/pipeline.sql. Then build and push the image
-- (see app/README.md) and run app/create_service.sql.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- 1. Image repository for the app image
CREATE IMAGE REPOSITORY IF NOT EXISTS SF_SOLUTIONS.CQC_ML.CQC_IMAGES;
SHOW IMAGE REPOSITORIES IN SCHEMA SF_SOLUTIONS.CQC_ML;

-- 2. Compute pool (single small CPU node)
CREATE COMPUTE POOL IF NOT EXISTS SF_SOLUTIONS_CQC_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_RESUME = TRUE
  AUTO_SUSPEND_SECS = 3600
  COMMENT = 'Customer Quality Command app';
