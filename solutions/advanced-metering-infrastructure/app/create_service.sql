-- =============================================================================
-- Solution: Advanced Metering Infrastructure (AMI 2.0) - optional dashboard (SPCS)
-- Step 2 of 2: run after app/setup_app.sql and after pushing the image to
-- SF_SOLUTIONS.AMI_MART.AMI_REPO (see app/README.md).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE SERVICE IF NOT EXISTS SF_SOLUTIONS.AMI_MART.AMI_DASHBOARD_SVC
  IN COMPUTE POOL SF_SOLUTIONS_AMI_POOL
  FROM SPECIFICATION $$
spec:
  containers:
  - name: ami-dashboard
    image: /sf_solutions/ami_mart/ami_repo/ami-dashboard:latest
    env:
      HOSTNAME: "0.0.0.0"
      PORT: "8080"
      NODE_ENV: production
      SNOWFLAKE_WAREHOUSE: SF_SOLUTIONS_WH
    resources:
      requests:
        memory: 512Mi
        cpu: 250m
      limits:
        memory: 1Gi
        cpu: 500m
    readinessProbe:
      port: 8080
      path: /api/ingestion/kpi
  endpoints:
  - name: ami-ui
    port: 8080
    public: true
$$
  EXTERNAL_ACCESS_INTEGRATIONS = (SF_SOLUTIONS_AMI_TILES_EAI)
  QUERY_WAREHOUSE = SF_SOLUTIONS_WH
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1;

-- Dashboard URL (endpoint provisioning can take a few minutes)
SHOW ENDPOINTS IN SERVICE SF_SOLUTIONS.AMI_MART.AMI_DASHBOARD_SVC;
