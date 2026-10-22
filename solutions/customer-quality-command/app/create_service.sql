-- =============================================================================
-- Solution: Customer Quality Command (CQC) - optional app add-on (SPCS)
-- Step 2 of 2: run after app/setup_app.sql and after pushing the image to
-- SF_SOLUTIONS.CQC_ML.CQC_IMAGES (see app/README.md).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE SERVICE IF NOT EXISTS SF_SOLUTIONS.CQC_ML.CQC_APP_SERVICE
  IN COMPUTE POOL SF_SOLUTIONS_CQC_POOL
  FROM SPECIFICATION $$
spec:
  containers:
    - name: cqc
      image: /sf_solutions/cqc_ml/cqc_images/cqc:latest
      env:
        SNOWFLAKE_DATABASE: SF_SOLUTIONS
        SNOWFLAKE_WAREHOUSE: SF_SOLUTIONS_WH
        SCHEMA_PREFIX: CQC_
        SCHEMA_SUFFIX: ''
        CORTEX_AGENT_SCHEMA: CQC_ML
        CORTEX_AGENT_NAME: CUSTOMER_QUALITY_AGENT
        REVIEW_BOARD_MODEL: claude-sonnet-4-6
        LOG_LEVEL: INFO
      resources:
        requests: { memory: 2Gi, cpu: 1 }
        limits: { memory: 4Gi, cpu: 1 }
      readinessProbe:
        port: 8080
        path: /health
  endpoints:
    - name: cqc-endpoint
      port: 8080
      public: true
$$
  QUERY_WAREHOUSE = SF_SOLUTIONS_WH
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1;

-- App URL (endpoint provisioning can take a few minutes)
SHOW ENDPOINTS IN SERVICE SF_SOLUTIONS.CQC_ML.CQC_APP_SERVICE;
