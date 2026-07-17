-- =============================================================================
-- Solution: IROPS Intelligence Center for Network Operations Control
-- Industry: Airlines & Transportation
-- Database: SF_SOLUTIONS
-- Schemas:  IROPS_RAW, IROPS_DATA_MART, IROPS_CORTEX
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Shared infrastructure (idempotent)
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- ---------------------------------------------------------------------------
-- Section 1: Schema creation
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.IROPS_RAW
    COMMENT = 'Raw flight operations data for IROPS Intelligence Center';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.IROPS_DATA_MART
    COMMENT = 'Governed Dynamic Tables and analytics objects for IROPS';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.IROPS_CORTEX
    COMMENT = 'Cortex AI objects (Semantic View, Agent) for IROPS';

-- ---------------------------------------------------------------------------
-- Section 2: Raw flights table
-- Source: SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS
-- This table is the foundation for all net-new governed OTP / delay metrics.
-- ---------------------------------------------------------------------------
USE SCHEMA SF_SOLUTIONS.IROPS_RAW;

CREATE TABLE IF NOT EXISTS SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS (
    flight_id            VARCHAR(20)    NOT NULL COMMENT 'Unique flight identifier',
    flight_date          DATE           NOT NULL COMMENT 'Operating date',
    airline_code         VARCHAR(3)     NOT NULL COMMENT 'IATA airline code',
    flight_number        VARCHAR(10)    NOT NULL COMMENT 'Flight number',
    origin_airport       VARCHAR(3)     NOT NULL COMMENT 'Origin IATA airport code',
    destination_airport  VARCHAR(3)     NOT NULL COMMENT 'Destination IATA airport code',
    scheduled_departure  TIMESTAMP_NTZ  COMMENT 'Scheduled departure datetime (UTC)',
    status               VARCHAR(20)    NOT NULL COMMENT 'ON_TIME | DELAYED | CANCELLED',
    delay_minutes        NUMBER(6,0)    COMMENT 'Departure delay in minutes (NULL = no delay recorded)'
);

-- ---------------------------------------------------------------------------
-- Section 3: Governed serving table (simulated ML risk scores)
-- In production this is DT_FLIGHT_RISK_REALTIME fed by a GNN/XGBoost scorer.
-- For the demo, a VIEW over RAW_FLIGHTS provides derived risk proxies.
-- ---------------------------------------------------------------------------
USE SCHEMA SF_SOLUTIONS.IROPS_DATA_MART;

CREATE OR REPLACE VIEW SF_SOLUTIONS.IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME AS
SELECT
    flight_id,
    flight_date,
    origin_airport,
    destination_airport,
    scheduled_departure,
    -- Risk score proxy: DELAYED=0.7, CANCELLED=0.95, ON_TIME=0.1
    CASE status
        WHEN 'DELAYED'   THEN 0.70
        WHEN 'CANCELLED' THEN 0.95
        ELSE 0.10
    END                                                      AS realtime_risk_score,
    -- Propagated risk (downstream impact proxy)
    CASE status
        WHEN 'DELAYED'   THEN 0.55
        WHEN 'CANCELLED' THEN 0.85
        ELSE 0.05
    END                                                      AS propagated_risk_score,
    -- Hidden risk: delayed flights that are not yet showing as cancelled
    CASE WHEN status = 'DELAYED' AND delay_minutes > 90 THEN TRUE ELSE FALSE END
                                                             AS is_hidden_risk,
    -- Revenue at risk proxy (seats * avg_fare placeholder)
    CASE status
        WHEN 'DELAYED'   THEN COALESCE(delay_minutes, 30) * 12.5
        WHEN 'CANCELLED' THEN 8500.0
        ELSE 0.0
    END                                                      AS revenue_at_risk
FROM SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS;

-- ---------------------------------------------------------------------------
-- Section 4: Dynamic Tables — net-new governed OTP / delay metrics
-- Adapted from: scripts/dt_otp_delay_metrics.sql
-- WAF: reliability (declarative), performance (incremental refresh)
-- ---------------------------------------------------------------------------

-- (A) Average delay minutes — FLIGHT-LEG grain
CREATE OR REPLACE DYNAMIC TABLE SF_SOLUTIONS.IROPS_DATA_MART.DT_AVG_DELAY_FLIGHT_LEG
    TARGET_LAG = '60 minutes'
    WAREHOUSE  = SF_SOLUTIONS_WH
AS
SELECT
    f.flight_id,
    f.flight_date,
    f.airline_code,
    f.flight_number,
    f.origin_airport,
    f.destination_airport,
    f.status,
    COALESCE(f.delay_minutes, 0)  AS delay_minutes,
    CURRENT_TIMESTAMP()           AS computed_at
FROM SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS f;

-- (B) On-Time Departure rate — ROUTE-DAY grain
CREATE OR REPLACE DYNAMIC TABLE SF_SOLUTIONS.IROPS_DATA_MART.DT_OTP_RATE_ROUTE_DAY
    TARGET_LAG = '60 minutes'
    WAREHOUSE  = SF_SOLUTIONS_WH
AS
SELECT
    f.flight_date,
    f.origin_airport,
    f.destination_airport,
    COUNT(*)                                                             AS scheduled_departures,
    SUM(CASE WHEN f.status = 'ON_TIME'   THEN 1 ELSE 0 END)            AS on_time_departures,
    SUM(CASE WHEN f.status = 'CANCELLED' THEN 1 ELSE 0 END)            AS cancelled_departures,
    ROUND(
        100.0 * SUM(CASE WHEN f.status = 'ON_TIME' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)
    , 2)                                                                AS otp_departure_rate_pct,
    ROUND(AVG(COALESCE(f.delay_minutes, 0)), 2)                        AS avg_delay_minutes_route_day,
    CURRENT_TIMESTAMP()                                                AS computed_at
FROM SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS f
GROUP BY f.flight_date, f.origin_airport, f.destination_airport;

-- ---------------------------------------------------------------------------
-- Section 5: Semantic View for Cortex Analyst
-- Adapted from: scripts/semantic_view.yaml
-- ---------------------------------------------------------------------------
USE SCHEMA SF_SOLUTIONS.IROPS_CORTEX;

CREATE OR REPLACE SEMANTIC VIEW SF_SOLUTIONS.IROPS_CORTEX.IROP_OPERATIONS_SV
    COMMENT = 'Governed IROP operations semantic view for Cortex Analyst. Surfaces route-day OTP rate and flight-leg average delay alongside real-time delay-risk and revenue-at-risk measures.'
    AS (
        WITH flights AS (
            SELECT
                flight_id,
                flight_date,
                airline_code,
                flight_number,
                origin_airport,
                destination_airport,
                scheduled_departure,
                status,
                delay_minutes
            FROM SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS
        ),
        flight_risk AS (
            SELECT
                flight_id,
                flight_date,
                origin_airport,
                destination_airport,
                scheduled_departure,
                realtime_risk_score,
                propagated_risk_score,
                is_hidden_risk,
                revenue_at_risk
            FROM SF_SOLUTIONS.IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME
        )
        SELECT
            -- Dimensions
            f.flight_id,
            f.flight_date,
            f.airline_code,
            f.origin_airport,
            f.destination_airport,
            f.status,
            f.delay_minutes,
            -- Risk measures from governed DT
            fr.realtime_risk_score,
            fr.propagated_risk_score,
            fr.is_hidden_risk,
            fr.revenue_at_risk
        FROM flights f
        LEFT JOIN flight_risk fr
            ON f.flight_id = fr.flight_id AND f.flight_date = fr.flight_date
    );

GRANT SELECT ON SEMANTIC VIEW SF_SOLUTIONS.IROPS_CORTEX.IROP_OPERATIONS_SV TO ROLE PUBLIC;

-- ---------------------------------------------------------------------------
-- Section 6: Scoped analytics role (least-privilege)
-- Adapted from: scripts/setup.sql
-- ---------------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE ROLE IF NOT EXISTS IROPS_OCC_ROLE
    COMMENT = 'Least-privilege OCC/Cortex-AI operating role for IROPS Intelligence Center';
GRANT ROLE IROPS_OCC_ROLE TO ROLE SYSADMIN;

USE ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE SF_SOLUTIONS_WH              TO ROLE IROPS_OCC_ROLE;
GRANT USAGE ON DATABASE  SF_SOLUTIONS                 TO ROLE IROPS_OCC_ROLE;
GRANT USAGE ON SCHEMA    SF_SOLUTIONS.IROPS_RAW       TO ROLE IROPS_OCC_ROLE;
GRANT USAGE ON SCHEMA    SF_SOLUTIONS.IROPS_DATA_MART TO ROLE IROPS_OCC_ROLE;
GRANT USAGE ON SCHEMA    SF_SOLUTIONS.IROPS_CORTEX    TO ROLE IROPS_OCC_ROLE;

GRANT SELECT ON TABLE SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS           TO ROLE IROPS_OCC_ROLE;
GRANT SELECT ON VIEW  SF_SOLUTIONS.IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME TO ROLE IROPS_OCC_ROLE;
GRANT SELECT ON DYNAMIC TABLE SF_SOLUTIONS.IROPS_DATA_MART.DT_OTP_RATE_ROUTE_DAY  TO ROLE IROPS_OCC_ROLE;
GRANT SELECT ON DYNAMIC TABLE SF_SOLUTIONS.IROPS_DATA_MART.DT_AVG_DELAY_FLIGHT_LEG TO ROLE IROPS_OCC_ROLE;
GRANT SELECT ON SEMANTIC VIEW SF_SOLUTIONS.IROPS_CORTEX.IROP_OPERATIONS_SV TO ROLE IROPS_OCC_ROLE;
