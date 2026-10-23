-- =============================================================================
-- Solution: FieldIQ - pipeline
-- Database: SF_SOLUTIONS
-- Schemas:  FIQ_ATOMIC, FIQ_ANALYTICS, FIQ_CORTEX, FIQ_ACTIONS, FIQ_STAGES
-- Creates datamart views, semantic view, Cortex Search service and the FieldIQ Cortex Agent.
-- Run after data.sql.
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed
-- by the terms in LICENSE, unless expressly agreed to in writing. You use this
-- application at your own risk, and Snowflake has no obligation to support your use
-- of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- -------------------------------------------------------------------------
-- Datamart views
-- Source: ddl/003_datamart_views.sql
-- -------------------------------------------------------------------------

USE SCHEMA FIQ_ANALYTICS;

-- Account 360 — one row per account with rolled-up KPIs
CREATE OR REPLACE VIEW V_ACCOUNT_360 AS
SELECT
    a.ACCOUNT_ID,
    a.ACCOUNT_NAME,
    a.INDUSTRY,
    a.SEGMENT,
    a.ACCOUNT_TIER,
    a.SERVICE_PLAN,
    a.ACCOUNT_OWNER,
    a.BILLING_CITY,
    a.BILLING_STATE,
    a.BILLING_COUNTRY,
    a.LATITUDE,
    a.LONGITUDE,
    a.ANNUAL_REVENUE_M,
    a.EMPLOYEES,
    a.LAST_ACTIVITY_DATE,
    -- Pipeline
    (SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES o
        WHERE o.ACCOUNT_ID=a.ACCOUNT_ID AND o.STAGE NOT IN ('Closed Won','Closed Lost')) AS OPEN_OPPORTUNITY_COUNT,
    (SELECT COALESCE(SUM(o.AMOUNT_USD),0) FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES o
        WHERE o.ACCOUNT_ID=a.ACCOUNT_ID AND o.STAGE NOT IN ('Closed Won','Closed Lost')) AS OPEN_PIPELINE_USD,
    (SELECT COALESCE(SUM(o.AMOUNT_USD),0) FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES o
        WHERE o.ACCOUNT_ID=a.ACCOUNT_ID AND o.STAGE='Closed Won' AND o.CLOSE_DATE >= DATEADD(year,-1,CURRENT_DATE())) AS CLOSED_WON_LTM_USD,
    -- Orders
    (SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.OPEN_ORDERS oo
        WHERE oo.ACCOUNT_ID=a.ACCOUNT_ID AND oo.ORDER_STATUS NOT IN ('Shipped')) AS OPEN_ORDER_COUNT,
    (SELECT COALESCE(SUM(oo.LINE_TOTAL_USD),0) FROM SF_SOLUTIONS.FIQ_ATOMIC.OPEN_ORDERS oo
        WHERE oo.ACCOUNT_ID=a.ACCOUNT_ID AND oo.ORDER_STATUS NOT IN ('Shipped')) AS OPEN_ORDER_VALUE_USD,
    -- Installed base
    (SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s WHERE s.ACCOUNT_ID=a.ACCOUNT_ID) AS INSTALLED_ASSET_COUNT,
    (SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s
        WHERE s.ACCOUNT_ID=a.ACCOUNT_ID AND s.ALERT_LEVEL IN ('WARNING','CRITICAL')) AS ASSETS_AT_RISK,
    (SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s
        WHERE s.ACCOUNT_ID=a.ACCOUNT_ID AND s.SERVICE_PLAN='None') AS ASSETS_NO_SERVICE_PLAN,
    -- Service
    (SELECT COUNT(*) FROM SF_SOLUTIONS.FIQ_ATOMIC.SERVICE_ACTIVITIES sa
        WHERE sa.ACCOUNT_ID=a.ACCOUNT_ID AND sa.ACTIVITY_DATE >= DATEADD(year,-1,CURRENT_DATE())) AS SERVICE_ACTIVITIES_LTM,
    (SELECT COALESCE(SUM(sa.TOTAL_COST_USD),0) FROM SF_SOLUTIONS.FIQ_ATOMIC.SERVICE_ACTIVITIES sa
        WHERE sa.ACCOUNT_ID=a.ACCOUNT_ID AND sa.ACTIVITY_DATE >= DATEADD(year,-1,CURRENT_DATE())) AS SERVICE_SPEND_LTM_USD
FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a;

-- Pipeline summary by stage
CREATE OR REPLACE VIEW V_PIPELINE_BY_STAGE AS
SELECT STAGE,
       COUNT(*)              AS OPP_COUNT,
       SUM(AMOUNT_USD)       AS TOTAL_AMOUNT_USD,
       AVG(PROBABILITY_PCT)  AS AVG_PROBABILITY_PCT,
       SUM(AMOUNT_USD * PROBABILITY_PCT/100.0) AS WEIGHTED_AMOUNT_USD
FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES
GROUP BY STAGE;

-- Asset risk view
CREATE OR REPLACE VIEW V_ASSET_RISK AS
SELECT s.ASSET_ID, s.ACCOUNT_ID, a.ACCOUNT_NAME, a.BILLING_CITY, a.BILLING_STATE,
       s.PRODUCT_ID, p.MODEL_CODE, p.PRODUCT_FAMILY,
       s.SERIAL_NUMBER, s.LOCATION_AT_SITE, s.SERVICE_PLAN,
       s.OPERATING_HOURS, s.HEALTH_SCORE, s.PRESSURE_AVG_PSI,
       s.TEMP_AVG_F, s.VIBRATION_AVG_MMS, s.ALERT_LEVEL,
       s.NEXT_PM_DATE, s.WARRANTY_END_DATE, s.INSTALL_DATE,
       DATEDIFF(year, s.INSTALL_DATE, CURRENT_DATE()) AS AGE_YEARS,
       CASE WHEN s.WARRANTY_END_DATE < CURRENT_DATE() THEN TRUE ELSE FALSE END AS OUT_OF_WARRANTY
FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s
JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a USING (ACCOUNT_ID)
JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON s.PRODUCT_ID=p.PRODUCT_ID;

-- Daily order pipeline / shipments
CREATE OR REPLACE VIEW V_OPEN_ORDERS_ENRICHED AS
SELECT o.*, a.ACCOUNT_NAME, a.BILLING_CITY, a.BILLING_STATE,
       p.MODEL_CODE, p.PRODUCT_FAMILY, p.DESCRIPTION AS PRODUCT_DESCRIPTION
FROM SF_SOLUTIONS.FIQ_ATOMIC.OPEN_ORDERS o
JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a USING (ACCOUNT_ID)
LEFT JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON o.PRODUCT_ID=p.PRODUCT_ID;

-- Inventory by location
CREATE OR REPLACE VIEW V_INVENTORY_ENRICHED AS
SELECT i.*, p.MODEL_CODE, p.PRODUCT_FAMILY, p.DESCRIPTION,
       p.LIST_PRICE_USD, p.LEAD_TIME_WEEKS, p.HORSEPOWER, p.CAPACITY_CFM, p.PRESSURE_PSI
FROM SF_SOLUTIONS.FIQ_ATOMIC.INVENTORY i
JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON i.PRODUCT_ID=p.PRODUCT_ID;

-- Opportunities enriched
CREATE OR REPLACE VIEW V_OPPORTUNITIES_ENRICHED AS
SELECT o.*, a.ACCOUNT_NAME, a.INDUSTRY, a.SEGMENT, a.ACCOUNT_TIER, a.BILLING_CITY, a.BILLING_STATE,
       p.MODEL_CODE, p.PRODUCT_FAMILY
FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES o
JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a USING (ACCOUNT_ID)
LEFT JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON o.PRODUCT_ID=p.PRODUCT_ID;

-- Service activities enriched
CREATE OR REPLACE VIEW V_SERVICE_ACTIVITIES_ENRICHED AS
SELECT sa.*, a.ACCOUNT_NAME, ast.SERIAL_NUMBER, ast.PRODUCT_ID,
       p.MODEL_CODE, p.PRODUCT_FAMILY
FROM SF_SOLUTIONS.FIQ_ATOMIC.SERVICE_ACTIVITIES sa
JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a USING (ACCOUNT_ID)
LEFT JOIN SF_SOLUTIONS.FIQ_ATOMIC.ASSETS ast ON sa.ASSET_ID=ast.ASSET_ID
LEFT JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON ast.PRODUCT_ID=p.PRODUCT_ID;

-- Contacts enriched
CREATE OR REPLACE VIEW V_CONTACTS_ENRICHED AS
SELECT c.*, a.ACCOUNT_NAME, a.BILLING_CITY, a.BILLING_STATE
FROM SF_SOLUTIONS.FIQ_ATOMIC.CONTACTS c
JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a USING (ACCOUNT_ID);

SHOW VIEWS IN SCHEMA SF_SOLUTIONS.FIQ_ANALYTICS;

-- -------------------------------------------------------------------------
-- Semantic view for Cortex Analyst
-- Source: cortex/fieldiq_semantic_model.yaml
-- -------------------------------------------------------------------------

DROP SEMANTIC VIEW IF EXISTS SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_SEMANTIC_MODEL;
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('SF_SOLUTIONS.FIQ_CORTEX', $$
name: fieldiq_semantic_model
description: |
  FieldIQ by Apex Industrial — semantic model over CRM (accounts, contacts,
  opportunities) and ERP (open orders, inventory) plus installed-base assets and
  service activities for industrial-equipment sales reps. Use for pricing & lead
  times, customer pipeline, open orders, asset health, contacts, and service
  history questions.

tables:
  # ----------------------------------------------------------------------
  - name: ACCOUNTS
    description: Customer companies (manufacturers, food/bev, packaging, etc.)
    base_table:
      database: SF_SOLUTIONS
      schema: FIQ_ATOMIC
      table: ACCOUNTS
    primary_key:
      columns: [ACCOUNT_ID]
    dimensions:
      - name: account_id
        synonyms: [account, customer id]
        expr: ACCOUNT_ID
        data_type: TEXT
        unique: true
      - name: account_name
        synonyms: [customer, customer name, company]
        description: >-
          Unique customer name. Filter with an exact, case-insensitive match (ACCOUNT_NAME ILIKE '<name>',
          no wildcards): names can contain other names, e.g. 'Cascade Partners' and
          'Cascade Partners of Portland' are different accounts.
        expr: ACCOUNT_NAME
        data_type: TEXT
        sample_values: ["Cascade Partners", "Beacon Pharma", "Evergreen Industries"]
      - name: industry
        expr: INDUSTRY
        data_type: TEXT
        sample_values: ["Food & Beverage", "Packaging", "Automotive", "Pharmaceuticals"]
      - name: segment
        expr: SEGMENT
        data_type: TEXT
        sample_values: ["Strategic", "Enterprise", "Mid-Market", "SMB"]
      - name: account_tier
        synonyms: [tier]
        expr: ACCOUNT_TIER
        data_type: TEXT
      - name: service_plan
        synonyms: [apexcare plan, service contract]
        expr: SERVICE_PLAN
        data_type: TEXT
        sample_values: ["ApexCare Premier", "ApexCare Standard", "None"]
      - name: account_owner
        synonyms: [sales rep, owner]
        expr: ACCOUNT_OWNER
        data_type: TEXT
      - name: billing_city
        synonyms: [city, location]
        expr: BILLING_CITY
        data_type: TEXT
      - name: billing_state
        synonyms: [state]
        expr: BILLING_STATE
        data_type: TEXT
      - name: billing_country
        expr: BILLING_COUNTRY
        data_type: TEXT
      - name: latitude
        expr: LATITUDE
        data_type: NUMBER
      - name: longitude
        expr: LONGITUDE
        data_type: NUMBER
    facts:
      - name: annual_revenue_m
        synonyms: [annual revenue, customer revenue]
        expr: ANNUAL_REVENUE_M
        data_type: NUMBER
        description: Customer annual revenue in millions USD
      - name: employees
        expr: EMPLOYEES
        data_type: NUMBER
    time_dimensions:
      - name: created_date
        expr: CREATED_DATE
        data_type: DATE
      - name: last_activity_date
        expr: LAST_ACTIVITY_DATE
        data_type: DATE
    metrics:
      - name: account_count
        expr: COUNT(DISTINCT ACCOUNT_ID)
        description: Number of unique accounts

  # ----------------------------------------------------------------------
  - name: CONTACTS
    description: Buyers, plant managers, maintenance leads, and procurement contacts at customer accounts.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: CONTACTS}
    primary_key: {columns: [CONTACT_ID]}
    dimensions:
      - name: contact_id
        expr: CONTACT_ID
        data_type: TEXT
        unique: true
      - name: account_id
        expr: ACCOUNT_ID
        data_type: TEXT
      - name: first_name
        expr: FIRST_NAME
        data_type: TEXT
      - name: last_name
        expr: LAST_NAME
        data_type: TEXT
      - name: title
        synonyms: [job title, role]
        expr: TITLE
        data_type: TEXT
        sample_values: ["Plant Manager", "Maintenance Manager", "Procurement Manager"]
      - name: department
        expr: DEPARTMENT
        data_type: TEXT
      - name: email
        expr: EMAIL
        data_type: TEXT
      - name: phone
        expr: PHONE
        data_type: TEXT
      - name: is_primary
        expr: IS_PRIMARY
        data_type: BOOLEAN
      - name: decision_role
        synonyms: [decision maker]
        expr: DECISION_ROLE
        data_type: TEXT
        sample_values: ["Decision Maker", "Influencer", "User", "Gatekeeper"]
    time_dimensions:
      - name: last_contacted
        expr: LAST_CONTACTED
        data_type: DATE
    metrics:
      - name: contact_count
        expr: COUNT(DISTINCT CONTACT_ID)

  # ----------------------------------------------------------------------
  - name: PRODUCTS
    description: Apex Industrial product catalog with pricing, lead time, and engineering specifications.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: PRODUCTS}
    primary_key: {columns: [PRODUCT_ID]}
    dimensions:
      - name: product_id
        synonyms: [sku, model number]
        expr: PRODUCT_ID
        data_type: TEXT
        unique: true
        sample_values: ["RS37i-A110", "RS75i-A125", "C750-GA", "DR10", "TS15M", "AQ-250"]
      - name: model_code
        expr: MODEL_CODE
        data_type: TEXT
      - name: product_family
        synonyms: [product type, family]
        expr: PRODUCT_FAMILY
        data_type: TEXT
        sample_values: ["Rotary Screw", "Centrifugal", "Diesel Reciprocating", "Vacuum Pump", "Air Treatment", "Air Quality", "Blower"]
      - name: product_line
        expr: PRODUCT_LINE
        data_type: TEXT
      - name: description
        expr: DESCRIPTION
        data_type: TEXT
      - name: voltage
        expr: VOLTAGE
        data_type: TEXT
      - name: status
        expr: STATUS
        data_type: TEXT
      - name: cagi_certified
        synonyms: [cagi]
        expr: CAGI_CERTIFIED
        data_type: BOOLEAN
    facts:
      - name: horsepower
        synonyms: [hp]
        expr: HORSEPOWER
        data_type: NUMBER
      - name: kw
        synonyms: [kilowatts, power]
        expr: KW
        data_type: NUMBER
      - name: full_load_amps
        synonyms: [fla, full load amperage]
        expr: FULL_LOAD_AMPS
        data_type: NUMBER
      - name: capacity_cfm
        synonyms: [cfm, airflow, scfm]
        expr: CAPACITY_CFM
        data_type: NUMBER
      - name: pressure_psi
        synonyms: [psi, pressure, working pressure]
        expr: PRESSURE_PSI
        data_type: NUMBER
      - name: list_price_usd
        synonyms: [price, list price, cost]
        expr: LIST_PRICE_USD
        data_type: NUMBER
      - name: lead_time_weeks
        synonyms: [lead time, delivery]
        expr: LEAD_TIME_WEEKS
        data_type: NUMBER
    metrics:
      - name: product_count
        expr: COUNT(DISTINCT PRODUCT_ID)
      - name: avg_list_price
        expr: AVG(LIST_PRICE_USD)
      - name: avg_lead_time_weeks
        expr: AVG(LEAD_TIME_WEEKS)

  # ----------------------------------------------------------------------
  - name: INVENTORY
    description: |
      Stock on hand by distribution center ("barn units"). Use this for
      questions about availability, reservations, and stock for a given product.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: INVENTORY}
    primary_key: {columns: [INVENTORY_ID]}
    dimensions:
      - name: inventory_id
        expr: INVENTORY_ID
        data_type: TEXT
        unique: true
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: location
        synonyms: [warehouse, dc, distribution center, barn]
        expr: LOCATION
        data_type: TEXT
        sample_values: ["Davidson NC","Fairfield OH","Reno NV","Dallas TX","Atlanta GA"]
    facts:
      - name: qty_on_hand
        synonyms: [quantity, stock, units on hand, barn units]
        expr: QTY_ON_HAND
        data_type: NUMBER
      - name: qty_reserved
        expr: QTY_RESERVED
        data_type: NUMBER
      - name: qty_available
        synonyms: [available stock, available]
        expr: QTY_AVAILABLE
        data_type: NUMBER
      - name: avg_days_in_stock
        expr: AVG_DAYS_IN_STOCK
        data_type: NUMBER
      - name: unit_cost_usd
        expr: UNIT_COST_USD
        data_type: NUMBER
    time_dimensions:
      - name: last_received_date
        expr: LAST_RECEIVED_DATE
        data_type: DATE
    metrics:
      - name: total_on_hand
        expr: SUM(QTY_ON_HAND)
      - name: total_available
        expr: SUM(QTY_AVAILABLE)

  # ----------------------------------------------------------------------
  - name: OPPORTUNITIES
    description: Sales pipeline opportunities by account.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: OPPORTUNITIES}
    primary_key: {columns: [OPPORTUNITY_ID]}
    dimensions:
      - name: opportunity_id
        expr: OPPORTUNITY_ID
        data_type: TEXT
        unique: true
      - name: account_id
        expr: ACCOUNT_ID
        data_type: TEXT
      - name: opp_name
        expr: OPP_NAME
        data_type: TEXT
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: stage
        synonyms: [pipeline stage, deal stage]
        expr: STAGE
        data_type: TEXT
        sample_values: ["Prospecting","Qualification","Proposal","Negotiation","Closed Won","Closed Lost"]
      - name: owner
        expr: OWNER
        data_type: TEXT
      - name: source
        expr: SOURCE
        data_type: TEXT
      - name: next_step
        expr: NEXT_STEP
        data_type: TEXT
    facts:
      - name: amount_usd
        synonyms: [opportunity amount, deal size]
        expr: AMOUNT_USD
        data_type: NUMBER
      - name: probability_pct
        synonyms: [probability]
        expr: PROBABILITY_PCT
        data_type: NUMBER
    time_dimensions:
      - name: close_date
        expr: CLOSE_DATE
        data_type: DATE
      - name: created_date
        expr: CREATED_DATE
        data_type: DATE
    metrics:
      - name: pipeline_total
        expr: SUM(CASE WHEN STAGE NOT IN ('Closed Won','Closed Lost') THEN AMOUNT_USD ELSE 0 END)
      - name: weighted_pipeline
        expr: SUM(CASE WHEN STAGE NOT IN ('Closed Won','Closed Lost') THEN AMOUNT_USD * PROBABILITY_PCT/100.0 ELSE 0 END)
      - name: opportunity_count
        expr: COUNT(DISTINCT OPPORTUNITY_ID)

  # ----------------------------------------------------------------------
  - name: OPEN_ORDERS
    description: Booked / in-production / not-yet-shipped sales orders.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: OPEN_ORDERS}
    primary_key: {columns: [ORDER_ID]}
    dimensions:
      - name: order_id
        expr: ORDER_ID
        data_type: TEXT
        unique: true
      - name: account_id
        expr: ACCOUNT_ID
        data_type: TEXT
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: order_status
        synonyms: [status]
        expr: ORDER_STATUS
        data_type: TEXT
        sample_values: ["Booked","In Production","Ready to Ship","Shipped","Delayed"]
      - name: po_number
        synonyms: [purchase order]
        expr: PO_NUMBER
        data_type: TEXT
      - name: sales_rep
        expr: SALES_REP
        data_type: TEXT
    facts:
      - name: quantity
        expr: QUANTITY
        data_type: NUMBER
      - name: unit_price_usd
        expr: UNIT_PRICE_USD
        data_type: NUMBER
      - name: line_total_usd
        synonyms: [order value]
        expr: LINE_TOTAL_USD
        data_type: NUMBER
    time_dimensions:
      - name: order_date
        expr: ORDER_DATE
        data_type: DATE
      - name: promised_ship_date
        synonyms: [ship date, delivery date]
        expr: PROMISED_SHIP_DATE
        data_type: DATE
    metrics:
      - name: open_order_value
        expr: SUM(LINE_TOTAL_USD)
      - name: open_order_count
        expr: COUNT(DISTINCT ORDER_ID)

  # ----------------------------------------------------------------------
  - name: ASSETS
    description: Installed base of equipment at customer sites with health/IoT data.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: ASSETS}
    primary_key: {columns: [ASSET_ID]}
    dimensions:
      - name: asset_id
        expr: ASSET_ID
        data_type: TEXT
        unique: true
      - name: account_id
        expr: ACCOUNT_ID
        data_type: TEXT
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: serial_number
        expr: SERIAL_NUMBER
        data_type: TEXT
      - name: location_at_site
        expr: LOCATION_AT_SITE
        data_type: TEXT
      - name: service_plan
        expr: SERVICE_PLAN
        data_type: TEXT
        sample_values: ["ApexCare Premier","ApexCare Standard","None"]
      - name: alert_level
        synonyms: [risk, health alert]
        expr: ALERT_LEVEL
        data_type: TEXT
        sample_values: ["OK","WATCH","WARNING","CRITICAL"]
    facts:
      - name: operating_hours
        expr: OPERATING_HOURS
        data_type: NUMBER
      - name: health_score
        expr: HEALTH_SCORE
        data_type: NUMBER
      - name: pressure_avg_psi
        expr: PRESSURE_AVG_PSI
        data_type: NUMBER
      - name: temp_avg_f
        expr: TEMP_AVG_F
        data_type: NUMBER
      - name: vibration_avg_mms
        expr: VIBRATION_AVG_MMS
        data_type: NUMBER
    time_dimensions:
      - name: install_date
        expr: INSTALL_DATE
        data_type: DATE
      - name: warranty_end_date
        expr: WARRANTY_END_DATE
        data_type: DATE
      - name: next_pm_date
        synonyms: [next service, next preventive maintenance]
        expr: NEXT_PM_DATE
        data_type: DATE
    metrics:
      - name: asset_count
        expr: COUNT(DISTINCT ASSET_ID)
      - name: at_risk_count
        expr: COUNT(DISTINCT CASE WHEN ALERT_LEVEL IN ('WARNING','CRITICAL') THEN ASSET_ID END)
      - name: avg_health_score
        expr: AVG(HEALTH_SCORE)

  # ----------------------------------------------------------------------
  - name: SERVICE_ACTIVITIES
    description: Service history (PM, corrective, inspection) by asset/account.
    base_table: {database: SF_SOLUTIONS, schema: FIQ_ATOMIC, table: SERVICE_ACTIVITIES}
    primary_key: {columns: [ACTIVITY_ID]}
    dimensions:
      - name: activity_id
        expr: ACTIVITY_ID
        data_type: TEXT
        unique: true
      - name: account_id
        expr: ACCOUNT_ID
        data_type: TEXT
      - name: asset_id
        expr: ASSET_ID
        data_type: TEXT
      - name: activity_type
        synonyms: [service type, work type]
        expr: ACTIVITY_TYPE
        data_type: TEXT
        sample_values: ["Preventive Maintenance","Corrective","Inspection","Audit","Install","Warranty"]
      - name: technician
        expr: TECHNICIAN
        data_type: TEXT
      - name: status
        expr: STATUS
        data_type: TEXT
    facts:
      - name: duration_hours
        expr: DURATION_HOURS
        data_type: NUMBER
      - name: parts_cost_usd
        expr: PARTS_COST_USD
        data_type: NUMBER
      - name: labor_cost_usd
        expr: LABOR_COST_USD
        data_type: NUMBER
      - name: total_cost_usd
        expr: TOTAL_COST_USD
        data_type: NUMBER
    time_dimensions:
      - name: activity_date
        expr: ACTIVITY_DATE
        data_type: DATE
    metrics:
      - name: service_spend
        expr: SUM(TOTAL_COST_USD)
      - name: service_activity_count
        expr: COUNT(DISTINCT ACTIVITY_ID)

# ----------------------------------------------------------------------
relationships:
  - name: contacts_to_accounts
    left_table: CONTACTS
    right_table: ACCOUNTS
    relationship_columns:
      - {left_column: account_id, right_column: account_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: opportunities_to_accounts
    left_table: OPPORTUNITIES
    right_table: ACCOUNTS
    relationship_columns:
      - {left_column: account_id, right_column: account_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: opportunities_to_products
    left_table: OPPORTUNITIES
    right_table: PRODUCTS
    relationship_columns:
      - {left_column: product_id, right_column: product_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: open_orders_to_accounts
    left_table: OPEN_ORDERS
    right_table: ACCOUNTS
    relationship_columns:
      - {left_column: account_id, right_column: account_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: open_orders_to_products
    left_table: OPEN_ORDERS
    right_table: PRODUCTS
    relationship_columns:
      - {left_column: product_id, right_column: product_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: inventory_to_products
    left_table: INVENTORY
    right_table: PRODUCTS
    relationship_columns:
      - {left_column: product_id, right_column: product_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: assets_to_accounts
    left_table: ASSETS
    right_table: ACCOUNTS
    relationship_columns:
      - {left_column: account_id, right_column: account_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: assets_to_products
    left_table: ASSETS
    right_table: PRODUCTS
    relationship_columns:
      - {left_column: product_id, right_column: product_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: service_activities_to_accounts
    left_table: SERVICE_ACTIVITIES
    right_table: ACCOUNTS
    relationship_columns:
      - {left_column: account_id, right_column: account_id}
    join_type: left_outer
    relationship_type: many_to_one
  - name: service_activities_to_assets
    left_table: SERVICE_ACTIVITIES
    right_table: ASSETS
    relationship_columns:
      - {left_column: asset_id, right_column: asset_id}
    join_type: left_outer
    relationship_type: many_to_one

verified_queries:
  - name: price_for_product
    question: "What is the price for RS37i-A110?"
    sql: "SELECT PRODUCT_ID, MODEL_CODE, DESCRIPTION, LIST_PRICE_USD, LEAD_TIME_WEEKS FROM SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS WHERE PRODUCT_ID = 'RS37i-A110'"

  - name: lead_time_for_model
    question: "Lead time for TS15M 15T models"
    sql: "SELECT PRODUCT_ID, DESCRIPTION, LEAD_TIME_WEEKS FROM SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS WHERE MODEL_CODE = 'TS15M' OR PRODUCT_ID = 'TS15M'"

  - name: barn_units_for_model
    question: "Barn units for RS45"
    sql: |
      SELECT i.LOCATION, i.QTY_ON_HAND, i.QTY_AVAILABLE, p.PRODUCT_ID, p.DESCRIPTION
      FROM SF_SOLUTIONS.FIQ_ATOMIC.INVENTORY i
      JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON i.PRODUCT_ID = p.PRODUCT_ID
      WHERE p.MODEL_CODE = 'RS45' OR p.PRODUCT_ID LIKE 'RS45%'
      ORDER BY i.QTY_AVAILABLE DESC

  - name: full_load_amps
    question: "what is full load package amps for RS75i-A125"
    sql: "SELECT PRODUCT_ID, VOLTAGE, FULL_LOAD_AMPS, HORSEPOWER, KW FROM SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS WHERE PRODUCT_ID = 'RS75i-A125'"

  - name: contacts_for_account
    question: "Who are the key contacts at Beacon Pharma?"
    sql: |
      SELECT c.FIRST_NAME, c.LAST_NAME, c.TITLE, c.DEPARTMENT, c.EMAIL, c.PHONE, c.IS_PRIMARY, c.DECISION_ROLE
      FROM SF_SOLUTIONS.FIQ_ATOMIC.CONTACTS c
      JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a ON c.ACCOUNT_ID = a.ACCOUNT_ID
      WHERE a.ACCOUNT_NAME ILIKE 'Beacon Pharma'
      ORDER BY c.IS_PRIMARY DESC

  - name: open_orders_for_account
    question: "Show me open orders, opportunities, and assets for Beacon Pharma"
    sql: |
      SELECT 'Open Order'  AS RECORD_TYPE, oo.ORDER_ID AS ID, oo.ORDER_STATUS AS STATUS,
             oo.PRODUCT_ID, oo.LINE_TOTAL_USD AS AMOUNT, oo.PROMISED_SHIP_DATE AS DT
      FROM SF_SOLUTIONS.FIQ_ATOMIC.OPEN_ORDERS oo JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a ON oo.ACCOUNT_ID=a.ACCOUNT_ID
      WHERE a.ACCOUNT_NAME ILIKE 'Beacon Pharma'
      UNION ALL
      SELECT 'Opportunity', op.OPPORTUNITY_ID, op.STAGE, op.PRODUCT_ID, op.AMOUNT_USD, op.CLOSE_DATE
      FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES op JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a ON op.ACCOUNT_ID=a.ACCOUNT_ID
      WHERE a.ACCOUNT_NAME ILIKE 'Beacon Pharma'
      UNION ALL
      SELECT 'Asset', s.ASSET_ID, s.ALERT_LEVEL, s.PRODUCT_ID, NULL, s.NEXT_PM_DATE
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a ON s.ACCOUNT_ID=a.ACCOUNT_ID
      WHERE a.ACCOUNT_NAME ILIKE 'Beacon Pharma'

  - name: nearby_customers
    question: "Are there any other customers close to Fairfield, OH?"
    sql: |
      WITH center AS (
          SELECT AVG(LATITUDE) lat, AVG(LONGITUDE) lon
          FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS
          WHERE BILLING_CITY = 'Fairfield' AND BILLING_STATE = 'OH'
      )
      SELECT a.ACCOUNT_NAME, a.BILLING_CITY, a.BILLING_STATE, a.INDUSTRY,
             ROUND(ST_DISTANCE(ST_MAKEPOINT(a.LONGITUDE,a.LATITUDE),
                               ST_MAKEPOINT(c.lon,c.lat))/1609.34, 1) AS DISTANCE_MILES
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a, center c
      ORDER BY DISTANCE_MILES
      LIMIT 25

  - name: assets_without_service_plan
    question: "List my customer assets that don't have a service plan."
    sql: |
      SELECT a.ACCOUNT_NAME, s.SERIAL_NUMBER, s.PRODUCT_ID, p.DESCRIPTION, s.OPERATING_HOURS, s.ALERT_LEVEL
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s
      JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a ON s.ACCOUNT_ID = a.ACCOUNT_ID
      JOIN SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS p ON s.PRODUCT_ID = p.PRODUCT_ID
      WHERE s.SERVICE_PLAN = 'None'
      ORDER BY s.OPERATING_HOURS DESC
$$);

-- -------------------------------------------------------------------------
-- Cortex Search over the document chunks
-- -------------------------------------------------------------------------

CREATE OR REPLACE CORTEX SEARCH SERVICE SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_DOC_SEARCH
    ON CONTENT
    ATTRIBUTES DOC_TITLE, DOC_TYPE, PRODUCT_ID
    WAREHOUSE = SF_SOLUTIONS_WH
    TARGET_LAG = '1 hour'
    AS (SELECT CHUNK_ID, DOC_FILE, DOC_TITLE, DOC_TYPE, PRODUCT_ID, CHUNK_INDEX, CONTENT
        FROM SF_SOLUTIONS.FIQ_CORTEX.DOC_CHUNKS);

-- -------------------------------------------------------------------------
-- Cortex Agent (Analyst + Search + 5 action tools)
-- Source: cortex/deploy_agent.py
-- -------------------------------------------------------------------------

CREATE OR REPLACE AGENT SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_AGENT
FROM SPECIFICATION $$
{
  "models": {
    "orchestration": "auto"
  },
  "instructions": {
    "response": "You are FieldIQ, the AI sales co-pilot for Apex Industrial. Apex Industrial is a generic industrial-equipment manufacturer producing rotary-screw and centrifugal air compressors, diesel reciprocating compressors, vacuum pumps, dryers, filtration, and blowers. Your audience is field sales reps and account managers. Be concise, factual, action-oriented. Always cite specific facts from the data: product IDs, customer names, dollar amounts, dates, serial numbers. Format currency as $X,XXX.XX, dates as YYYY-MM-DD.",
    "orchestration": "Routing rules:\n- For PRICING, LEAD TIMES, BARN UNITS / inventory / stock, OPEN ORDERS, OPPORTUNITIES, ASSETS, SERVICE ACTIVITIES, CONTACTS, accounts/customer counts, and any quantitative question about CRM/ERP data: use the data_analyst tool.\n- For PRODUCT SPECIFICATIONS, ENGINEERING DATA, GA DRAWINGS, SUBMITTALS, datasheets, full-load amps, CAGI performance, sales-training materials / 'how to sell', or ANY document lookup: use the doc_search tool.\n- For 'sales call plan', 'call plan', or 'prep me for {customer}': call sales_call_plan_tool with the customer name.\n- For 'meeting agenda' for a customer: call meeting_agenda_tool.\n- For drafting/writing emails to customers (any language): call email_draft_tool.\n- For 'find nearby customers near {city}': call nearby_customers_tool.\n- For 'route plan' / 'multi-day visit' / 'two-day agenda factoring travel time': call route_plan_tool.\n- For multilingual responses, generate in the requested language.\n- Customer names are unique and some contain others (e.g. 'Cascade Partners' and 'Cascade Partners of Portland'): when asking data_analyst about one customer, name it exactly and ask for an exact name match.",
    "sample_questions": [
      {
        "question": "How to sell a 10HP diesel reciprocating compressor?"
      },
      {
        "question": "Drawing for C750 GA"
      },
      {
        "question": "What is full load amps for RS75i-A125 at 460V?"
      },
      {
        "question": "Price for RS37i-A110"
      },
      {
        "question": "Lead time for TS15M models"
      },
      {
        "question": "Barn units for RS45"
      },
      {
        "question": "Key contacts at Cascade Partners"
      },
      {
        "question": "Generate a sales call plan for Cascade Partners"
      },
      {
        "question": "Open orders, opportunities, and assets for Cascade Partners"
      },
      {
        "question": "Write a meeting agenda for Beacon Pharma"
      },
      {
        "question": "Are there any other customers close to Fairfield, OH?"
      },
      {
        "question": "I'm visiting Cascade Partners on May 12 — plan a 2-day route with nearby customers"
      },
      {
        "question": "Draft an email to Cascade Partners about assets without service plans, propose an inspection, in Spanish"
      }
    ]
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "data_analyst",
        "description": "Query the FieldIQ CRM/ERP semantic model for quantitative answers about products (price/lead time/specs), inventory (barn units), accounts, contacts, opportunities, open orders, assets/installed base, and service activities."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "doc_search",
        "description": "Semantic search over Apex Industrial engineering datasheets, GA drawings, submittal packages, sales-training playbooks, and pricing/lead-time sheets. Use for product specs, drawings, submittals, 'how to sell', engineering data."
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "sales_call_plan_tool",
        "description": "Generate an actionable SALES CALL PLAN for a customer: snapshot, objectives, talk tracks, risks, next steps. Input: customer name (substring match).",
        "input_schema": {
          "type": "object",
          "properties": {
            "customer_name": {
              "type": "string",
              "description": "Customer/account name"
            }
          },
          "required": [
            "customer_name"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "meeting_agenda_tool",
        "description": "Generate a 60-minute MEETING AGENDA timeline for a customer visit, grounded in their orders/opportunities/assets/service history.",
        "input_schema": {
          "type": "object",
          "properties": {
            "customer_name": {
              "type": "string"
            }
          },
          "required": [
            "customer_name"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "email_draft_tool",
        "description": "Draft a short outbound email to the customer's primary contact in any language. Provide the topic and the language.",
        "input_schema": {
          "type": "object",
          "properties": {
            "customer_name": {
              "type": "string",
              "description": "Customer/account name (substring ok)"
            },
            "topic": {
              "type": "string",
              "description": "What the email should be about (e.g., 'assets without service plan, propose inspection')"
            },
            "language": {
              "type": "string",
              "description": "Output language. Always provide one. Use 'English' if no language is specified."
            }
          },
          "required": [
            "customer_name",
            "topic",
            "language"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "nearby_customers_tool",
        "description": "Find Apex customers within N miles of a city/state.",
        "input_schema": {
          "type": "object",
          "properties": {
            "city": {
              "type": "string"
            },
            "state": {
              "type": "string",
              "description": "Two-letter US state code"
            },
            "radius_mi": {
              "type": "number",
              "description": "Radius in miles",
              "default": 50
            }
          },
          "required": [
            "city",
            "state"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "route_plan_tool",
        "description": "Plan a multi-day customer visit route anchored on a customer, filling with nearby customers ranked by pipeline.",
        "input_schema": {
          "type": "object",
          "properties": {
            "anchor_customer": {
              "type": "string"
            },
            "visit_date": {
              "type": "string",
              "description": "ISO date YYYY-MM-DD"
            },
            "num_days": {
              "type": "number",
              "default": 2
            }
          },
          "required": [
            "anchor_customer",
            "visit_date"
          ]
        }
      }
    }
  ],
  "tool_resources": {
    "data_analyst": {
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SF_SOLUTIONS_WH",
        "query_timeout": 60
      },
      "semantic_view": "SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_SEMANTIC_MODEL"
    },
    "doc_search": {
      "name": "SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_DOC_SEARCH",
      "max_results": 8,
      "title_column": "DOC_TITLE",
      "id_column": "CHUNK_ID"
    },
    "sales_call_plan_tool": {
      "type": "procedure",
      "identifier": "SF_SOLUTIONS.FIQ_ACTIONS.SALES_CALL_PLAN",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SF_SOLUTIONS_WH",
        "query_timeout": 120
      }
    },
    "meeting_agenda_tool": {
      "type": "procedure",
      "identifier": "SF_SOLUTIONS.FIQ_ACTIONS.MEETING_AGENDA",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SF_SOLUTIONS_WH",
        "query_timeout": 120
      }
    },
    "email_draft_tool": {
      "type": "procedure",
      "identifier": "SF_SOLUTIONS.FIQ_ACTIONS.EMAIL_DRAFT",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SF_SOLUTIONS_WH",
        "query_timeout": 120
      }
    },
    "nearby_customers_tool": {
      "type": "procedure",
      "identifier": "SF_SOLUTIONS.FIQ_ACTIONS.NEARBY_CUSTOMERS_JSON",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SF_SOLUTIONS_WH",
        "query_timeout": 60
      }
    },
    "route_plan_tool": {
      "type": "procedure",
      "identifier": "SF_SOLUTIONS.FIQ_ACTIONS.ROUTE_PLAN",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SF_SOLUTIONS_WH",
        "query_timeout": 120
      }
    }
  }
}
$$;

-- Make the agent visible in Snowflake Intelligence / CoWork
GRANT USAGE ON AGENT SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_AGENT TO ROLE PUBLIC;

SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
    || '/#/agents/database/SF_SOLUTIONS/schema/FIQ_CORTEX/agent/FIELDIQ_AGENT/details' AS AGENT_URL;
