-- =============================================================================
-- Solution: FieldIQ - setup
-- Database: SF_SOLUTIONS
-- Schemas:  FIQ_ATOMIC, FIQ_ANALYTICS, FIQ_CORTEX, FIQ_ACTIONS, FIQ_STAGES
-- Creates schemas, stages, tables, agent-tool procedures and the data generator.
-- Run order: setup.sql -> data.sql -> pipeline.sql
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SELECT 'This application is not part of the Snowflake Service and is governed by the terms in LICENSE, unless expressly agreed to in writing. You use this application at your own risk, and Snowflake has no obligation to support your use of this application.' AS DISCLAIMER;

-- Shared infrastructure (idempotent; never dropped by teardown)
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Solution schemas
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.FIQ_ATOMIC COMMENT = 'CRM/ERP atomic tables (accounts, contacts, products, inventory, orders, assets, service, docs registry).';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.FIQ_ANALYTICS COMMENT = 'Datamart views over the atomic tables (account 360, pipeline, asset risk).';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.FIQ_CORTEX COMMENT = 'Doc chunks, Cortex Search service, semantic view, Cortex Agent, optional SPCS objects.';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.FIQ_ACTIONS COMMENT = 'Stored procedures used as agent tools (call plan, agenda, email, nearby, route).';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.FIQ_STAGES COMMENT = 'Internal stages for generated documents and parquet bulk loads.';

-- Stages
CREATE STAGE IF NOT EXISTS SF_SOLUTIONS.FIQ_STAGES.SEMANTIC_MODELS
    DIRECTORY = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Holds Cortex Analyst semantic model YAML';

CREATE STAGE IF NOT EXISTS SF_SOLUTIONS.FIQ_STAGES.DOCS
    DIRECTORY = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Engineering datasheets, drawings, manuals, sales training materials';

CREATE STAGE IF NOT EXISTS SF_SOLUTIONS.FIQ_STAGES.PARQUET
    DIRECTORY = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Synthetic parquet files for bulk load';

-- -------------------------------------------------------------------------
-- CRM/ERP atomic tables
-- Source: ddl/002_atomic_tables.sql
-- -------------------------------------------------------------------------

USE SCHEMA FIQ_ATOMIC;

-- ---------------------------------------------------------------------------
-- ACCOUNTS — customer companies (manufacturers, food/bev, packaging, etc.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE ACCOUNTS (
    ACCOUNT_ID        STRING        NOT NULL,
    ACCOUNT_NAME      STRING        NOT NULL,
    INDUSTRY          STRING,                   -- Food & Beverage, Packaging, Auto, Pharma, Chemicals, Metals
    SEGMENT           STRING,                   -- Strategic, Enterprise, Mid-Market, SMB
    ANNUAL_REVENUE_M  NUMBER(12,2),             -- in $M
    EMPLOYEES         NUMBER(10,0),
    BILLING_CITY      STRING,
    BILLING_STATE     STRING,
    BILLING_COUNTRY   STRING,
    LATITUDE          NUMBER(9,6),
    LONGITUDE         NUMBER(9,6),
    ACCOUNT_OWNER     STRING,                   -- sales rep name
    ACCOUNT_TIER      STRING,                   -- A / B / C
    PARENT_ACCOUNT_ID STRING,
    SERVICE_PLAN      STRING,                   -- ApexCare / Standard / None
    CREATED_DATE      DATE,
    LAST_ACTIVITY_DATE DATE
);

-- ---------------------------------------------------------------------------
-- CONTACTS — buyers, plant managers, maintenance leads, procurement
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CONTACTS (
    CONTACT_ID        STRING        NOT NULL,
    ACCOUNT_ID        STRING        NOT NULL,
    FIRST_NAME        STRING,
    LAST_NAME         STRING,
    TITLE             STRING,
    DEPARTMENT        STRING,                   -- Operations, Maintenance, Procurement, Engineering, Plant Mgmt
    EMAIL             STRING,
    PHONE             STRING,
    IS_PRIMARY        BOOLEAN,
    DECISION_ROLE     STRING,                   -- Decision Maker, Influencer, User, Gatekeeper
    LAST_CONTACTED    DATE,
    CREATED_DATE      DATE
);

-- ---------------------------------------------------------------------------
-- PRODUCTS — generic Apex Industrial SKU catalog
--   Families: Rotary Screw Air Compressor (RS), Centrifugal Compressor (CS),
--             Diesel Reciprocating (DR), Vacuum Pump (VP), Air Treatment / Dryer (TS),
--             Air Quality (AQ), Blower (BL)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE PRODUCTS (
    PRODUCT_ID        STRING        NOT NULL,   -- e.g. RS37i-A110
    MODEL_CODE        STRING        NOT NULL,
    PRODUCT_FAMILY    STRING,                   -- Rotary Screw, Centrifugal, Diesel Recip, Vacuum, Dryer, Air Quality, Blower
    PRODUCT_LINE      STRING,                   -- e.g. RS-Series, TS-Series, DR-Series
    DESCRIPTION       STRING,
    HORSEPOWER        NUMBER(8,2),
    KW                NUMBER(8,2),
    VOLTAGE           STRING,                   -- 230V/460V/575V
    FULL_LOAD_AMPS    NUMBER(8,2),
    CAPACITY_CFM      NUMBER(10,2),             -- airflow CFM (compressors/blowers)
    PRESSURE_PSI      NUMBER(8,2),
    LIST_PRICE_USD    NUMBER(12,2),
    LEAD_TIME_WEEKS   NUMBER(5,1),
    STATUS            STRING,                   -- Active / EOL / NPI
    CAGI_CERTIFIED    BOOLEAN,
    LAUNCH_DATE       DATE
);

-- ---------------------------------------------------------------------------
-- INVENTORY — "Barn Units" stock at distribution centers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INVENTORY (
    INVENTORY_ID      STRING        NOT NULL,
    PRODUCT_ID        STRING        NOT NULL,
    LOCATION          STRING,                   -- Davidson NC, Fairfield OH, Reno NV, Dallas TX, Atlanta GA
    QTY_ON_HAND       NUMBER(8,0),
    QTY_RESERVED      NUMBER(8,0),
    QTY_AVAILABLE     NUMBER(8,0),
    AVG_DAYS_IN_STOCK NUMBER(6,0),
    LAST_RECEIVED_DATE DATE,
    UNIT_COST_USD     NUMBER(12,2)
);

-- ---------------------------------------------------------------------------
-- OPPORTUNITIES — sales pipeline
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE OPPORTUNITIES (
    OPPORTUNITY_ID    STRING        NOT NULL,
    ACCOUNT_ID        STRING        NOT NULL,
    OPP_NAME          STRING,
    PRODUCT_ID        STRING,
    STAGE             STRING,                   -- Prospecting, Qualification, Proposal, Negotiation, Closed Won, Closed Lost
    AMOUNT_USD        NUMBER(14,2),
    PROBABILITY_PCT   NUMBER(5,2),
    CLOSE_DATE        DATE,
    OWNER             STRING,
    SOURCE            STRING,                   -- Inbound, Outbound, Partner, Existing Customer
    NEXT_STEP         STRING,
    CREATED_DATE      DATE,
    LAST_MODIFIED     DATE
);

-- ---------------------------------------------------------------------------
-- OPEN_ORDERS — ERP orders not yet shipped/invoiced
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE OPEN_ORDERS (
    ORDER_ID          STRING        NOT NULL,
    ACCOUNT_ID        STRING        NOT NULL,
    PRODUCT_ID        STRING,
    ORDER_DATE        DATE,
    PROMISED_SHIP_DATE DATE,
    QUANTITY          NUMBER(8,0),
    UNIT_PRICE_USD    NUMBER(12,2),
    LINE_TOTAL_USD    NUMBER(14,2),
    ORDER_STATUS      STRING,                   -- Booked, In Production, Ready to Ship, Shipped, Delayed
    PO_NUMBER         STRING,
    SALES_REP         STRING
);

-- ---------------------------------------------------------------------------
-- ASSETS — installed base at customer sites (with optional IoT data)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE ASSETS (
    ASSET_ID          STRING        NOT NULL,
    ACCOUNT_ID        STRING        NOT NULL,
    PRODUCT_ID        STRING,
    SERIAL_NUMBER     STRING,
    INSTALL_DATE      DATE,
    LOCATION_AT_SITE  STRING,                   -- Plant 1 - Compressor Room A
    WARRANTY_END_DATE DATE,
    SERVICE_PLAN      STRING,                   -- ApexCare Premier, ApexCare Standard, None
    OPERATING_HOURS   NUMBER(10,0),
    LAST_TELEMETRY_TS TIMESTAMP_NTZ,
    HEALTH_SCORE      NUMBER(5,2),              -- 0-100
    PRESSURE_AVG_PSI  NUMBER(8,2),
    TEMP_AVG_F        NUMBER(8,2),
    VIBRATION_AVG_MMS NUMBER(8,3),
    ALERT_LEVEL       STRING,                   -- OK, WATCH, WARNING, CRITICAL
    NEXT_PM_DATE      DATE
);

-- ---------------------------------------------------------------------------
-- SERVICE_ACTIVITIES — service history (work orders, PMs, inspections)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE SERVICE_ACTIVITIES (
    ACTIVITY_ID       STRING        NOT NULL,
    ASSET_ID          STRING,
    ACCOUNT_ID        STRING        NOT NULL,
    ACTIVITY_TYPE     STRING,                   -- Preventive Maintenance, Corrective, Inspection, Audit, Install, Warranty
    ACTIVITY_DATE     DATE,
    TECHNICIAN        STRING,
    DURATION_HOURS    NUMBER(6,2),
    DESCRIPTION       STRING,
    STATUS            STRING,                   -- Completed, Scheduled, In Progress, Cancelled
    PARTS_COST_USD    NUMBER(12,2),
    LABOR_COST_USD    NUMBER(12,2),
    TOTAL_COST_USD    NUMBER(12,2)
);

-- ---------------------------------------------------------------------------
-- DOCS_REGISTRY — metadata about engineering/sales docs in stage
--   The chunked content table for Cortex Search lives in CORTEX schema.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DOCS_REGISTRY (
    DOC_ID            STRING        NOT NULL,
    DOC_TITLE         STRING,
    DOC_TYPE          STRING,                   -- Datasheet, GA Drawing, Submittal, Manual, Sales Training, Pricing, Spec
    PRODUCT_FAMILY    STRING,
    PRODUCT_ID        STRING,                   -- nullable if generic
    STAGE_PATH        STRING,                   -- @SF_SOLUTIONS.FIQ_STAGES.DOCS/...
    FILE_FORMAT       STRING,                   -- pdf, md, txt
    PAGE_COUNT        NUMBER(6,0),
    SOURCE_URL        STRING,                   -- original web URL if sourced from public web
    PUBLISHED_DATE    DATE,
    LAST_INDEXED_TS   TIMESTAMP_NTZ
);

SHOW TABLES IN SCHEMA SF_SOLUTIONS.FIQ_ATOMIC;

-- -------------------------------------------------------------------------
-- Agent-tool stored procedures
-- Source: ddl/004_action_procs.sql
-- -------------------------------------------------------------------------

USE SCHEMA FIQ_ACTIONS;

-- ---------------------------------------------------------------------------
-- 1. NEARBY_CUSTOMERS — accounts within N miles of a city/state
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE FIQ_ACTIONS.NEARBY_CUSTOMERS(CITY STRING, STATE STRING, RADIUS_MI FLOAT)
RETURNS TABLE (ACCOUNT_ID STRING, ACCOUNT_NAME STRING, INDUSTRY STRING,
               BILLING_CITY STRING, BILLING_STATE STRING, ACCOUNT_OWNER STRING,
               OPEN_PIPELINE_USD FLOAT, INSTALLED_ASSET_COUNT FLOAT,
               DISTANCE_MI FLOAT)
LANGUAGE SQL
AS
$$
DECLARE
  res RESULTSET;
BEGIN
  res := (
    WITH center AS (
      SELECT AVG(LATITUDE)::FLOAT lat, AVG(LONGITUDE)::FLOAT lon
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS
      WHERE BILLING_CITY ILIKE :CITY AND BILLING_STATE ILIKE :STATE
    )
    SELECT a360.ACCOUNT_ID::STRING, a360.ACCOUNT_NAME::STRING, a360.INDUSTRY::STRING,
           a360.BILLING_CITY::STRING, a360.BILLING_STATE::STRING, a360.ACCOUNT_OWNER::STRING,
           a360.OPEN_PIPELINE_USD::FLOAT, a360.INSTALLED_ASSET_COUNT::FLOAT,
           ROUND(ST_DISTANCE(ST_MAKEPOINT(a360.LONGITUDE, a360.LATITUDE),
                              ST_MAKEPOINT(c.lon, c.lat))/1609.34, 1)::FLOAT AS DISTANCE_MI
    FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 a360, center c
    WHERE c.lat IS NOT NULL
      AND ST_DISTANCE(ST_MAKEPOINT(a360.LONGITUDE, a360.LATITUDE),
                      ST_MAKEPOINT(c.lon, c.lat))/1609.34 <= :RADIUS_MI
    ORDER BY DISTANCE_MI
    LIMIT 50
  );
  RETURN TABLE(res);
END;
$$;

-- NEARBY_CUSTOMERS_JSON — agent-tool wrapper. Agent procedure tools need a single-cell
-- result, so this returns NEARBY_CUSTOMERS as a JSON array (the app calls the table form).
CREATE OR REPLACE PROCEDURE FIQ_ACTIONS.NEARBY_CUSTOMERS_JSON(CITY STRING, STATE STRING, RADIUS_MI FLOAT)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
  payload VARIANT;
BEGIN
  CALL SF_SOLUTIONS.FIQ_ACTIONS.NEARBY_CUSTOMERS(:CITY, :STATE, COALESCE(:RADIUS_MI, 50));
  SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(*)), ARRAY_CONSTRUCT())
    INTO :payload
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  RETURN payload;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. SALES_CALL_PLAN
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE FIQ_ACTIONS.SALES_CALL_PLAN(CUSTOMER_NAME STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  acct_id STRING; acct_json STRING; contacts STRING;
  opps STRING; orders STRING; assets STRING;
  ctx STRING; resp STRING;
BEGIN
  acct_id := (SELECT ACCOUNT_ID FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS
              WHERE ACCOUNT_NAME ILIKE '%' || :CUSTOMER_NAME || '%'
              ORDER BY (ACCOUNT_NAME ILIKE :CUSTOMER_NAME) DESC, LENGTH(ACCOUNT_NAME), ACCOUNT_ID LIMIT 1);
  IF (acct_id IS NULL) THEN RETURN 'No customer matching "' || :CUSTOMER_NAME || '" was found.'; END IF;

  acct_json := (
    SELECT TO_VARCHAR(OBJECT_CONSTRUCT_KEEP_NULL(
      'name', a.ACCOUNT_NAME, 'industry', a.INDUSTRY, 'segment', a.SEGMENT,
      'tier', a.ACCOUNT_TIER, 'service_plan', a.SERVICE_PLAN,
      'city', a.BILLING_CITY, 'state', a.BILLING_STATE, 'owner', a.ACCOUNT_OWNER,
      'annual_revenue_m', a.ANNUAL_REVENUE_M, 'employees', a.EMPLOYEES,
      'open_pipeline_usd', a360.OPEN_PIPELINE_USD,
      'open_order_count', a360.OPEN_ORDER_COUNT,
      'installed_asset_count', a360.INSTALLED_ASSET_COUNT,
      'assets_at_risk', a360.ASSETS_AT_RISK,
      'assets_no_service_plan', a360.ASSETS_NO_SERVICE_PLAN,
      'service_spend_ltm', a360.SERVICE_SPEND_LTM_USD,
      'last_activity', a360.LAST_ACTIVITY_DATE
    ))
    FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a
    JOIN SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 a360 ON a.ACCOUNT_ID = a360.ACCOUNT_ID
    WHERE a.ACCOUNT_ID = :acct_id
  );
  contacts := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
                'name', FIRST_NAME||' '||LAST_NAME, 'title', TITLE, 'role', DECISION_ROLE)))
               FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.CONTACTS WHERE ACCOUNT_ID=:acct_id LIMIT 6));
  opps := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
            'name', OPP_NAME, 'stage', STAGE, 'amount', AMOUNT_USD, 'close_date', CLOSE_DATE)))
           FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES
                 WHERE ACCOUNT_ID=:acct_id AND STAGE NOT IN ('Closed Won','Closed Lost') LIMIT 5));
  orders := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
              'id', ORDER_ID, 'product', PRODUCT_ID, 'status', ORDER_STATUS,
              'amount', LINE_TOTAL_USD, 'ship_date', PROMISED_SHIP_DATE)))
             FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.OPEN_ORDERS WHERE ACCOUNT_ID=:acct_id LIMIT 5));
  assets := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
              'serial', SERIAL_NUMBER, 'product', PRODUCT_ID,
              'health', HEALTH_SCORE, 'alert', ALERT_LEVEL, 'service_plan', SERVICE_PLAN)))
             FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS
                   WHERE ACCOUNT_ID=:acct_id
                     AND (ALERT_LEVEL IN ('WARNING','CRITICAL') OR SERVICE_PLAN='None') LIMIT 5));

  ctx := '{"account":' || COALESCE(acct_json,'null')
       || ',"top_contacts":' || COALESCE(contacts,'[]')
       || ',"open_opportunities":' || COALESCE(opps,'[]')
       || ',"open_orders":' || COALESCE(orders,'[]')
       || ',"risky_assets":' || COALESCE(assets,'[]') || '}';

  resp := (SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'claude-sonnet-4-6',
    'You are FieldIQ, an AI sales co-pilot for Apex Industrial. Generate a concise, actionable SALES CALL PLAN '
    || 'using the JSON facts below. Structure: 1) Customer Snapshot (1 paragraph), 2) Strategic Objectives (3 bullets), '
    || '3) Talk Tracks tied to specific opportunities/orders/assets, '
    || '4) Risks & Cross-sell Opportunities (especially assets without service plans, at-risk assets), '
    || '5) Suggested Next Steps with timeline. Be specific — cite product IDs, amounts, dates from the data. '
    || 'Keep it under 350 words. CUSTOMER FACTS (JSON): ' || :ctx
  ));
  RETURN resp;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. MEETING_AGENDA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE FIQ_ACTIONS.MEETING_AGENDA(CUSTOMER_NAME STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  acct_id STRING; acct_json STRING; orders STRING; opps STRING;
  asset_sum STRING; recent STRING; ctx STRING; resp STRING;
BEGIN
  acct_id := (SELECT ACCOUNT_ID FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS
              WHERE ACCOUNT_NAME ILIKE '%' || :CUSTOMER_NAME || '%'
              ORDER BY (ACCOUNT_NAME ILIKE :CUSTOMER_NAME) DESC, LENGTH(ACCOUNT_NAME), ACCOUNT_ID LIMIT 1);
  IF (acct_id IS NULL) THEN RETURN 'No customer matching "' || :CUSTOMER_NAME || '" was found.'; END IF;

  acct_json := (SELECT TO_VARCHAR(OBJECT_CONSTRUCT(
                'name', ACCOUNT_NAME, 'industry', INDUSTRY,
                'tier', ACCOUNT_TIER, 'owner', ACCOUNT_OWNER, 'service_plan', SERVICE_PLAN))
                FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS WHERE ACCOUNT_ID = :acct_id);
  orders := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
              'product', PRODUCT_ID, 'status', ORDER_STATUS, 'ship_date', PROMISED_SHIP_DATE)))
             FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.OPEN_ORDERS WHERE ACCOUNT_ID=:acct_id LIMIT 4));
  opps := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
            'name', OPP_NAME, 'stage', STAGE, 'amount', AMOUNT_USD, 'next_step', NEXT_STEP)))
           FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES
                 WHERE ACCOUNT_ID=:acct_id AND STAGE NOT IN ('Closed Won','Closed Lost') LIMIT 4));
  asset_sum := (SELECT TO_VARCHAR(OBJECT_CONSTRUCT(
                  'count', COUNT(*),
                  'at_risk', SUM(CASE WHEN ALERT_LEVEL IN ('WARNING','CRITICAL') THEN 1 ELSE 0 END),
                  'no_plan', SUM(CASE WHEN SERVICE_PLAN='None' THEN 1 ELSE 0 END)))
                FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS WHERE ACCOUNT_ID=:acct_id);
  recent := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
              'date', ACTIVITY_DATE, 'type', ACTIVITY_TYPE, 'desc', DESCRIPTION)))
             FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.SERVICE_ACTIVITIES
                   WHERE ACCOUNT_ID=:acct_id
                     AND ACTIVITY_DATE >= DATEADD(month,-6,CURRENT_DATE()) LIMIT 4));

  ctx := '{"account":' || COALESCE(acct_json,'null')
       || ',"open_orders":' || COALESCE(orders,'[]')
       || ',"opportunities":' || COALESCE(opps,'[]')
       || ',"asset_summary":' || COALESCE(asset_sum,'null')
       || ',"recent_service":' || COALESCE(recent,'[]') || '}';

  resp := (SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'claude-sonnet-4-6',
    'Generate a detailed, actionable MEETING AGENDA for an upcoming customer visit by an Apex Industrial sales rep. '
    || 'Format as a numbered timeline (e.g., 0:00-0:10 Welcome, 0:10-0:30 Account Review). '
    || 'Cover: introductions/rapport, recap of recent service activity and orders, review of open opportunities and next steps, '
    || 'asset health & service-plan opportunities (especially assets with WARNING/CRITICAL alerts or no service plan), '
    || 'product recommendations, Q&A / wrap-up. Keep total agenda 60 minutes. '
    || 'Cite specific facts (product IDs, dates, dollar amounts). CUSTOMER FACTS (JSON): ' || :ctx
  ));
  RETURN resp;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. EMAIL_DRAFT (multilingual)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE FIQ_ACTIONS.EMAIL_DRAFT(CUSTOMER_NAME STRING, TOPIC STRING, LANGUAGE STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  acct_id STRING; acct_json STRING; contact_json STRING; assets STRING;
  ctx STRING; resp STRING; lang STRING;
BEGIN
  lang := COALESCE(NULLIF(:LANGUAGE,''),'English');
  acct_id := (SELECT ACCOUNT_ID FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS
              WHERE ACCOUNT_NAME ILIKE '%' || :CUSTOMER_NAME || '%'
              ORDER BY (ACCOUNT_NAME ILIKE :CUSTOMER_NAME) DESC, LENGTH(ACCOUNT_NAME), ACCOUNT_ID LIMIT 1);
  IF (acct_id IS NULL) THEN RETURN 'No customer matching "' || :CUSTOMER_NAME || '" was found.'; END IF;

  acct_json := (SELECT TO_VARCHAR(OBJECT_CONSTRUCT(
                  'name', ACCOUNT_NAME, 'industry', INDUSTRY,
                  'service_plan', SERVICE_PLAN, 'owner', ACCOUNT_OWNER))
                FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS WHERE ACCOUNT_ID=:acct_id);
  contact_json := (SELECT TO_VARCHAR(OBJECT_CONSTRUCT(
                    'name', FIRST_NAME||' '||LAST_NAME,
                    'title', TITLE, 'email', EMAIL))
                  FROM SF_SOLUTIONS.FIQ_ATOMIC.CONTACTS
                  WHERE ACCOUNT_ID=:acct_id AND IS_PRIMARY=TRUE LIMIT 1);
  assets := (SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
              'serial', SERIAL_NUMBER, 'product', PRODUCT_ID,
              'service_plan', SERVICE_PLAN, 'alert', ALERT_LEVEL)))
             FROM (SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS
                   WHERE ACCOUNT_ID=:acct_id
                     AND (SERVICE_PLAN='None' OR ALERT_LEVEL IN ('WARNING','CRITICAL')) LIMIT 5));

  ctx := '{"account":' || COALESCE(acct_json,'null')
       || ',"primary_contact":' || COALESCE(contact_json,'null')
       || ',"risky_assets":' || COALESCE(assets,'[]') || '}';

  resp := (SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'claude-sonnet-4-6',
    'Write a short, professional outbound email (about 150 words) from an Apex Industrial sales rep to the primary '
    || 'contact at the customer. Topic: "' || :TOPIC || '". Output the email in ' || :lang || '. '
    || 'Include subject line, greeting, body grounded in the customer facts, and a clear single call-to-action. '
    || 'Be specific (cite product/serial/asset/plan facts). Keep tone consultative, not pushy. '
    || 'CUSTOMER FACTS (JSON): ' || :ctx
  ));
  RETURN resp;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. ROUTE_PLAN
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE FIQ_ACTIONS.ROUTE_PLAN(ANCHOR_CUSTOMER STRING, VISIT_DATE DATE, NUM_DAYS NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  acct_id STRING; anchor_json STRING; nearby_json STRING; ctx STRING; resp STRING;
BEGIN
  acct_id := (SELECT ACCOUNT_ID FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS
              WHERE ACCOUNT_NAME ILIKE '%' || :ANCHOR_CUSTOMER || '%'
              ORDER BY (ACCOUNT_NAME ILIKE :ANCHOR_CUSTOMER) DESC, LENGTH(ACCOUNT_NAME), ACCOUNT_ID LIMIT 1);
  IF (acct_id IS NULL) THEN RETURN 'No anchor customer matching "' || :ANCHOR_CUSTOMER || '" was found.'; END IF;

  anchor_json := (SELECT TO_VARCHAR(OBJECT_CONSTRUCT(
                    'name', ACCOUNT_NAME, 'city', BILLING_CITY,
                    'state', BILLING_STATE, 'lat', LATITUDE, 'lon', LONGITUDE))
                  FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS WHERE ACCOUNT_ID=:acct_id);

  nearby_json := (
    SELECT TO_VARCHAR(ARRAY_AGG(OBJECT_CONSTRUCT(
        'name', x.ACCOUNT_NAME, 'city', x.BILLING_CITY, 'state', x.BILLING_STATE,
        'industry', x.INDUSTRY, 'tier', x.ACCOUNT_TIER,
        'pipeline', x.OPEN_PIPELINE_USD, 'distance_mi', x.DISTANCE_MI)))
    FROM (
      WITH anchor AS (SELECT LATITUDE lat, LONGITUDE lon FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS WHERE ACCOUNT_ID=:acct_id)
      SELECT n.ACCOUNT_NAME, n.BILLING_CITY, n.BILLING_STATE, n.INDUSTRY, n.ACCOUNT_TIER,
             a360.OPEN_PIPELINE_USD,
             ROUND(ST_DISTANCE(ST_MAKEPOINT(n.LONGITUDE,n.LATITUDE),
                                ST_MAKEPOINT(a.lon,a.lat))/1609.34,1) AS DISTANCE_MI
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS n
      JOIN SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 a360 ON n.ACCOUNT_ID=a360.ACCOUNT_ID
      , anchor a
      WHERE n.ACCOUNT_ID <> :acct_id
        AND ST_DISTANCE(ST_MAKEPOINT(n.LONGITUDE,n.LATITUDE),
                        ST_MAKEPOINT(a.lon,a.lat))/1609.34 <= 80
      ORDER BY a360.OPEN_PIPELINE_USD DESC NULLS LAST
      LIMIT 8
    ) x
  );

  ctx := '{"anchor":' || COALESCE(anchor_json,'null')
       || ',"visit_date":"' || TO_VARCHAR(:VISIT_DATE) || '"'
       || ',"num_days":' || :NUM_DAYS::STRING
       || ',"nearby":' || COALESCE(nearby_json,'[]') || '}';

  resp := (SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'claude-sonnet-4-6',
    'You are planning a multi-day field trip for an Apex Industrial sales rep. Build a ' || :NUM_DAYS::STRING
    || '-day route plan starting on ' || TO_VARCHAR(:VISIT_DATE)
    || '. The anchor visit is at the "anchor" customer; fill the remaining time with nearby customers. '
    || 'Assume each customer visit is 1 hour and travel speed averages 45 mph. '
    || 'Output a day-by-day timeline (Day 1 starts 8:30 AM) listing for each stop: time, customer, city, '
    || 'distance from previous stop, why visit (cite pipeline value or strategic reason). '
    || 'End each day no later than 5:30 PM. CONTEXT (JSON): ' || :ctx
  ));
  RETURN resp;
END;
$$;

SHOW PROCEDURES IN SCHEMA SF_SOLUTIONS.FIQ_ACTIONS;

-- -------------------------------------------------------------------------
-- Data generator: synthetic CRM/ERP tables, engineering PDFs + markdown, search chunks
-- Source: scripts/{generate_synthetic_data, generate_docs, build_doc_chunks}.py (embedded unchanged)
-- -------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.FIQ_ATOMIC.SP_GENERATE_DATA()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python==1.55.2', 'pandas==2.3.3', 'numpy==2.4.6', 'pyarrow==24.0.0', 'reportlab==5.0.0')
HANDLER = 'run'
COMMENT = 'FieldIQ synthetic CRM/ERP data, engineering documents and search chunks'
EXECUTE AS CALLER
AS
$$
ORDER = ['generate_synthetic_data', 'generate_docs', 'build_doc_chunks']

SOURCES = {}

SOURCES['generate_synthetic_data'] = r'''
"""Generate synthetic industrial-equipment sales data for FieldIQ by Apex Industrial.

Outputs parquet files into ../data/synthetic, then loads them into SF_SOLUTIONS.FIQ_ATOMIC tables.
Run:
    SNOWFLAKE_CONNECTION_NAME=my_snowflake python scripts/generate_synthetic_data.py
"""
from __future__ import annotations
import os, random
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd
import numpy as np

random.seed(7)
np.random.seed(7)

OUT = Path(__file__).resolve().parent.parent / "data" / "synthetic"
OUT.mkdir(parents=True, exist_ok=True)

# --------------------------------------------------------------------------
# Reference data
# --------------------------------------------------------------------------
INDUSTRIES = ["Food & Beverage", "Packaging", "Automotive", "Pharmaceuticals",
              "Chemicals", "Metals & Mining", "Pulp & Paper", "Plastics",
              "Aerospace", "Electronics", "General Manufacturing"]
SEGMENTS = ["Strategic", "Enterprise", "Mid-Market", "SMB"]
SERVICE_PLANS = ["ApexCare Premier", "ApexCare Standard", "None"]
TIERS = ["A", "B", "C"]

# 25 cities with lat/lng (US manufacturing hubs)
CITIES = [
    ("Fairfield", "OH", 39.3454, -84.5603),
    ("Cincinnati", "OH", 39.1031, -84.5120),
    ("Dayton", "OH", 39.7589, -84.1916),
    ("Columbus", "OH", 39.9612, -82.9988),
    ("Indianapolis", "IN", 39.7684, -86.1581),
    ("Louisville", "KY", 38.2527, -85.7585),
    ("Nashville", "TN", 36.1627, -86.7816),
    ("Atlanta", "GA", 33.7490, -84.3880),
    ("Charlotte", "NC", 35.2271, -80.8431),
    ("Davidson", "NC", 35.4993, -80.8487),
    ("Greenville", "SC", 34.8526, -82.3940),
    ("Birmingham", "AL", 33.5186, -86.8104),
    ("Houston", "TX", 29.7604, -95.3698),
    ("Dallas", "TX", 32.7767, -96.7970),
    ("San Antonio", "TX", 29.4241, -98.4936),
    ("Phoenix", "AZ", 33.4484, -112.0740),
    ("Reno", "NV", 39.5296, -119.8138),
    ("Los Angeles", "CA", 34.0522, -118.2437),
    ("Fresno", "CA", 36.7378, -119.7871),
    ("Portland", "OR", 45.5152, -122.6784),
    ("Seattle", "WA", 47.6062, -122.3321),
    ("Chicago", "IL", 41.8781, -87.6298),
    ("Milwaukee", "WI", 43.0389, -87.9065),
    ("Minneapolis", "MN", 44.9778, -93.2650),
    ("Detroit", "MI", 42.3314, -83.0458),
]

# 30 sales reps
SALES_REPS = [
    "Alex Carter","Brianna Reyes","Carlos Mendez","Dana Whitfield","Evan Park",
    "Fatima Khan","Gavin O'Neill","Hannah Liu","Ian McAllister","Jenna Ortiz",
    "Kevin Schmidt","Laila Patel","Marcus Brennan","Nina Tanaka","Owen Becker",
    "Priya Subramanian","Quinn Avery","Rachel Donovan","Samir Bhatt","Tara Nguyen",
    "Umesh Rao","Vivian Cole","Wesley Booth","Xochitl Ramos","Yusuf Akin",
    "Zachary Hunt","Aiden Cole","Bella Knight","Caleb Foster","Diana Wells",
]

# Customer name fragments (generic)
PREFIXES = ["Northstar", "Atlas", "Beacon", "Cardinal", "Delta", "Evergreen",
            "Falcon", "Granite", "Horizon", "Ironworks", "Juno", "Keystone",
            "Lakeshore", "Meridian", "Nova", "Orion", "Pacific", "Quanta",
            "Riverstone", "Sentinel", "Titan", "Unity", "Vertex", "Westline",
            "Pinnacle", "Summit", "Cascade", "Brightline", "Apex Foods", "Steelcraft"]
SUFFIXES = ["Foods", "Beverages", "Manufacturing", "Industries", "Packaging",
            "Plastics", "Metals", "Chemicals", "Pharma", "Aerospace",
            "Components", "Mills", "Works", "Group", "Holdings", "Co",
            "LLC", "Corp", "Partners", "Systems"]

# --------------------------------------------------------------------------
# Product catalog (generic Apex SKUs)
# Families:
#   RS = Rotary Screw Air Compressor (oil-flooded)
#   RSi = RS variable-speed (i suffix)
#   CS = Centrifugal Compressor
#   DR = Diesel Reciprocating Compressor
#   VP = Vacuum Pump
#   TS = Refrigerated/Desiccant Dryer (T-Series)
#   AQ = Air Quality / Filtration
#   BL = Centrifugal Blower
# --------------------------------------------------------------------------
def build_products():
    rows = []
    # Rotary screw fixed-speed: RS5, RS7, RS11, RS15, RS18, RS22, RS30, RS37, RS45, RS55, RS75, RS90, RS110, RS132, RS160, RS200, RS250
    rs_kw = [5,7,11,15,18,22,30,37,45,55,75,90,110,132,160,200,250]
    for kw in rs_kw:
        for v_suffix, voltage in [("A110","460V"),("A125","460V"),("A210","230V")]:
            hp = round(kw*1.341, 1)
            cfm = round(kw*4.8 + np.random.uniform(-5,5), 1)
            psi = float(np.random.choice([100,125,150]))
            fla = round(hp*1.25 if voltage=="460V" else hp*2.5, 1)
            price = round(kw*620 + np.random.uniform(-300,500), 2)
            lead = round(np.random.uniform(4,14),1)
            base = f"RS{kw}"
            pid = f"{base}-{v_suffix}"
            rows.append(dict(
                PRODUCT_ID=pid, MODEL_CODE=base, PRODUCT_FAMILY="Rotary Screw",
                PRODUCT_LINE="RS-Series", DESCRIPTION=f"Apex {base} {hp}HP rotary screw air compressor, {voltage}, {psi} PSI",
                HORSEPOWER=hp, KW=kw, VOLTAGE=voltage, FULL_LOAD_AMPS=fla,
                CAPACITY_CFM=cfm, PRESSURE_PSI=psi, LIST_PRICE_USD=price,
                LEAD_TIME_WEEKS=lead, STATUS="Active", CAGI_CERTIFIED=True,
                LAUNCH_DATE=date(2019,1,1) + timedelta(days=int(np.random.randint(0,1800)))
            ))
    # Variable-speed RSi: RS37i, RS45i, RS55i, RS75i, RS90i, RS110i, RS132i, RS160i
    for kw in [37,45,55,75,90,110,132,160]:
        for v_suffix, voltage in [("A110","460V"),("A125","460V")]:
            hp = round(kw*1.341,1)
            cfm = round(kw*5.1 + np.random.uniform(-5,5),1)
            psi = float(np.random.choice([125,150]))
            fla = round(hp*1.18,1)
            price = round(kw*820 + np.random.uniform(-200,800),2)
            lead = round(np.random.uniform(6,16),1)
            base = f"RS{kw}i"
            pid = f"{base}-{v_suffix}"
            rows.append(dict(
                PRODUCT_ID=pid, MODEL_CODE=base, PRODUCT_FAMILY="Rotary Screw",
                PRODUCT_LINE="RSi-Series (Variable Speed)",
                DESCRIPTION=f"Apex {base} {hp}HP variable-speed rotary screw, {voltage}, {psi} PSI",
                HORSEPOWER=hp, KW=kw, VOLTAGE=voltage, FULL_LOAD_AMPS=fla,
                CAPACITY_CFM=cfm, PRESSURE_PSI=psi, LIST_PRICE_USD=price,
                LEAD_TIME_WEEKS=lead, STATUS="Active", CAGI_CERTIFIED=True,
                LAUNCH_DATE=date(2020,6,1) + timedelta(days=int(np.random.randint(0,1500)))
            ))
    # Centrifugal compressors: C500, C750, C1000, C1500, C2000
    for size in [500, 750, 1000, 1500, 2000]:
        kw = size*0.55
        hp = round(kw*1.341,1)
        cfm = float(size*5)
        psi = float(np.random.choice([125,150,200]))
        fla = round(hp*1.1,1)
        price = round(size*1200 + np.random.uniform(-2000,5000),2)
        lead = round(np.random.uniform(16,32),1)
        for variant in ["GA","NA"]:
            pid = f"C{size}-{variant}"
            rows.append(dict(
                PRODUCT_ID=pid, MODEL_CODE=f"C{size}", PRODUCT_FAMILY="Centrifugal",
                PRODUCT_LINE="C-Series Centrifugal",
                DESCRIPTION=f"Apex C{size} centrifugal air compressor, {variant} configuration, {psi} PSI",
                HORSEPOWER=hp, KW=round(kw,1), VOLTAGE="460V", FULL_LOAD_AMPS=fla,
                CAPACITY_CFM=cfm, PRESSURE_PSI=psi, LIST_PRICE_USD=price,
                LEAD_TIME_WEEKS=lead, STATUS="Active", CAGI_CERTIFIED=True,
                LAUNCH_DATE=date(2018,3,1) + timedelta(days=int(np.random.randint(0,2000)))
            ))
    # Diesel reciprocating: DR10, DR15, DR25, DR50, DR100
    for hp in [10,15,25,50,100]:
        cfm = float(hp*3.8)
        psi = 175.0
        price = round(hp*350 + np.random.uniform(-200,500),2)
        lead = round(np.random.uniform(3,10),1)
        pid = f"DR{hp}"
        rows.append(dict(
            PRODUCT_ID=pid, MODEL_CODE=pid, PRODUCT_FAMILY="Diesel Reciprocating",
            PRODUCT_LINE="DR-Series Portable",
            DESCRIPTION=f"Apex DR{hp} {hp}HP diesel-engine reciprocating air compressor, portable, {psi} PSI",
            HORSEPOWER=float(hp), KW=round(hp*0.745,1), VOLTAGE="N/A",
            FULL_LOAD_AMPS=None, CAPACITY_CFM=cfm, PRESSURE_PSI=psi,
            LIST_PRICE_USD=price, LEAD_TIME_WEEKS=lead, STATUS="Active",
            CAGI_CERTIFIED=False,
            LAUNCH_DATE=date(2017,1,1) + timedelta(days=int(np.random.randint(0,2500)))
        ))
    # Vacuum pumps: VP25, VP50, VP100, VP200
    for hp in [25,50,100,200]:
        cfm = float(hp*6)
        price = round(hp*450 + np.random.uniform(-300,700),2)
        lead = round(np.random.uniform(4,12),1)
        pid = f"VP{hp}"
        rows.append(dict(
            PRODUCT_ID=pid, MODEL_CODE=pid, PRODUCT_FAMILY="Vacuum Pump",
            PRODUCT_LINE="VP-Series Vacuum",
            DESCRIPTION=f"Apex VP{hp} {hp}HP rotary-vane vacuum pump",
            HORSEPOWER=float(hp), KW=round(hp*0.745,1), VOLTAGE="460V",
            FULL_LOAD_AMPS=round(hp*1.2,1), CAPACITY_CFM=cfm, PRESSURE_PSI=None,
            LIST_PRICE_USD=price, LEAD_TIME_WEEKS=lead, STATUS="Active",
            CAGI_CERTIFIED=False,
            LAUNCH_DATE=date(2019,5,1) + timedelta(days=int(np.random.randint(0,1800)))
        ))
    # Refrigerated dryers: TS5, TS10, TS15M, TS25, TS50, TS100, TS200, TS500
    for size in [5,10,15,25,50,100,200,500]:
        suffix = "M" if size==15 else ""
        cfm = float(size*10)
        price = round(size*120 + np.random.uniform(-100,400),2)
        lead = round(np.random.uniform(2,8),1)
        pid = f"TS{size}{suffix}"
        rows.append(dict(
            PRODUCT_ID=pid, MODEL_CODE=pid, PRODUCT_FAMILY="Air Treatment",
            PRODUCT_LINE="TS-Series Refrigerated Dryer",
            DESCRIPTION=f"Apex TS{size}{suffix} refrigerated air dryer, {cfm:.0f} SCFM",
            HORSEPOWER=None, KW=round(size*0.05,2), VOLTAGE="230V",
            FULL_LOAD_AMPS=round(size*0.2,1), CAPACITY_CFM=cfm, PRESSURE_PSI=150.0,
            LIST_PRICE_USD=price, LEAD_TIME_WEEKS=lead, STATUS="Active",
            CAGI_CERTIFIED=True,
            LAUNCH_DATE=date(2020,1,1) + timedelta(days=int(np.random.randint(0,1500)))
        ))
    # Air Quality / Filtration: AQ-100, AQ-250, AQ-500, AQ-1000
    for size in [100,250,500,1000]:
        cfm = float(size)
        price = round(size*15 + np.random.uniform(-100,200),2)
        pid = f"AQ-{size}"
        rows.append(dict(
            PRODUCT_ID=pid, MODEL_CODE=pid, PRODUCT_FAMILY="Air Quality",
            PRODUCT_LINE="AQ-Series Filtration",
            DESCRIPTION=f"Apex AQ-{size} oil-removal coalescing filter assembly, {size} SCFM",
            HORSEPOWER=None, KW=None, VOLTAGE=None, FULL_LOAD_AMPS=None,
            CAPACITY_CFM=cfm, PRESSURE_PSI=200.0,
            LIST_PRICE_USD=price, LEAD_TIME_WEEKS=round(np.random.uniform(2,6),1),
            STATUS="Active", CAGI_CERTIFIED=False,
            LAUNCH_DATE=date(2021,1,1) + timedelta(days=int(np.random.randint(0,1200)))
        ))
    # Blowers: BL-30, BL-60, BL-100, BL-200
    for hp in [30,60,100,200]:
        cfm = float(hp*30)
        price = round(hp*420 + np.random.uniform(-200,600),2)
        pid = f"BL-{hp}"
        rows.append(dict(
            PRODUCT_ID=pid, MODEL_CODE=pid, PRODUCT_FAMILY="Blower",
            PRODUCT_LINE="BL-Series Centrifugal Blower",
            DESCRIPTION=f"Apex BL-{hp} {hp}HP centrifugal blower for low-pressure air",
            HORSEPOWER=float(hp), KW=round(hp*0.745,1), VOLTAGE="460V",
            FULL_LOAD_AMPS=round(hp*1.2,1), CAPACITY_CFM=cfm, PRESSURE_PSI=15.0,
            LIST_PRICE_USD=price, LEAD_TIME_WEEKS=round(np.random.uniform(8,16),1),
            STATUS="Active", CAGI_CERTIFIED=False,
            LAUNCH_DATE=date(2020,3,1) + timedelta(days=int(np.random.randint(0,1400)))
        ))
    # Mark a couple EOL
    df = pd.DataFrame(rows)
    eol_idx = df.sample(n=4, random_state=3).index
    df.loc[eol_idx, "STATUS"] = "EOL"
    return df

# --------------------------------------------------------------------------
def build_accounts(n=120):
    rows = []
    for i in range(n):
        city = random.choice(CITIES)
        name = f"{random.choice(PREFIXES)} {random.choice(SUFFIXES)}"
        if random.random() < 0.15:
            name = f"{name} of {city[0]}"
        rows.append(dict(
            ACCOUNT_ID=f"ACC-{i+1001:05d}",
            ACCOUNT_NAME=name,
            INDUSTRY=random.choice(INDUSTRIES),
            SEGMENT=random.choices(SEGMENTS, weights=[1,2,4,3])[0],
            ANNUAL_REVENUE_M=round(np.random.lognormal(mean=4.0, sigma=1.0), 2),
            EMPLOYEES=int(np.random.lognormal(mean=5.5, sigma=1.0)),
            BILLING_CITY=city[0], BILLING_STATE=city[1], BILLING_COUNTRY="USA",
            LATITUDE=round(city[2] + np.random.uniform(-0.15,0.15), 6),
            LONGITUDE=round(city[3] + np.random.uniform(-0.15,0.15), 6),
            ACCOUNT_OWNER=random.choice(SALES_REPS),
            ACCOUNT_TIER=random.choices(TIERS, weights=[2,4,5])[0],
            PARENT_ACCOUNT_ID=None,
            SERVICE_PLAN=random.choices(SERVICE_PLANS, weights=[2,3,2])[0],
            CREATED_DATE=date(2018,1,1) + timedelta(days=int(np.random.randint(0,2900))),
            LAST_ACTIVITY_DATE=date.today() - timedelta(days=int(np.random.randint(0,180))),
        ))
    # Account names must be unique: the agent tools look customers up by name. Later
    # duplicates get their city (and a numeral if needed); no extra random draws, so
    # every other generated value is unchanged.
    seen = set()
    for r in rows:
        name, k = r["ACCOUNT_NAME"], 2
        if name in seen and " of " not in name:
            name = f"{name} of {r['BILLING_CITY']}"
        base = name
        while name in seen:
            name, k = f"{base} {k}", k + 1
        r["ACCOUNT_NAME"] = name
        seen.add(name)
    return pd.DataFrame(rows)

def build_contacts(accounts):
    titles = [("Plant Manager","Plant Mgmt","Decision Maker"),
              ("Operations Director","Operations","Decision Maker"),
              ("Maintenance Manager","Maintenance","Influencer"),
              ("Maintenance Supervisor","Maintenance","User"),
              ("Procurement Manager","Procurement","Decision Maker"),
              ("Buyer","Procurement","Influencer"),
              ("Reliability Engineer","Engineering","Influencer"),
              ("Process Engineer","Engineering","Influencer"),
              ("Facilities Manager","Plant Mgmt","Decision Maker"),
              ("Energy Manager","Engineering","Influencer"),
              ("Plant Engineer","Engineering","User"),
              ("VP Operations","Operations","Decision Maker"),
              ("Controller","Finance","Gatekeeper")]
    first_names = ["James","Mary","Robert","Patricia","John","Jennifer","Michael","Linda",
                   "David","Elizabeth","William","Barbara","Richard","Susan","Joseph","Jessica",
                   "Thomas","Sarah","Charles","Karen","Christopher","Nancy","Daniel","Lisa",
                   "Matthew","Margaret","Anthony","Betty","Mark","Sandra","Donald","Ashley",
                   "Steven","Kimberly","Paul","Emily","Andrew","Donna","Joshua","Michelle",
                   "Carlos","Maria","Wei","Mei","Aarav","Priya","Amir","Fatima"]
    last_names = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis",
                  "Rodriguez","Martinez","Hernandez","Lopez","Gonzalez","Wilson","Anderson",
                  "Thomas","Taylor","Moore","Jackson","Martin","Lee","Perez","Thompson","White",
                  "Harris","Sanchez","Clark","Ramirez","Lewis","Robinson","Walker","Young",
                  "Allen","King","Wright","Scott","Torres","Nguyen","Hill","Flores","Patel",
                  "Khan","Singh","Chen","Wang","Kim","Park","Cohen"]
    rows = []
    cid = 1
    for _, a in accounts.iterrows():
        n_contacts = random.randint(2,6)
        used_titles = random.sample(titles, n_contacts)
        for j, (title, dept, role) in enumerate(used_titles):
            fn = random.choice(first_names); ln = random.choice(last_names)
            email_dom = a["ACCOUNT_NAME"].lower().split()[0].replace("'","") + ".com"
            rows.append(dict(
                CONTACT_ID=f"CON-{cid:06d}",
                ACCOUNT_ID=a["ACCOUNT_ID"],
                FIRST_NAME=fn, LAST_NAME=ln, TITLE=title, DEPARTMENT=dept,
                EMAIL=f"{fn.lower()}.{ln.lower()}@{email_dom}",
                PHONE=f"({random.randint(200,999)}) {random.randint(200,999)}-{random.randint(1000,9999)}",
                IS_PRIMARY=(j==0),
                DECISION_ROLE=role,
                LAST_CONTACTED=date.today() - timedelta(days=int(np.random.randint(0,200))),
                CREATED_DATE=date(2019,1,1) + timedelta(days=int(np.random.randint(0,2300))),
            ))
            cid += 1
    return pd.DataFrame(rows)

def build_inventory(products):
    rows = []
    locations = ["Davidson NC","Fairfield OH","Reno NV","Dallas TX","Atlanta GA"]
    iid = 1
    for _, p in products.iterrows():
        if p["STATUS"] != "Active": 
            continue
        # Most active products in 1-3 locations
        n_loc = random.choice([1,2,3])
        for loc in random.sample(locations, n_loc):
            qty = int(max(0, np.random.poisson(4)))
            res = int(min(qty, np.random.poisson(1)))
            rows.append(dict(
                INVENTORY_ID=f"INV-{iid:06d}",
                PRODUCT_ID=p["PRODUCT_ID"],
                LOCATION=loc,
                QTY_ON_HAND=qty,
                QTY_RESERVED=res,
                QTY_AVAILABLE=qty-res,
                AVG_DAYS_IN_STOCK=int(np.random.uniform(15,180)),
                LAST_RECEIVED_DATE=date.today() - timedelta(days=int(np.random.randint(0,90))),
                UNIT_COST_USD=round(float(p["LIST_PRICE_USD"])*0.62 if p["LIST_PRICE_USD"] else 0.0, 2),
            ))
            iid += 1
    return pd.DataFrame(rows)

def build_opportunities(accounts, products):
    stages = ["Prospecting","Qualification","Proposal","Negotiation","Closed Won","Closed Lost"]
    weights= [3,4,3,2,3,2]
    sources = ["Inbound","Outbound","Partner","Existing Customer","Trade Show"]
    rows = []
    oid = 1
    for _, a in accounts.iterrows():
        n = random.choices([0,1,2,3,4,5], weights=[1,3,4,3,2,1])[0]
        for _ in range(n):
            p = products.sample(1).iloc[0]
            stage = random.choices(stages, weights=weights)[0]
            qty = random.choice([1,1,1,2,2,3])
            amt = round(float(p["LIST_PRICE_USD"] or 50000) * qty * np.random.uniform(0.85, 1.05), 2)
            prob = {"Prospecting":10,"Qualification":25,"Proposal":50,"Negotiation":75,"Closed Won":100,"Closed Lost":0}[stage]
            close = date.today() + timedelta(days=int(np.random.randint(-90, 240)))
            rows.append(dict(
                OPPORTUNITY_ID=f"OPP-{oid:06d}",
                ACCOUNT_ID=a["ACCOUNT_ID"],
                OPP_NAME=f"{a['ACCOUNT_NAME']} - {p['MODEL_CODE']} {('Replacement' if random.random()<0.5 else 'Expansion')}",
                PRODUCT_ID=p["PRODUCT_ID"],
                STAGE=stage,
                AMOUNT_USD=amt,
                PROBABILITY_PCT=prob,
                CLOSE_DATE=close,
                OWNER=a["ACCOUNT_OWNER"],
                SOURCE=random.choice(sources),
                NEXT_STEP=random.choice([
                    "Schedule site walk","Send quote","Follow up on proposal",
                    "Negotiate terms","Confirm PO","Discovery call",
                    "Demo at customer site","Engineering review",""
                ]),
                CREATED_DATE=date.today() - timedelta(days=int(np.random.randint(15,365))),
                LAST_MODIFIED=date.today() - timedelta(days=int(np.random.randint(0,30))),
            ))
            oid += 1
    return pd.DataFrame(rows)

def build_open_orders(accounts, products):
    statuses = ["Booked","In Production","Ready to Ship","Shipped","Delayed"]
    rows = []
    oid = 1
    for _, a in accounts.iterrows():
        n = random.choices([0,1,2,3], weights=[3,4,2,1])[0]
        for _ in range(n):
            p = products.sample(1).iloc[0]
            qty = random.choice([1,1,1,2])
            up = float(p["LIST_PRICE_USD"] or 25000)
            order_dt = date.today() - timedelta(days=int(np.random.randint(5,120)))
            rows.append(dict(
                ORDER_ID=f"ORD-{oid:06d}",
                ACCOUNT_ID=a["ACCOUNT_ID"],
                PRODUCT_ID=p["PRODUCT_ID"],
                ORDER_DATE=order_dt,
                PROMISED_SHIP_DATE=order_dt + timedelta(days=int(p["LEAD_TIME_WEEKS"]*7)),
                QUANTITY=qty,
                UNIT_PRICE_USD=round(up*np.random.uniform(0.9,1.0),2),
                LINE_TOTAL_USD=round(up*qty*np.random.uniform(0.9,1.0),2),
                ORDER_STATUS=random.choices(statuses, weights=[3,4,2,2,1])[0],
                PO_NUMBER=f"PO-{random.randint(100000,999999)}",
                SALES_REP=a["ACCOUNT_OWNER"],
            ))
            oid += 1
    return pd.DataFrame(rows)

def build_assets(accounts, products):
    plans = ["ApexCare Premier","ApexCare Standard","None"]
    locations = ["Plant 1 - Compressor Room A","Plant 1 - Compressor Room B",
                 "Plant 2 - Utilities","Plant 2 - Process Air","Maintenance Shop",
                 "Building 3 Mezzanine","Building 4 Roof"]
    alerts = ["OK","WATCH","WARNING","CRITICAL"]
    rows = []
    aid = 1
    for _, a in accounts.iterrows():
        n_assets = random.choices([1,2,3,4,5,6,8], weights=[1,2,3,3,2,2,1])[0]
        for _ in range(n_assets):
            p = products.sample(1).iloc[0]
            install = date(2014,1,1) + timedelta(days=int(np.random.randint(0,3500)))
            warranty = install + timedelta(days=365*random.choice([1,2,3,5]))
            ohrs = int(np.random.uniform(500, 60000))
            health = round(np.random.uniform(35,99),2)
            alert = random.choices(alerts, weights=[6,3,2,1])[0]
            rows.append(dict(
                ASSET_ID=f"AST-{aid:06d}",
                ACCOUNT_ID=a["ACCOUNT_ID"],
                PRODUCT_ID=p["PRODUCT_ID"],
                SERIAL_NUMBER=f"APX-{random.randint(1000000,9999999)}",
                INSTALL_DATE=install,
                LOCATION_AT_SITE=random.choice(locations),
                WARRANTY_END_DATE=warranty,
                SERVICE_PLAN=random.choices(plans, weights=[2,3,3])[0],
                OPERATING_HOURS=ohrs,
                LAST_TELEMETRY_TS=datetime.now() - timedelta(hours=int(np.random.randint(0,48))),
                HEALTH_SCORE=health,
                PRESSURE_AVG_PSI=round(np.random.uniform(95,155),2),
                TEMP_AVG_F=round(np.random.uniform(160,230),2),
                VIBRATION_AVG_MMS=round(np.random.uniform(0.5,8.5),3),
                ALERT_LEVEL=alert,
                NEXT_PM_DATE=date.today() + timedelta(days=int(np.random.randint(-30,180))),
            ))
            aid += 1
    return pd.DataFrame(rows)

def build_service_activities(assets):
    types = ["Preventive Maintenance","Corrective","Inspection","Audit","Install","Warranty"]
    weights= [5,3,2,1,1,1]
    statuses = ["Completed","Completed","Completed","Scheduled","In Progress","Cancelled"]
    technicians = ["T. Hayes","M. Singh","R. Brennan","J. Castillo","D. Park","L. Petrov",
                   "S. Okafor","V. Krishnan","B. Anders","C. Mason","E. Morales","K. Jiang"]
    descriptions = {
        "Preventive Maintenance":[
            "Quarterly PM: oil/filter change, leak check, inlet valve inspection.",
            "Annual PM: coupling alignment, belt replacement, sensor calibration.",
            "Semi-annual PM: separator element swap, condensate drain service.",
        ],
        "Corrective":[
            "Replaced failed inlet valve solenoid; system back online.",
            "Repaired oil leak at separator gasket.",
            "Replaced air-end after high-vibration alarm.",
        ],
        "Inspection":[
            "Performed system audit; no critical issues.",
            "Air audit found 14% leak load; remediation plan provided.",
            "Vibration analysis baseline collected.",
        ],
        "Audit":["Energy audit performed; recommendations issued."],
        "Install":["Installed new unit and commissioned; baseline operational."],
        "Warranty":["Warranty service: replaced controller; covered under ApexCare."],
    }
    rows = []
    sid = 1
    for _, a in assets.iterrows():
        n = random.choices([0,1,2,3,4,6], weights=[1,2,3,3,2,1])[0]
        for _ in range(n):
            t = random.choices(types, weights=weights)[0]
            stat = random.choices(statuses, weights=[5,5,5,2,1,1])[0]
            dur = round(np.random.uniform(0.5,12),2)
            parts = round(np.random.uniform(0,4500),2) if t!="Inspection" else round(np.random.uniform(0,200),2)
            labor = round(dur*135,2)
            rows.append(dict(
                ACTIVITY_ID=f"SRV-{sid:07d}",
                ASSET_ID=a["ASSET_ID"],
                ACCOUNT_ID=a["ACCOUNT_ID"],
                ACTIVITY_TYPE=t,
                ACTIVITY_DATE=date.today() - timedelta(days=int(np.random.randint(0,720))),
                TECHNICIAN=random.choice(technicians),
                DURATION_HOURS=dur,
                DESCRIPTION=random.choice(descriptions[t]),
                STATUS=stat,
                PARTS_COST_USD=parts,
                LABOR_COST_USD=labor,
                TOTAL_COST_USD=round(parts+labor,2),
            ))
            sid += 1
    return pd.DataFrame(rows)

# --------------------------------------------------------------------------
def main():
    print("Building products…")
    products = build_products()
    print(f"  products: {len(products)}")
    print("Building accounts…")
    accounts = build_accounts(120)
    print(f"  accounts: {len(accounts)}")
    print("Building contacts…")
    contacts = build_contacts(accounts)
    print(f"  contacts: {len(contacts)}")
    print("Building inventory…")
    inventory = build_inventory(products)
    print(f"  inventory rows: {len(inventory)}")
    print("Building opportunities…")
    opps = build_opportunities(accounts, products)
    print(f"  opportunities: {len(opps)}")
    print("Building open orders…")
    orders = build_open_orders(accounts, products)
    print(f"  open orders: {len(orders)}")
    print("Building assets…")
    assets = build_assets(accounts, products)
    print(f"  assets: {len(assets)}")
    print("Building service activities…")
    service = build_service_activities(assets)
    print(f"  service activities: {len(service)}")

    tables = {
        "PRODUCTS": products, "ACCOUNTS": accounts, "CONTACTS": contacts,
        "INVENTORY": inventory, "OPPORTUNITIES": opps, "OPEN_ORDERS": orders,
        "ASSETS": assets, "SERVICE_ACTIVITIES": service,
    }
    for name, df in tables.items():
        path = OUT / f"{name.lower()}.parquet"
        df.to_parquet(path, index=False)
        print(f"wrote {path}  rows={len(df)}")

    # ---------- load to Snowflake ----------
    print("\nLoading to Snowflake…")
    import snowflake.connector
    conn = snowflake.connector.connect(
        connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME","my_snowflake")
    )
    cs = conn.cursor()
    cs.execute("USE DATABASE SF_SOLUTIONS")
    cs.execute("USE SCHEMA FIQ_ATOMIC")
    cs.execute("USE WAREHOUSE SF_SOLUTIONS_WH")

    for name in tables:
        path = OUT / f"{name.lower()}.parquet"
        cs.execute(f"PUT 'file://{path}' @SF_SOLUTIONS.FIQ_STAGES.PARQUET/{name.lower()}/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
        cs.execute(f"TRUNCATE TABLE SF_SOLUTIONS.FIQ_ATOMIC.{name}")
        cs.execute(f"""
            COPY INTO SF_SOLUTIONS.FIQ_ATOMIC.{name}
            FROM @SF_SOLUTIONS.FIQ_STAGES.PARQUET/{name.lower()}/
            FILE_FORMAT = (TYPE = PARQUET)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
            ON_ERROR = ABORT_STATEMENT
        """)
        cs.execute(f"SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.{name}")
        print(f"  {name}: {cs.fetchone()[0]} rows loaded")

    cs.close(); conn.close()
    print("\nDone.")

if __name__ == "__main__":
    main()
'''

SOURCES['generate_docs'] = r'''
"""Generate synthetic engineering docs (datasheets, GA drawings, submittals,
sales-training playbooks, CAGI sheets, pricing sheets) for FieldIQ by Apex Industrial.

Renders Markdown + PDF for each doc, writes to data/docs/, then uploads them to
@SF_SOLUTIONS.FIQ_STAGES.DOCS and registers them in SF_SOLUTIONS.FIQ_ATOMIC.DOCS_REGISTRY.

Run:
    SNOWFLAKE_CONNECTION_NAME=my_snowflake python3 scripts/generate_docs.py
"""
from __future__ import annotations
import os, random, math
from pathlib import Path
from datetime import date, datetime, timedelta

import pandas as pd
import numpy as np
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle)
from reportlab.pdfgen import canvas
from reportlab.graphics.shapes import Drawing, Rect, Line, String

random.seed(11)
np.random.seed(11)

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "synthetic"
DOCS = ROOT / "data" / "docs"
PDF_DIR = DOCS / "pdf"
MD_DIR  = DOCS / "md"
PDF_DIR.mkdir(parents=True, exist_ok=True)
MD_DIR.mkdir(parents=True, exist_ok=True)

def _v(x, default=None):
    """Treat NaN/None as default."""
    if x is None: return default
    if isinstance(x, float) and math.isnan(x): return default
    return x

# ----- Apex brand --------
APEX_RED = colors.HexColor("#E03C31")
APEX_DARK = colors.HexColor("#1F2937")
APEX_GRAY = colors.HexColor("#6B7280")

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="ApexTitle",  fontName="Helvetica-Bold", fontSize=22, leading=26, textColor=APEX_DARK, spaceAfter=4))
styles.add(ParagraphStyle(name="ApexSub",    fontName="Helvetica", fontSize=11, textColor=APEX_GRAY, spaceAfter=10))
styles.add(ParagraphStyle(name="ApexH2",     fontName="Helvetica-Bold", fontSize=13, leading=16, textColor=APEX_RED, spaceBefore=12, spaceAfter=6))
styles.add(ParagraphStyle(name="ApexBody",   fontName="Helvetica", fontSize=10, leading=13, textColor=APEX_DARK))
styles.add(ParagraphStyle(name="ApexFoot",   fontName="Helvetica-Oblique", fontSize=8, textColor=APEX_GRAY))

def header_footer(c: canvas.Canvas, doc):
    """Apex header bar + footer on every page."""
    w, h = LETTER
    # red banner top-left (angled motif)
    c.setFillColor(APEX_RED)
    p = c.beginPath()
    p.moveTo(0, h)
    p.lineTo(0, h-0.55*inch)
    p.lineTo(1.6*inch, h-0.55*inch)
    p.lineTo(2.0*inch, h)
    p.close()
    c.drawPath(p, stroke=0, fill=1)
    # word mark
    c.setFillColor(APEX_DARK)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(2.3*inch, h-0.35*inch, "APEX INDUSTRIAL")
    c.setFillColor(APEX_GRAY)
    c.setFont("Helvetica", 8)
    c.drawString(2.3*inch, h-0.5*inch, "Power. Air. Productivity.")
    # footer
    c.setStrokeColor(APEX_GRAY); c.setLineWidth(0.4)
    c.line(0.5*inch, 0.55*inch, w-0.5*inch, 0.55*inch)
    c.setFillColor(APEX_GRAY); c.setFont("Helvetica", 8)
    c.drawString(0.5*inch, 0.4*inch, f"Apex Industrial (fictional) — Sample Document")
    c.drawRightString(w-0.5*inch, 0.4*inch, f"Page {c.getPageNumber()}")

def make_pdf(path: Path, title: str, story_blocks):
    doc = SimpleDocTemplate(str(path), pagesize=LETTER,
                            leftMargin=0.6*inch, rightMargin=0.6*inch,
                            topMargin=0.95*inch, bottomMargin=0.7*inch,
                            title=title, author="Apex Industrial")
    doc.build(story_blocks, onFirstPage=header_footer, onLaterPages=header_footer)

def ga_drawing(p) -> Drawing:
    """Render a simple General-Arrangement plan-view box w/ dimensions for a product."""
    d = Drawing(450, 230)
    # outer box (top view)
    d.add(Rect(40, 60, 320, 130, strokeColor=APEX_DARK, fillColor=colors.whitesmoke, strokeWidth=1.5))
    # inlet/outlet ports
    d.add(Rect(360, 110, 14, 30, strokeColor=APEX_DARK, fillColor=APEX_RED))
    d.add(String(380, 122, "AIR OUT", fontSize=7, fillColor=APEX_DARK))
    d.add(Rect(26, 110, 14, 30, strokeColor=APEX_DARK, fillColor=APEX_RED))
    d.add(String(0, 122, "AIR IN", fontSize=7, fillColor=APEX_DARK))
    # cooling fins / louvres
    for x in range(60, 340, 18):
        d.add(Line(x, 70, x, 88, strokeColor=APEX_GRAY, strokeWidth=0.5))
    # title block
    d.add(Rect(40, 18, 320, 32, strokeColor=APEX_DARK, fillColor=colors.white, strokeWidth=0.7))
    d.add(String(50, 36, f"GENERAL ARRANGEMENT — {p['MODEL_CODE']}", fontSize=10, fillColor=APEX_DARK, fontName="Helvetica-Bold"))
    d.add(String(50, 24, f"DWG: GA-{p['MODEL_CODE']}-001  |  REV B  |  APEX INDUSTRIAL  |  SCALE NTS",
                 fontSize=7, fillColor=APEX_GRAY))
    # dimension callouts
    L = 84.0; W = 48.0; H = 66.0
    hp = _v(p["HORSEPOWER"])
    if hp:
        L = 56 + float(hp)*0.45
        W = 32 + float(hp)*0.18
        H = 48 + float(hp)*0.21
    d.add(String(190, 200, f"L = {L:.0f} in", fontSize=8, fillColor=APEX_DARK))
    d.add(String(2, 175, f"W = {W:.0f} in", fontSize=8, fillColor=APEX_DARK))
    d.add(String(380, 175, f"H = {H:.0f} in", fontSize=8, fillColor=APEX_DARK))
    # arrows for L
    d.add(Line(40, 195, 360, 195, strokeColor=APEX_DARK, strokeWidth=0.5))
    return d

# --------------------------------------------------------------------------
# Datasheet
# --------------------------------------------------------------------------
def write_datasheet(p) -> tuple[Path, Path, str]:
    pid = p["PRODUCT_ID"]
    title = f"{pid} — Product Datasheet"
    md_path  = MD_DIR / f"datasheet_{pid}.md"
    pdf_path = PDF_DIR / f"datasheet_{pid}.pdf"

    family = p["PRODUCT_FAMILY"]
    desc   = p["DESCRIPTION"]
    hp     = _v(p["HORSEPOWER"]); kw = _v(p["KW"])
    cfm    = _v(p["CAPACITY_CFM"]); psi = _v(p["PRESSURE_PSI"])
    voltage= _v(p["VOLTAGE"]); fla = _v(p["FULL_LOAD_AMPS"])
    price  = _v(p["LIST_PRICE_USD"], 0.0)
    lead   = _v(p["LEAD_TIME_WEEKS"], 0.0)
    cagi   = bool(_v(p["CAGI_CERTIFIED"], False))

    # selling points by family
    selling = {
        "Rotary Screw": [
            "Industry-leading specific power (kW/100 cfm) for energy savings",
            "Continuous-duty oil-flooded design rated 100% load 24/7",
            "Integrated cooler, separator, and starter for reduced footprint",
            "Optional variable-speed drive (RSi) cuts ~35% energy on variable-load plants",
            "ApexCare service plan covers parts, labor, and remote monitoring",
        ],
        "Centrifugal":[
            "Oil-free Class-Zero (ISO 8573-1) air for food/bev, pharma, electronics",
            "Three-stage compression with intercoolers and aftercooler",
            "Industry-leading turndown ratio (40%) reduces blow-off losses",
            "Predictive analytics via ApexInsight IoT gateway",
            "Designed for continuous duty in the harshest plant environments",
        ],
        "Diesel Reciprocating":[
            "Portable, no-electrical-utility diesel-driven recip for remote sites",
            "Tier-4 final compliant engine, low-emission certified",
            "Skid-mounted, lift-truck-fork pockets, optional trailer mount",
            "Heavy-duty cast-iron crankcase rated for severe-duty cycling",
            "Ideal for construction, drilling, mobile rental fleets",
        ],
        "Vacuum Pump":[
            "Rotary-vane oil-flooded design for stable deep vacuum",
            "Quiet operation < 72 dBA, suitable for in-plant siting",
            "Integrated oil mist separator, no oil carryover to process",
            "Spare-parts kits and ApexCare PM intervals at 4,000 hr",
        ],
        "Air Treatment":[
            "Refrigerated dryer to 38 °F PDP, ISO 8573-1 Class 4 water removal",
            "Eco-mode reduces compressor load by ~12% during low-flow periods",
            "Side-stream condensate management with auto-drain",
            "Designed to pair seamlessly with RS- and C-Series compressors",
        ],
        "Air Quality":[
            "Coalescing element removes oil aerosol to <0.01 mg/m³ (Class 1)",
            "Differential-pressure indicator built-in, predictive element-change alerts",
            "Snap-action housing, no-tools element replacement",
            "Required per CAGI / ISO 8573 for sensitive applications",
        ],
        "Blower":[
            "High-volume low-pressure air for wastewater aeration, pneumatic conveying",
            "Variable-speed control delivers 30-100% turndown",
            "Acoustic enclosure rated < 78 dBA",
            "Stainless impeller for long life in corrosive service",
        ],
    }.get(family, ["Engineered for industrial duty.","Designed by Apex Industrial."])

    # build markdown
    md_lines = [
        f"# {pid} — Product Datasheet",
        f"*{p['PRODUCT_LINE']}* — Apex Industrial",
        "",
        f"**Description:** {desc}",
        "",
        "## Key Specifications",
        "| Field | Value |",
        "|---|---|",
        f"| Product ID | {pid} |",
        f"| Model Code | {p['MODEL_CODE']} |",
        f"| Family | {family} |",
        f"| Horsepower | {hp if hp else 'N/A'} HP |",
        f"| Power | {kw if kw else 'N/A'} kW |",
        f"| Voltage | {voltage or 'N/A'} |",
        f"| Full-Load Amps | {fla if fla else 'N/A'} A |",
        f"| Capacity | {cfm if cfm else 'N/A'} CFM/SCFM |",
        f"| Working Pressure | {psi if psi else 'N/A'} PSI |",
        f"| Lead Time | {lead} weeks |",
        f"| List Price (USD) | ${price:,.2f} |",
        f"| CAGI Certified | {'Yes' if cagi else 'No'} |",
        f"| Status | {p['STATUS']} |",
        "",
        "## Selling Points",
    ] + [f"- {s}" for s in selling] + [
        "",
        "## Typical Applications",
        f"{family} units like the {pid} are commonly deployed in food & beverage, packaging, automotive, pharmaceutical, and general manufacturing plants. Selection should match flow (CFM), pressure (PSI), and duty cycle to the customer's process air demand profile.",
        "",
        "## Service & Warranty",
        "Standard 1-year parts/labor warranty. ApexCare Premier extends to 5 years, with 24/7 telemetry monitoring, predictive PM scheduling, and priority parts dispatch. ApexCare Standard provides scheduled PM and 8x5 telephone support.",
        "",
        "## How to Sell",
        f"Lead with total-cost-of-ownership and energy savings. For variable-load plants, position the variable-speed (i-suffix) variant. For oil-sensitive processes (food, pharma, electronics), upsell to oil-free centrifugal C-Series. Always pair with TS-Series dryer + AQ-Series filtration to deliver Class-1 air per ISO 8573.",
        "",
    ]
    md = "\n".join(md_lines)
    md_path.write_text(md)

    # build PDF
    story = []
    story.append(Paragraph(title, styles["ApexTitle"]))
    story.append(Paragraph(f"{p['PRODUCT_LINE']} &nbsp;&nbsp;|&nbsp;&nbsp; Apex Industrial", styles["ApexSub"]))
    story.append(Paragraph(desc, styles["ApexBody"]))
    story.append(Spacer(1, 8))
    story.append(Paragraph("Key Specifications", styles["ApexH2"]))
    spec_rows = [
        ["Product ID", pid],
        ["Model Code", p["MODEL_CODE"]],
        ["Product Family", family],
        ["Product Line", p["PRODUCT_LINE"]],
        ["Horsepower", f"{hp} HP" if hp else "N/A"],
        ["Rated Power", f"{kw} kW" if kw else "N/A"],
        ["Voltage", voltage or "N/A"],
        ["Full-Load Amps", f"{fla} A" if fla else "N/A"],
        ["Capacity", f"{cfm} CFM" if cfm else "N/A"],
        ["Working Pressure", f"{psi} PSI" if psi else "N/A"],
        ["Lead Time", f"{lead} weeks"],
        ["List Price (USD)", f"${price:,.2f}"],
        ["CAGI Certified", "Yes" if cagi else "No"],
        ["Status", p["STATUS"]],
    ]
    t = Table(spec_rows, colWidths=[2.0*inch, 4.7*inch])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (0,-1), colors.HexColor("#FEF2F2")),
        ("TEXTCOLOR", (0,0), (0,-1), APEX_DARK),
        ("FONTNAME", (0,0), (0,-1), "Helvetica-Bold"),
        ("FONTSIZE", (0,0), (-1,-1), 9),
        ("ROWBACKGROUNDS", (1,0), (-1,-1), [colors.white, colors.HexColor("#F9FAFB")]),
        ("GRID", (0,0), (-1,-1), 0.25, APEX_GRAY),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("BOTTOMPADDING", (0,0), (-1,-1), 4),
    ]))
    story.append(t)
    story.append(Paragraph("Selling Points", styles["ApexH2"]))
    for s in selling:
        story.append(Paragraph(f"• {s}", styles["ApexBody"]))
    story.append(Paragraph("Typical Applications", styles["ApexH2"]))
    story.append(Paragraph(
        f"{family} units like the <b>{pid}</b> are commonly deployed in food & beverage, packaging, automotive, "
        "pharmaceutical, and general manufacturing plants. Selection should match flow (CFM), pressure (PSI), "
        "and duty cycle to the customer's process air demand profile.", styles["ApexBody"]))
    story.append(Paragraph("Service & Warranty", styles["ApexH2"]))
    story.append(Paragraph(
        "Standard 1-year parts/labor warranty. <b>ApexCare Premier</b> extends to 5 years, with 24/7 telemetry "
        "monitoring, predictive PM scheduling, and priority parts dispatch. <b>ApexCare Standard</b> provides "
        "scheduled PM and 8x5 telephone support.", styles["ApexBody"]))
    make_pdf(pdf_path, title, story)
    return md_path, pdf_path, title

# --------------------------------------------------------------------------
# GA Drawing doc
# --------------------------------------------------------------------------
def write_ga_drawing(p) -> tuple[Path, Path, str]:
    pid = p["PRODUCT_ID"]; mc = p["MODEL_CODE"]
    title = f"{pid} GA — General Arrangement Drawing"
    md_path  = MD_DIR / f"drawing_{pid}_GA.md"
    pdf_path = PDF_DIR / f"drawing_{pid}_GA.pdf"

    L = 84.0; W = 48.0; H = 66.0
    hp_ = _v(p["HORSEPOWER"])
    if hp_:
        L = round(56 + float(hp_)*0.45, 1)
        W = round(32 + float(hp_)*0.18, 1)
        H = round(48 + float(hp_)*0.21, 1)
    try:
        weight_lb = int((L*W*H)*0.45 + 200)
    except Exception:
        weight_lb = 800
    cfm_val = p["CAPACITY_CFM"]
    if cfm_val is None or (isinstance(cfm_val, float) and math.isnan(cfm_val)):
        cfm_val = 0
    air_port  = "2.5\" NPT" if cfm_val < 200 else ("3\" NPT" if cfm_val < 600 else "4\" Flange")

    md = f"""# {title}
*Drawing Number: GA-{mc}-001 | Revision: B | Apex Industrial*

This General Arrangement (GA) drawing for the **{pid}** ({p['DESCRIPTION']}) provides
overall envelope dimensions, port locations, and clearance requirements for installation
planning and submittal review.

## Footprint & Envelope (in inches)
| Dimension | Value |
|---|---|
| Length (L) | {L} in |
| Width (W) | {W} in |
| Height (H) | {H} in |
| Net Weight | {weight_lb} lb |
| Recommended service clearance | 36 in (front), 24 in (sides/rear) |

## Port & Connection Schedule
| Item | Connection |
|---|---|
| Air outlet | {air_port} |
| Cooling air inlet | Side-mounted louvre, {int(W*0.6)} sq in |
| Power entry | Bottom, conduit fitting |
| Condensate drain | 1/2" NPT auto-drain |
| Service access door | Front, 32" wide |

## Notes
- Drawing not to scale; consult certified submittal drawing for installation.
- Foundation: level concrete pad, 6" thick min., M16 anchor bolts on 4-corner pattern.
- Ambient operating range: 35-115 °F. Derate above 110 °F per Apex install manual.

— Apex Industrial Engineering, Drawing Office
"""
    md_path.write_text(md)

    story = []
    story.append(Paragraph(title, styles["ApexTitle"]))
    story.append(Paragraph(f"Drawing No. GA-{mc}-001 &nbsp;|&nbsp; Revision B &nbsp;|&nbsp; Apex Industrial", styles["ApexSub"]))
    story.append(Paragraph(p["DESCRIPTION"], styles["ApexBody"]))
    story.append(Spacer(1, 6))
    story.append(ga_drawing(p))
    story.append(Spacer(1, 8))
    story.append(Paragraph("Footprint & Envelope", styles["ApexH2"]))
    rows = [
        ["Length (L)", f"{L} in"],
        ["Width (W)",  f"{W} in"],
        ["Height (H)", f"{H} in"],
        ["Net Weight", f"{weight_lb} lb"],
        ["Service Clearance", "36 in front / 24 in sides & rear"],
    ]
    t = Table(rows, colWidths=[2.0*inch, 4.7*inch])
    t.setStyle(TableStyle([("GRID",(0,0),(-1,-1),0.25,APEX_GRAY),
                           ("FONTSIZE",(0,0),(-1,-1),9),
                           ("BACKGROUND",(0,0),(0,-1),colors.HexColor("#FEF2F2")),
                           ("FONTNAME",(0,0),(0,-1),"Helvetica-Bold")]))
    story.append(t)
    story.append(Paragraph("Port & Connection Schedule", styles["ApexH2"]))
    rows = [["Air outlet", air_port],
            ["Cooling air inlet", f"Side-mounted louvre, {int(W*0.6)} sq in"],
            ["Power entry", "Bottom, conduit fitting"],
            ["Condensate drain", '1/2" NPT auto-drain'],
            ["Service access door", '32" wide front']]
    t = Table(rows, colWidths=[2.0*inch, 4.7*inch])
    t.setStyle(TableStyle([("GRID",(0,0),(-1,-1),0.25,APEX_GRAY),("FONTSIZE",(0,0),(-1,-1),9),
                           ("BACKGROUND",(0,0),(0,-1),colors.HexColor("#FEF2F2")),
                           ("FONTNAME",(0,0),(0,-1),"Helvetica-Bold")]))
    story.append(t)
    story.append(Paragraph("Installation Notes", styles["ApexH2"]))
    story.append(Paragraph(
        "Drawing is for reference; certified-for-construction submittal supersedes this document. "
        "Foundation: level concrete pad, 6 in thick minimum, M16 anchor bolts on 4-corner pattern. "
        "Ambient operating range 35–115 °F; derate above 110 °F per install manual.",
        styles["ApexBody"]))
    make_pdf(pdf_path, title, story)
    return md_path, pdf_path, title

# --------------------------------------------------------------------------
# Submittal package (multi-section)
# --------------------------------------------------------------------------
def write_submittal(p) -> tuple[Path, Path, str]:
    pid = p["PRODUCT_ID"]
    title = f"{pid} Submittal Package"
    md_path  = MD_DIR / f"submittal_{pid}.md"
    pdf_path = PDF_DIR / f"submittal_{pid}.pdf"
    md = f"""# {title}
*Apex Industrial — Engineering Submittal Document*

Project: __________________  Date: __________  PE Stamp: __________

## Section 1 — Equipment Schedule
- Tag/Identifier: CMP-1
- Manufacturer: Apex Industrial
- Model: {pid}
- Quantity: 1

## Section 2 — Datasheet
See attached `datasheet_{pid}.pdf` — full specifications.

## Section 3 — General Arrangement
See attached `drawing_{pid}_GA.pdf` — footprint and port locations.

## Section 4 — Electrical Data
- Voltage: {_v(p['VOLTAGE']) or 'N/A'}
- Full-Load Amps: {_v(p['FULL_LOAD_AMPS']) or 'N/A'} A
- Recommended overcurrent protection: per NEC 430 (FLA × 1.25)
- Disconnect: customer-supplied lockable

## Section 5 — Performance Curve (CAGI)
- Capacity (CFM): {_v(p['CAPACITY_CFM']) or 'N/A'}
- Working Pressure (PSI): {_v(p['PRESSURE_PSI']) or 'N/A'}
- Specific Power (kW/100 cfm): {round((_v(p['KW']) or 0)/((_v(p['CAPACITY_CFM']) or 1)/100), 2) if _v(p['KW']) and _v(p['CAPACITY_CFM']) else 'N/A'}

## Section 6 — Warranty & Service
Apex 1-year standard warranty; ApexCare Premier 5-year option available.

— Submittal package compiled by Apex Industrial Sales Engineering
"""
    md_path.write_text(md)

    story = []
    story.append(Paragraph(title, styles["ApexTitle"]))
    story.append(Paragraph("Engineering Submittal — for review and approval", styles["ApexSub"]))

    story.append(Paragraph("Section 1 — Equipment Schedule", styles["ApexH2"]))
    rows = [["Tag", "CMP-1"],["Manufacturer","Apex Industrial"],
            ["Model", pid],["Quantity","1"],
            ["Description", p["DESCRIPTION"]]]
    t = Table(rows, colWidths=[2.0*inch, 4.7*inch])
    t.setStyle(TableStyle([("GRID",(0,0),(-1,-1),0.25,APEX_GRAY),("FONTSIZE",(0,0),(-1,-1),9),
                           ("BACKGROUND",(0,0),(0,-1),colors.HexColor("#FEF2F2")),
                           ("FONTNAME",(0,0),(0,-1),"Helvetica-Bold")]))
    story.append(t)

    story.append(Paragraph("Section 2 — General Arrangement", styles["ApexH2"]))
    story.append(ga_drawing(p))

    story.append(Paragraph("Section 3 — Electrical Data", styles["ApexH2"]))
    rows = [["Voltage", _v(p["VOLTAGE"]) or "N/A"],
            ["Full-Load Amps", f"{_v(p['FULL_LOAD_AMPS'])} A" if _v(p['FULL_LOAD_AMPS']) else "N/A"],
            ["Overcurrent Protection","Per NEC 430 (FLA × 1.25)"],
            ["Disconnect","Customer-supplied lockable"]]
    t = Table(rows, colWidths=[2.0*inch, 4.7*inch])
    t.setStyle(TableStyle([("GRID",(0,0),(-1,-1),0.25,APEX_GRAY),("FONTSIZE",(0,0),(-1,-1),9),
                           ("BACKGROUND",(0,0),(0,-1),colors.HexColor("#FEF2F2")),
                           ("FONTNAME",(0,0),(0,-1),"Helvetica-Bold")]))
    story.append(t)

    story.append(Paragraph("Section 4 — Performance Data (CAGI Reference)", styles["ApexH2"]))
    rows = [["Capacity", f"{_v(p['CAPACITY_CFM'])} CFM" if _v(p['CAPACITY_CFM']) else "N/A"],
            ["Working Pressure", f"{_v(p['PRESSURE_PSI'])} PSI" if _v(p['PRESSURE_PSI']) else "N/A"],
            ["Power Input", f"{_v(p['KW'])} kW" if _v(p['KW']) else "N/A"],
            ["Specific Power",
             f"{round((_v(p['KW']) or 0)/((_v(p['CAPACITY_CFM']) or 1)/100), 2)} kW / 100 cfm"
             if (_v(p['KW']) and _v(p['CAPACITY_CFM'])) else "N/A"]]
    t = Table(rows, colWidths=[2.0*inch, 4.7*inch])
    t.setStyle(TableStyle([("GRID",(0,0),(-1,-1),0.25,APEX_GRAY),("FONTSIZE",(0,0),(-1,-1),9),
                           ("BACKGROUND",(0,0),(0,-1),colors.HexColor("#FEF2F2")),
                           ("FONTNAME",(0,0),(0,-1),"Helvetica-Bold")]))
    story.append(t)

    story.append(Paragraph("Section 5 — Warranty", styles["ApexH2"]))
    story.append(Paragraph(
        "Apex 1-year standard parts/labor warranty included. <b>ApexCare Premier</b> 5-year extension "
        "available with 24/7 remote monitoring, predictive PM, priority parts dispatch.",
        styles["ApexBody"]))
    make_pdf(pdf_path, title, story)
    return md_path, pdf_path, title

# --------------------------------------------------------------------------
# Family-level sales-training playbook
# --------------------------------------------------------------------------
PLAYBOOKS = {
    "Rotary Screw": dict(
        name="RS-Series Rotary Screw Air Compressors",
        target="Plant Manager, Operations Director, Energy Manager, Procurement",
        when_to_sell="Continuous-duty plant air, 100-7,500 CFM, 100-200 PSI. Replacing aging competitor fleets, capacity expansions, or energy-efficiency upgrades.",
        objections=[
            ("Customer says: 'Your price is higher than competitor.'",
             "Lead with 7-year specific-power energy savings. A 100-HP RS-series saves ~$8K-$14K/yr in electricity vs. an old fixed-speed unit. Total cost of ownership beats list-price gap in <18 months."),
            ("Customer says: 'We already have ApexCare with our incumbent.'",
             "Position ApexCare Premier with telemetry: 24/7 health, predictive PM, priority parts. Reduces unplanned downtime by ~40% in our installed base."),
            ("Customer says: 'My maintenance team prefers fixed-speed.'",
             "VSD only when load varies >25%. For steady-load plants, fixed-speed RS-series is the right answer — and we offer both."),
        ],
        roi=[
            "Energy: ~30% reduction vs. 10+ yr-old units (fixed-speed); ~35% with VSD on variable-load plants",
            "Service spend: ~25% reduction with ApexCare Premier (predictive vs reactive PM)",
            "Downtime: ~40% reduction with telemetry-guided service",
        ],
    ),
    "Centrifugal":dict(
        name="C-Series Centrifugal Compressors",
        target="Plant Engineer, Reliability Engineer, VP Operations (oil-free critical)",
        when_to_sell="Large-volume oil-free air for food/bev, pharma, electronics. 500-2000 HP. Replacing old centrifugals or scaling beyond rotary-screw economics.",
        objections=[
            ("Customer is concerned about turndown / blow-off losses.",
             "C-Series offers industry-leading 40% turndown via inlet-guide-vane control — beats class average by 10 pts. Pair with ApexInsight for adaptive control."),
            ("Customer worried about complexity vs rotary-screw.",
             "Above ~600 CFM continuous oil-free, centrifugal is the only viable option. Apex C-Series simplifies with integrated controls and our certified field-service network."),
        ],
        roi=[
            "Energy: ~6% improvement vs. legacy three-stage centrifugals via stage-2/3 impeller redesign",
            "Air quality: Class-Zero oil-free certified per ISO 8573-1",
        ],
    ),
    "Diesel Reciprocating":dict(
        name="DR-Series Diesel Reciprocating Compressors",
        target="Rental fleet manager, Site superintendent, Drilling/Construction lead",
        when_to_sell="Mobile/portable air for construction, drilling, and remote sites without grid power. 10-100 HP diesel-driven recip. Customers needing tier-4 emissions compliance.",
        objections=[
            ("Customer says: 'We use rental units instead.'",
             "For >120 hours/year usage, owned DR-Series breaks even in <2 years vs. weekly rental. We offer rental-to-own conversion programs."),
            ("Customer concerned about diesel emissions.",
             "DR-Series is Tier-4 Final certified; meets all EPA non-road emissions standards. Optional regen DPF available."),
        ],
        roi=[
            "Diesel-driven: no electrical infrastructure required at remote sites",
            "Skid + lift-truck pockets, 10-min site setup",
        ],
    ),
    "Vacuum Pump":dict(
        name="VP-Series Vacuum Pumps",
        target="Process Engineer, Plant Engineer (food packaging, plastics, paper)",
        when_to_sell="Vacuum applications: packaging, plastics extrusion, paper handling, lab/pharma. 25-200 HP rotary-vane oil-flooded.",
        objections=[
            ("Customer using dry-claw vacuum.",
             "VP-Series oil-flooded delivers deeper vacuum, lower noise, and better tolerance to wet inlet streams. We offer both — match technology to process."),
        ],
        roi=["Quiet ops <72 dBA", "Spare-part kits standardized to 4,000-hr PM intervals"],
    ),
    "Air Treatment":dict(
        name="TS-Series Air Treatment / Refrigerated Dryers",
        target="Reliability Engineer, Maintenance Manager",
        when_to_sell="Always pair with new compressor sale. Customers with quality-sensitive applications (paint, food, pneumatics).",
        objections=[("Customer says: 'I don't need a dryer.'",
            "Untreated compressed air carries 25-40 g/m³ moisture. Causes pneumatic-tool failure, paint defects, microbial growth. ROI on dryer is typically <12 months in failed-pneumatics avoidance.")],
        roi=["Class 4 PDP per ISO 8573", "Eco-mode reduces ~12% load at low flow"],
    ),
    "Air Quality":dict(
        name="AQ-Series Filtration",
        target="Process Engineer (food, pharma, electronics)",
        when_to_sell="Mandatory pair-sale with any new compressor where ISO 8573 Class 1 oil-removal is required.",
        objections=[("Customer asks why coalescing + activated-carbon both needed.",
            "Coalescing removes oil aerosol >3 µm. Activated-carbon removes oil vapor. Together = ISO 8573 Class 1. Pharma and food safety auditors require both stages.")],
        roi=["Element life ~6,000 hr", "Predictive replacement alerts via ApexInsight"],
    ),
    "Blower":dict(
        name="BL-Series Centrifugal Blowers",
        target="Wastewater treatment plant lead, Pneumatic-conveying engineer",
        when_to_sell="High-volume low-pressure (15 PSI or less) air for aeration, conveying, drying. 30-200 HP.",
        objections=[("Customer using positive-displacement blowers.",
            "Centrifugal beats PD on energy >100 HP and runs quieter. Stainless impeller version handles corrosive WWTP duty.")],
        roi=["~12% energy savings vs PD blowers at >100 HP", "30-100% turndown via VSD"],
    ),
}

def write_playbook(family: str) -> tuple[Path, Path, str]:
    pb = PLAYBOOKS[family]
    title = f"How to Sell {pb['name']}"
    safe = family.replace(" ","_")
    md_path  = MD_DIR / f"playbook_{safe}.md"
    pdf_path = PDF_DIR / f"playbook_{safe}.pdf"

    md = [f"# {title}",
          "*Sales Training Playbook — Apex Industrial*",
          "",
          f"**Target Personas:** {pb['target']}",
          "",
          f"**When to Sell:** {pb['when_to_sell']}",
          "",
          "## Objection Handling",
    ]
    for q,a in pb["objections"]:
        md += [f"- **{q}**", f"  - {a}"]
    md += ["", "## ROI / Value Story"]
    for r in pb["roi"]:
        md.append(f"- {r}")
    md += ["",
           "## Recommended Discovery Questions",
           "- What is your current compressed-air load profile (steady vs. variable)?",
           "- What does an unplanned downtime hour cost your operation?",
           "- Are you on a service contract today, and what does it cover?",
           "- What ISO 8573 air-quality class is required for your process?",
           "- What is your typical procurement evaluation timeline (weeks)?",
           ""]
    md_path.write_text("\n".join(md))

    story = []
    story.append(Paragraph(title, styles["ApexTitle"]))
    story.append(Paragraph("Sales Training Playbook — Apex Industrial", styles["ApexSub"]))
    story.append(Paragraph(f"<b>Target Personas:</b> {pb['target']}", styles["ApexBody"]))
    story.append(Paragraph(f"<b>When to Sell:</b> {pb['when_to_sell']}", styles["ApexBody"]))
    story.append(Paragraph("Objection Handling", styles["ApexH2"]))
    for q,a in pb["objections"]:
        story.append(Paragraph(f"<b>{q}</b>", styles["ApexBody"]))
        story.append(Paragraph(f"&nbsp;&nbsp;{a}", styles["ApexBody"]))
        story.append(Spacer(1,4))
    story.append(Paragraph("ROI / Value Story", styles["ApexH2"]))
    for r in pb["roi"]:
        story.append(Paragraph(f"• {r}", styles["ApexBody"]))
    story.append(Paragraph("Recommended Discovery Questions", styles["ApexH2"]))
    for q in ["What is your current compressed-air load profile (steady vs. variable)?",
              "What does an unplanned downtime hour cost your operation?",
              "Are you on a service contract today, and what does it cover?",
              "What ISO 8573 air-quality class is required for your process?",
              "What is your typical procurement evaluation timeline (weeks)?"]:
        story.append(Paragraph(f"• {q}", styles["ApexBody"]))
    make_pdf(pdf_path, title, story)
    return md_path, pdf_path, title

# --------------------------------------------------------------------------
# Pricing & lead-time sheet (one per family)
# --------------------------------------------------------------------------
def write_pricing_sheet(products: pd.DataFrame, family: str) -> tuple[Path, Path, str]:
    title = f"Apex {family} — Pricing & Lead-Time Sheet (Q2 2026)"
    safe = family.replace(" ","_")
    md_path  = MD_DIR / f"pricing_{safe}.md"
    pdf_path = PDF_DIR / f"pricing_{safe}.pdf"
    df = products[products["PRODUCT_FAMILY"]==family].sort_values(["PRODUCT_LINE","PRODUCT_ID"])
    md = [f"# {title}", "*Sample document — Apex Industrial (fictional)*", "",
          "| Product ID | Description | List Price (USD) | Lead Time (wks) | Status |",
          "|---|---|---|---|---|"]
    for _, r in df.iterrows():
        md.append(f"| {r['PRODUCT_ID']} | {r['DESCRIPTION']} | ${r['LIST_PRICE_USD']:,.2f} | {r['LEAD_TIME_WEEKS']} | {r['STATUS']} |")
    md_path.write_text("\n".join(md))

    story = []
    story.append(Paragraph(title, styles["ApexTitle"]))
    story.append(Paragraph("Sample document — Apex Industrial (fictional)", styles["ApexSub"]))
    rows = [["Product ID","Description","List Price (USD)","Lead (wks)","Status"]]
    for _, r in df.iterrows():
        rows.append([r["PRODUCT_ID"],
                     r["DESCRIPTION"][:60]+("…" if len(r["DESCRIPTION"])>60 else ""),
                     f"${r['LIST_PRICE_USD']:,.0f}",
                     f"{r['LEAD_TIME_WEEKS']}",
                     r["STATUS"]])
    t = Table(rows, colWidths=[1.1*inch, 3.5*inch, 1.1*inch, 0.7*inch, 0.7*inch], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND",(0,0),(-1,0),APEX_RED),
        ("TEXTCOLOR",(0,0),(-1,0),colors.white),
        ("FONTNAME",(0,0),(-1,0),"Helvetica-Bold"),
        ("FONTSIZE",(0,0),(-1,-1),8),
        ("GRID",(0,0),(-1,-1),0.25,APEX_GRAY),
        ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,colors.HexColor("#F9FAFB")]),
        ("VALIGN",(0,0),(-1,-1),"MIDDLE"),
    ]))
    story.append(t)
    make_pdf(pdf_path, title, story)
    return md_path, pdf_path, title

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main():
    products = pd.read_parquet(DATA / "products.parquet")
    print(f"Generating docs for {len(products)} products…")

    rows = []  # for DOCS_REGISTRY

    # Datasheets, GA drawings, submittals — one each per active product
    for _, p in products.iterrows():
        if p["STATUS"] != "Active":
            continue
        # datasheet (always)
        md, pdf, title = write_datasheet(p)
        rows.append(dict(
            DOC_ID=f"DOC-DS-{p['PRODUCT_ID']}", DOC_TITLE=title, DOC_TYPE="Datasheet",
            PRODUCT_FAMILY=p["PRODUCT_FAMILY"], PRODUCT_ID=p["PRODUCT_ID"],
            STAGE_PATH=f"@SF_SOLUTIONS.FIQ_STAGES.DOCS/datasheets/{pdf.name}",
            FILE_FORMAT="pdf", PAGE_COUNT=1,
            SOURCE_URL=None,
            PUBLISHED_DATE=date.today() - timedelta(days=int(np.random.randint(60,720))),
            LAST_INDEXED_TS=datetime.now()))
        # GA drawing — only for compressors/blowers/pumps (skip filters/dryers? include all for completeness)
        if p["PRODUCT_FAMILY"] in ("Rotary Screw","Centrifugal","Diesel Reciprocating","Vacuum Pump","Blower","Air Treatment"):
            md, pdf, title = write_ga_drawing(p)
            rows.append(dict(
                DOC_ID=f"DOC-GA-{p['PRODUCT_ID']}", DOC_TITLE=title, DOC_TYPE="GA Drawing",
                PRODUCT_FAMILY=p["PRODUCT_FAMILY"], PRODUCT_ID=p["PRODUCT_ID"],
                STAGE_PATH=f"@SF_SOLUTIONS.FIQ_STAGES.DOCS/drawings/{pdf.name}",
                FILE_FORMAT="pdf", PAGE_COUNT=1, SOURCE_URL=None,
                PUBLISHED_DATE=date.today() - timedelta(days=int(np.random.randint(120,1200))),
                LAST_INDEXED_TS=datetime.now()))
        # Submittals — only for top SKUs (centrifugal, large rotary, large blowers)
        kw_v = _v(p["KW"]); hp_v = _v(p["HORSEPOWER"])
        if (p["PRODUCT_FAMILY"]=="Centrifugal" or
            (p["PRODUCT_FAMILY"]=="Rotary Screw" and kw_v and kw_v>=37) or
            (p["PRODUCT_FAMILY"]=="Blower" and hp_v and hp_v>=60)):
            md, pdf, title = write_submittal(p)
            rows.append(dict(
                DOC_ID=f"DOC-SB-{p['PRODUCT_ID']}", DOC_TITLE=title, DOC_TYPE="Submittal",
                PRODUCT_FAMILY=p["PRODUCT_FAMILY"], PRODUCT_ID=p["PRODUCT_ID"],
                STAGE_PATH=f"@SF_SOLUTIONS.FIQ_STAGES.DOCS/submittals/{pdf.name}",
                FILE_FORMAT="pdf", PAGE_COUNT=4, SOURCE_URL=None,
                PUBLISHED_DATE=date.today() - timedelta(days=int(np.random.randint(60,500))),
                LAST_INDEXED_TS=datetime.now()))

    # Family playbooks
    for fam in PLAYBOOKS:
        md, pdf, title = write_playbook(fam)
        rows.append(dict(
            DOC_ID=f"DOC-PB-{fam.replace(' ','_')}", DOC_TITLE=title, DOC_TYPE="Sales Training",
            PRODUCT_FAMILY=fam, PRODUCT_ID=None,
            STAGE_PATH=f"@SF_SOLUTIONS.FIQ_STAGES.DOCS/playbooks/{pdf.name}",
            FILE_FORMAT="pdf", PAGE_COUNT=2, SOURCE_URL=None,
            PUBLISHED_DATE=date.today() - timedelta(days=int(np.random.randint(30,365))),
            LAST_INDEXED_TS=datetime.now()))

    # Pricing & lead-time sheets per family
    for fam in products["PRODUCT_FAMILY"].unique():
        md, pdf, title = write_pricing_sheet(products, fam)
        rows.append(dict(
            DOC_ID=f"DOC-PR-{fam.replace(' ','_')}", DOC_TITLE=title, DOC_TYPE="Pricing",
            PRODUCT_FAMILY=fam, PRODUCT_ID=None,
            STAGE_PATH=f"@SF_SOLUTIONS.FIQ_STAGES.DOCS/pricing/{pdf.name}",
            FILE_FORMAT="pdf", PAGE_COUNT=1, SOURCE_URL=None,
            PUBLISHED_DATE=date.today() - timedelta(days=int(np.random.randint(0,90))),
            LAST_INDEXED_TS=datetime.now()))

    registry = pd.DataFrame(rows)
    print(f"Generated {len(registry)} docs.  Counts by type:")
    print(registry["DOC_TYPE"].value_counts())

    registry_pq = DATA / "docs_registry.parquet"
    registry.to_parquet(registry_pq, index=False)

    # ---------- upload to Snowflake ----------
    print("\nUploading to Snowflake stage and indexing into DOCS_REGISTRY…")
    import snowflake.connector
    conn = snowflake.connector.connect(connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME","my_snowflake"))
    cs = conn.cursor()
    cs.execute("USE DATABASE SF_SOLUTIONS"); cs.execute("USE WAREHOUSE SF_SOLUTIONS_WH")
    # Upload PDFs
    cs.execute("REMOVE @SF_SOLUTIONS.FIQ_STAGES.DOCS")
    folders = {"datasheets":"datasheet_*.pdf","drawings":"drawing_*.pdf",
               "submittals":"submittal_*.pdf","playbooks":"playbook_*.pdf",
               "pricing":"pricing_*.pdf"}
    for sub, glob in folders.items():
        files = list(PDF_DIR.glob(glob))
        if not files: continue
        # PUT in batches
        for i, f in enumerate(files):
            cs.execute(f"PUT 'file://{f}' @SF_SOLUTIONS.FIQ_STAGES.DOCS/{sub}/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
        # Also upload markdown (Cortex Search prefers text)
    for f in MD_DIR.glob("*.md"):
        # route md to same subfolder by prefix
        base = f.stem
        if base.startswith("datasheet_"):  sub = "datasheets"
        elif base.startswith("drawing_"):  sub = "drawings"
        elif base.startswith("submittal_"):sub = "submittals"
        elif base.startswith("playbook_"): sub = "playbooks"
        elif base.startswith("pricing_"):  sub = "pricing"
        else: sub = "misc"
        cs.execute(f"PUT 'file://{f}' @SF_SOLUTIONS.FIQ_STAGES.DOCS/md/{sub}/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE")

    # Load registry
    cs.execute(f"PUT 'file://{registry_pq}' @SF_SOLUTIONS.FIQ_STAGES.PARQUET/docs_registry/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
    cs.execute("TRUNCATE TABLE SF_SOLUTIONS.FIQ_ATOMIC.DOCS_REGISTRY")
    cs.execute("""
        COPY INTO SF_SOLUTIONS.FIQ_ATOMIC.DOCS_REGISTRY
        FROM @SF_SOLUTIONS.FIQ_STAGES.PARQUET/docs_registry/
        FILE_FORMAT = (TYPE=PARQUET)
        MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
        ON_ERROR=ABORT_STATEMENT
    """)
    cs.execute("SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.DOCS_REGISTRY"); n=cs.fetchone()[0]
    print(f"DOCS_REGISTRY rows: {n}")
    cs.execute("LIST @SF_SOLUTIONS.FIQ_STAGES.DOCS")
    files = cs.fetchall()
    print(f"Stage @SF_SOLUTIONS.FIQ_STAGES.DOCS now has {len(files)} files")
    cs.close(); conn.close()
    print("Done.")

if __name__ == "__main__":
    main()
'''

SOURCES['build_doc_chunks'] = r'''
"""Build the SF_SOLUTIONS.FIQ_CORTEX.DOC_CHUNKS table by reading the markdown
versions of every doc and chunking them into ~800-token blocks for Cortex Search.
"""
from __future__ import annotations
import os, re, hashlib
from pathlib import Path
import pandas as pd
import snowflake.connector

ROOT = Path(__file__).resolve().parent.parent
MD_DIR = ROOT / "data" / "docs" / "md"
PARQUET_OUT = ROOT / "data" / "synthetic" / "doc_chunks.parquet"

def chunk_text(text: str, max_chars: int = 1800) -> list[str]:
    paras = re.split(r"\n\s*\n", text)
    chunks, cur = [], ""
    for p in paras:
        if len(cur) + len(p) + 2 <= max_chars:
            cur += ("\n\n" if cur else "") + p
        else:
            if cur: chunks.append(cur.strip())
            cur = p
    if cur: chunks.append(cur.strip())
    return chunks or [text[:max_chars]]

def main():
    files = sorted(MD_DIR.glob("*.md"))
    print(f"Reading {len(files)} markdown docs…")
    rows = []
    for f in files:
        text = f.read_text()
        # Pull title (1st line `# ...`)
        title_m = re.match(r"^#\s+(.+)$", text.split("\n",1)[0])
        title = title_m.group(1) if title_m else f.stem.replace("_"," ")
        # doc_type from prefix
        if f.stem.startswith("datasheet_"): dtype="Datasheet"
        elif f.stem.startswith("drawing_"): dtype="GA Drawing"
        elif f.stem.startswith("submittal_"): dtype="Submittal"
        elif f.stem.startswith("playbook_"): dtype="Sales Training"
        elif f.stem.startswith("pricing_"): dtype="Pricing"
        else: dtype="Other"
        # Try to extract product_id (datasheet_RS37i-A110.md, drawing_RS37i-A110_GA.md, submittal_RS37i-A110.md)
        m = re.match(r"(datasheet|drawing|submittal)_([A-Z0-9\-i]+?)(?:_GA)?$", f.stem)
        product_id = m.group(2) if m else None
        chunks = chunk_text(text)
        for i, c in enumerate(chunks):
            cid = hashlib.md5(f"{f.stem}::{i}".encode()).hexdigest()[:16]
            rows.append(dict(
                CHUNK_ID=cid,
                DOC_FILE=f.stem,
                DOC_TITLE=title,
                DOC_TYPE=dtype,
                PRODUCT_ID=product_id,
                CHUNK_INDEX=i,
                CONTENT=c,
            ))
    df = pd.DataFrame(rows)
    df.to_parquet(PARQUET_OUT, index=False)
    print(f"Wrote {len(df)} chunks -> {PARQUET_OUT}")

    print("Loading to Snowflake…")
    conn = snowflake.connector.connect(connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME","my_snowflake"))
    cs = conn.cursor()
    cs.execute("USE DATABASE SF_SOLUTIONS"); cs.execute("USE SCHEMA FIQ_CORTEX"); cs.execute("USE WAREHOUSE SF_SOLUTIONS_WH")
    cs.execute("""
        CREATE OR REPLACE TABLE DOC_CHUNKS (
            CHUNK_ID    STRING,
            DOC_FILE    STRING,
            DOC_TITLE   STRING,
            DOC_TYPE    STRING,
            PRODUCT_ID  STRING,
            CHUNK_INDEX NUMBER,
            CONTENT     STRING
        )
    """)
    cs.execute(f"PUT 'file://{PARQUET_OUT}' @SF_SOLUTIONS.FIQ_STAGES.PARQUET/doc_chunks/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
    cs.execute("""
        COPY INTO DOC_CHUNKS FROM @SF_SOLUTIONS.FIQ_STAGES.PARQUET/doc_chunks/
        FILE_FORMAT=(TYPE=PARQUET)
        MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE
        ON_ERROR=ABORT_STATEMENT
    """)
    cs.execute("SELECT COUNT(*) FROM DOC_CHUNKS"); print("DOC_CHUNKS rows:", cs.fetchone()[0])
    cs.close(); conn.close()
    print("Done.")

if __name__ == "__main__":
    main()
'''

import contextlib
import hashlib
import io
import os
import re
import shutil
import sys
import types

WORK = "/tmp/fiq"
PUT_RE = re.compile(r"^\s*PUT\s+'file://(?P<path>[^']+)'\s+(?P<stage>@\S+)", re.I)

class _Cursor:
    """Minimal snowflake.connector cursor over a Snowpark session.

    PUT statements are batched: files are grouped per target stage folder and uploaded
    with one session.file.put per folder before the next non-PUT statement runs.
    """

    def __init__(self, session):
        self.session, self.rows, self.pending = session, [], {}

    def _flush(self):
        for stage, src_dir in self.pending.items():
            self.session.file.put(f"{src_dir}/*", stage, auto_compress=False, overwrite=True)
        self.pending = {}

    def execute(self, sql, params=None):
        m = PUT_RE.match(sql)
        if m:
            stage = m.group("stage").rstrip("/")
            d = self.pending.get(stage) or f"{WORK}/put/{hashlib.md5(stage.encode()).hexdigest()}"
            os.makedirs(d, exist_ok=True)
            shutil.copy(m.group("path"), d)
            self.pending[stage] = d
            return self
        self._flush()
        self.rows = [tuple(r) for r in self.session.sql(sql, params=params).collect()]
        return self

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return self.rows

    def close(self):
        self._flush()

class _Conn:
    def __init__(self, session):
        self.session = session

    def cursor(self):
        return _Cursor(self.session)

    def close(self):
        pass

def run(session):
    """Run the generators in order and return their combined log."""
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(f"{WORK}/scripts", exist_ok=True)
    import snowflake

    shim = types.ModuleType("snowflake.connector")
    shim.connect = lambda **kwargs: _Conn(session)
    sys.modules["snowflake.connector"] = shim
    snowflake.connector = shim
    log = io.StringIO()
    with contextlib.redirect_stdout(log):
        for name in ORDER:
            print(f"== {name}")
            module = {"__name__": f"fiq_{name}", "__file__": f"{WORK}/scripts/{name}.py"}
            exec(compile(SOURCES[name], f"{name}.py", "exec"), module)
            module["main"]()
    return log.getvalue()[-15000:]
$$;

SELECT 'FieldIQ setup complete. Next: run scripts/data.sql' AS STATUS;
