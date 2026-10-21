-- =============================================================================
-- Solution: Advanced Metering Infrastructure (AMI 2.0) - pipeline
-- Database: SF_SOLUTIONS
-- Schemas:  AMI_RAW, AMI_CURATED, AMI_MART, AMI_OBSERVABILITY, AMI_ML, AMI_SHARED
-- Creates dynamic tables, observability, anomaly models, governance, semantic view, search and agent.
-- Run after data.sql. The scoring task and SLA alert are created SUSPENDED.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- -------------------------------------------------------------------------
-- Rollup dynamic tables
-- Source: sql/04_rollups/01_rollup_dts.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_CURATED;

-- Blueprint DT: VARIANT -> typed canonical shape for newly-landed reads
CREATE OR REPLACE DYNAMIC TABLE DT_NEW_READS_NORMALIZED
  TARGET_LAG = '1 minute'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  raw.RAW_PAYLOAD:meter_id::VARCHAR                       AS METER_ID,
  TO_TIMESTAMP_NTZ(raw.RAW_PAYLOAD:read_ts::VARCHAR)      AS READ_TS,
  CONVERT_TIMEZONE('UTC', m.TIMEZONE, TO_TIMESTAMP_NTZ(raw.RAW_PAYLOAD:read_ts::VARCHAR))::TIMESTAMP_NTZ AS READ_LOCAL_TS,
  raw.RAW_PAYLOAD:kwh_delivered::NUMBER(14,4)             AS KWH_DELIVERED,
  raw.RAW_PAYLOAD:kwh_received::NUMBER(14,4)              AS KWH_RECEIVED,
  raw.RAW_PAYLOAD:demand_kw::NUMBER(10,4)                 AS DEMAND_KW,
  raw.RAW_PAYLOAD:voltage_v::NUMBER(6,2)                  AS VOLTAGE_V,
  raw.RAW_PAYLOAD:quality_flag::VARCHAR                   AS QUALITY_FLAG,
  raw.RAW_PAYLOAD:vee_status::VARCHAR                     AS VEE_STATUS,
  raw.RAW_PAYLOAD:estimation_method::VARCHAR              AS ESTIMATION_METHOD,
  m.UTILITY_TERRITORY,
  raw.SOURCE_FILE,
  raw.INGESTED_AT,
  DATEDIFF(second, TO_TIMESTAMP_NTZ(raw.RAW_PAYLOAD:read_ts::VARCHAR), raw.INGESTED_AT) AS INGESTION_LAG_SEC
FROM AMI_RAW.INTERVAL_READ_15MIN_RAW raw
JOIN AMI_CURATED.METER m
  ON m.METER_ID = raw.RAW_PAYLOAD:meter_id::VARCHAR
-- Last-write-wins dedup for late arrivals / replays
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY raw.RAW_PAYLOAD:meter_id, raw.RAW_PAYLOAD:read_ts
  ORDER BY raw.INGESTED_AT DESC
) = 1;

-- Hourly rollup
CREATE OR REPLACE DYNAMIC TABLE DT_HOURLY_ROLLUP
  TARGET_LAG = '5 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  METER_ID,
  DATE_TRUNC('hour', READ_TS)          AS ROLLUP_TS,
  'HOUR'                               AS ROLLUP_GRAIN,
  UTILITY_TERRITORY,
  SUM(KWH_DELIVERED)                   AS KWH_DELIVERED,
  SUM(KWH_RECEIVED)                    AS KWH_RECEIVED,
  SUM(KWH_DELIVERED - KWH_RECEIVED)    AS KWH_NET,
  MAX(DEMAND_KW)                       AS MAX_DEMAND_KW,
  MIN(VOLTAGE_V)                       AS MIN_VOLTAGE,
  MAX(VOLTAGE_V)                       AS MAX_VOLTAGE,
  AVG(VOLTAGE_V)                       AS AVG_VOLTAGE,
  COUNT(*)                             AS SOURCE_INTERVAL_COUNT,
  4                                    AS EXPECTED_INTERVAL_COUNT,
  (COUNT(*)/4.0 * 100)::NUMBER(5,2)    AS COMPLETENESS_PCT,
  (SUM(CASE WHEN VEE_STATUS='VALID' THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0)*100)::NUMBER(5,2) AS VEE_PASS_PCT
FROM AMI_CURATED.INTERVAL_READ_15MIN
GROUP BY METER_ID, DATE_TRUNC('hour', READ_TS), UTILITY_TERRITORY;

-- Daily rollup (built on hourly for efficiency)
CREATE OR REPLACE DYNAMIC TABLE DT_DAILY_ROLLUP
  TARGET_LAG = '10 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  METER_ID,
  DATE_TRUNC('day', ROLLUP_TS)         AS ROLLUP_TS,
  'DAY'                                AS ROLLUP_GRAIN,
  UTILITY_TERRITORY,
  SUM(KWH_DELIVERED)                   AS KWH_DELIVERED,
  SUM(KWH_RECEIVED)                    AS KWH_RECEIVED,
  SUM(KWH_NET)                         AS KWH_NET,
  MAX(MAX_DEMAND_KW)                   AS MAX_DEMAND_KW,
  MIN(MIN_VOLTAGE)                     AS MIN_VOLTAGE,
  MAX(MAX_VOLTAGE)                     AS MAX_VOLTAGE,
  AVG(AVG_VOLTAGE)                     AS AVG_VOLTAGE,
  SUM(SOURCE_INTERVAL_COUNT)           AS SOURCE_INTERVAL_COUNT,
  96                                   AS EXPECTED_INTERVAL_COUNT,
  (SUM(SOURCE_INTERVAL_COUNT)/96.0*100)::NUMBER(5,2) AS COMPLETENESS_PCT,
  AVG(VEE_PASS_PCT)::NUMBER(5,2)       AS VEE_PASS_PCT
FROM AMI_CURATED.DT_HOURLY_ROLLUP
GROUP BY METER_ID, DATE_TRUNC('day', ROLLUP_TS), UTILITY_TERRITORY;

-- Monthly rollup (built on daily)
CREATE OR REPLACE DYNAMIC TABLE DT_MONTHLY_ROLLUP
  TARGET_LAG = '1 hour'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  METER_ID,
  DATE_TRUNC('month', ROLLUP_TS)       AS ROLLUP_TS,
  'MONTH'                              AS ROLLUP_GRAIN,
  UTILITY_TERRITORY,
  SUM(KWH_DELIVERED)                   AS KWH_DELIVERED,
  SUM(KWH_RECEIVED)                    AS KWH_RECEIVED,
  SUM(KWH_NET)                         AS KWH_NET,
  MAX(MAX_DEMAND_KW)                   AS MAX_DEMAND_KW,
  MIN(MIN_VOLTAGE)                     AS MIN_VOLTAGE,
  MAX(MAX_VOLTAGE)                     AS MAX_VOLTAGE,
  SUM(SOURCE_INTERVAL_COUNT)           AS SOURCE_INTERVAL_COUNT,
  AVG(COMPLETENESS_PCT)::NUMBER(5,2)   AS COMPLETENESS_PCT,
  AVG(VEE_PASS_PCT)::NUMBER(5,2)       AS VEE_PASS_PCT
FROM AMI_CURATED.DT_DAILY_ROLLUP
GROUP BY METER_ID, DATE_TRUNC('month', ROLLUP_TS), UTILITY_TERRITORY;

-- -------------------------------------------------------------------------
-- Channel rollup dynamic tables
-- Source: sql/04_rollups/02_channel_dts.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_CURATED;

-- Hourly rollup per (METER_ID, CHANNEL_CODE)
CREATE OR REPLACE DYNAMIC TABLE DT_CHANNEL_HOURLY_ROLLUP
  TARGET_LAG = '15 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  c.METER_ID,
  c.CHANNEL_CODE,
  c.UOM,
  DATE_TRUNC('hour', c.READ_TS) AS ROLLUP_TS,
  c.UTILITY_TERRITORY,
  SUM(CASE WHEN mc.AGGREGATION = 'SUM' THEN c.VALUE END)::NUMBER(16,4) AS VALUE_SUM,
  MAX(CASE WHEN mc.AGGREGATION = 'MAX' THEN c.VALUE END)::NUMBER(16,4) AS VALUE_MAX,
  MIN(CASE WHEN mc.AGGREGATION = 'MIN' THEN c.VALUE END)::NUMBER(16,4) AS VALUE_MIN,
  AVG(CASE WHEN mc.AGGREGATION = 'AVG' THEN c.VALUE END)::NUMBER(16,4) AS VALUE_AVG,
  -- Resolve to the canonical value using the channel's aggregation rule
  CASE mc.AGGREGATION
    WHEN 'SUM' THEN SUM(c.VALUE)
    WHEN 'MAX' THEN MAX(c.VALUE)
    WHEN 'MIN' THEN MIN(c.VALUE)
    WHEN 'AVG' THEN AVG(c.VALUE)
  END::NUMBER(16,4) AS CANONICAL_VALUE,
  COUNT(*) AS SOURCE_INTERVAL_COUNT,
  4 AS EXPECTED_INTERVAL_COUNT,
  (COUNT(*)/4.0 * 100)::NUMBER(5,2) AS COMPLETENESS_PCT,
  (SUM(CASE WHEN c.VEE_STATUS='VALID' THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0)*100)::NUMBER(5,2) AS VEE_PASS_PCT
FROM AMI_CURATED.INTERVAL_READ_CHANNEL c
JOIN AMI_CURATED.METER_CHANNEL mc
  ON mc.METER_ID = c.METER_ID AND mc.CHANNEL_CODE = c.CHANNEL_CODE
GROUP BY c.METER_ID, c.CHANNEL_CODE, c.UOM, mc.AGGREGATION,
         DATE_TRUNC('hour', c.READ_TS), c.UTILITY_TERRITORY;

-- Daily rollup per (METER_ID, CHANNEL_CODE), built on hourly
CREATE OR REPLACE DYNAMIC TABLE DT_CHANNEL_DAILY_ROLLUP
  TARGET_LAG = '30 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  METER_ID,
  CHANNEL_CODE,
  UOM,
  DATE_TRUNC('day', ROLLUP_TS) AS ROLLUP_DATE,
  UTILITY_TERRITORY,
  SUM(VALUE_SUM)::NUMBER(18,4) AS VALUE_SUM,
  MAX(VALUE_MAX)::NUMBER(18,4) AS VALUE_MAX,
  MIN(VALUE_MIN)::NUMBER(18,4) AS VALUE_MIN,
  AVG(VALUE_AVG)::NUMBER(18,4) AS VALUE_AVG,
  SUM(SOURCE_INTERVAL_COUNT) AS SOURCE_INTERVAL_COUNT,
  96 AS EXPECTED_INTERVAL_COUNT,
  (SUM(SOURCE_INTERVAL_COUNT)/96.0*100)::NUMBER(5,2) AS COMPLETENESS_PCT,
  AVG(VEE_PASS_PCT)::NUMBER(5,2) AS VEE_PASS_PCT
FROM AMI_CURATED.DT_CHANNEL_HOURLY_ROLLUP
GROUP BY METER_ID, CHANNEL_CODE, UOM,
         DATE_TRUNC('day', ROLLUP_TS), UTILITY_TERRITORY;

-- ---- Backward-compat wide view over the long-form fact ---------------
-- Existing DTs (DT_HOURLY_ROLLUP, TOU, billing) and the dashboard continue
-- to read the wide shape via this view.
CREATE OR REPLACE VIEW AMI_CURATED.V_INTERVAL_READ_15MIN_WIDE AS
SELECT
  METER_ID,
  READ_TS,
  MAX(IFF(CHANNEL_CODE='KWH_DEL',  VALUE, NULL))::NUMBER(14,4) AS KWH_DELIVERED,
  MAX(IFF(CHANNEL_CODE='KWH_REC',  VALUE, NULL))::NUMBER(14,4) AS KWH_RECEIVED,
  MAX(IFF(CHANNEL_CODE='KW_DEM',   VALUE, NULL))::NUMBER(10,4) AS DEMAND_KW,
  MAX(IFF(CHANNEL_CODE='VOLT_AVG', VALUE, NULL))::NUMBER(6,2)  AS VOLTAGE_V,
  ANY_VALUE(QUALITY_FLAG)      AS QUALITY_FLAG,
  ANY_VALUE(VEE_STATUS)        AS VEE_STATUS,
  ANY_VALUE(ESTIMATION_METHOD) AS ESTIMATION_METHOD,
  ANY_VALUE(EVENT_ID)          AS EVENT_ID,
  ANY_VALUE(UTILITY_TERRITORY) AS UTILITY_TERRITORY,
  ANY_VALUE(SOURCE_FILE)       AS SOURCE_FILE,
  ANY_VALUE(INGESTED_AT)       AS INGESTED_AT,
  ANY_VALUE(INGESTION_LAG_SEC) AS INGESTION_LAG_SEC
FROM AMI_CURATED.INTERVAL_READ_CHANNEL
GROUP BY METER_ID, READ_TS;

-- -------------------------------------------------------------------------
-- TOU tagging, charge lines and billing readiness
-- Source: sql/05_tou/01_tou_and_billing_dts.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_MART;

CREATE OR REPLACE DYNAMIC TABLE DT_INTERVAL_TOU_TAGGED
  TARGET_LAG = '15 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  i.METER_ID,
  i.READ_TS,
  i.KWH_DELIVERED AS KWH,
  i.DEMAND_KW,
  i.UTILITY_TERRITORY,
  td.DAY_TYPE,
  td.SEASON,
  c.RATE_PLAN_ID,
  rw.RATE_WINDOW_ID,
  rw.TOU_BUCKET,
  rw.ENERGY_RATE_PER_KWH,
  rw.DEMAND_RATE_PER_KW
FROM AMI_CURATED.INTERVAL_READ_15MIN i
JOIN AMI_CURATED.METER_SERVICE_POINT_LINK l
  ON l.METER_ID = i.METER_ID AND l.IS_CURRENT
JOIN AMI_CURATED.CUSTOMER c
  ON c.CUSTOMER_ID = l.CUSTOMER_ID
JOIN AMI_CURATED.TIME_DIM td
  ON td.TS_UTC = i.READ_TS
JOIN AMI_CURATED.TOU_RATE_WINDOW rw
  ON rw.RATE_PLAN_ID = c.RATE_PLAN_ID
 AND rw.DAY_TYPE    = td.DAY_TYPE
 AND (rw.SEASON = 'ALL' OR rw.SEASON = td.SEASON)
 AND td.LOCAL_TIME >= rw.START_TIME
 AND td.LOCAL_TIME <= rw.END_TIME
WHERE i.VEE_STATUS IN ('VALID','ESTIMATED');

CREATE OR REPLACE DYNAMIC TABLE DT_INTERVAL_CHARGE_LINE
  TARGET_LAG = '15 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  METER_ID,
  READ_TS,
  UTILITY_TERRITORY,
  RATE_PLAN_ID,
  RATE_WINDOW_ID,
  TOU_BUCKET,
  KWH,
  DEMAND_KW,
  ENERGY_RATE_PER_KWH,
  DEMAND_RATE_PER_KW,
  (KWH * ENERGY_RATE_PER_KWH)::NUMBER(14,4)             AS ENERGY_CHARGE,
  (DEMAND_KW * DEMAND_RATE_PER_KW / 96.0)::NUMBER(14,4) AS DEMAND_CHARGE
FROM AMI_MART.DT_INTERVAL_TOU_TAGGED;

CREATE OR REPLACE DYNAMIC TABLE DT_BILLING_PERIOD_CONSUMPTION
  TARGET_LAG = '30 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  bp.BILLING_PERIOD_ID,
  bp.CIS_ACCOUNT_ID,
  bp.SERVICE_POINT_ID,
  m.METER_ID,
  bp.START_DATE,
  bp.END_DATE,
  SUM(d.KWH_DELIVERED)   AS KWH_TOTAL,
  SUM(d.KWH_RECEIVED)    AS KWH_RECEIVED,
  SUM(d.KWH_NET)         AS KWH_NET,
  MAX(d.MAX_DEMAND_KW)   AS MAX_DEMAND_KW,
  AVG(d.COMPLETENESS_PCT)::NUMBER(5,2) AS COMPLETENESS_PCT,
  AVG(d.VEE_PASS_PCT)::NUMBER(5,2)     AS VEE_PASS_PCT,
  CASE WHEN AVG(d.COMPLETENESS_PCT) >= 99 AND AVG(d.VEE_PASS_PCT) >= 97 THEN TRUE ELSE FALSE END AS IS_BILLING_READY
FROM AMI_CURATED.BILLING_PERIOD bp
JOIN AMI_CURATED.METER m ON m.SERVICE_POINT_ID = bp.SERVICE_POINT_ID
JOIN AMI_CURATED.DT_DAILY_ROLLUP d
  ON d.METER_ID = m.METER_ID
 AND d.ROLLUP_TS BETWEEN bp.START_DATE AND bp.END_DATE
GROUP BY bp.BILLING_PERIOD_ID, bp.CIS_ACCOUNT_ID, bp.SERVICE_POINT_ID,
         m.METER_ID, bp.START_DATE, bp.END_DATE;

-- Reconciliation view between interval-derived and CIS-reported
CREATE OR REPLACE VIEW V_BILLING_RECONCILIATION AS
SELECT
  bpc.BILLING_PERIOD_ID,
  bpc.CIS_ACCOUNT_ID,
  bpc.METER_ID,
  bpc.KWH_TOTAL             AS INTERVAL_SUM_KWH,
  bp.CIS_BILLED_KWH,
  (bpc.KWH_TOTAL - COALESCE(bp.CIS_BILLED_KWH, bpc.KWH_TOTAL)) AS VARIANCE_KWH,
  CASE WHEN bp.CIS_BILLED_KWH IS NULL OR bp.CIS_BILLED_KWH = 0 THEN NULL
       ELSE ABS(bpc.KWH_TOTAL - bp.CIS_BILLED_KWH) / bp.CIS_BILLED_KWH * 100 END AS VARIANCE_PCT,
  bpc.COMPLETENESS_PCT,
  bpc.IS_BILLING_READY
FROM AMI_MART.DT_BILLING_PERIOD_CONSUMPTION bpc
JOIN AMI_CURATED.BILLING_PERIOD bp
  ON bp.BILLING_PERIOD_ID = bpc.BILLING_PERIOD_ID;

-- -------------------------------------------------------------------------
-- Observability: SLA/DQ metrics, DMFs, SLA alert
-- Source: sql/07_observability/01_observability.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_OBSERVABILITY;

-- ---- Manual pipeline-run audit (stored proc / task log) --------------
CREATE OR REPLACE TABLE PIPELINE_RUN_AUDIT (
  PIPELINE_NAME    VARCHAR       NOT NULL,
  RUN_ID           VARCHAR       NOT NULL,
  START_TIME       TIMESTAMP_NTZ,
  END_TIME         TIMESTAMP_NTZ,
  STATUS           VARCHAR,        -- RUNNING | SUCCESS | FAILED
  ROWS_PROCESSED   NUMBER,
  ERROR_COUNT      NUMBER,
  MESSAGE          VARCHAR
);

-- ---- Convenience view over DT refresh history ------------------------
-- Rolls up all AMI_* dynamic table refresh history from INFORMATION_SCHEMA
CREATE OR REPLACE VIEW V_DT_REFRESH_HISTORY AS
SELECT
  NAME AS DYNAMIC_TABLE_NAME,
  SCHEMA_NAME,
  DATABASE_NAME,
  STATE,
  DATA_TIMESTAMP,
  REFRESH_START_TIME,
  REFRESH_END_TIME,
  DATEDIFF(second, REFRESH_START_TIME, REFRESH_END_TIME) AS DURATION_SEC,
  REFRESH_ACTION,
  STATISTICS
FROM TABLE(SF_SOLUTIONS.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
  DATA_TIMESTAMP_START => DATEADD(day, -7, CURRENT_TIMESTAMP()),
  DATA_TIMESTAMP_END   => CURRENT_TIMESTAMP()
));

-- ---- Ingestion SLA metrics (dynamic table) ---------------------------
CREATE OR REPLACE DYNAMIC TABLE DT_INGESTION_SLA_METRICS
  TARGET_LAG = '15 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  DATE_TRUNC('day', READ_TS)::DATE AS DATE_KEY,
  UTILITY_TERRITORY,
  COUNT(*)                                                          AS TOTAL_READS,
  MAX(INGESTION_LAG_SEC)/60                                         AS MAX_INGESTION_LAG_MIN,
  (AVG(IFF(INGESTION_LAG_SEC <= 900, 1, 0)) * 100)::NUMBER(5,2)     AS PCT_ARRIVED_WITHIN_15MIN,
  COUNT_IF(INGESTION_LAG_SEC > 900)                                 AS LATE_ARRIVAL_COUNT,
  COUNT_IF(INGESTION_LAG_SEC > 3600)                                AS VERY_LATE_ARRIVAL_COUNT
FROM AMI_CURATED.INTERVAL_READ_15MIN
GROUP BY DATE_TRUNC('day', READ_TS)::DATE, UTILITY_TERRITORY;

-- ---- Data quality metrics (dynamic table) ----------------------------
CREATE OR REPLACE DYNAMIC TABLE DT_DATA_QUALITY_METRICS
  TARGET_LAG = '30 minutes'
  WAREHOUSE = SF_SOLUTIONS_WH
AS
SELECT
  DATE_TRUNC('day', READ_TS)::DATE AS DATE_KEY,
  UTILITY_TERRITORY,
  COUNT(*)                                                                  AS TOTAL_READS,
  (COUNT_IF(VEE_STATUS='VALID')/COUNT(*)*100)::NUMBER(5,2)                  AS VEE_PASS_RATE,
  COUNT_IF(VEE_STATUS='ESTIMATED')                                          AS ESTIMATED_INTERVALS,
  COUNT_IF(VEE_STATUS='FAILED')                                             AS FAILED_INTERVALS,
  (96 * COUNT(DISTINCT METER_ID) - COUNT(*))                                AS MISSING_INTERVALS,
  (COUNT(*)/(96.0 * COUNT(DISTINCT METER_ID)) * 100)::NUMBER(5,2)           AS COMPLETENESS_PCT
FROM AMI_CURATED.INTERVAL_READ_15MIN
GROUP BY DATE_TRUNC('day', READ_TS)::DATE, UTILITY_TERRITORY;

-- ---- Data Metric Functions with automatic anomaly detection ----------
-- Row count + freshness on RAW and canonical
ALTER TABLE AMI_CURATED.INTERVAL_READ_15MIN SET
  DATA_METRIC_SCHEDULE = '15 MINUTE';

ALTER TABLE AMI_CURATED.INTERVAL_READ_15MIN
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

ALTER TABLE AMI_CURATED.INTERVAL_READ_15MIN
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ();  -- table-level; column form needs DATE or TIMESTAMP_LTZ/TZ

ALTER TABLE AMI_RAW.INTERVAL_READ_15MIN_RAW SET
  DATA_METRIC_SCHEDULE = '15 MINUTE';

ALTER TABLE AMI_RAW.INTERVAL_READ_15MIN_RAW
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

ALTER TABLE AMI_RAW.INTERVAL_READ_15MIN_RAW
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ();  -- table-level; column form needs DATE or TIMESTAMP_LTZ/TZ

-- ---- Unified observability view --------------------------------------
CREATE OR REPLACE VIEW V_AMI_OBSERVABILITY_DASHBOARD AS
SELECT
  sla.DATE_KEY,
  sla.UTILITY_TERRITORY,
  sla.TOTAL_READS,
  sla.MAX_INGESTION_LAG_MIN,
  sla.PCT_ARRIVED_WITHIN_15MIN,
  sla.LATE_ARRIVAL_COUNT,
  dq.VEE_PASS_RATE,
  dq.ESTIMATED_INTERVALS,
  dq.FAILED_INTERVALS,
  dq.MISSING_INTERVALS,
  dq.COMPLETENESS_PCT
FROM AMI_OBSERVABILITY.DT_INGESTION_SLA_METRICS sla
FULL OUTER JOIN AMI_OBSERVABILITY.DT_DATA_QUALITY_METRICS dq
  ON sla.DATE_KEY = dq.DATE_KEY
 AND sla.UTILITY_TERRITORY = dq.UTILITY_TERRITORY;

-- ---- SLA Breach alert -------------------------------------------------
CREATE OR REPLACE ALERT AMI_SLA_BREACH
  WAREHOUSE = SF_SOLUTIONS_WH
  SCHEDULE = '15 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM AMI_OBSERVABILITY.DT_INGESTION_SLA_METRICS
    WHERE DATE_KEY = CURRENT_DATE()
      AND PCT_ARRIVED_WITHIN_15MIN < 95
  ))
  THEN
    INSERT INTO AMI_OBSERVABILITY.PIPELINE_RUN_AUDIT
    SELECT 'SLA_BREACH_ALERT', UUID_STRING(), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(),
           'ALERT', 0, 1, 'SLA breach: ingestion < 95% within 15-min window';

-- -------------------------------------------------------------------------
-- Edge-case audit tables
-- Source: sql/07_observability/30_edge_case_seeds.sql
-- -------------------------------------------------------------------------

CREATE OR REPLACE TABLE SF_SOLUTIONS.AMI_OBSERVABILITY.DT_DUPLICATE_AUDIT AS
WITH ranked AS (
  SELECT METER_ID, READ_TS, VALUE, INGESTED_AT, CHANNEL_CODE, UTILITY_TERRITORY,
    ROW_NUMBER() OVER (ORDER BY HASH(METER_ID, READ_TS)) AS RN
  FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_CHANNEL
  WHERE CHANNEL_CODE = 'KWH_DEL'
    AND READ_TS >= DATEADD(day, -2, (SELECT MAX(READ_TS) FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_CHANNEL))
)
SELECT
  RN AS DUPLICATE_ID,
  METER_ID,
  UTILITY_TERRITORY,
  READ_TS,
  VALUE                                                      AS VALUE_FIRST,
  ROUND(VALUE * (1 + (UNIFORM(-15, 15, RANDOM()) / 100.0)), 4) AS VALUE_SECOND,
  INGESTED_AT                                                AS RECEIVED_FIRST,
  DATEADD(minute, UNIFORM(5, 240, RANDOM()), INGESTED_AT)   AS RECEIVED_SECOND,
  'last-write-wins (kept VALUE_SECOND)'                      AS RESOLUTION,
  CHANNEL_CODE
FROM ranked
WHERE RN <= 200;

-- 2. Meter ↔ premise mismatch audit. Computes hourly load shape per meter
--    over the last 7 days and classifies each meter (RES/SMB/CNI) by load
--    pattern. Rows where the suggested type disagrees with the assigned
--    METER_TYPE are flagged for review with a confidence score (load-shape
--    divergence). 50 sampled mismatches.
CREATE OR REPLACE TABLE SF_SOLUTIONS.AMI_OBSERVABILITY.DT_METER_PREMISE_MISMATCH AS
WITH
  cur AS (SELECT MAX(READ_TS) AS m FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_CHANNEL),
  sampled AS (
    SELECT METER_ID, METER_TYPE FROM SF_SOLUTIONS.AMI_CURATED.METER TABLESAMPLE (5000 ROWS)
  ),
  shape AS (
    SELECT
      i.METER_ID,
      s.METER_TYPE,
      AVG(IFF(HOUR(i.READ_TS) BETWEEN 17 AND 21, i.VALUE, NULL)) AS EVE,
      AVG(IFF(HOUR(i.READ_TS) BETWEEN 9 AND 16,  i.VALUE, NULL)) AS DAY,
      AVG(IFF(HOUR(i.READ_TS) BETWEEN 0 AND 5,   i.VALUE, NULL)) AS NIGHT,
      AVG(i.VALUE) AS OVERALL
    FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_CHANNEL i
    JOIN sampled s USING (METER_ID)
    JOIN cur ON 1=1
    WHERE i.CHANNEL_CODE = 'KWH_DEL'
      AND i.READ_TS >= DATEADD(day, -7, cur.m)
    GROUP BY 1, 2
  ),
  classified AS (
    SELECT *,
      CASE
        WHEN DAY / NULLIF(EVE, 0) > 1.15 AND OVERALL >= 0.8 THEN 'CNI'
        WHEN DAY / NULLIF(EVE, 0) > 1.05 AND OVERALL <  0.8 THEN 'SMB'
        WHEN EVE / NULLIF(DAY, 0) > 1.10                    THEN 'RES'
        ELSE METER_TYPE
      END AS SUGGESTED_TYPE,
      ABS(EVE - DAY) / NULLIF(GREATEST(EVE, DAY), 0)        AS SHAPE_SEPARATION
    FROM shape
    WHERE EVE IS NOT NULL AND DAY IS NOT NULL AND NIGHT IS NOT NULL
  )
SELECT
  ROW_NUMBER() OVER (ORDER BY SHAPE_SEPARATION DESC) AS RANK,
  METER_ID,
  METER_TYPE       AS CURRENT_TYPE,
  SUGGESTED_TYPE,
  ROUND(EVE, 3)    AS AVG_EVE_KWH,
  ROUND(DAY, 3)    AS AVG_DAY_KWH,
  ROUND(NIGHT, 3)  AS AVG_NIGHT_KWH,
  ROUND(OVERALL,3) AS AVG_OVERALL,
  ROUND(SHAPE_SEPARATION, 3) AS CONFIDENCE
FROM classified
WHERE METER_TYPE != SUGGESTED_TYPE
ORDER BY SHAPE_SEPARATION DESC
LIMIT 50;

-- -------------------------------------------------------------------------
-- Feeder anomaly model and scoring task
-- Source: sql/08_anomaly/01_anomaly_model.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_ML;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- ---- Training view (feeder-level hourly load) ------------------------
CREATE OR REPLACE VIEW V_FEEDER_TRAINING_DATA AS
SELECT
  sp.FEEDER_ID                       AS FEEDER_ID,
  DATE_TRUNC('hour', i.READ_TS)      AS TS,
  SUM(i.KWH_DELIVERED)               AS KWH
FROM AMI_CURATED.INTERVAL_READ_15MIN i
JOIN AMI_CURATED.METER m         USING (METER_ID)
JOIN AMI_CURATED.SERVICE_POINT sp USING (SERVICE_POINT_ID)
WHERE i.VEE_STATUS = 'VALID'
  -- Training ends strictly before the scoring window (V_FEEDER_RECENT_LOAD, last 14 days)
  AND i.READ_TS >= DATEADD(day, -180, CURRENT_DATE())
  AND i.READ_TS <  DATEADD(day, -14, CURRENT_DATE())
GROUP BY sp.FEEDER_ID, DATE_TRUNC('hour', i.READ_TS);

-- Snapshot into a concrete table for training (ANOMALY_DETECTION requires table)
CREATE OR REPLACE TABLE FEEDER_TRAINING_SNAPSHOT AS
SELECT * FROM V_FEEDER_TRAINING_DATA;

-- ---- Train the anomaly detection model -------------------------------
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ami_feeder_anom_model(
  INPUT_DATA        => SYSTEM$REFERENCE('TABLE', 'AMI_ML.FEEDER_TRAINING_SNAPSHOT'),
  SERIES_COLNAME    => 'FEEDER_ID',
  TIMESTAMP_COLNAME => 'TS',
  TARGET_COLNAME    => 'KWH',
  LABEL_COLNAME     => ''
);

-- ---- Detection input view (latest 2 days, feeder-hour aggregate) -----
CREATE OR REPLACE VIEW V_FEEDER_RECENT_LOAD AS
SELECT
  sp.FEEDER_ID,
  DATE_TRUNC('hour', i.READ_TS) AS TS,
  SUM(i.KWH_DELIVERED) AS KWH
FROM AMI_CURATED.INTERVAL_READ_15MIN i
JOIN AMI_CURATED.METER m         USING (METER_ID)
JOIN AMI_CURATED.SERVICE_POINT sp USING (SERVICE_POINT_ID)
WHERE i.READ_TS >= DATEADD(day, -14, CURRENT_DATE())
GROUP BY sp.FEEDER_ID, DATE_TRUNC('hour', i.READ_TS);

CREATE OR REPLACE TABLE FEEDER_RECENT_SNAPSHOT AS
SELECT * FROM V_FEEDER_RECENT_LOAD;

-- ---- Output table for anomaly events ---------------------------------
CREATE OR REPLACE TABLE AMI_MART.AMI_ANOMALY_EVENTS (
  FEEDER_ID      VARCHAR,
  TS             TIMESTAMP_NTZ,
  KWH            NUMBER(14,4),
  FORECAST       FLOAT,
  LOWER_BOUND    FLOAT,
  UPPER_BOUND    FLOAT,
  IS_ANOMALY     BOOLEAN,
  DISTANCE       FLOAT,
  DETECTED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ---- Scoring task (every 30 minutes) ---------------------------------
CREATE OR REPLACE TASK T_SCORE_FEEDER_ANOMALIES
  WAREHOUSE = SF_SOLUTIONS_WH
  SCHEDULE  = '30 MINUTE'
AS
EXECUTE IMMEDIATE
$$
DECLARE
  qid STRING;
  n_rows NUMBER;
BEGIN
  CREATE OR REPLACE TABLE SF_SOLUTIONS.AMI_ML.FEEDER_RECENT_SNAPSHOT AS
    SELECT sp.FEEDER_ID, DATE_TRUNC('hour', i.READ_TS) AS TS, SUM(i.KWH_DELIVERED) AS KWH
    FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_15MIN i
    JOIN SF_SOLUTIONS.AMI_CURATED.METER m USING (METER_ID)
    JOIN SF_SOLUTIONS.AMI_CURATED.SERVICE_POINT sp USING (SERVICE_POINT_ID)
    WHERE i.READ_TS > DATEADD(hour, -2, CURRENT_TIMESTAMP())
    GROUP BY sp.FEEDER_ID, DATE_TRUNC('hour', i.READ_TS);

  CALL SF_SOLUTIONS.AMI_ML.ami_feeder_anom_model!DETECT_ANOMALIES(
    INPUT_DATA        => SYSTEM$REFERENCE('TABLE', 'SF_SOLUTIONS.AMI_ML.FEEDER_RECENT_SNAPSHOT'),
    SERIES_COLNAME    => 'FEEDER_ID',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME    => 'KWH'
  );
  qid := LAST_QUERY_ID();

  INSERT INTO SF_SOLUTIONS.AMI_MART.AMI_ANOMALY_EVENTS
    (FEEDER_ID, TS, KWH, FORECAST, LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, DISTANCE)
  SELECT SERIES::VARCHAR, TS, Y, FORECAST, LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, DISTANCE
  FROM TABLE(RESULT_SCAN(:qid))
  WHERE IS_ANOMALY;
  n_rows := SQLROWCOUNT;

  INSERT INTO SF_SOLUTIONS.AMI_OBSERVABILITY.PIPELINE_RUN_AUDIT
  SELECT 'T_SCORE_FEEDER_ANOMALIES', UUID_STRING(), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(),
         'SUCCESS', :n_rows, 0, 'Feeder anomaly scoring complete';
END;
$$;

-- Task is created suspended - resume manually after first manual run
-- ALTER TASK T_SCORE_FEEDER_ANOMALIES RESUME;

-- -------------------------------------------------------------------------
-- C&I meter anomaly model
-- Source: sql/08_anomaly/02_cni_meter_model.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_ML;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- ---- Training data (500 random C&I meters, 180-day history) ----------
CREATE OR REPLACE TABLE CNI_METER_TRAINING AS
WITH sampled AS (
  SELECT METER_ID FROM SF_SOLUTIONS.AMI_CURATED.METER
  WHERE METER_TYPE = 'CNI'
  ORDER BY RANDOM() LIMIT 500
)
SELECT i.METER_ID, DATE_TRUNC('hour', i.READ_TS) AS TS, SUM(i.KWH_DELIVERED) AS KWH
FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_15MIN i
JOIN sampled s USING (METER_ID)
WHERE i.VEE_STATUS = 'VALID'
  AND i.READ_TS BETWEEN DATEADD(day, -180, CURRENT_DATE()) AND DATEADD(day, -14, CURRENT_DATE())
GROUP BY i.METER_ID, DATE_TRUNC('hour', i.READ_TS);

-- ---- Train meter-level anomaly model ---------------------------------
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ami_cni_meter_anom_model(
  INPUT_DATA        => SYSTEM$REFERENCE('TABLE', 'SF_SOLUTIONS.AMI_ML.CNI_METER_TRAINING'),
  SERIES_COLNAME    => 'METER_ID',
  TIMESTAMP_COLNAME => 'TS',
  TARGET_COLNAME    => 'KWH',
  LABEL_COLNAME     => ''
);

-- ---- Recent data for scoring -----------------------------------------
CREATE OR REPLACE TABLE CNI_METER_RECENT AS
WITH sampled AS (
  SELECT DISTINCT METER_ID FROM SF_SOLUTIONS.AMI_ML.CNI_METER_TRAINING
)
SELECT i.METER_ID, DATE_TRUNC('hour', i.READ_TS) AS TS, SUM(i.KWH_DELIVERED) AS KWH
FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_15MIN i
JOIN sampled s USING (METER_ID)
WHERE i.READ_TS > DATEADD(day, -13, CURRENT_DATE())
GROUP BY i.METER_ID, DATE_TRUNC('hour', i.READ_TS);

-- ---- Output table for meter-level anomaly events ---------------------
CREATE OR REPLACE TABLE SF_SOLUTIONS.AMI_MART.AMI_METER_ANOMALY_EVENTS (
  METER_ID      VARCHAR,
  TS            TIMESTAMP_NTZ,
  KWH           NUMBER(14,4),
  FORECAST      FLOAT,
  LOWER_BOUND   FLOAT,
  UPPER_BOUND   FLOAT,
  IS_ANOMALY    BOOLEAN,
  DISTANCE      FLOAT,
  DETECTED_AT   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ---- Initial scoring run ---------------------------------------------
CALL SF_SOLUTIONS.AMI_ML.ami_cni_meter_anom_model!DETECT_ANOMALIES(
  INPUT_DATA        => SYSTEM$REFERENCE('TABLE', 'SF_SOLUTIONS.AMI_ML.CNI_METER_RECENT'),
  SERIES_COLNAME    => 'METER_ID',
  TIMESTAMP_COLNAME => 'TS',
  TARGET_COLNAME    => 'KWH'
);

INSERT INTO SF_SOLUTIONS.AMI_MART.AMI_METER_ANOMALY_EVENTS
  (METER_ID, TS, KWH, FORECAST, LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, DISTANCE)
SELECT SERIES::VARCHAR, TS, Y, FORECAST, LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, DISTANCE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)));

-- -------------------------------------------------------------------------
-- Initial feeder anomaly scoring
-- Source: sql/08_anomaly/03_initial_scoring.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_ML;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Snapshot recent 14-day data for scoring
CREATE OR REPLACE TABLE FEEDER_RECENT_SNAPSHOT AS
SELECT * FROM V_FEEDER_RECENT_LOAD;

-- Augmented snapshot (used by dashboard for training-data visualization)
CREATE OR REPLACE TABLE FEEDER_AUG_SNAPSHOT AS
SELECT sp.FEEDER_ID, DATE_TRUNC('hour', i.READ_TS) AS TS, SUM(i.KWH_DELIVERED) AS KWH
FROM SF_SOLUTIONS.AMI_CURATED.INTERVAL_READ_15MIN i
JOIN SF_SOLUTIONS.AMI_CURATED.METER m USING (METER_ID)
JOIN SF_SOLUTIONS.AMI_CURATED.SERVICE_POINT sp USING (SERVICE_POINT_ID)
WHERE i.READ_TS BETWEEN DATEADD(day, -14, CURRENT_DATE()) AND CURRENT_TIMESTAMP()
GROUP BY sp.FEEDER_ID, DATE_TRUNC('hour', i.READ_TS);

-- Run feeder anomaly detection
CALL SF_SOLUTIONS.AMI_ML.ami_feeder_anom_model!DETECT_ANOMALIES(
  INPUT_DATA        => SYSTEM$REFERENCE('TABLE', 'SF_SOLUTIONS.AMI_ML.FEEDER_RECENT_SNAPSHOT'),
  SERIES_COLNAME    => 'FEEDER_ID',
  TIMESTAMP_COLNAME => 'TS',
  TARGET_COLNAME    => 'KWH'
);

INSERT INTO SF_SOLUTIONS.AMI_MART.AMI_ANOMALY_EVENTS
  (FEEDER_ID, TS, KWH, FORECAST, LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, DISTANCE)
SELECT SERIES::VARCHAR, TS, Y, FORECAST, LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, DISTANCE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)));

-- -------------------------------------------------------------------------
-- Row access, masking and secure views
-- Source: sql/09_security/01_security_and_sharing.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_CURATED;

-- ---- Role -> territory map -------------------------------------------
CREATE OR REPLACE TABLE ROLE_TERRITORY_MAP (
  ROLE_NAME         VARCHAR,
  UTILITY_TERRITORY VARCHAR
);

-- Example assignments (extend as needed)
INSERT INTO ROLE_TERRITORY_MAP VALUES
  ('AMI_ANALYST_NE', 'NE'),
  ('AMI_ANALYST_SE', 'SE'),
  ('AMI_ANALYST_MW', 'MW'),
  ('AMI_ANALYST_W',  'W');

-- ---- Row access policy by territory ----------------------------------
CREATE OR REPLACE ROW ACCESS POLICY RAP_TERRITORY
  AS (territory VARCHAR) RETURNS BOOLEAN ->
  CURRENT_ROLE() IN ('ACCOUNTADMIN','SYSADMIN','AMI_OWNER','AMI_ENG','AMI_OPS')
  OR territory IN (
    SELECT UTILITY_TERRITORY FROM AMI_CURATED.ROLE_TERRITORY_MAP
    WHERE ROLE_NAME = CURRENT_ROLE()
  );

ALTER TABLE AMI_CURATED.INTERVAL_READ_15MIN
  ADD ROW ACCESS POLICY RAP_TERRITORY ON (UTILITY_TERRITORY);

ALTER TABLE AMI_CURATED.METER
  ADD ROW ACCESS POLICY RAP_TERRITORY ON (UTILITY_TERRITORY);

-- ---- Masking policy on CIS_ACCOUNT_ID --------------------------------
CREATE OR REPLACE MASKING POLICY MP_CIS_ACCOUNT AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN','AMI_OWNER','AMI_ENG') THEN val
    ELSE SHA2(val, 256)
  END;

ALTER TABLE AMI_CURATED.CUSTOMER
  MODIFY COLUMN CIS_ACCOUNT_ID SET MASKING POLICY MP_CIS_ACCOUNT;

ALTER TABLE AMI_CURATED.BILLING_PERIOD
  MODIFY COLUMN CIS_ACCOUNT_ID SET MASKING POLICY MP_CIS_ACCOUNT;

-- ---- Secure views in AMI_SHARED --------------------------------------
USE SCHEMA AMI_SHARED;

CREATE OR REPLACE SECURE VIEW V_CIS_BILLING_CONSUMPTION AS
SELECT
  BILLING_PERIOD_ID, CIS_ACCOUNT_ID, SERVICE_POINT_ID, METER_ID,
  START_DATE, END_DATE, KWH_TOTAL, KWH_RECEIVED, KWH_NET,
  MAX_DEMAND_KW, COMPLETENESS_PCT, VEE_PASS_PCT, IS_BILLING_READY
FROM AMI_MART.DT_BILLING_PERIOD_CONSUMPTION;

CREATE OR REPLACE SECURE VIEW V_METER_DAILY_KWH AS
SELECT
  METER_ID, UTILITY_TERRITORY, ROLLUP_TS::DATE AS READ_DATE,
  KWH_DELIVERED, KWH_RECEIVED, MAX_DEMAND_KW,
  COMPLETENESS_PCT, VEE_PASS_PCT
FROM AMI_CURATED.DT_DAILY_ROLLUP;

CREATE OR REPLACE SECURE VIEW V_FEEDER_ANOMALIES AS
SELECT FEEDER_ID, TS, KWH, FORECAST, LOWER_BOUND, UPPER_BOUND,
       IS_ANOMALY, DISTANCE, DETECTED_AT
FROM AMI_MART.AMI_ANOMALY_EVENTS
WHERE IS_ANOMALY;

-- ---- Outbound share scaffold -----------------------------------------
-- Commented out to avoid accidental share creation; enable per deployment
-- CREATE SHARE IF NOT EXISTS AMI_REGULATOR_SHARE;
-- GRANT USAGE ON DATABASE SF_SOLUTIONS TO SHARE AMI_REGULATOR_SHARE;
-- GRANT USAGE ON SCHEMA AMI_SHARED TO SHARE AMI_REGULATOR_SHARE;
-- GRANT SELECT ON ALL SECURE VIEWS IN SCHEMA AMI_SHARED TO SHARE AMI_REGULATOR_SHARE;

-- -------------------------------------------------------------------------
-- Semantic view for Cortex Analyst
-- Source: sql/11_semantic/01_semantic_view.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_MART;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE OR REPLACE SEMANTIC VIEW AMI_SEMANTIC_VIEW

  TABLES (
    daily_rollup AS SF_SOLUTIONS.AMI_CURATED.DT_DAILY_ROLLUP
      PRIMARY KEY (METER_ID, ROLLUP_TS)
      WITH SYNONYMS = ('meter daily usage','daily consumption')
      COMMENT = 'Daily interval read rollup per meter',

    billing AS SF_SOLUTIONS.AMI_MART.DT_BILLING_PERIOD_CONSUMPTION
      PRIMARY KEY (BILLING_PERIOD_ID)
      WITH SYNONYMS = ('billing period','monthly bill')
      COMMENT = 'Meter-level billing period consumption and readiness',

    charge_line AS SF_SOLUTIONS.AMI_MART.DT_INTERVAL_CHARGE_LINE
      WITH SYNONYMS = ('TOU charges','interval charges')
      COMMENT = 'TOU-tagged interval energy and demand charges',

    anomalies AS SF_SOLUTIONS.AMI_MART.AMI_ANOMALY_EVENTS
      WITH SYNONYMS = ('anomaly events','flagged anomalies')
      COMMENT = 'Feeder-level anomaly events from Cortex ML',

    meter AS SF_SOLUTIONS.AMI_CURATED.METER
      PRIMARY KEY (METER_ID)
      WITH SYNONYMS = ('meters','smart meter')
      COMMENT = 'Meter dimension',

    service_point AS SF_SOLUTIONS.AMI_CURATED.SERVICE_POINT
      PRIMARY KEY (SERVICE_POINT_ID)
      WITH SYNONYMS = ('premise','service location')
      COMMENT = 'Service point / premise',

    sla AS SF_SOLUTIONS.AMI_OBSERVABILITY.DT_INGESTION_SLA_METRICS
      WITH SYNONYMS = ('ingestion SLA','pipeline SLA')
      COMMENT = 'Daily ingestion SLA metrics by territory'
  )

  RELATIONSHIPS (
    daily_to_meter AS daily_rollup(METER_ID) REFERENCES meter(METER_ID),
    billing_to_meter AS billing(METER_ID) REFERENCES meter(METER_ID),
    charge_to_meter AS charge_line(METER_ID) REFERENCES meter(METER_ID),
    meter_to_sp AS meter(SERVICE_POINT_ID) REFERENCES service_point(SERVICE_POINT_ID)
  )

  FACTS (
    daily_rollup.kwh_delivered AS KWH_DELIVERED COMMENT = 'kWh delivered that day',
    daily_rollup.kwh_received  AS KWH_RECEIVED  COMMENT = 'kWh pushed back (DER/solar)',
    daily_rollup.max_demand    AS MAX_DEMAND_KW COMMENT = 'Peak demand in kW',
    daily_rollup.completeness  AS COMPLETENESS_PCT,
    billing.kwh_total          AS KWH_TOTAL,
    billing.kwh_net            AS KWH_NET,
    billing.completeness       AS COMPLETENESS_PCT,
    charge_line.energy_charge  AS ENERGY_CHARGE,
    charge_line.demand_charge  AS DEMAND_CHARGE,
    charge_line.kwh            AS KWH,
    anomalies.distance         AS DISTANCE,
    anomalies.kwh              AS KWH,
    sla.pct_on_time            AS PCT_ARRIVED_WITHIN_15MIN,
    sla.late_arrivals          AS LATE_ARRIVAL_COUNT
  )

  DIMENSIONS (
    daily_rollup.rollup_date AS ROLLUP_TS COMMENT = 'Day of the rollup',
    daily_rollup.territory   AS UTILITY_TERRITORY WITH SYNONYMS = ('region','territory'),
    billing.start_date       AS START_DATE,
    billing.is_billing_ready AS IS_BILLING_READY WITH SYNONYMS = ('billing ready'),
    billing.cis_account      AS CIS_ACCOUNT_ID,
    charge_line.tou_bucket   AS TOU_BUCKET WITH SYNONYMS = ('time of use bucket','peak period'),
    charge_line.rate_plan    AS RATE_PLAN_ID,
    anomalies.feeder         AS FEEDER_ID,
    anomalies.ts             AS TS,
    anomalies.is_anomaly     AS IS_ANOMALY,
    meter.meter_type         AS METER_TYPE WITH SYNONYMS = ('customer type','segment'),
    meter.has_der            AS HAS_DER WITH SYNONYMS = ('has solar','solar'),
    meter.territory          AS UTILITY_TERRITORY,
    service_point.premise    AS PREMISE_TYPE WITH SYNONYMS = ('residential','commercial'),
    service_point.feeder     AS FEEDER_ID,
    sla.date_key             AS DATE_KEY,
    sla.territory            AS UTILITY_TERRITORY
  )

  METRICS (
    daily_rollup.total_kwh       AS SUM(daily_rollup.kwh_delivered) COMMENT = 'Total kWh',
    daily_rollup.total_kwh_net   AS SUM(daily_rollup.kwh_delivered) - SUM(daily_rollup.kwh_received),
    daily_rollup.avg_completeness AS AVG(daily_rollup.completeness),
    daily_rollup.meter_count     AS COUNT(DISTINCT daily_rollup.METER_ID),
    billing.billing_ready_pct    AS AVG(CASE WHEN billing.is_billing_ready THEN 1.0 ELSE 0.0 END) * 100,
    billing.total_billed_kwh     AS SUM(billing.kwh_total),
    charge_line.total_energy_charge AS SUM(charge_line.energy_charge),
    charge_line.total_demand_charge AS SUM(charge_line.demand_charge),
    charge_line.avg_energy_rate  AS SUM(charge_line.energy_charge) / NULLIF(SUM(charge_line.kwh), 0),
    anomalies.anomaly_count      AS SUM(CASE WHEN anomalies.is_anomaly THEN 1 ELSE 0 END),
    sla.avg_pct_on_time          AS AVG(sla.pct_on_time)
  )

  COMMENT = 'AMI 2.0 semantic view - ask about kWh, charges, anomalies, billing readiness, SLA by territory/feeder/meter/TOU bucket';

-- -------------------------------------------------------------------------
-- Operations knowledge base
-- Source: sql/12_intelligence/01_knowledge_base.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_ML;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE OR REPLACE TABLE AMI_KNOWLEDGE_BASE (
  DOC_ID      VARCHAR,
  TITLE       VARCHAR,
  CATEGORY    VARCHAR,
  CONTENT     VARCHAR,
  UPDATED_AT  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO AMI_KNOWLEDGE_BASE (DOC_ID, TITLE, CATEGORY, CONTENT)
VALUES
  ('KB-001', 'Outage Response Runbook', 'OPERATIONS',
   'When METER_EVENT.EVENT_TYPE=OUTAGE is detected, dispatch field crew within SLA window. For C&I customers with demand charges (large industrial TOU schedules), prioritize within 1 hour. For residential, within 4 hours. CARE customers and medical-baseline meters must be prioritized regardless of class.'),
  ('KB-002', 'VEE Failure Investigation', 'OPERATIONS',
   'Sustained VEE_STATUS=FAILED for >24 hours indicates meter health issue. Check firmware version, comms link, and physical access. May indicate tamper if combined with sudden consumption drop.'),
  ('KB-003', 'Voltage Sag Patterns', 'OPERATIONS',
   'VOLTAGE_V below 200V sustained more than 1 hour suggests transformer overload or feeder fault. Cross-reference DT_DAILY_ROLLUP.MIN_VOLTAGE by feeder. Check transformer KVA_RATING vs peak demand.'),
  ('KB-004', 'Theft Detection Pattern', 'REVENUE_ASSURANCE',
   'Sudden 3x consumption spike followed by drop indicates possible meter tamper. Cross-reference QUALITY_FLAG=F intervals. Coordinate with revenue protection team for site visit.'),
  ('KB-005', 'TOU Rate Plan Glossary', 'BILLING',
   'RP-FLAT: Standard flat rate at $0.12/kWh, no demand charge. RP-TOU3: Three-tier TOU with on-peak at $0.28/kWh and $8.50/kW demand. RP-CPP: Critical peak pricing with summer event days at $0.75/kWh.'),
  ('KB-006', 'Anomaly Detection Thresholds', 'ANALYTICS',
   'Cortex ML feeder model trained on 180 days. Anomaly distance > 4.0 indicates significant deviation. Cross-reference with weather and event data before alerting.'),
  ('KB-007', 'Billing Readiness Criteria', 'BILLING',
   'IS_BILLING_READY=TRUE requires COMPLETENESS_PCT >= 99 and VEE_PASS_PCT >= 97. Otherwise period is held for manual review.'),
  ('KB-008', 'Streaming SLA', 'OPERATIONS',
   'PCT_ARRIVED_WITHIN_15MIN below 95% triggers AMI_SLA_BREACH alert. Investigate Snowpipe Streaming channel health and head-end connectivity.'),
  ('KB-009', 'Utility Tariff Hierarchy', 'TARIFF',
   'Representative investor-owned utility tariff classes. Domestic: default tiered, CARE low-income discount, TOU 4-9 PM, whole-house TOU. General Service: small commercial default, energy-only TOU, medium commercial TOU with demand charges, real-time pricing. Large C&I: TOU with demand charges at secondary, primary and sub-transmission voltage. Agricultural: AG-TOU.'),
  ('KB-010', 'Demand Charge Mechanics', 'TARIFF',
   'Demand charges based on max 15-min interval kW within billing period. For TOU schedules, may be specific to on-peak window. Demand window exposure factor approximates probability that current interval becomes peak.');

-- -------------------------------------------------------------------------
-- Cortex Search service
-- Source: sql/12_intelligence/02_search_service.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_ML;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE OR REPLACE CORTEX SEARCH SERVICE AMI_KB_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_ID, TITLE, CATEGORY
  WAREHOUSE = SF_SOLUTIONS_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'
AS (
  SELECT DOC_ID, TITLE, CATEGORY, CONTENT, UPDATED_AT
  FROM SF_SOLUTIONS.AMI_ML.AMI_KNOWLEDGE_BASE
);

-- -------------------------------------------------------------------------
-- Cortex Agent
-- Source: sql/12_intelligence/03_agent.sql
-- -------------------------------------------------------------------------

USE DATABASE SF_SOLUTIONS;
USE SCHEMA AMI_MART;
USE WAREHOUSE SF_SOLUTIONS_WH;

CREATE OR REPLACE AGENT AMI_INTELLIGENCE_AGENT
  COMMENT = 'AMI 2.0 intelligence agent: text-to-SQL + ops knowledge search + chart generation'
  PROFILE = '{"display_name": "AMI Intelligence"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >-
    You are an AMI operations and analytics expert. Use Cortex Analyst for any
    quantitative question about kWh, charges, anomalies, billing readiness, or SLA.
    Use Cortex Search for runbook, definitional, or tariff questions. When the user
    asks for a chart, plot, graph, or asks about trends/comparison, after generating
    SQL also call data_to_chart to produce a Vega-Lite spec. Be concise.
  orchestration: >-
    Prefer Cortex Analyst for quantitative questions, Cortex Search for qualitative
    ones. After Cortex Analyst returns rows for a chartable question, invoke
    data_to_chart on those results.
  sample_questions:
    - question: Plot total kWh by territory in the last month
    - question: Show me a chart of billing readiness over time
    - question: What is the outage response runbook?
    - question: Compare TOU bucket charges as a bar chart
    - question: Explain the billing readiness criteria

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: ami_analyst
  - tool_spec:
      type: cortex_search
      name: search_kb
  - tool_spec:
      type: data_to_chart
      name: to_chart

tool_resources:
  ami_analyst:
    semantic_view: SF_SOLUTIONS.AMI_MART.AMI_SEMANTIC_VIEW
    execution_environment:
      type: warehouse
      warehouse: SF_SOLUTIONS_WH
      query_timeout: 60
  search_kb:
    name: SF_SOLUTIONS.AMI_ML.AMI_KB_SEARCH
    max_results: 5
    title_column: TITLE
    id_column: DOC_ID
$$;

-- Make the agent visible in Snowflake Intelligence / CoWork
GRANT USAGE ON AGENT SF_SOLUTIONS.AMI_MART.AMI_INTELLIGENCE_AGENT TO ROLE PUBLIC;

SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
    || '/#/agents/database/SF_SOLUTIONS/schema/AMI_MART/agent/AMI_INTELLIGENCE_AGENT/details' AS AGENT_URL;
