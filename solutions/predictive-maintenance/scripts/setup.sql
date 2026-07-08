/*************************************************************************************************/
-- SNOWCORE INDUSTRIES PREDICTIVE MAINTENANCE SETUP
-- Version: 1.0
--
-- PREREQUISITES:
-- This script requires ACCOUNTADMIN role or a role with the following privileges:
--   - CREATE DATABASE, SCHEMA, TABLE, VIEW
--   - CREATE WAREHOUSE
--   - CREATE COMPUTE POOL (for SPCS deployment)
--   - CREATE INTEGRATION (for external access and network rules)
--   - CREATE AGENT (for Snowflake Intelligence)
--   - BIND SERVICE ENDPOINT (account-level permission for SPCS)
--
-- WHAT THIS SCRIPT CREATES:
--   - Database: SF_SOLUTIONS with Bronze, Silver, Gold schemas
--   - Warehouses: SF_SOLUTIONS_WH, SF_SOLUTIONS_STREAMLIT_WH
--   - Compute Pool: SF_SOLUTIONS_STREAMLIT_POOL (for SPCS)
--   - External Access Integration: SF_SOLUTIONS_EAI (for PyPI & APIs)
--   - Sample data: ~160,000+ telemetry records, 12+ months of maintenance history
--   - Semantic View: For natural language queries via Cortex Analyst
--   - Intelligence Agent: PREDICTIVE_MAINTENANCE_ASSISTANT
/*************************************************************************************************/

USE ROLE ACCOUNTADMIN;

-- assign Query Tag to Session. This helps with performance monitoring and troubleshooting
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is",'
    || '"name":"product analytics_snowcore_industries'
    || '_predictive_maintenance_dashboard",'
    || '"version":{"major":1,"minor":0},'
    || '"attributes":{"is_quickstart":1,"source":"sql"}}';

CREATE ROLE IF NOT EXISTS SF_SOLUTIONS_ROLE;

/*************************************************************************************************/
-- SF_SOLUTIONS PREDICTIVE MAINTENANCE DATABASE
-- Description: DDL and sample DML for the Bronze, Silver, and Gold layers.
/*************************************************************************************************/

-- Step 0: Setup Database and Schemas
CREATE OR REPLACE DATABASE SF_SOLUTIONS;


USE DATABASE SF_SOLUTIONS;
USE SCHEMA PUBLIC;

GRANT CREATE TABLE ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE VIEW ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE PROCEDURE ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE FUNCTION ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE SEQUENCE ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE STREAMLIT ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE SEMANTIC VIEW ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
CREATE OR REPLACE SCHEMA MPM_BRONZE COMMENT = 'Schema for raw, unaltered source data';
CREATE OR REPLACE SCHEMA MPM_SILVER COMMENT = 'Schema for cleaned, conformed, and integrated data (Star Schema)';
CREATE OR REPLACE SCHEMA MPM_GOLD COMMENT = 'Schema for business-level aggregates and ML feature stores';

-- Create an event table if it doesn't already exist
CREATE or replace EVENT TABLE SF_SOLUTIONS.PUBLIC.SF_SOLUTIONS_EVENTS;
-- Associate the event table with the account
ALTER ACCOUNT SET EVENT_TABLE = SF_SOLUTIONS.PUBLIC.SF_SOLUTIONS_EVENTS;

-- Set the log level for the database containing your app
ALTER DATABASE SF_SOLUTIONS SET LOG_LEVEL = INFO;

-- Set the trace level for the database containing your app
ALTER DATABASE SF_SOLUTIONS SET TRACE_LEVEL = ON_EVENT;

GRANT CREATE STAGE ON ALL SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE STAGE ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE STREAMLIT ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT USAGE ON ALL STAGES IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;

-- Grants for the Snowflake Intelligence Roles
CREATE DATABASE IF NOT EXISTS snowflake_intelligence;
CREATE SCHEMA IF NOT EXISTS snowflake_intelligence.agents;
GRANT USAGE ON DATABASE snowflake_intelligence TO ROLE SF_SOLUTIONS_ROLE;
GRANT USAGE ON SCHEMA snowflake_intelligence.agents TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE AGENT ON SCHEMA snowflake_intelligence.agents TO ROLE SF_SOLUTIONS_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE AGENT ON ALL SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE AGENT ON FUTURE SCHEMAS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT CREATE AGENT ON SCHEMA SF_SOLUTIONS.MPM_GOLD TO ROLE SF_SOLUTIONS_ROLE;


GRANT SELECT ON ALL SEMANTIC VIEWS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;
GRANT SELECT ON FUTURE SEMANTIC VIEWS IN DATABASE SF_SOLUTIONS TO ROLE SF_SOLUTIONS_ROLE;

GRANT ALL ON SCHEMA SF_SOLUTIONS.MPM_GOLD TO ROLE SF_SOLUTIONS_ROLE;

-- Create warehouses
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
  WAREHOUSE_SIZE = 'LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Default Warehouse';

GRANT USAGE ON WAREHOUSE sf_solutions_wh TO ROLE public;

-- Create warehouse for Streamlit apps
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_STREAMLIT_WH
  WAREHOUSE_SIZE = 'LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for Snowcore Streamlit applications';

-- Grant warehouse usage to roles
GRANT USAGE ON WAREHOUSE SF_SOLUTIONS_STREAMLIT_WH TO ROLE SF_SOLUTIONS_ROLE;

-- Grant the new role to user 
GRANT ROLE SF_SOLUTIONS_ROLE TO ROLE ACCOUNTADMIN;

/*************************************************************************************************/
-- SPCS INFRASTRUCTURE (OPTIONAL — skip on Trial accounts)
-- These resources are ONLY needed for Streamlit-on-SPCS deployment.
-- The core solution (tables, data, semantic view, agent) works WITHOUT them.
-- Trial accounts cannot create External Access Integrations or Compute Pools.
/*************************************************************************************************/

-- UNCOMMENT the block below if you want SPCS-based Streamlit deployment
-- (requires Enterprise edition or higher, NOT available on Trial accounts):
--
-- CREATE COMPUTE POOL IF NOT EXISTS SF_SOLUTIONS_STREAMLIT_POOL
--   MIN_NODES = 1
--   MAX_NODES = 3
--   INSTANCE_FAMILY = CPU_X64_XS
--   AUTO_RESUME = TRUE
--   INITIALLY_SUSPENDED = FALSE
--   AUTO_SUSPEND_SECS = 3600
--   COMMENT = 'Compute pool for Predictive Maintenance Streamlit app on SPCS';
--
-- GRANT USAGE ON COMPUTE POOL SF_SOLUTIONS_STREAMLIT_POOL
--   TO ROLE SF_SOLUTIONS_ROLE;
--
-- CREATE OR REPLACE NETWORK RULE SF_SOLUTIONS.MPM_GOLD.SF_SOLUTIONS_PYPI_NETWORK_RULE
--   MODE = EGRESS
--   TYPE = HOST_PORT
--   VALUE_LIST = ('pypi.org', 'pypi.python.org', 'pythonhosted.org', 'files.pythonhosted.org');
--
-- CREATE OR REPLACE NETWORK RULE SF_SOLUTIONS.MPM_GOLD.SF_SOLUTIONS_CORTEX_NETWORK_RULE
--   MODE = EGRESS
--   TYPE = HOST_PORT
--   VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80');
--
-- CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION SF_SOLUTIONS_EAI
--   ALLOWED_NETWORK_RULES = (
--     SF_SOLUTIONS.MPM_GOLD.SF_SOLUTIONS_PYPI_NETWORK_RULE,
--     SF_SOLUTIONS.MPM_GOLD.SF_SOLUTIONS_CORTEX_NETWORK_RULE
--   )
--   ENABLED = TRUE
--   COMMENT = 'External access for PyPI packages and Cortex Analyst API';
--
-- GRANT USAGE ON INTEGRATION SF_SOLUTIONS_EAI
--   TO ROLE SF_SOLUTIONS_ROLE;
--
-- GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE SF_SOLUTIONS_ROLE;

/*************************************************************************************************/


USE ROLE SF_SOLUTIONS_ROLE;


---------------------------------------------------------------------------------------------------
-- ## BRONZE LAYER (Raw & Staging)
-- Tables in this layer use the VARIANT data type to land semi-structured JSON as-is.
---------------------------------------------------------------------------------------------------
USE SCHEMA SF_SOLUTIONS.MPM_BRONZE;

CREATE OR REPLACE TABLE RAW_IOT_TELEMETRY (
    RAW_PAYLOAD         VARIANT,
    SOURCE_TIMESTAMP    TIMESTAMP_NTZ,
    INGESTION_TIMESTAMP TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_MAINTENANCE_LOGS (
    LOG_DATA            VARIANT,
    SOURCE_FILENAME     VARCHAR,
    INGESTION_TIMESTAMP TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_EQUIPMENT_MASTER (
    EQUIPMENT_DATA      VARIANT,
    INGESTION_TIMESTAMP TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);


---------------------------------------------------------------------------------------------------
-- ## SILVER LAYER (Conformed & Integrated Star Schema)
-- This is the single source of truth, structured for analytics.
-- Rationalized to align with plant hierarchy and business impact modeling
---------------------------------------------------------------------------------------------------
USE SCHEMA SF_SOLUTIONS.MPM_SILVER;

-- Dimension Tables (The "Who, What, Where")

-- Date Dimension (Standard)
CREATE OR REPLACE TABLE DIM_DATE (
    DATE_SK         NUMBER(8) PRIMARY KEY, -- YYYYMMDD
    FULL_DATE       DATE NOT NULL,
    DAY_OF_WEEK     VARCHAR(10),
    MONTH_NAME      VARCHAR(10),
    QUARTER         NUMBER(1),
    YEAR            NUMBER(4)
);

-- Plant Dimension (Location Hierarchy Level 1)
CREATE OR REPLACE TABLE DIM_PLANT (
    PLANT_ID        NUMBER(10,0) PRIMARY KEY,
    PLANT_NAME      VARCHAR(100),
    LOCATION        VARCHAR(100),
    PLANT_UNS_NK    VARCHAR(100) -- UNS Natural Key (enterprise/site)
);

-- Production Line Dimension (Location Hierarchy Level 2)
CREATE OR REPLACE TABLE DIM_LINE (
    LINE_ID         NUMBER(10,0) PRIMARY KEY,
    PLANT_ID        NUMBER(10,0),
    LINE_NAME       VARCHAR(100),
    HOURLY_REVENUE  NUMBER(10,2), -- Used for calculating revenue loss
    LINE_UNS_NK     VARCHAR(150), -- UNS Natural Key (enterprise/site/line)
    FOREIGN KEY (PLANT_ID) REFERENCES DIM_PLANT(PLANT_ID)
);

-- Process Dimension (Manufacturing Process Level)
CREATE OR REPLACE TABLE DIM_PROCESS (
    PROCESS_ID       INTEGER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
    PROCESS_NK       VARCHAR(50) NOT NULL, -- Natural Key (Process Code)
    PROCESS_NAME     VARCHAR(100),
    PROCESS_TYPE     VARCHAR(50), -- e.g., 'Manufacturing', 'Assembly', 'Testing'
    LINE_ID          NUMBER(10,0),
    PROCESS_UNS_NK   VARCHAR(200), -- UNS Natural Key (enterprise/site/line/process)
    DESCRIPTION      VARCHAR(255),
    IS_ACTIVE        BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (LINE_ID) REFERENCES DIM_LINE(LINE_ID)
);

-- Asset Class Dimension (Asset Categorization)
CREATE OR REPLACE TABLE DIM_ASSET_CLASS (
    ASSET_CLASS_ID  NUMBER(10,0) PRIMARY KEY,
    CLASS_NAME      VARCHAR(100)
);

-- Asset Dimension (Central Dimension - replaces DIM_EQUIPMENT)
CREATE OR REPLACE TABLE DIM_ASSET (
    ASSET_ID                INTEGER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
    ASSET_NK                VARCHAR(50) NOT NULL, -- Natural Key (Serial Number)
    ASSET_NAME              VARCHAR(100),
    MODEL                   VARCHAR(50),
    OEM_NAME                VARCHAR(50),
    PROCESS_ID              INTEGER, -- Foreign Key to DIM_PROCESS
    PROCESS_SEQUENCE        INTEGER, -- Sequence within the process (1, 2, 3, etc.)
    ASSET_CLASS_ID          NUMBER(10,0),
    INSTALLATION_DATE       DATE,
    DOWNTIME_IMPACT_PER_HOUR NUMBER(12,2), -- Used for "Production at Risk" KPI
    ASSET_UNS_NK            VARCHAR(250), -- UNS Natural Key (enterprise/site/line/process/asset)
    -- For Slowly Changing Dimensions (Type 2)
    SCD_START_DATE          TIMESTAMP_NTZ NOT NULL,
    SCD_END_DATE            TIMESTAMP_NTZ,
    IS_CURRENT              BOOLEAN,
    FOREIGN KEY (PROCESS_ID) REFERENCES DIM_PROCESS(PROCESS_ID),
    FOREIGN KEY (ASSET_CLASS_ID) REFERENCES DIM_ASSET_CLASS(ASSET_CLASS_ID)
);

-- Work Order Type Dimension (Enhanced maintenance categorization)
CREATE OR REPLACE TABLE DIM_WORK_ORDER_TYPE (
    WO_TYPE_ID      NUMBER(10,0) PRIMARY KEY,
    WO_TYPE_NAME    VARCHAR(50), -- e.g., 'Unplanned Emergency', 'Planned Predictive', 'Planned Preventive'
    WO_TYPE_CODE    VARCHAR(10)
);

-- Sensor Dimension (Retained for detailed sensor tracking)
CREATE OR REPLACE TABLE DIM_SENSOR (
    SENSOR_SK       INTEGER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
    SENSOR_NK       VARCHAR(50) NOT NULL, -- Natural Key (Sensor UUID)
    ASSET_ID        INTEGER, -- Foreign Key to DIM_ASSET
    SENSOR_TYPE     VARCHAR(50),
    UNITS_OF_MEASURE VARCHAR(20),
    SENSOR_UNS_NK   VARCHAR(300), -- UNS Natural Key (enterprise/site/line/process/asset/sensor_type)
    FOREIGN KEY (ASSET_ID) REFERENCES DIM_ASSET(ASSET_ID)
);

-- Fact Tables (The "Measurements and Events")

-- Time-series sensor data and ML predictions (Consolidated telemetry)
CREATE OR REPLACE TABLE FCT_ASSET_TELEMETRY (
    TELEMETRY_ID        NUMBER(38,0) AUTOINCREMENT PRIMARY KEY,
    ASSET_ID            INTEGER NOT NULL,
    PROCESS_ID          INTEGER, -- Foreign Key to DIM_PROCESS
    DATE_SK             NUMBER(8) NOT NULL,
    RECORDED_AT         TIMESTAMP_NTZ,
    TEMPERATURE_C       NUMBER(5,2),
    VIBRATION_MM_S      NUMBER(5,2),
    PRESSURE_PSI        NUMBER(6,2),
    HEALTH_SCORE        NUMBER(5,2), -- e.g., 0-100
    FAILURE_PROBABILITY NUMBER(3,2), -- e.g., 0-1.0
    RUL_DAYS            NUMBER(5,0), -- Remaining Useful Life in days
    IS_ANOMALOUS        BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (ASSET_ID) REFERENCES DIM_ASSET(ASSET_ID),
    FOREIGN KEY (PROCESS_ID) REFERENCES DIM_PROCESS(PROCESS_ID)
) COMMENT = 'Consolidated telemetry with ML predictions and health scores'
CLUSTER BY (ASSET_ID, RECORDED_AT); -- Optimized for time-series queries on specific assets



CREATE OR REPLACE TABLE DIM_TECHNICIAN (
    TECHNICIAN_ID   NUMBER(38,0) AUTOINCREMENT  PRIMARY KEY,
    EMPLOYEE_NK     VARCHAR(20) NOT NULL, -- Natural Key from HR system
    TECHNICIAN_NAME VARCHAR(100),
    CRAFT           VARCHAR(50), -- e.g., 'Mechanic', 'Electrician', 'Instrumentation'
    SHIFT           VARCHAR(10),
    HIRE_DATE       DATE,
    IS_ACTIVE       BOOLEAN
);


CREATE OR REPLACE TABLE DIM_FAILURE_CODE (
    FAILURE_CODE_ID     NUMBER(38,0) AUTOINCREMENT PRIMARY KEY,
    FAILURE_HIERARCHY_1 VARCHAR(50), -- e.g., 'Mechanical', 'Electrical', 'Operational'
    FAILURE_HIERARCHY_2 VARCHAR(50), -- e.g., 'Bearing', 'Motor', 'Seal'
    FAILURE_HIERARCHY_3 VARCHAR(50), -- e.g., 'Over-lubrication', 'Misalignment', 'Contamination'
    FAILURE_DESCRIPTION VARCHAR(255)
);


CREATE OR REPLACE TABLE DIM_MATERIAL (
    MATERIAL_ID         INTEGER PRIMARY KEY,
    MATERIAL_NK         VARCHAR(50) NOT NULL, -- Part Number / SKU
    MATERIAL_DESC       VARCHAR(255),
    SUPPLIER_NAME       VARCHAR(100),
    UNIT_COST           NUMBER(10,2)
);


-- Log of all maintenance activities (Enhanced)
CREATE OR REPLACE TABLE FCT_MAINTENANCE_LOG (
    LOG_ID              NUMBER(38,0) AUTOINCREMENT PRIMARY KEY,
    ASSET_ID            INTEGER NOT NULL,
    PROCESS_ID          INTEGER, -- Foreign Key to DIM_PROCESS
    WO_TYPE_ID          NUMBER(10,0) NOT NULL,
    ACTION_DATE_SK      NUMBER(8) NOT NULL,
    COMPLETED_DATE      DATE,
    DOWNTIME_HOURS      NUMBER(5,1),
    PARTS_COST          NUMBER(10,2),
    LABOR_COST          NUMBER(10,2),
    FAILURE_FLAG        BOOLEAN COMMENT 'TRUE if this action was in response to a failure',
    TECHNICIAN_ID       NUMBER(38,0) COMMENT 'Foreign key to DIM_TECHNICIAN',
    FAILURE_CODE_ID     NUMBER(38,0) COMMENT 'Foreign key to DIM_FAILURE_CODE, populated when FAILURE_FLAG is TRUE',
    TECHNICIAN_NOTES    VARCHAR(1000),
    FOREIGN KEY (ASSET_ID) REFERENCES DIM_ASSET(ASSET_ID),
    FOREIGN KEY (PROCESS_ID) REFERENCES DIM_PROCESS(PROCESS_ID),
    FOREIGN KEY (WO_TYPE_ID) REFERENCES DIM_WORK_ORDER_TYPE(WO_TYPE_ID),
    FOREIGN KEY (TECHNICIAN_ID) REFERENCES DIM_TECHNICIAN(TECHNICIAN_ID),
    FOREIGN KEY (FAILURE_CODE_ID) REFERENCES DIM_FAILURE_CODE(FAILURE_CODE_ID)
) CLUSTER BY (ASSET_ID, ACTION_DATE_SK);

-- Daily production summary for OEE calculations (New)
CREATE OR REPLACE TABLE FCT_PRODUCTION_LOG (
    PROD_LOG_ID         NUMBER(38,0) AUTOINCREMENT PRIMARY KEY,
    ASSET_ID            INTEGER NOT NULL,
    PROCESS_ID          INTEGER, -- Foreign Key to DIM_PROCESS
    DATE_SK             NUMBER(8) NOT NULL,
    PRODUCTION_DATE     DATE,
    PLANNED_RUNTIME_HOURS   NUMBER(4,1),
    ACTUAL_RUNTIME_HOURS    NUMBER(4,1), -- Drives OEE "Availability"
    UNITS_PRODUCED      NUMBER(10,0), -- Drives OEE "Performance"
    UNITS_SCRAPPED      NUMBER(10,0), -- Drives OEE "Quality"
    FOREIGN KEY (ASSET_ID) REFERENCES DIM_ASSET(ASSET_ID),
    FOREIGN KEY (PROCESS_ID) REFERENCES DIM_PROCESS(PROCESS_ID)
) CLUSTER BY (ASSET_ID, PRODUCTION_DATE);


CREATE OR REPLACE TABLE FCT_MAINTENANCE_PARTS_USED (
    LOG_ID              NUMBER(38,0) NOT NULL, -- Foreign Key to FCT_MAINTENANCE_LOG
    MATERIAL_ID         INTEGER NOT NULL,      -- Foreign Key to DIM_MATERIAL
    QUANTITY_USED       NUMBER(8,2),
    TOTAL_COST          NUMBER(10,2),
    PRIMARY KEY (LOG_ID, MATERIAL_ID)
);

CREATE OR REPLACE TABLE FCT_BUDGET (
    BUDGET_ID           INTEGER PRIMARY KEY,
    PLANT_ID            NUMBER(10,0),
    YEAR                NUMBER(4),
    QUARTER             NUMBER(1),
    BUDGET_TYPE         VARCHAR(50), -- e.g., 'OpEx Maintenance', 'CapEx Project'
    BUDGET_AMOUNT       NUMBER(15,2),
    FOREIGN KEY (PLANT_ID) REFERENCES DIM_PLANT(PLANT_ID)
);


---------------------------------------------------------------------------------------------------
-- ## GOLD LAYER (Application & Feature Store)
-- Purpose-built tables for high-speed dashboards and ML model training.
---------------------------------------------------------------------------------------------------
USE SCHEMA SF_SOLUTIONS.MPM_GOLD;

CREATE OR REPLACE TABLE AGG_ASSET_HOURLY_HEALTH (
    HOUR_TIMESTAMP          TIMESTAMP_NTZ,
    ASSET_ID                INTEGER,
    AVG_TEMPERATURE_C       FLOAT,
    MAX_VIBRATION_MM_S      FLOAT,
    STDDEV_PRESSURE_PSI     FLOAT,
    LATEST_HEALTH_SCORE     NUMBER(5, 2),
    AVG_FAILURE_PROBABILITY NUMBER(3, 2),
    MIN_RUL_DAYS            NUMBER(5, 0)
);

CREATE OR REPLACE TABLE ML_FEATURE_STORE (
    OBSERVATION_DATE_SK     NUMBER(8),
    ASSET_ID                INTEGER,
    -- Example Features
    AVG_TEMP_LAST_24H       FLOAT,
    VIBRATION_STDDEV_7D     FLOAT,
    PRESSURE_TREND_7D       FLOAT,
    CYCLES_SINCE_LAST_PM    INTEGER,
    DAYS_SINCE_LAST_FAILURE INTEGER,
    OEM_FAILURE_RATE_EST    FLOAT,
    DOWNTIME_IMPACT_RISK    NUMBER(12, 2), -- Calculated risk based on asset downtime impact
    -- Target Variable
    FAILED_IN_NEXT_7_DAYS   BOOLEAN
);

-- Daily OEE Metrics (for detailed analysis and trending)
CREATE OR REPLACE TABLE AGG_DAILY_OEE (
    PRODUCTION_DATE         DATE,
    DATE_SK                 NUMBER(8),
    ASSET_ID                INTEGER,
    PROCESS_ID              INTEGER,
    -- OEE Components
    AVAILABILITY_PERCENT    NUMBER(5, 2), -- (Actual Runtime / Planned Runtime) * 100
    PERFORMANCE_PERCENT     NUMBER(5, 2), -- (Actual Output / Theoretical Max Output) * 100
    QUALITY_PERCENT         NUMBER(5, 2), -- (Good Units / Total Units) * 100
    -- Overall OEE
    OEE_PERCENT             NUMBER(5, 2), -- Availability × Performance × Quality
    -- Supporting Metrics
    PLANNED_RUNTIME_HOURS   NUMBER(4, 1),
    ACTUAL_RUNTIME_HOURS    NUMBER(4, 1),
    UNITS_PRODUCED          NUMBER(10, 0),
    UNITS_SCRAPPED          NUMBER(10, 0),
    GOOD_UNITS              NUMBER(10, 0),
    FOREIGN KEY (ASSET_ID) REFERENCES SF_SOLUTIONS.MPM_SILVER.DIM_ASSET(ASSET_ID)
);

-- Monthly Trend Aggregations (optimized for Intelligence Agent queries)
CREATE OR REPLACE TABLE AGG_MONTHLY_TRENDS (
    YEAR_MONTH              VARCHAR(7), -- YYYY-MM format for easy sorting and display
    YEAR                    NUMBER(4),
    MONTH                   NUMBER(2),
    PLANT_ID                NUMBER(10, 0),
    LINE_ID                 NUMBER(10, 0),
    PROCESS_ID              INTEGER,
    -- OEE Metrics
    AVG_OEE_PERCENT         NUMBER(5, 2),
    MIN_OEE_PERCENT         NUMBER(5, 2),
    MAX_OEE_PERCENT         NUMBER(5, 2),
    AVG_AVAILABILITY_PERCENT NUMBER(5, 2),
    AVG_PERFORMANCE_PERCENT  NUMBER(5, 2),
    AVG_QUALITY_PERCENT      NUMBER(5, 2),
    -- Maintenance Costs
    TOTAL_MAINTENANCE_COST   NUMBER(12, 2), -- Parts + Labor
    TOTAL_PARTS_COST         NUMBER(12, 2),
    TOTAL_LABOR_COST         NUMBER(12, 2),
    -- Maintenance Activities
    TOTAL_DOWNTIME_HOURS     NUMBER(10, 1),
    PREVENTIVE_WO_COUNT      NUMBER(10, 0),
    PREDICTIVE_WO_COUNT      NUMBER(10, 0),
    EMERGENCY_WO_COUNT       NUMBER(10, 0),
    FAILURE_COUNT            NUMBER(10, 0),
    -- Production Metrics
    TOTAL_UNITS_PRODUCED     NUMBER(15, 0),
    TOTAL_UNITS_SCRAPPED     NUMBER(15, 0),
    -- Asset Count
    ASSET_COUNT              NUMBER(10, 0)
);

/*************************************************************************************************/
-- Step 2: Insert Sample Data (DML)
-- Data has been extracted to data.sql to keep this file focused on DDL.
-- Run: snow sql -f scripts/data.sql
/*************************************************************************************************/

/*************************************************************************************************/
-- Step 3: Create Stage and Semantic View for Cortex Analyst
/*************************************************************************************************/

USE SCHEMA SF_SOLUTIONS.MPM_GOLD;

-- Create a stage for uploading the semantic view definition
CREATE STAGE IF NOT EXISTS SEMANTIC_VIEW_STAGE
  DIRECTORY = ( ENABLE = TRUE )
  COMMENT = 'Stage for semantic view YAML definitions';

CREATE STAGE IF NOT EXISTS STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for Streamlit application files';

-- Note: The YAML file upload and semantic view creation are handled by the deploy.sh script
-- This ensures proper file staging and semantic view creation in the correct sequence

SELECT 'SF_SOLUTIONS database, data, and Cortex Analyst semantic view created successfully.' AS status;

CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('SF_SOLUTIONS.MPM_GOLD',
$$
name: SF_SOLUTIONS_SV
verified_queries:
  - name: oee_vs_maintenance_cost_12_month_trend
    question: "Show me the trend of our OEE versus our total maintenance cost over the last 12 months"
    sql: |
      SELECT 
        year_month,
        year,
        month,
        AVG(avg_oee_percent) as avg_oee_percent,
        SUM(total_maintenance_cost) as total_maintenance_cost,
        SUM(total_parts_cost) as total_parts_cost,
        SUM(total_labor_cost) as total_labor_cost,
        SUM(total_downtime_hours) as total_downtime_hours,
        SUM(failure_count) as total_failures,
        SUM(preventive_wo_count) as total_preventive_work_orders,
        SUM(predictive_wo_count) as total_predictive_work_orders,
        SUM(emergency_wo_count) as total_emergency_work_orders,
        SUM(total_units_produced) as total_units_produced,
        SUM(total_units_scrapped) as total_units_scrapped,
        SUM(asset_count) as total_assets
      FROM SF_SOLUTIONS.MPM_GOLD.AGG_MONTHLY_TRENDS
      WHERE year_month >= TO_CHAR(DATEADD(month, -12, DATE_TRUNC('month', CURRENT_DATE)), 'YYYY-MM')
        AND year_month <= TO_CHAR(DATE_TRUNC('month', CURRENT_DATE), 'YYYY-MM')
      GROUP BY year_month, year, month
      ORDER BY year_month ASC
tables:
  - name: AGG_ASSET_HOURLY_HEALTH
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_GOLD
      table: AGG_ASSET_HOURLY_HEALTH
    dimensions:
      - name: ASSET_ID
        description: Unique identifier for an asset, used to track and monitor its health and performance over time.
        expr: ASSET_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
    time_dimensions:
      - name: HOUR_TIMESTAMP
        description: The timestamp representing the hour for which the asset health data is aggregated.
        expr: HOUR_TIMESTAMP
        data_type: TIMESTAMP_NTZ(9)
        sample_values:
          - 2025-09-22T10:00:00.000+0000
          - 2025-09-22T11:00:00.000+0000
          - 2025-09-23T08:00:00.000+0000
    facts:
      - name: AVG_FAILURE_PROBABILITY
        description: >-
          The average probability of an asset failing within a given hour, expressed as a decimal value between 0 and 1, where 0
          represents no probability of failure and 1 represents a 100% probability of failure.
        expr: AVG_FAILURE_PROBABILITY
        data_type: NUMBER(3,2)
        sample_values:
          - '0.03'
          - '0.85'
          - '0.02'
      - name: AVG_TEMPERATURE_C
        description: The average temperature in degrees Celsius of the asset over a one-hour period.
        expr: AVG_TEMPERATURE_C
        data_type: FLOAT
        sample_values:
          - '66.1'
          - '75.8'
          - '65.2'
      - name: LATEST_HEALTH_SCORE
        description: >-
          The LATEST_HEALTH_SCORE column represents the most recent health score of an asset, measured as a percentage,
          indicating the asset's current performance and operational status, with higher scores indicating better health.
        expr: LATEST_HEALTH_SCORE
        data_type: NUMBER(5,2)
        sample_values:
          - '98.50'
          - '98.20'
          - '35.10'
      - name: MAX_VIBRATION_MM_S
        description: Maximum vibration measured in millimeters per second.
        expr: MAX_VIBRATION_MM_S
        data_type: FLOAT
        sample_values:
          - '0.51'
          - '0.55'
          - '2.15'
      - name: MIN_RUL_DAYS
        description: >-
          Minimum Remaining Useful Life in Days, representing the estimated number of days until the asset is expected to reach
          the end of its useful life.
        expr: MIN_RUL_DAYS
        data_type: NUMBER(5,0)
        sample_values:
          - '365'
          - '364'
          - '400'
      - name: STDDEV_PRESSURE_PSI
        description: >-
          Standard Deviation of Pressure in Pounds per Square Inch, representing the variability of pressure readings for an
          asset over a one-hour period.
        expr: STDDEV_PRESSURE_PSI
        data_type: FLOAT
        sample_values:
          - '1.2'
          - '1.1'
          - '5.8'
  - name: ML_FEATURE_STORE
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_GOLD
      table: ML_FEATURE_STORE
    dimensions:
      - name: FAILED_IN_NEXT_7_DAYS
        description: Indicates whether the customer failed to make a payment within the next 7 days from the current date.
        expr: FAILED_IN_NEXT_7_DAYS
        data_type: BOOLEAN
        sample_values:
          - 'FALSE'
          - 'TRUE'
    facts:
      - name: ASSET_ID
        description: >-
          Unique identifier for a financial asset, such as a stock, bond, or commodity, used to track and analyze its performance
          and characteristics within the machine learning feature store.
        expr: ASSET_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
      - name: AVG_TEMP_LAST_24H
        description: The average temperature over the last 24 hours.
        expr: AVG_TEMP_LAST_24H
        data_type: FLOAT
        sample_values:
          - '71.5'
          - '68.8'
      - name: CYCLES_SINCE_LAST_PM
        description: The number of production cycles that have occurred since the last planned maintenance (PM) event.
        expr: CYCLES_SINCE_LAST_PM
        data_type: NUMBER(38,0)
        sample_values:
          - '12000'
          - '8500'
      - name: DAYS_SINCE_LAST_FAILURE
        description: The number of days since the last time a failure occurred.
        expr: DAYS_SINCE_LAST_FAILURE
        data_type: NUMBER(38,0)
        sample_values:
          - '365'
          - '180'
      - name: DOWNTIME_IMPACT_RISK
        description: >-
          The estimated financial impact of downtime on the organization, representing the potential loss in dollars per hour of
          system unavailability.
        expr: DOWNTIME_IMPACT_RISK
        data_type: NUMBER(12,2)
        sample_values:
          - '20000.00'
          - '63750.00'
      - name: OBSERVATION_DATE_SK
        description: Unique identifier for the date of observation, in the format YYYYMMDD, used to track and analyze data over time.
        expr: OBSERVATION_DATE_SK
        data_type: NUMBER(8,0)
        sample_values:
          - '20250923'
      - name: OEM_FAILURE_RATE_EST
        description: >-
          Estimated rate of failures for original equipment manufacturer (OEM) parts, expressed as a decimal value between 0 and
          1, where 0 represents no failures and 1 represents 100% failures.
        expr: OEM_FAILURE_RATE_EST
        data_type: FLOAT
        sample_values:
          - '0.15'
          - '0.08'
      - name: PRESSURE_TREND_7D
        description: The average rate of change in pressure over the last 7 days.
        expr: PRESSURE_TREND_7D
        data_type: FLOAT
        sample_values:
          - '2.3'
      - name: VIBRATION_STDDEV_7D
        description: >-
          The standard deviation of vibration measurements over a 7-day period, indicating the variability or consistency of
          vibration levels over time.
        expr: VIBRATION_STDDEV_7D
        data_type: FLOAT
        sample_values:
          - '0.87'
          - '0.12'
  - name: AGG_DAILY_OEE
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_GOLD
      table: AGG_DAILY_OEE
    dimensions:
      - name: PRODUCTION_DATE
        description: The date on which production occurred.
        expr: PRODUCTION_DATE
        data_type: DATE
        sample_values:
          - '2024-11-01'
          - '2024-12-15'
      - name: DATE_SK
        description: Date surrogate key in YYYYMMDD format.
        expr: DATE_SK
        data_type: NUMBER(8,0)
        sample_values:
          - '20241101'
          - '20241215'
      - name: ASSET_ID
        description: Unique identifier for the asset/equipment.
        expr: ASSET_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
      - name: PROCESS_ID
        description: Unique identifier for the manufacturing process.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
    facts:
      - name: OEE_PERCENT
        description: >-
          Overall Equipment Effectiveness percentage (0-100). Calculated as Availability × Performance × Quality. Higher values
          indicate better equipment utilization.
        expr: OEE_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '85.50'
          - '72.30'
      - name: AVAILABILITY_PERCENT
        description: >-
          Equipment availability percentage (0-100). Calculated as (Actual Runtime / Planned Runtime) × 100. Measures uptime vs
          planned time.
        expr: AVAILABILITY_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '95.50'
          - '88.20'
      - name: PERFORMANCE_PERCENT
        description: Equipment performance percentage (0-100). Measures actual output vs theoretical maximum output at ideal cycle time.
        expr: PERFORMANCE_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '90.00'
          - '85.50'
      - name: QUALITY_PERCENT
        description: Product quality percentage (0-100). Calculated as (Good Units / Total Units) × 100. Measures yield and defect rate.
        expr: QUALITY_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '98.50'
          - '95.00'
      - name: PLANNED_RUNTIME_HOURS
        description: Planned or scheduled runtime hours for the asset on this production date.
        expr: PLANNED_RUNTIME_HOURS
        data_type: NUMBER(4,1)
        sample_values:
          - '24.0'
          - '20.0'
      - name: ACTUAL_RUNTIME_HOURS
        description: Actual runtime hours achieved by the asset on this production date.
        expr: ACTUAL_RUNTIME_HOURS
        data_type: NUMBER(4,1)
        sample_values:
          - '22.5'
          - '18.8'
      - name: UNITS_PRODUCED
        description: Total number of units produced by the asset on this production date.
        expr: UNITS_PRODUCED
        data_type: NUMBER(10,0)
        sample_values:
          - '15000'
          - '8500'
      - name: UNITS_SCRAPPED
        description: Number of units that were scrapped or rejected due to quality issues on this production date.
        expr: UNITS_SCRAPPED
        data_type: NUMBER(10,0)
        sample_values:
          - '150'
          - '85'
      - name: GOOD_UNITS
        description: Number of good quality units produced (Units Produced - Units Scrapped).
        expr: GOOD_UNITS
        data_type: NUMBER(10,0)
        sample_values:
          - '14850'
          - '8415'
  - name: AGG_MONTHLY_TRENDS
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_GOLD
      table: AGG_MONTHLY_TRENDS
    dimensions:
      - name: YEAR_MONTH
        description: Year and month in YYYY-MM format for easy sorting and display.
        expr: YEAR_MONTH
        data_type: VARCHAR(7)
        sample_values:
          - '2024-11'
          - '2024-12'
          - '2025-01'
      - name: YEAR
        description: Four-digit year of the aggregation period.
        expr: YEAR
        data_type: NUMBER(4)
        sample_values:
          - '2024'
          - '2025'
      - name: MONTH
        description: Month number (1-12) of the aggregation period.
        expr: MONTH
        data_type: NUMBER(2)
        sample_values:
          - '1'
          - '11'
          - '12'
      - name: PLANT_ID
        description: Unique identifier for the manufacturing plant.
        expr: PLANT_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
          - '2'
      - name: LINE_ID
        description: Unique identifier for the production line within the plant.
        expr: LINE_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '101'
          - '201'
      - name: PROCESS_ID
        description: Unique identifier for the manufacturing process.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
    facts:
      - name: AVG_OEE_PERCENT
        description: >-
          Average Overall Equipment Effectiveness percentage for the month. Use this to track OEE trends over time. Higher values
          indicate better overall equipment performance.
        expr: AVG_OEE_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '82.50'
          - '75.30'
      - name: MIN_OEE_PERCENT
        description: Minimum OEE percentage recorded during the month.
        expr: MIN_OEE_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '65.00'
          - '58.50'
      - name: MAX_OEE_PERCENT
        description: Maximum OEE percentage recorded during the month.
        expr: MAX_OEE_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '95.00'
          - '88.50'
      - name: AVG_AVAILABILITY_PERCENT
        description: Average equipment availability percentage for the month.
        expr: AVG_AVAILABILITY_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '92.50'
          - '88.00'
      - name: AVG_PERFORMANCE_PERCENT
        description: Average equipment performance percentage for the month.
        expr: AVG_PERFORMANCE_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '89.00'
          - '85.50'
      - name: AVG_QUALITY_PERCENT
        description: Average product quality percentage for the month.
        expr: AVG_QUALITY_PERCENT
        data_type: NUMBER(5,2)
        sample_values:
          - '97.50'
          - '95.00'
      - name: TOTAL_MAINTENANCE_COST
        description: >-
          Total maintenance cost for the month in dollars, including both parts and labor costs. Use this to track maintenance
          spending trends and correlate with OEE.
        expr: TOTAL_MAINTENANCE_COST
        data_type: NUMBER(12,2)
        sample_values:
          - '125000.00'
          - '98500.50'
      - name: TOTAL_PARTS_COST
        description: Total cost of parts used in maintenance activities during the month.
        expr: TOTAL_PARTS_COST
        data_type: NUMBER(12,2)
        sample_values:
          - '75000.00'
          - '60000.00'
      - name: TOTAL_LABOR_COST
        description: Total labor cost for maintenance activities during the month.
        expr: TOTAL_LABOR_COST
        data_type: NUMBER(12,2)
        sample_values:
          - '50000.00'
          - '38500.50'
      - name: TOTAL_DOWNTIME_HOURS
        description: Total hours of equipment downtime due to maintenance during the month.
        expr: TOTAL_DOWNTIME_HOURS
        data_type: NUMBER(10,1)
        sample_values:
          - '45.5'
          - '32.0'
      - name: PREVENTIVE_WO_COUNT
        description: Number of preventive maintenance work orders completed during the month.
        expr: PREVENTIVE_WO_COUNT
        data_type: NUMBER(10,0)
        sample_values:
          - '15'
          - '12'
      - name: PREDICTIVE_WO_COUNT
        description: Number of predictive maintenance work orders completed during the month.
        expr: PREDICTIVE_WO_COUNT
        data_type: NUMBER(10,0)
        sample_values:
          - '8'
          - '5'
      - name: EMERGENCY_WO_COUNT
        description: Number of emergency maintenance work orders completed during the month.
        expr: EMERGENCY_WO_COUNT
        data_type: NUMBER(10,0)
        sample_values:
          - '3'
          - '1'
      - name: FAILURE_COUNT
        description: Number of equipment failures that occurred during the month.
        expr: FAILURE_COUNT
        data_type: NUMBER(10,0)
        sample_values:
          - '5'
          - '2'
      - name: TOTAL_UNITS_PRODUCED
        description: Total number of units produced during the month.
        expr: TOTAL_UNITS_PRODUCED
        data_type: NUMBER(15,0)
        sample_values:
          - '450000'
          - '380000'
      - name: TOTAL_UNITS_SCRAPPED
        description: Total number of units scrapped during the month.
        expr: TOTAL_UNITS_SCRAPPED
        data_type: NUMBER(15,0)
        sample_values:
          - '4500'
          - '3800'
      - name: ASSET_COUNT
        description: Number of distinct assets included in this monthly aggregation.
        expr: ASSET_COUNT
        data_type: NUMBER(10,0)
        sample_values:
          - '3'
          - '6'
  - name: DIM_PROCESS
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_PROCESS
    dimensions:
      - name: PROCESS_ID
        description: Unique identifier for a manufacturing process within a production line.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: PROCESS_NK
        description: Natural key for the process, typically a process code or identifier.
        expr: PROCESS_NK
        data_type: VARCHAR(50)
        sample_values:
          - machining_process_a
          - assembly_process_a
          - testing_process_a
      - name: PROCESS_NAME
        description: The name of the manufacturing process.
        expr: PROCESS_NAME
        data_type: VARCHAR(100)
        sample_values:
          - Machining Operations
          - Assembly Operations
          - Quality Testing
      - name: PROCESS_TYPE
        description: The type of process, such as Manufacturing, Assembly, or Testing.
        expr: PROCESS_TYPE
        data_type: VARCHAR(50)
        sample_values:
          - Manufacturing
          - Assembly
          - Testing
      - name: LINE_ID
        description: Unique identifier for the production line this process belongs to.
        expr: LINE_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '101'
          - '102'
          - '201'
      - name: DESCRIPTION
        description: Detailed description of the manufacturing process.
        expr: DESCRIPTION
        data_type: VARCHAR(255)
        sample_values:
          - Primary machining operations including cutting, drilling, and shaping
          - Component assembly and integration operations
          - Quality control and testing operations
      - name: IS_ACTIVE
        description: Indicates whether the process is currently active.
        expr: IS_ACTIVE
        data_type: BOOLEAN
        sample_values:
          - 'TRUE'
    facts: []
    primary_key:
      columns:
        - PROCESS_ID
  - name: DIM_ASSET
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_ASSET
    dimensions:
      - name: ASSET_CLASS_ID
        description: >-
          A unique identifier for the asset class to which the asset belongs, used to categorize and group similar assets for
          reporting and analysis purposes.
        expr: ASSET_CLASS_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
      - name: ASSET_ID
        description: Unique identifier for an asset.
        expr: ASSET_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
      - name: ASSET_NAME
        description: The name of the asset being monitored or tracked, such as a piece of equipment or machinery.
        expr: ASSET_NAME
        data_type: VARCHAR(100)
        sample_values:
          - Primary Coolant Pump
          - Conveyor Drive Motor
      - name: ASSET_NK
        description: >-
          Unique identifier for a specific asset, such as a piece of equipment or machinery, used to track and manage its
          performance, maintenance, and other relevant information.
        expr: ASSET_NK
        data_type: VARCHAR(50)
        sample_values:
          - eq_pump_001
          - eq_motor_007
      - name: IS_CURRENT
        description: Indicates whether the asset is currently active or in use.
        expr: IS_CURRENT
        data_type: BOOLEAN
        sample_values:
          - 'TRUE'
      - name: MODEL
        description: The type of asset or equipment used in the organization, such as a specific model of pump or engine.
        expr: MODEL
        data_type: VARCHAR(50)
        sample_values:
          - IronHorse 75HP
          - HydroFlow 5000
      - name: OEM_NAME
        description: The name of the original equipment manufacturer (OEM) that produced the asset.
        expr: OEM_NAME
        data_type: VARCHAR(50)
        sample_values:
          - FlowServe
          - Siemens
      - name: PROCESS_ID
        description: Unique identifier for the manufacturing process this asset belongs to.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: PROCESS_SEQUENCE
        description: The sequence number of this asset within its manufacturing process.
        expr: PROCESS_SEQUENCE
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
    time_dimensions:
      - name: INSTALLATION_DATE
        description: Date when the asset was installed.
        expr: INSTALLATION_DATE
        data_type: DATE
        sample_values:
          - '2021-11-20'
          - '2022-01-15'
      - name: SCD_END_DATE
        description: The date when the asset's current state or version is no longer valid or effective.
        expr: SCD_END_DATE
        data_type: TIMESTAMP_NTZ(9)
      - name: SCD_START_DATE
        description: The date and time when the asset's current version became effective, marking the start of its validity period.
        expr: SCD_START_DATE
        data_type: TIMESTAMP_NTZ(9)
        sample_values:
          - 2022-01-15T00:00:00.000+0000
          - 2021-11-20T00:00:00.000+0000
    facts:
      - name: DOWNTIME_IMPACT_PER_HOUR
        description: The estimated financial impact or loss per hour of downtime for a specific asset.
        expr: DOWNTIME_IMPACT_PER_HOUR
        data_type: NUMBER(12,2)
        sample_values:
          - '7500.00'
          - '5000.00'
    primary_key:
      columns:
        - ASSET_ID
  - name: DIM_ASSET_CLASS
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_ASSET_CLASS
    dimensions:
      - name: ASSET_CLASS_ID
        description: >-
          Unique identifier for a category of assets, such as stocks, bonds, or real estate, used to classify and group similar
          assets for investment and reporting purposes.
        expr: ASSET_CLASS_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: CLASS_NAME
        description: >-
          The type of asset classification, which categorizes assets into distinct groups based on their functional
          characteristics, such as Static Equipment (e.g. tanks, vessels), Rotating Equipment (e.g. pumps, motors), and Electrical Systems
          (e.g. electrical panels, switchgear).
        expr: CLASS_NAME
        data_type: VARCHAR(100)
        sample_values:
          - Static Equipment
          - Rotating Equipment
          - Electrical Systems
    facts: []
    primary_key:
      columns:
        - ASSET_CLASS_ID
  - name: DIM_DATE
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_DATE
    dimensions:
      - name: DATE_SK
        description: >-
          Unique identifier for a specific date, represented in the format YYYYMMDD, used to link date-related data across the
          data warehouse.
        expr: DATE_SK
        data_type: NUMBER(8,0)
        sample_values:
          - '20250922'
          - '20250923'
      - name: DAY_OF_WEEK
        description: The day of the week on which a date falls, with possible values including Monday and Tuesday.
        expr: DAY_OF_WEEK
        data_type: VARCHAR(10)
        sample_values:
          - Monday
          - Tuesday
      - name: MONTH_NAME
        description: The full name of the month, e.g. January, February, etc.
        expr: MONTH_NAME
        data_type: VARCHAR(10)
        sample_values:
          - September
      - name: QUARTER
        description: >-
          The quarter of the year in which a date falls, with possible values being 1 (January-March), 2 (April-June), 3
          (July-September), or 4 (October-December).
        expr: QUARTER
        data_type: NUMBER(1,0)
        sample_values:
          - '3'
      - name: YEAR
        description: The calendar year in which a date falls.
        expr: YEAR
        data_type: NUMBER(4,0)
        sample_values:
          - '2025'
    time_dimensions:
      - name: FULL_DATE
        description: Date of the transaction or event, represented in the format 'YYYY-MM-DD'.
        expr: FULL_DATE
        data_type: DATE
        sample_values:
          - '2025-09-22'
          - '2025-09-23'
    facts: []
    primary_key:
      columns:
        - DATE_SK
  - name: DIM_LINE
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_LINE
    dimensions:
      - name: LINE_ID
        description: Unique identifier for a specific line in the production process.
        expr: LINE_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '201'
          - '101'
          - '102'
      - name: LINE_NAME
        description: The name of the production or assembly line where the product is manufactured.
        expr: LINE_NAME
        data_type: VARCHAR(100)
        sample_values:
          - Production Line B
          - Assembly Line 1
          - Production Line A
      - name: PLANT_ID
        description: Unique identifier for the plant where the production line is located.
        expr: PLANT_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
          - '2'
    facts:
      - name: HOURLY_REVENUE
        description: The total revenue generated by a specific line item within a one-hour time frame.
        expr: HOURLY_REVENUE
        data_type: NUMBER(10,2)
        sample_values:
          - '18000.00'
          - '12000.00'
          - '15000.00'
    primary_key:
      columns:
        - LINE_ID
  - name: DIM_PLANT
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_PLANT
    dimensions:
      - name: LOCATION
        description: The physical location of the plant, including city and state.
        expr: LOCATION
        data_type: VARCHAR(100)
        sample_values:
          - Davidson NC
          - Charlotte NC
      - name: PLANT_ID
        description: Unique identifier for a manufacturing plant or facility.
        expr: PLANT_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
          - '2'
      - name: PLANT_NAME
        description: The name of the manufacturing plant where the product is produced.
        expr: PLANT_NAME
        data_type: VARCHAR(100)
        sample_values:
          - Davidson Manufacturing
          - Charlotte Assembly
    facts: []
    primary_key:
      columns:
        - PLANT_ID
  - name: DIM_SENSOR
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_SENSOR
    dimensions:
      - name: ASSET_ID
        description: Unique identifier for a physical or logical asset being monitored by a sensor.
        expr: ASSET_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
      - name: SENSOR_NK
        description: >-
          Sensor identifier, uniquely naming each sensor across all equipment, in the format "EQ-[Equipment Type]-[Equipment
          Number]-[Sensor Type]" where Equipment Type is the type of equipment the sensor is attached to, Equipment Number is the unique
          identifier of the equipment, and Sensor Type is the type of measurement the sensor is taking (e.g. VIB for vibration, PSI for
          pressure, TMP for temperature).
        expr: SENSOR_NK
        data_type: VARCHAR(50)
        sample_values:
          - EQ-PUMP-001-VIB
          - EQ-PUMP-001-PSI
          - EQ-PUMP-001-TMP
      - name: SENSOR_SK
        description: Unique identifier for a sensor in the fact table, used to link to the dimension table for additional sensor details.
        expr: SENSOR_SK
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: SENSOR_TYPE
        description: Type of sensor used to collect data, such as temperature, pressure, or vibration sensors.
        expr: SENSOR_TYPE
        data_type: VARCHAR(50)
        sample_values:
          - Temperature
          - Pressure
          - Vibration
      - name: UNITS_OF_MEASURE
        description: The unit of measurement for the sensor reading, such as temperature, pressure, or velocity.
        expr: UNITS_OF_MEASURE
        data_type: VARCHAR(20)
        sample_values:
          - Celsius
          - PSI
          - mm/s
    facts: []
    primary_key:
      columns:
        - SENSOR_SK
  - name: DIM_WORK_ORDER_TYPE
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_WORK_ORDER_TYPE
    dimensions:
      - name: WO_TYPE_CODE
        description: 'Work Order Type Code, which categorizes work orders into one of three types: Unplanned Emergency (UE), Planned
          Maintenance (PM), or Planned Project (PP).'
        expr: WO_TYPE_CODE
        data_type: VARCHAR(10)
        sample_values:
          - UE
          - PM
          - PP
      - name: WO_TYPE_NAME
        description: >-
          The type of work order, indicating whether it was unplanned and emergency in nature, or planned as part of a preventive
          or predictive maintenance schedule.
        expr: WO_TYPE_NAME
        data_type: VARCHAR(50)
        sample_values:
          - Unplanned Emergency
          - Planned Preventive
          - Planned Predictive
    facts:
      - name: WO_TYPE_ID
        description: Unique identifier for the type of work order, such as maintenance, repair, or installation.
        expr: WO_TYPE_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
          - '2'
          - '3'
    primary_key:
      columns:
        - WO_TYPE_ID
  - name: DIM_TECHNICIAN
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_TECHNICIAN
    dimensions:
      - name: TECHNICIAN_ID
        description: Unique identifier for a technician.
        expr: TECHNICIAN_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: EMPLOYEE_NK
        description: Natural key for the employee from the HR system.
        expr: EMPLOYEE_NK
        data_type: VARCHAR(20)
        sample_values:
          - EMP001
          - EMP002
          - EMP003
      - name: TECHNICIAN_NAME
        description: The name of the technician.
        expr: TECHNICIAN_NAME
        data_type: VARCHAR(100)
        sample_values:
          - John Martinez
          - Sarah Chen
          - Mike Johnson
      - name: CRAFT
        description: The craft or specialty of the technician.
        expr: CRAFT
        data_type: VARCHAR(50)
        sample_values:
          - Mechanic
          - Electrician
          - Instrumentation
      - name: SHIFT
        description: The shift the technician works.
        expr: SHIFT
        data_type: VARCHAR(10)
        sample_values:
          - Day
          - Evening
          - Night
      - name: IS_ACTIVE
        description: Indicates whether the technician is currently active.
        expr: IS_ACTIVE
        data_type: BOOLEAN
        sample_values:
          - 'TRUE'
    time_dimensions:
      - name: HIRE_DATE
        description: Date when the technician was hired.
        expr: HIRE_DATE
        data_type: DATE
        sample_values:
          - '2020-03-15'
          - '2019-08-22'
          - '2021-01-10'
    facts: []
    primary_key:
      columns:
        - TECHNICIAN_ID
  - name: DIM_FAILURE_CODE
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_FAILURE_CODE
    dimensions:
      - name: FAILURE_CODE_ID
        description: Unique identifier for a failure code.
        expr: FAILURE_CODE_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: FAILURE_HIERARCHY_1
        description: First level of failure hierarchy, such as Mechanical, Electrical, or Operational.
        expr: FAILURE_HIERARCHY_1
        data_type: VARCHAR(50)
        sample_values:
          - Mechanical
          - Electrical
          - Operational
      - name: FAILURE_HIERARCHY_2
        description: Second level of failure hierarchy, such as Bearing, Motor, or Seal.
        expr: FAILURE_HIERARCHY_2
        data_type: VARCHAR(50)
        sample_values:
          - Bearing
          - Motor
          - Seal
      - name: FAILURE_HIERARCHY_3
        description: Third level of failure hierarchy, such as Over-lubrication, Misalignment, or Contamination.
        expr: FAILURE_HIERARCHY_3
        data_type: VARCHAR(50)
        sample_values:
          - Over-lubrication
          - Misalignment
          - Contamination
      - name: FAILURE_DESCRIPTION
        description: Detailed description of the failure.
        expr: FAILURE_DESCRIPTION
        data_type: VARCHAR(255)
        sample_values:
          - Bearing misalignment causing excessive vibration and wear
          - Motor winding failure due to overheating or insulation breakdown
          - Equipment operated beyond design capacity
    facts: []
    primary_key:
      columns:
        - FAILURE_CODE_ID
  - name: DIM_MATERIAL
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: DIM_MATERIAL
    dimensions:
      - name: MATERIAL_ID
        description: Unique identifier for a material or part.
        expr: MATERIAL_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: MATERIAL_NK
        description: Natural key for the material, typically a part number or SKU.
        expr: MATERIAL_NK
        data_type: VARCHAR(50)
        sample_values:
          - BEARING-001
          - SEAL-002
          - FILTER-003
      - name: MATERIAL_DESC
        description: Description of the material or part.
        expr: MATERIAL_DESC
        data_type: VARCHAR(255)
        sample_values:
          - High-speed bearing for rotating equipment
          - Hydraulic seal for pump applications
          - Air filter for compressor systems
      - name: SUPPLIER_NAME
        description: Name of the supplier for this material.
        expr: SUPPLIER_NAME
        data_type: VARCHAR(100)
        sample_values:
          - SKF Bearings
          - Parker Hannifin
          - Donaldson Filters
    facts:
      - name: UNIT_COST
        description: The unit cost of the material.
        expr: UNIT_COST
        data_type: NUMBER(10,2)
        sample_values:
          - '125.50'
          - '45.75'
          - '89.25'
    primary_key:
      columns:
        - MATERIAL_ID
  - name: FCT_ASSET_TELEMETRY
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: FCT_ASSET_TELEMETRY
    dimensions:
      - name: ASSET_ID
        description: Unique identifier for an asset, used to track and monitor its telemetry data.
        expr: ASSET_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
      - name: PROCESS_ID
        description: Unique identifier for the manufacturing process this telemetry data belongs to.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: DATE_SK
        description: Date key representing the date of the telemetry data, in the format YYYYMMDD.
        expr: DATE_SK
        data_type: NUMBER(8,0)
        sample_values:
          - '20250922'
          - '20250923'
      - name: IS_ANOMALOUS
        description: >-
          Indicates whether the asset's telemetry data is outside of its normal operating range, suggesting a potential issue or
          anomaly.
        expr: IS_ANOMALOUS
        data_type: BOOLEAN
        sample_values:
          - 'FALSE'
          - 'TRUE'
      - name: TELEMETRY_ID
        description: Unique identifier for a specific telemetry data point.
        expr: TELEMETRY_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
    time_dimensions:
      - name: RECORDED_AT
        description: The date and time when the asset telemetry data was recorded.
        expr: RECORDED_AT
        data_type: TIMESTAMP_NTZ(9)
        sample_values:
          - 2025-09-22T10:00:00.000+0000
          - 2025-09-22T11:00:00.000+0000
          - 2025-09-23T08:00:00.000+0000
    facts:
      - name: FAILURE_PROBABILITY
        description: >-
          The probability of an asset failing, expressed as a decimal value between 0 and 1, where 0 represents no chance of
          failure and 1 represents certainty of failure.
        expr: FAILURE_PROBABILITY
        data_type: NUMBER(3,2)
        sample_values:
          - '0.03'
          - '0.85'
          - '0.02'
      - name: HEALTH_SCORE
        description: >-
          The HEALTH_SCORE column represents a calculated metric that indicates the overall health or performance of an asset,
          with higher values indicating better health and lower values indicating potential issues or degradation, allowing for proactive
          maintenance and optimization.
        expr: HEALTH_SCORE
        data_type: NUMBER(5,2)
        sample_values:
          - '98.50'
          - '98.20'
          - '35.10'
      - name: PRESSURE_PSI
        description: The pressure of the asset, measured in pounds per square inch (PSI).
        expr: PRESSURE_PSI
        data_type: NUMBER(6,2)
        sample_values:
          - '146.20'
          - '145.00'
          - '155.80'
      - name: RUL_DAYS
        description: The number of days remaining until the asset is expected to reach the end of its useful life.
        expr: RUL_DAYS
        data_type: NUMBER(5,0)
        sample_values:
          - '365'
          - '364'
          - '400'
      - name: TEMPERATURE_C
        description: The temperature reading of an asset in degrees Celsius.
        expr: TEMPERATURE_C
        data_type: NUMBER(5,2)
        sample_values:
          - '65.20'
          - '66.10'
          - '75.80'
      - name: VIBRATION_MM_S
        description: Vibration measurement in millimeters per second, indicating the level of vibration experienced by the asset.
        expr: VIBRATION_MM_S
        data_type: NUMBER(5,2)
        sample_values:
          - '0.51'
          - '0.55'
          - '2.15'
    primary_key:
      columns:
        - TELEMETRY_ID
  - name: FCT_MAINTENANCE_LOG
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: FCT_MAINTENANCE_LOG
    dimensions:
      - name: ACTION_DATE_SK
        description: Date on which the maintenance activity was performed, in the format YYYYMMDD.
        expr: ACTION_DATE_SK
        data_type: NUMBER(8,0)
        sample_values:
          - '20250923'
      - name: ASSET_ID
        description: Unique identifier for the asset that the maintenance activity was performed on.
        expr: ASSET_ID
        data_type: INTEGER
        sample_values:
          - '1'
      - name: PROCESS_ID
        description: Unique identifier for the manufacturing process this maintenance activity belongs to.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: FAILURE_FLAG
        description: TRUE if this action was in response to a failure
        expr: FAILURE_FLAG
        data_type: BOOLEAN
        sample_values:
          - 'TRUE'
      - name: LOG_ID
        description: Unique identifier for each maintenance log entry.
        expr: LOG_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
      - name: TECHNICIAN_ID
        description: Unique identifier for the technician who performed the maintenance.
        expr: TECHNICIAN_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: FAILURE_CODE_ID
        description: Unique identifier for the failure code, populated when FAILURE_FLAG is TRUE.
        expr: FAILURE_CODE_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: TECHNICIAN_NOTES
        description: >-
          Free-form text notes recorded by the technician during maintenance activities, detailing the issues encountered,
          actions taken, and any other relevant information.
        expr: TECHNICIAN_NOTES
        data_type: VARCHAR(1000)
        sample_values:
          - High vibration detected. Found bearing misalignment. Emergency repair completed.
      - name: WO_TYPE_ID
        description: Type of work order (e.g. Preventative, Corrective, Predictive, etc.)
        expr: WO_TYPE_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
    time_dimensions:
      - name: COMPLETED_DATE
        description: Date when the maintenance activity was completed.
        expr: COMPLETED_DATE
        data_type: DATE
        sample_values:
          - '2025-09-23'
    facts:
      - name: DOWNTIME_HOURS
        description: The total number of hours a machine or system was unavailable due to maintenance or repair.
        expr: DOWNTIME_HOURS
        data_type: NUMBER(5,1)
        sample_values:
          - '4.0'
      - name: LABOR_COST
        description: >-
          The cost of labor incurred during a maintenance activity, representing the total amount paid to personnel for their
          work.
        expr: LABOR_COST
        data_type: NUMBER(10,2)
        sample_values:
          - '600.00'
      - name: PARTS_COST
        description: The total cost of parts used to perform the maintenance activity.
        expr: PARTS_COST
        data_type: NUMBER(10,2)
        sample_values:
          - '250.00'
    primary_key:
      columns:
        - LOG_ID
  - name: FCT_PRODUCTION_LOG
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: FCT_PRODUCTION_LOG
    dimensions:
      - name: ASSET_ID
        description: Unique identifier for the asset being produced.
        expr: ASSET_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
      - name: PROCESS_ID
        description: Unique identifier for the manufacturing process this production data belongs to.
        expr: PROCESS_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: DATE_SK
        description: Date key representing the date of production in the format YYYYMMDD.
        expr: DATE_SK
        data_type: NUMBER(8,0)
        sample_values:
          - '20250922'
          - '20250923'
      - name: PROD_LOG_ID
        description: Unique identifier for each production log entry.
        expr: PROD_LOG_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
    time_dimensions:
      - name: PRODUCTION_DATE
        description: Date on which the production activity took place.
        expr: PRODUCTION_DATE
        data_type: DATE
        sample_values:
          - '2025-09-22'
          - '2025-09-23'
    facts:
      - name: ACTUAL_RUNTIME_HOURS
        description: The actual number of hours spent on production, representing the real-world time taken to complete a task or process.
        expr: ACTUAL_RUNTIME_HOURS
        data_type: NUMBER(4,1)
        sample_values:
          - '20.0'
          - '23.5'
          - '24.0'
      - name: PLANNED_RUNTIME_HOURS
        description: The planned number of hours allocated for production to run.
        expr: PLANNED_RUNTIME_HOURS
        data_type: NUMBER(4,1)
        sample_values:
          - '24.0'
      - name: UNITS_PRODUCED
        description: The total quantity of units manufactured or produced during a specific production run or period.
        expr: UNITS_PRODUCED
        data_type: NUMBER(10,0)
        sample_values:
          - '2400'
          - '1250'
          - '980'
      - name: UNITS_SCRAPPED
        description: The total number of units that were produced but did not meet quality standards and were therefore scrapped.
        expr: UNITS_SCRAPPED
        data_type: NUMBER(10,0)
        sample_values:
          - '5'
          - '15'
          - '35'
    primary_key:
      columns:
        - PROD_LOG_ID
  - name: FCT_MAINTENANCE_PARTS_USED
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: FCT_MAINTENANCE_PARTS_USED
    dimensions:
      - name: LOG_ID
        description: Foreign key to FCT_MAINTENANCE_LOG.
        expr: LOG_ID
        data_type: NUMBER(38,0)
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: MATERIAL_ID
        description: Foreign key to DIM_MATERIAL.
        expr: MATERIAL_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
    facts:
      - name: QUANTITY_USED
        description: The quantity of material used in the maintenance activity.
        expr: QUANTITY_USED
        data_type: NUMBER(8,2)
        sample_values:
          - '2.00'
          - '1.50'
          - '3.25'
      - name: TOTAL_COST
        description: The total cost of the material used.
        expr: TOTAL_COST
        data_type: NUMBER(10,2)
        sample_values:
          - '251.00'
          - '68.63'
          - '290.06'
    primary_key:
      columns:
        - LOG_ID
        - MATERIAL_ID
  - name: FCT_BUDGET
    base_table:
      database: SF_SOLUTIONS
      schema: MPM_SILVER
      table: FCT_BUDGET
    dimensions:
      - name: BUDGET_ID
        description: Unique identifier for a budget entry.
        expr: BUDGET_ID
        data_type: INTEGER
        sample_values:
          - '1'
          - '2'
          - '3'
      - name: PLANT_ID
        description: Unique identifier for the plant this budget belongs to.
        expr: PLANT_ID
        data_type: NUMBER(10,0)
        sample_values:
          - '1'
          - '2'
      - name: YEAR
        description: The year for this budget entry.
        expr: YEAR
        data_type: NUMBER(4,0)
        sample_values:
          - '2025'
          - '2024'
      - name: QUARTER
        description: The quarter for this budget entry.
        expr: QUARTER
        data_type: NUMBER(1,0)
        sample_values:
          - '1'
          - '2'
          - '3'
          - '4'
      - name: BUDGET_TYPE
        description: The type of budget, such as OpEx Maintenance or CapEx Project.
        expr: BUDGET_TYPE
        data_type: VARCHAR(50)
        sample_values:
          - OpEx Maintenance
          - CapEx Project
    facts:
      - name: BUDGET_AMOUNT
        description: The budget amount for this entry.
        expr: BUDGET_AMOUNT
        data_type: NUMBER(15,2)
        sample_values:
          - '450000.00'
          - '125000.00'
          - '550000.00'
    primary_key:
      columns:
        - BUDGET_ID
relationships:
  - name: DIM_PROCESS__TO__DIM_LINE
    left_table: DIM_PROCESS
    relationship_columns:
      - left_column: LINE_ID
        right_column: LINE_ID
    right_table: DIM_LINE
  - name: DIM_ASSET__TO__DIM_PROCESS
    left_table: DIM_ASSET
    relationship_columns:
      - left_column: PROCESS_ID
        right_column: PROCESS_ID
    right_table: DIM_PROCESS
  - name: DIM_ASSET__TO__DIM_ASSET_CLASS
    left_table: DIM_ASSET
    relationship_columns:
      - left_column: ASSET_CLASS_ID
        right_column: ASSET_CLASS_ID
    right_table: DIM_ASSET_CLASS
  - name: DIM_SENSOR__TO__DIM_ASSET
    left_table: DIM_SENSOR
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
    right_table: DIM_ASSET
  - name: DIM_LINE__TO__DIM_PLANT
    left_table: DIM_LINE
    relationship_columns:
      - left_column: PLANT_ID
        right_column: PLANT_ID
    right_table: DIM_PLANT
  - name: FCT_ASSET_TELEMETRY__TO__DIM_ASSET
    left_table: FCT_ASSET_TELEMETRY
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
    right_table: DIM_ASSET
  - name: FCT_ASSET_TELEMETRY__TO__DIM_PROCESS
    left_table: FCT_ASSET_TELEMETRY
    relationship_columns:
      - left_column: PROCESS_ID
        right_column: PROCESS_ID
    right_table: DIM_PROCESS
  - name: FCT_ASSET_TELEMETRY__TO__DIM_DATE
    left_table: FCT_ASSET_TELEMETRY
    relationship_columns:
      - left_column: DATE_SK
        right_column: DATE_SK
    right_table: DIM_DATE
  - name: FCT_MAINTENANCE_LOG__TO__DIM_ASSET
    left_table: FCT_MAINTENANCE_LOG
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
    right_table: DIM_ASSET
  - name: FCT_MAINTENANCE_LOG__TO__DIM_PROCESS
    left_table: FCT_MAINTENANCE_LOG
    relationship_columns:
      - left_column: PROCESS_ID
        right_column: PROCESS_ID
    right_table: DIM_PROCESS
  - name: FCT_MAINTENANCE_LOG__TO__DIM_WORK_ORDER_TYPE
    left_table: FCT_MAINTENANCE_LOG
    relationship_columns:
      - left_column: WO_TYPE_ID
        right_column: WO_TYPE_ID
    right_table: DIM_WORK_ORDER_TYPE
  - name: FCT_MAINTENANCE_LOG__TO__DIM_TECHNICIAN
    left_table: FCT_MAINTENANCE_LOG
    relationship_columns:
      - left_column: TECHNICIAN_ID
        right_column: TECHNICIAN_ID
    right_table: DIM_TECHNICIAN
  - name: FCT_MAINTENANCE_LOG__TO__DIM_FAILURE_CODE
    left_table: FCT_MAINTENANCE_LOG
    relationship_columns:
      - left_column: FAILURE_CODE_ID
        right_column: FAILURE_CODE_ID
    right_table: DIM_FAILURE_CODE
  - name: FCT_MAINTENANCE_LOG__TO__DIM_DATE
    left_table: FCT_MAINTENANCE_LOG
    relationship_columns:
      - left_column: ACTION_DATE_SK
        right_column: DATE_SK
    right_table: DIM_DATE
  - name: FCT_MAINTENANCE_PARTS_USED__TO__FCT_MAINTENANCE_LOG
    left_table: FCT_MAINTENANCE_PARTS_USED
    relationship_columns:
      - left_column: LOG_ID
        right_column: LOG_ID
    right_table: FCT_MAINTENANCE_LOG
  - name: FCT_MAINTENANCE_PARTS_USED__TO__DIM_MATERIAL
    left_table: FCT_MAINTENANCE_PARTS_USED
    relationship_columns:
      - left_column: MATERIAL_ID
        right_column: MATERIAL_ID
    right_table: DIM_MATERIAL
  - name: FCT_PRODUCTION_LOG__TO__DIM_ASSET
    left_table: FCT_PRODUCTION_LOG
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
    right_table: DIM_ASSET
  - name: FCT_PRODUCTION_LOG__TO__DIM_PROCESS
    left_table: FCT_PRODUCTION_LOG
    relationship_columns:
      - left_column: PROCESS_ID
        right_column: PROCESS_ID
    right_table: DIM_PROCESS
  - name: FCT_PRODUCTION_LOG__TO__DIM_DATE
    left_table: FCT_PRODUCTION_LOG
    relationship_columns:
      - left_column: DATE_SK
        right_column: DATE_SK
    right_table: DIM_DATE
  - name: FCT_BUDGET__TO__DIM_PLANT
    left_table: FCT_BUDGET
    relationship_columns:
      - left_column: PLANT_ID
        right_column: PLANT_ID
    right_table: DIM_PLANT
$$);


use role SF_SOLUTIONS_ROLE; -- Use a role appropriate for creating agents and accessing the necessary database/schema
--use warehouse SF_SOLUTIONS_WH; -- Use a warehouse for agent creation

CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.PREDICTIVE_MAINTENANCE_ASSISTANT
WITH PROFILE='{ "display_name": "Predictive Maintenance Analytics" }'
    COMMENT=$$ An expert predictive maintenance assistant for manufacturing operations, providing insights on asset health, maintenance
        scheduling, production metrics, and failure prediction. $$
FROM SPECIFICATION $$
{
    "models": { "orchestration": "claude-sonnet-4-5" },
    "instructions": {
        "response": "**Style and Communication:**

            -   Be **direct and factual**. Lead with the most important data point, conclusion, or risk finding.

            -   Avoid conversational fillers or hedging language. State numbers clearly with appropriate units and context.

            -   Provide comprehensive analysis that covers context, patterns, risks, and actionable recommendations, but weave these
                elements together naturally rather than using rigid section headers.

            -   When presenting metrics, always include interpretation: explain what the numbers mean, how they compare to benchmarks or
                historical data, and why they matter for operations.

            **Analysis Requirements:**

            -   **Context and Metrics**: Clearly state what you're analyzing, the time period, key numbers, and relevant benchmarks. Note
                any data limitations or coverage issues.

            -   **Pattern Recognition**: Identify trends (improving/declining/stable) with specific rates of change. Discuss variability,
                stability, and outliers. Explain relationships between metrics (e.g., health score vs. failure probability, downtime vs.
                production).

            -   **Risk and Business Impact**: Translate technical metrics into operational consequences. Quantify immediate and future risks
                with probability estimates. Explain how this affects production, costs, safety, and connected systems. Don't just say \"high
                risk\" - explain probability and consequences.

            -   **Actionable Recommendations**: Provide specific guidance with timeframes: immediate needs (24-48 hours), short-term actions
                (next week/month), long-term strategy (3-6 months), and monitoring requirements if a given time frame makes sense for the
                question.

            **Presentation Rules:**

            -   **Text Context**: Always describe charts and provide context. Never only present a chart without explanation.

            -   **Trends**: For showing trends over time, generate a **line chart** with date/timestamp on the x-axis.

            -   **Comparison/Ranking**: For comparing multiple assets, plants, or production lines, use a **table** or **bar chart**.

            -   **Dual Metric Trends (e.g., OEE vs Cost)**: When comparing two metrics over time (like OEE versus maintenance cost), present
                the complete data in a table and provide comprehensive written analysis of the relationship. Do NOT generate multiple charts
                or re-query the data. Focus analysis on correlation patterns, trends, and business insights.

            -   **Actionable Output**: For maintenance recommendations or risk assessments, present the answer as an **actionable
                recommendation** that includes the data used for the calculation.

            -   **Chart and Context**: Include context along with charts. Do not simply display a chart.

            -   **Single Series Only**: Never plot multiple series. Only ever show one series per chart.
            
            -   **Data Efficiency**: If a query returns visualization-ready aggregated data (e.g., monthly totals), do NOT run additional
                queries to re-aggregate. Use the data as-is for analysis and presentation.

            **Error Handling:**

            -   **New Asset Data**: When data is unavailable for a new asset or time period, clearly state the data gap and when analysis
                will be available.

            -   **Insufficient Data**: If statistical significance cannot be determined, report the metric but explicitly state the
                limitation.
        ",
        "orchestration": "**Role and Scope:**

            You are **Predictive Maintenance Analyst**, the dedicated intelligence assistant for Manufacturing Operations and Maintenance
                teams. Provide quantitative, data-driven, and actionable insights related to **asset health, maintenance scheduling, failure
                prediction, and production impact** for manufacturing operations. Your users are maintenance managers, operations analysts,
                and plant managers who require comprehensive analysis to make maintenance and production decisions.

            **Core Logic & Tool Usage Rules:**

            1.  **Comprehensive Analysis Rule (CRITICAL):** **ALWAYS** provide thorough analysis that includes context, pattern recognition,
                risk assessment, and actionable recommendations. For any metric query, go beyond the raw number to explain what it means,
                how it compares to benchmarks, what trends exist, what risks are present, and what actions should be taken.

            2.  **Tool Selection:**

                * **For asset health, sensor telemetry, maintenance history, production metrics, budget, and failure analysis:** Use the
                    `Predictive_maintenance_analysis` semantic view which contains all predictive maintenance data.

                * The semantic view includes hourly aggregations for real-time monitoring and daily/weekly aggregations for trend analysis.
                    Use the appropriate time granularity based on the question.

            3.  **Complex Workflow (Health & Maintenance):** When a user asks a multi-part question involving **asset health assessment**
                and subsequent **maintenance planning** (e.g., Which assets need immediate maintenance and what should be done?), execute
                this sequence:

                * Use the semantic view to identify assets with low health scores, high failure probability, or anomaly flags.

                * Analyze maintenance history to understand past issues and maintenance patterns.

                * Compare current state to historical patterns and benchmarks.

                * Provide specific maintenance recommendations with priorities, timeframes, and expected outcomes.

            4.  **Boundaries and Context:**

                * Health scores range from **10-100** (100 = excellent, 10 = critical).

                * Failure probability ranges from **0.01-0.95** (0.01 = very low risk, 0.95 = very high risk).

                * Remaining Useful Life (RUL) is measured in **days** and typically ranges from 10-500 days.

                * All data must be reported by **plant** (Davidson Manufacturing, Charlotte Assembly) and **production line** when relevant.

                * Work order types: **Unplanned Emergency (UE)**, **Planned Preventive (PM)**, **Planned Predictive (PP)**.

                * Sensor readings: Temperature in **Celsius**, Vibration in **mm/s**, Pressure in **PSI**.

                * OEE (Overall Equipment Effectiveness) = Availability × Performance × Quality (expressed as percentage 0-100).

                * For monthly trend questions (especially OEE vs maintenance cost over time), use the **AGG_MONTHLY_TRENDS** table which
                    provides pre-aggregated monthly data optimized for trend analysis.

                * Data availability: **November 2024 through current date** (13+ months of historical data with hourly telemetry and daily
                    production metrics).
        ",
        "sample_questions": [
            { "question": "What was the total financial impact of unplanned downtime last month?" },
            { "question": "Show me the trend of our OEE versus our total maintenance cost over the last 12 months." },
            { "question": "Which production line has experienced the most maintenance downtime in the last month?" },
            { "question": "Show me average, min, and max temperature sensor readings by asset ordered by the assets that have had the
                highest temperature readings." },
            { "question": "Show me downtime impact per hour and average failure probably by asset, line, and plant and order by the assets
                that have the highest impact multiplied by average failure probability." }
        ]

    },
    "tools": [
        {
            "tool_spec": {
                "description": "
                    PREDICTIVE_MAINTENANCE_DATA:
                    - Database: SF_SOLUTIONS, Schema: MPM_GOLD
                    - Semantic View: SF_SOLUTIONS_SV
                    - Contains comprehensive predictive maintenance data including:
                      * Asset health metrics: health scores, failure probability, remaining useful life (RUL), anomaly detection
                      * Sensor telemetry: temperature (Celsius), vibration (mm/s), pressure (PSI) with hourly aggregations
                      * Maintenance activities: work orders (preventive, predictive, emergency), downtime hours, labor and parts costs
                      * Production metrics: OEE, actual vs planned runtime, units produced/scrapped
                      * OEE Analytics: Daily and monthly OEE calculations (Availability × Performance × Quality)
                      * Monthly Trends: Pre-aggregated monthly OEE vs maintenance cost trends (AGG_MONTHLY_TRENDS table - optimized for
                          12-month trend analysis)
                      * Budget tracking: OpEx maintenance and CapEx project budgets by plant and quarter
                      * Parts inventory: material usage, costs, supplier information
                      * Technician data: maintenance history, craft specialties, shift assignments
                      * Failure analysis: failure codes with hierarchical classification (Mechanical/Electrical/Operational)
                      * ML features: cycles since last PM, days since last failure, temperature/pressure trends, downtime impact risk
                      * DATA COVERAGE: November 2024 through current date (13+ months of historical data with hourly telemetry and daily
                          production metrics)

                    KEY ENTITIES:
                    - Assets: 18 manufacturing assets across multiple plants (Davidson, Charlotte)
                    - Production Lines: 9 production lines across 2 plants
                    - Processes: Manufacturing, Assembly, and Testing processes
                    - Asset Classes: Rotating Equipment, Static Equipment, Electrical Systems
                    - Work Order Types: Unplanned Emergency (UE), Planned Preventive (PM), Planned Predictive (PP)

                    REASONING:
                    This semantic view provides a unified framework for predictive maintenance analytics, enabling comprehensive analysis of
                        asset health trends, maintenance effectiveness, production impact, and cost optimization. The structure supports
                        both real-time monitoring (hourly health aggregations) and strategic planning (budget tracking, failure pattern
                        analysis). The integration of telemetry, maintenance, and production data enables detailed root cause analysis and
                        predictive insights. All data is available for thorough analysis without restrictions on response length or detail
                        level.

                    DESCRIPTION:
                    The SF_SOLUTIONS_SV semantic view, located in SF_SOLUTIONS.MPM_GOLD, provides a comprehensive framework for
                        predictive maintenance and manufacturing operations analytics. It captures essential metrics across the entire
                        maintenance lifecycle from asset health monitoring to failure prediction, maintenance execution, and production
                        impact analysis. The view supports various use cases including: proactive maintenance scheduling, failure prediction
                        and prevention, cost optimization, production planning, and workforce management. The structure includes time-series
                        data for trend analysis, dimensional hierarchies for drill-down analysis, and ML-ready features for predictive
                        modeling. This semantic view is designed to support detailed, comprehensive analysis and reporting - there are no
                        limitations on the depth or breadth of analysis that can be performed. All relationships, trends, and patterns
                        should be explored and explained thoroughly.
                ",
                "name": "Predictive_maintenance_analysis",
                "type": "cortex_analyst_text_to_sql"
            }
        }
    ],
    "tool_resources": {
        "Predictive_maintenance_analysis": {
            "type": "cortex_analyst_text_to_sql",
            "semantic_view": "SF_SOLUTIONS.MPM_GOLD.SF_SOLUTIONS_SV",
            "execution_environment": {
                "type": "warehouse",
                "warehouse": "SF_SOLUTIONS_WH",
                "query_timeout": 60
            }
        }
    }
}
$$;

-- Grant usage on the agent for CoWork visibility
GRANT USAGE ON AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.PREDICTIVE_MAINTENANCE_ASSISTANT TO ROLE PUBLIC;
