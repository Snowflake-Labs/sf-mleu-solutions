-- =============================================================================
-- Solution: FieldIQ - optional web app add-on (SPCS)
-- Step 2 of 2: run after app/setup_app.sql and after pushing the image to
-- SF_SOLUTIONS.FIQ_CORTEX.FIQ_IMAGES (see app/README.md).
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE SERVICE IF NOT EXISTS SF_SOLUTIONS.FIQ_CORTEX.FIQ_APP_SERVICE
  IN COMPUTE POOL SF_SOLUTIONS_FIQ_APP_POOL
  FROM SPECIFICATION $$
spec:
  containers:
    - name: fieldiq
      image: /sf_solutions/fiq_cortex/fiq_images/fieldiq:latest
      env:
        SNOWFLAKE_DATABASE: SF_SOLUTIONS
        SNOWFLAKE_WAREHOUSE: SF_SOLUTIONS_WH
        SNOWFLAKE_AGENT_SCHEMA: FIQ_CORTEX
        SNOWFLAKE_AGENT_NAME: FIELDIQ_AGENT
        LOG_LEVEL: INFO
      readinessProbe:
        port: 8080
        path: /health
      resources:
        requests:
          memory: 2Gi
          cpu: 1
        limits:
          memory: 4Gi
          cpu: 1
  endpoints:
    - name: fieldiq
      port: 8080
      public: true
$$
  QUERY_WAREHOUSE = SF_SOLUTIONS_WH
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1;

-- App URL (endpoint provisioning can take a few minutes)
SHOW ENDPOINTS IN SERVICE SF_SOLUTIONS.FIQ_CORTEX.FIQ_APP_SERVICE;
