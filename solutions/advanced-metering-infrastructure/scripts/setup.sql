-- =============================================================================
-- Solution: Advanced Metering Infrastructure (AMI 2.0) - setup
-- Database: SF_SOLUTIONS
-- Schemas:  AMI_RAW, AMI_CURATED, AMI_MART, AMI_OBSERVABILITY, AMI_ML, AMI_SHARED
-- Creates schemas, roles, tables and the synthetic-data procedures.
-- Run order: setup.sql -> data.sql -> pipeline.sql
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Shared infrastructure (idempotent; never dropped by teardown)
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Solution schemas
CREATE SCHEMA IF NOT EXISTS AMI_RAW           COMMENT = 'Landing VARIANT from MDMS / head-end';
CREATE SCHEMA IF NOT EXISTS AMI_CURATED       COMMENT = 'Conformed dimensions + canonical INTERVAL_READ_15MIN';
CREATE SCHEMA IF NOT EXISTS AMI_MART          COMMENT = 'Billing, TOU charges, anomaly events';
CREATE SCHEMA IF NOT EXISTS AMI_OBSERVABILITY COMMENT = 'Pipeline audit, SLA, DQ metrics';
CREATE SCHEMA IF NOT EXISTS AMI_ML            COMMENT = 'Training views, anomaly models';
CREATE SCHEMA IF NOT EXISTS AMI_SHARED        COMMENT = 'Secure views exposed to CIS/CRM/partners';

-- Roles: owner/engineer/analyst/ops/share hierarchy, scoped to the AMI schemas.
-- AMI_OWNER owns the six AMI schemas only (never the shared SF_SOLUTIONS DB).
CREATE ROLE IF NOT EXISTS AMI_OWNER   COMMENT = 'Owns the AMI schemas in SF_SOLUTIONS';
CREATE ROLE IF NOT EXISTS AMI_ENG     COMMENT = 'Read/write curated + mart';
CREATE ROLE IF NOT EXISTS AMI_ANALYST COMMENT = 'Read mart only';
CREATE ROLE IF NOT EXISTS AMI_OPS     COMMENT = 'Read observability, execute pipeline tasks';
CREATE ROLE IF NOT EXISTS AMI_SHARE   COMMENT = 'Consume AMI_SHARED secure views only';

GRANT ROLE AMI_OWNER   TO ROLE SYSADMIN;
GRANT ROLE AMI_ENG     TO ROLE AMI_OWNER;
GRANT ROLE AMI_ANALYST TO ROLE AMI_ENG;
GRANT ROLE AMI_OPS     TO ROLE AMI_OWNER;
GRANT ROLE AMI_SHARE   TO ROLE AMI_OWNER;

GRANT USAGE ON DATABASE SF_SOLUTIONS TO ROLE AMI_OWNER;
GRANT USAGE ON DATABASE SF_SOLUTIONS TO ROLE AMI_ANALYST;
GRANT USAGE ON DATABASE SF_SOLUTIONS TO ROLE AMI_OPS;
GRANT USAGE ON DATABASE SF_SOLUTIONS TO ROLE AMI_SHARE;
GRANT OWNERSHIP ON SCHEMA SF_SOLUTIONS.AMI_RAW TO ROLE AMI_OWNER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA SF_SOLUTIONS.AMI_CURATED TO ROLE AMI_OWNER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA SF_SOLUTIONS.AMI_MART TO ROLE AMI_OWNER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA SF_SOLUTIONS.AMI_OBSERVABILITY TO ROLE AMI_OWNER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA SF_SOLUTIONS.AMI_ML TO ROLE AMI_OWNER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA SF_SOLUTIONS.AMI_SHARED TO ROLE AMI_OWNER COPY CURRENT GRANTS;

GRANT USAGE ON WAREHOUSE SF_SOLUTIONS_WH TO ROLE AMI_OWNER;
GRANT USAGE ON WAREHOUSE SF_SOLUTIONS_WH TO ROLE AMI_ANALYST;
GRANT USAGE ON WAREHOUSE SF_SOLUTIONS_WH TO ROLE AMI_OPS;

-- Scale setting read by data.sql (default 100,000 meters). To build a smaller demo,
-- run this before data.sql:  UPDATE SF_SOLUTIONS.AMI_CURATED.AMI_CONFIG SET VALUE = '1000' WHERE KEY = 'N_METERS';
CREATE TABLE IF NOT EXISTS SF_SOLUTIONS.AMI_CURATED.AMI_CONFIG (KEY VARCHAR, VALUE VARCHAR);
MERGE INTO SF_SOLUTIONS.AMI_CURATED.AMI_CONFIG t USING (SELECT 'N_METERS' AS KEY, '100000' AS VALUE) s
  ON t.KEY = s.KEY
  WHEN NOT MATCHED THEN INSERT VALUES (s.KEY, s.VALUE);

-- -------------------------------------------------------------------------
-- Dimension and reference tables
-- Source: sql/01_dimensions/01_dimension_ddl.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_CURATED;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- ---- Substation / Feeder / Transformer hierarchy ---------------------
CREATE OR REPLACE TABLE SUBSTATION (
  SUBSTATION_ID        VARCHAR      NOT NULL,
  SUBSTATION_NAME      VARCHAR,
  UTILITY_TERRITORY    VARCHAR      NOT NULL,
  LAT                  NUMBER(9,6),
  LON                  NUMBER(9,6),
  CONSTRAINT PK_SUBSTATION PRIMARY KEY (SUBSTATION_ID)
);

CREATE OR REPLACE TABLE FEEDER (
  FEEDER_ID            VARCHAR      NOT NULL,
  SUBSTATION_ID        VARCHAR      NOT NULL,
  UTILITY_TERRITORY    VARCHAR      NOT NULL,
  VOLTAGE_KV           NUMBER(6,2),
  CONSTRAINT PK_FEEDER PRIMARY KEY (FEEDER_ID)
);

CREATE OR REPLACE TABLE TRANSFORMER (
  TRANSFORMER_ID       VARCHAR      NOT NULL,
  FEEDER_ID            VARCHAR      NOT NULL,
  KVA_RATING           NUMBER(8,2),
  PHASE                VARCHAR,
  CONSTRAINT PK_TRANSFORMER PRIMARY KEY (TRANSFORMER_ID)
);

-- ---- Service point / premise -----------------------------------------
CREATE OR REPLACE TABLE SERVICE_POINT (
  SERVICE_POINT_ID     VARCHAR      NOT NULL,
  ADDRESS_ID           VARCHAR,
  PREMISE_TYPE         VARCHAR,           -- RES | SMB | CNI
  FEEDER_ID            VARCHAR      NOT NULL,
  TRANSFORMER_ID       VARCHAR      NOT NULL,
  UTILITY_TERRITORY    VARCHAR      NOT NULL,
  LAT                  NUMBER(9,6),
  LON                  NUMBER(9,6),
  CONSTRAINT PK_SERVICE_POINT PRIMARY KEY (SERVICE_POINT_ID)
);

-- ---- Meter -----------------------------------------------------------
CREATE OR REPLACE TABLE METER (
  METER_ID             VARCHAR      NOT NULL,
  SERVICE_POINT_ID     VARCHAR      NOT NULL,
  METER_TYPE           VARCHAR,           -- RES | SMB | CNI | DER
  HAS_DER              BOOLEAN      DEFAULT FALSE,
  INSTALL_DATE         DATE,
  STATUS               VARCHAR,           -- ACTIVE | RETIRED
  UTILITY_TERRITORY    VARCHAR      NOT NULL,
  TIMEZONE             VARCHAR      NOT NULL,
  FIRMWARE_VERSION     VARCHAR,
  CONSTRAINT PK_METER PRIMARY KEY (METER_ID)
);

-- ---- Customer --------------------------------------------------------
CREATE OR REPLACE TABLE CUSTOMER (
  CUSTOMER_ID          VARCHAR      NOT NULL,
  CIS_ACCOUNT_ID       VARCHAR,
  SEGMENT              VARCHAR,
  RATE_PLAN_ID         VARCHAR,
  START_DATE           DATE,
  END_DATE             DATE,
  CONSTRAINT PK_CUSTOMER PRIMARY KEY (CUSTOMER_ID)
);

-- ---- Meter-Service Point link (SCD2) ---------------------------------
CREATE OR REPLACE TABLE METER_SERVICE_POINT_LINK (
  METER_ID             VARCHAR      NOT NULL,
  SERVICE_POINT_ID     VARCHAR      NOT NULL,
  CUSTOMER_ID          VARCHAR,
  EFFECTIVE_FROM       TIMESTAMP_NTZ NOT NULL,
  EFFECTIVE_TO         TIMESTAMP_NTZ,
  IS_CURRENT           BOOLEAN
);

-- ---- TIME_DIM @ 15-min grain -----------------------------------------
CREATE OR REPLACE TABLE TIME_DIM (
  TS_UTC               TIMESTAMP_NTZ NOT NULL,
  LOCAL_DATE           DATE,
  LOCAL_TIME           TIME,
  HOUR_LOCAL           NUMBER(2),
  DAY_OF_WEEK          NUMBER(1),
  DAY_TYPE             VARCHAR,     -- WEEKDAY | WEEKEND | HOLIDAY
  MONTH                NUMBER(2),
  SEASON               VARCHAR,     -- SUMMER | WINTER | SHOULDER
  IS_HOLIDAY           BOOLEAN
);

-- ---- TOU Rate Plan / Window ------------------------------------------
CREATE OR REPLACE TABLE TOU_RATE_PLAN (
  RATE_PLAN_ID         VARCHAR      NOT NULL,
  PLAN_NAME            VARCHAR,
  SEASON               VARCHAR,
  CURRENCY             VARCHAR      DEFAULT 'USD',
  EFFECTIVE_FROM       DATE,
  EFFECTIVE_TO         DATE,
  CONSTRAINT PK_TOU_RATE_PLAN PRIMARY KEY (RATE_PLAN_ID)
);

CREATE OR REPLACE TABLE TOU_RATE_WINDOW (
  RATE_WINDOW_ID       VARCHAR      NOT NULL,
  RATE_PLAN_ID         VARCHAR      NOT NULL,
  DAY_TYPE             VARCHAR,
  SEASON               VARCHAR,
  START_TIME           TIME,
  END_TIME             TIME,
  TOU_BUCKET           VARCHAR,     -- ON_PEAK | OFF_PEAK | SHOULDER | CRITICAL
  ENERGY_RATE_PER_KWH  NUMBER(8,5),
  DEMAND_RATE_PER_KW   NUMBER(8,4),
  CONSTRAINT PK_TOU_RATE_WINDOW PRIMARY KEY (RATE_WINDOW_ID)
);

-- ---- Billing period --------------------------------------------------
CREATE OR REPLACE TABLE BILLING_PERIOD (
  BILLING_PERIOD_ID    VARCHAR      NOT NULL,
  CIS_ACCOUNT_ID       VARCHAR,
  SERVICE_POINT_ID     VARCHAR,
  BILL_CYCLE           VARCHAR,
  START_DATE           DATE,
  END_DATE             DATE,
  CIS_BILLED_KWH       NUMBER(14,4),
  CONSTRAINT PK_BILLING_PERIOD PRIMARY KEY (BILLING_PERIOD_ID)
);

-- -------------------------------------------------------------------------
-- Raw landing tables and stage
-- Source: sql/02_raw/01_raw_landing.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_RAW;

CREATE OR REPLACE TABLE INTERVAL_READ_15MIN_RAW (
  RAW_PAYLOAD      VARIANT,
  SOURCE_FILE      VARCHAR,
  SCHEMA_VERSION   VARCHAR       DEFAULT 'v1',
  INGESTED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (DATE_TRUNC('day', INGESTED_AT));

CREATE OR REPLACE TABLE METER_EVENT (
  EVENT_ID         VARCHAR,
  METER_ID         VARCHAR,
  EVENT_TS         TIMESTAMP_NTZ,
  EVENT_TYPE       VARCHAR,          -- OUTAGE | RESTORE | TAMPER | COMMS_LOSS
  EVENT_PAYLOAD    VARIANT
);

-- Stage for file-based fallback ingest
CREATE STAGE IF NOT EXISTS LANDING_STAGE
  FILE_FORMAT = (TYPE = JSON);

-- -------------------------------------------------------------------------
-- Canonical 15-minute interval fact
-- Source: sql/03_canonical_dt/01_canonical_table.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_CURATED;

CREATE OR REPLACE TABLE INTERVAL_READ_15MIN (
  METER_ID           VARCHAR       NOT NULL,
  READ_TS            TIMESTAMP_NTZ NOT NULL,   -- UTC, 15-min aligned
  READ_LOCAL_TS      TIMESTAMP_NTZ,
  KWH_DELIVERED      NUMBER(14,4),
  KWH_RECEIVED       NUMBER(14,4),
  DEMAND_KW          NUMBER(10,4),
  VOLTAGE_V          NUMBER(6,2),
  QUALITY_FLAG       VARCHAR,                  -- 'A' actual, 'E' estimated, 'F' failed
  VEE_STATUS         VARCHAR,                  -- VALID | ESTIMATED | EDITED | FAILED
  ESTIMATION_METHOD  VARCHAR,
  EVENT_ID           VARCHAR,
  UTILITY_TERRITORY  VARCHAR,                  -- denormalized for RAP pushdown
  SOURCE_FILE        VARCHAR,
  INGESTED_AT        TIMESTAMP_NTZ,
  INGESTION_LAG_SEC  NUMBER,
  PRIMARY KEY (METER_ID, READ_TS)
)
CLUSTER BY (READ_TS, METER_ID);

-- -------------------------------------------------------------------------
-- Synthetic interval generator procedures
-- Source: sql/10_synthetic_data/01_generator_procedure.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_CURATED;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Base load per segment (kWh per 15-min interval, approximate)
--   RES: ~0.5     SMB: ~3.0     CNI: ~20.0
-- Peak factor 17-21 local: 1.6 / 1.4 / 1.3
-- Summer months: 1.3   Winter: 1.1   Shoulder: 1.0
-- Weekend factor: 0.9 RES, 0.6 CNI

CREATE OR REPLACE PROCEDURE SP_GENERATE_MONTH(MONTH_OFFSET NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  start_dt DATE;
  end_dt   DATE;
  row_ct   NUMBER;
BEGIN
  start_dt := DATEADD(month, :MONTH_OFFSET, DATE_TRUNC('month', DATEADD(year, -1, CURRENT_DATE())));
  end_dt   := DATEADD(month, 1, :start_dt);

  INSERT INTO AMI_CURATED.INTERVAL_READ_15MIN
  WITH meter_base AS (
    SELECT
      m.METER_ID, m.METER_TYPE, m.HAS_DER, m.UTILITY_TERRITORY, m.TIMEZONE,
      CASE m.METER_TYPE WHEN 'RES' THEN 0.5 WHEN 'SMB' THEN 3.0 ELSE 20.0 END AS base_kwh,
      -- persistent per-meter factor so each meter has its own "level"
      0.7 + (MOD(ABS(HASH(m.METER_ID)), 60)/100.0) AS level_factor
    FROM AMI_CURATED.METER m
  ),
  t AS (
    SELECT TS_UTC, LOCAL_TIME, HOUR_LOCAL, DAY_OF_WEEK, DAY_TYPE, MONTH, SEASON
    FROM AMI_CURATED.TIME_DIM
    WHERE TS_UTC >= :start_dt AND TS_UTC < :end_dt
  )
  SELECT
    mb.METER_ID,
    t.TS_UTC AS READ_TS,
    CONVERT_TIMEZONE('UTC', mb.TIMEZONE, t.TS_UTC)::TIMESTAMP_NTZ AS READ_LOCAL_TS,
    -- Energy delivered (non-negative). Apply hour-of-day / season / weekday / noise
    GREATEST(0,
      mb.base_kwh
      * mb.level_factor
      * CASE
          WHEN mb.METER_TYPE = 'CNI' AND t.DAY_TYPE = 'WEEKEND' THEN 0.6
          WHEN t.DAY_TYPE = 'WEEKEND' THEN 0.9
          ELSE 1.0 END
      * CASE t.SEASON WHEN 'SUMMER' THEN 1.3 WHEN 'WINTER' THEN 1.1 ELSE 1.0 END
      * CASE
          WHEN t.HOUR_LOCAL BETWEEN 17 AND 20 THEN 1.6
          WHEN t.HOUR_LOCAL BETWEEN 7 AND 9   THEN 1.2
          WHEN t.HOUR_LOCAL BETWEEN 0 AND 5   THEN 0.5
          ELSE 1.0 END
      * (1 + NORMAL(0, 0.05, RANDOM()))
    )::NUMBER(14,4) AS KWH_DELIVERED,
    -- DER solar generation, negative offset via kwh_received (10-14h peak)
    CASE WHEN mb.HAS_DER AND t.HOUR_LOCAL BETWEEN 9 AND 16
         THEN (mb.base_kwh * 0.8 * (1 - ABS(t.HOUR_LOCAL - 12.5)/4.0)
               * (1 + NORMAL(0, 0.1, RANDOM())))::NUMBER(14,4)
         ELSE 0 END AS KWH_RECEIVED,
    -- Demand kW ~ kwh * 4 (per hour) + noise
    (mb.base_kwh * mb.level_factor
     * CASE t.SEASON WHEN 'SUMMER' THEN 1.3 WHEN 'WINTER' THEN 1.1 ELSE 1.0 END
     * 4.5 * (1 + NORMAL(0, 0.08, RANDOM())))::NUMBER(10,4) AS DEMAND_KW,
    (240 + NORMAL(0, 3, RANDOM()))::NUMBER(6,2) AS VOLTAGE_V,
    -- Quality: 97% actual, 2% estimated, 1% late flag
    CASE WHEN UNIFORM(0,1000,RANDOM()) < 20 THEN 'E'
         WHEN UNIFORM(0,1000,RANDOM()) < 10 THEN 'F'
         ELSE 'A' END AS QUALITY_FLAG,
    CASE WHEN UNIFORM(0,1000,RANDOM()) < 20 THEN 'ESTIMATED'
         WHEN UNIFORM(0,1000,RANDOM()) < 10 THEN 'FAILED'
         ELSE 'VALID' END AS VEE_STATUS,
    CASE WHEN UNIFORM(0,1000,RANDOM()) < 20 THEN 'LOAD_PROFILE' ELSE NULL END AS ESTIMATION_METHOD,
    NULL AS EVENT_ID,
    mb.UTILITY_TERRITORY,
    'backfill-' || TO_CHAR(:start_dt,'YYYYMM') AS SOURCE_FILE,
    t.TS_UTC + INTERVAL '5 seconds' AS INGESTED_AT,
    -- Occasional late arrivals: 2% of reads get +30-240 min lag
    CASE WHEN UNIFORM(0,100,RANDOM()) < 2
         THEN UNIFORM(1800, 14400, RANDOM())
         ELSE 5 END AS INGESTION_LAG_SEC
  FROM meter_base mb
  CROSS JOIN t
  -- Inject ~0.5% missing intervals
  WHERE UNIFORM(0,1000,RANDOM()) >= 5;

  row_ct := SQLROWCOUNT;
  RETURN 'Generated ' || :row_ct || ' rows for month starting ' || :start_dt::STRING;
END;
$$;

-- Generate a range of months (0 = first month of the one-year window)
CREATE OR REPLACE PROCEDURE SP_GENERATE_ALL_MONTHS(FROM_OFFSET NUMBER, TO_OFFSET NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  i NUMBER;
  result STRING DEFAULT '';
BEGIN
  FOR i IN :FROM_OFFSET TO :TO_OFFSET DO
    CALL SP_GENERATE_MONTH(:i);
  END FOR;
  SELECT COUNT(*) INTO :result FROM AMI_CURATED.INTERVAL_READ_15MIN;
  RETURN 'Total rows: ' || :result;
END;
$$;

SELECT 'AMI setup complete. Next: run scripts/data.sql' AS STATUS;
