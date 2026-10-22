-- =============================================================================
-- Solution: Advanced Metering Infrastructure (AMI 2.0) - optional dashboard (SPCS)
-- Not available on trial accounts (compute pools / external access integrations).
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

-- 1. Image repository for the dashboard image
CREATE IMAGE REPOSITORY IF NOT EXISTS SF_SOLUTIONS.AMI_MART.AMI_REPO;
SHOW IMAGE REPOSITORIES IN SCHEMA SF_SOLUTIONS.AMI_MART;

-- 2. Compute pool
CREATE COMPUTE POOL IF NOT EXISTS SF_SOLUTIONS_AMI_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_SUSPEND_SECS = 3600
  COMMENT = 'AMI 2.0 dashboard';

-- 3. Map tiles: the viewer's browser loads OpenStreetMap tiles; SPCS only allows
--    browser-loaded hosts that are in the service's external access integration.
CREATE OR REPLACE NETWORK RULE SF_SOLUTIONS.AMI_MART.AMI_MAP_TILES_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('tile.openstreetmap.org:443');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION SF_SOLUTIONS_AMI_TILES_EAI
  ALLOWED_NETWORK_RULES = (SF_SOLUTIONS.AMI_MART.AMI_MAP_TILES_RULE)
  ENABLED = TRUE;
