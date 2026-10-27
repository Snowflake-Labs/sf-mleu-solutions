-- =============================================================================
-- Solution: Chemicals Pricing & Margin Intelligence - setup
-- Database: SF_SOLUTIONS
-- Schemas:  CHP_RAW, CHP_ATOMIC, CHP_OPS
-- Creates schemas, stages, tables and the data generator procedure.
-- Run order: setup.sql -> data.sql -> pipeline.sql -> (upload app files) -> streamlit.sql
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed by the terms in
-- LICENSE, unless expressly agreed to in writing. You use this application at your own
-- risk, and Snowflake has no obligation to support your use of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

SELECT 'This application is not part of the Snowflake Service and is governed by the terms in LICENSE, unless expressly agreed to in writing. You use this application at your own risk, and Snowflake has no obligation to support your use of this application.' AS DISCLAIMER;

-- Shared infrastructure (idempotent; never dropped by teardown)
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- Solution schemas
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CHP_RAW COMMENT = 'Landing zone: ERP sales orders, market reports, stage';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CHP_ATOMIC COMMENT = 'Normalized entities: products, customers, sites, market indices, orders, costs';
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.CHP_OPS COMMENT = 'Data mart, ML procedures and outputs, Cortex objects, Streamlit app';

CREATE STAGE IF NOT EXISTS SF_SOLUTIONS.CHP_RAW.DATA_STAGE COMMENT = 'Generated CSV files';
CREATE STAGE IF NOT EXISTS SF_SOLUTIONS.CHP_RAW.MARKET_DOCUMENTS DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Location referenced by market report records';
CREATE STAGE IF NOT EXISTS SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Streamlit app files';

-- =============================================================================
-- Raw tables
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_RAW;

-- =============================================================================
-- MARKET_FEEDSTOCK: External price indices (API feed simulation)
-- Source: price-reporting agencies and commodity exchanges (synthetic in this demo)
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_RAW.MARKET_FEEDSTOCK (
    record_id               INTEGER         NOT NULL,
    index_name              VARCHAR(100)    NOT NULL,      -- e.g., 'Ethylene CFR NEA', 'Propylene FOB USG'
    index_code              VARCHAR(50),                   -- e.g., 'ETH-CFR-NEA', 'PP-DEL-USG'
    price_date              DATE            NOT NULL,
    price_value             FLOAT           NOT NULL,
    price_currency          VARCHAR(10)     DEFAULT 'USD',
    price_unit              VARCHAR(20)     DEFAULT 'MT',  -- Metric Ton
    price_type              VARCHAR(20)     DEFAULT 'SPOT', -- SPOT, CONTRACT, FUTURES
    region                  VARCHAR(50),                   -- NEA, SEA, USG, ARA
    source                  VARCHAR(50),                   -- price-assessment source
    load_timestamp          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (record_id)
);

COMMENT ON TABLE CHP_RAW.MARKET_FEEDSTOCK IS 'External market price indices - daily feedstock prices';

-- =============================================================================
-- ERP_SALES_ORDERS: Transaction history from ERP system
-- Source: SAP, Oracle, or other ERP
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_RAW.ERP_SALES_ORDERS (
    order_id                VARCHAR(50)     NOT NULL,
    order_line_id           INTEGER         NOT NULL,
    order_date              DATE            NOT NULL,
    ship_date               DATE,
    customer_id             VARCHAR(50)     NOT NULL,
    customer_name           VARCHAR(200),
    product_id              VARCHAR(50)     NOT NULL,
    product_name            VARCHAR(200),
    quantity_mt             FLOAT           NOT NULL,      -- Quantity in Metric Tons
    unit_price              FLOAT           NOT NULL,      -- Price per MT
    total_amount            FLOAT,
    currency                VARCHAR(10)     DEFAULT 'USD',
    sales_region            VARCHAR(50),                   -- North America, Europe, Asia Pacific
    sales_channel           VARCHAR(50),                   -- Direct, Distributor, Spot
    customer_segment        VARCHAR(50),                   -- Industrial, Consumer, Agricultural
    contract_id             VARCHAR(50),                   -- Link to contract if applicable
    discount_pct            FLOAT           DEFAULT 0,
    rebate_amount           FLOAT           DEFAULT 0,
    freight_cost            FLOAT           DEFAULT 0,
    ship_from_site          VARCHAR(50),
    ship_to_location        VARCHAR(100),
    incoterms               VARCHAR(20),                   -- FOB, CIF, DDP
    load_timestamp          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (order_id, order_line_id)
);

COMMENT ON TABLE CHP_RAW.ERP_SALES_ORDERS IS 'Sales transaction history from ERP system';

-- =============================================================================
-- PLANT_COSTS: Allocated fixed/variable costs from manufacturing
-- Source: Cost accounting system
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_RAW.PLANT_COSTS (
    cost_record_id          INTEGER         NOT NULL,
    cost_date               DATE            NOT NULL,
    plant_id                VARCHAR(50)     NOT NULL,
    plant_name              VARCHAR(100),
    product_id              VARCHAR(50)     NOT NULL,
    cost_type               VARCHAR(50)     NOT NULL,      -- FEEDSTOCK, ENERGY, LABOR, OVERHEAD, DEPRECIATION
    cost_category           VARCHAR(50),                   -- VARIABLE, FIXED
    cost_amount             FLOAT           NOT NULL,
    cost_per_mt             FLOAT,                         -- Cost per metric ton produced
    production_volume_mt    FLOAT,                         -- Volume this cost applies to
    currency                VARCHAR(10)     DEFAULT 'USD',
    allocation_method       VARCHAR(50),                   -- DIRECT, ACTIVITY_BASED, VOLUME_BASED
    load_timestamp          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (cost_record_id)
);

COMMENT ON TABLE CHP_RAW.PLANT_COSTS IS 'Manufacturing cost allocations by plant and product';

-- =============================================================================
-- MARKET_REPORTS: Unstructured market intelligence documents
-- Source: Analyst reports, trade journals, earnings transcripts
-- For Cortex Search indexing
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_RAW.MARKET_REPORTS (
    report_id               INTEGER         NOT NULL,
    report_date             DATE            NOT NULL,
    report_type             VARCHAR(50),                   -- ANALYST_REPORT, EARNINGS_CALL, TRADE_JOURNAL
    report_title            VARCHAR(500),
    report_source           VARCHAR(100),                  -- publisher of the report
    chemical_name           VARCHAR(100),                  -- Primary chemical discussed
    region                  VARCHAR(50),
    report_summary          VARCHAR(2000),
    report_content          TEXT,                          -- Full text content
    file_path               VARCHAR(500),                  -- Path to PDF if applicable
    author                  VARCHAR(100),
    load_timestamp          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    
    PRIMARY KEY (report_id)
);

COMMENT ON TABLE CHP_RAW.MARKET_REPORTS IS 'Market intelligence documents for Cortex Search';

-- =============================================================================
-- Verification
-- =============================================================================
SHOW TABLES IN SCHEMA CHP_RAW;

-- =============================================================================
-- Atomic core tables
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_ATOMIC;

-- =============================================================================
-- PRODUCT: Chemical product master
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.PRODUCT (
    product_id              VARCHAR(50)     NOT NULL,
    product_name            VARCHAR(200)    NOT NULL,
    cas_number              VARCHAR(20),                   -- Chemical Abstract Service number
    product_family          VARCHAR(100),                  -- Olefins, Aromatics, Polymers, Intermediates
    product_category        VARCHAR(100),                  -- Ethylene, Propylene, Polyethylene, etc.
    product_grade           VARCHAR(50),                   -- Grade A, Grade B, Industrial, Food Grade
    molecular_weight        FLOAT,
    density_kg_m3           FLOAT,
    hazard_class            VARCHAR(50),
    un_number               VARCHAR(20),
    base_unit               VARCHAR(20)     DEFAULT 'MT',  -- Metric Ton
    standard_cost_per_mt    FLOAT,                         -- Standard cost for planning
    target_margin_pct       FLOAT           DEFAULT 15,    -- Target margin percentage
    min_order_quantity_mt   FLOAT           DEFAULT 1,
    lead_time_days          INTEGER         DEFAULT 7,
    is_active               BOOLEAN         DEFAULT TRUE,
    created_date            DATE            DEFAULT CURRENT_DATE(),
    
    PRIMARY KEY (product_id)
);

COMMENT ON TABLE CHP_ATOMIC.PRODUCT IS 'Chemical product master with CAS numbers and product families';

-- =============================================================================
-- CUSTOMER: Customer master
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.CUSTOMER (
    customer_id             VARCHAR(50)     NOT NULL,
    customer_name           VARCHAR(200)    NOT NULL,
    customer_segment        VARCHAR(50),                   -- Industrial, Consumer, Agricultural
    customer_tier           VARCHAR(20),                   -- Platinum, Gold, Silver, Standard
    credit_limit            FLOAT,
    payment_terms_days      INTEGER         DEFAULT 30,
    primary_region          VARCHAR(50),
    primary_contact         VARCHAR(100),
    annual_volume_mt        FLOAT,                         -- Historical annual volume
    customer_since          DATE,
    is_active               BOOLEAN         DEFAULT TRUE,
    
    PRIMARY KEY (customer_id)
);

COMMENT ON TABLE CHP_ATOMIC.CUSTOMER IS 'Customer master with segmentation and credit info';

-- =============================================================================
-- SITE: Manufacturing and distribution sites
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.SITE (
    site_id                 VARCHAR(50)     NOT NULL,
    site_name               VARCHAR(100)    NOT NULL,
    site_type               VARCHAR(50),                   -- MANUFACTURING, DISTRIBUTION, TERMINAL
    region                  VARCHAR(50),
    country                 VARCHAR(50),
    city                    VARCHAR(100),
    latitude                FLOAT,
    longitude               FLOAT,
    capacity_mt_year        FLOAT,                         -- Annual capacity
    utilization_target_pct  FLOAT           DEFAULT 85,
    storage_capacity_mt     FLOAT,
    is_active               BOOLEAN         DEFAULT TRUE,
    
    PRIMARY KEY (site_id)
);

COMMENT ON TABLE CHP_ATOMIC.SITE IS 'Manufacturing plants and distribution sites';

-- =============================================================================
-- PRODUCTION_RUN: Batch/production run data
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.PRODUCTION_RUN (
    run_id                  VARCHAR(50)     NOT NULL,
    site_id                 VARCHAR(50)     NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    start_time              TIMESTAMP_NTZ   NOT NULL,
    end_time                TIMESTAMP_NTZ,
    planned_quantity_mt     FLOAT,
    actual_yield_mt         FLOAT,                         -- Actual production
    yield_pct               FLOAT,                         -- Yield percentage
    feedstock_consumed_mt   FLOAT,
    feedstock_cost          FLOAT,
    energy_cost             FLOAT,
    labor_cost              FLOAT,
    overhead_cost           FLOAT,
    total_variable_cost     FLOAT,
    total_fixed_cost        FLOAT,
    cost_per_mt             FLOAT,                         -- Calculated cost per MT
    quality_grade           VARCHAR(50),
    batch_status            VARCHAR(50),                   -- PLANNED, IN_PROGRESS, COMPLETED, QC_HOLD
    carbon_footprint_kg     FLOAT,                         -- CO2 equivalent per batch
    
    PRIMARY KEY (run_id)
);

COMMENT ON TABLE CHP_ATOMIC.PRODUCTION_RUN IS 'Production batch data with yields and costs';

-- =============================================================================
-- INVENTORY_BALANCE: Inventory levels by product and site
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.INVENTORY_BALANCE (
    inventory_balance_id    INTEGER         NOT NULL,
    snapshot_date           DATE            NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    site_id                 VARCHAR(50)     NOT NULL,
    quantity_mt             FLOAT           NOT NULL,
    quantity_allocated_mt   FLOAT           DEFAULT 0,     -- Allocated to orders
    quantity_available_mt   FLOAT,                         -- Available for sale
    inventory_value         FLOAT,                         -- Value at standard cost
    days_of_supply          FLOAT,                         -- Based on avg daily demand
    reorder_point_mt        FLOAT,
    safety_stock_mt         FLOAT,
    storage_cost_daily      FLOAT,
    inventory_age_days      INTEGER,
    quality_status          VARCHAR(50)     DEFAULT 'RELEASED',
    
    PRIMARY KEY (inventory_balance_id)
);

COMMENT ON TABLE CHP_ATOMIC.INVENTORY_BALANCE IS 'Daily inventory snapshots by product and site';

-- =============================================================================
-- SALES_ORDER: Cleaned/transformed sales orders
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.SALES_ORDER (
    order_id                VARCHAR(50)     NOT NULL,
    order_line_id           INTEGER         NOT NULL,
    order_date              DATE            NOT NULL,
    ship_date               DATE,
    customer_id             VARCHAR(50)     NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    site_id                 VARCHAR(50),                   -- Ship from site
    quantity_mt             FLOAT           NOT NULL,
    unit_price              FLOAT           NOT NULL,
    total_revenue           FLOAT,
    discount_amount         FLOAT           DEFAULT 0,
    rebate_amount           FLOAT           DEFAULT 0,
    freight_cost            FLOAT           DEFAULT 0,
    net_revenue             FLOAT,                         -- Revenue after discounts
    sales_region            VARCHAR(50),
    sales_channel           VARCHAR(50),
    contract_id             VARCHAR(50),
    order_status            VARCHAR(50),
    
    PRIMARY KEY (order_id, order_line_id)
);

COMMENT ON TABLE CHP_ATOMIC.SALES_ORDER IS 'Transformed sales orders with calculated fields';

-- =============================================================================
-- Foreign Key Constraints (optional - uncomment if needed)
-- =============================================================================
-- ALTER TABLE CHP_ATOMIC.PRODUCTION_RUN ADD CONSTRAINT fk_run_site 
--     FOREIGN KEY (site_id) REFERENCES CHP_ATOMIC.SITE(site_id);
-- ALTER TABLE CHP_ATOMIC.PRODUCTION_RUN ADD CONSTRAINT fk_run_product 
--     FOREIGN KEY (product_id) REFERENCES CHP_ATOMIC.PRODUCT(product_id);
-- ALTER TABLE CHP_ATOMIC.INVENTORY_BALANCE ADD CONSTRAINT fk_inv_product 
--     FOREIGN KEY (product_id) REFERENCES CHP_ATOMIC.PRODUCT(product_id);
-- ALTER TABLE CHP_ATOMIC.INVENTORY_BALANCE ADD CONSTRAINT fk_inv_site 
--     FOREIGN KEY (site_id) REFERENCES CHP_ATOMIC.SITE(site_id);
-- ALTER TABLE CHP_ATOMIC.SALES_ORDER ADD CONSTRAINT fk_order_customer 
--     FOREIGN KEY (customer_id) REFERENCES CHP_ATOMIC.CUSTOMER(customer_id);
-- ALTER TABLE CHP_ATOMIC.SALES_ORDER ADD CONSTRAINT fk_order_product 
--     FOREIGN KEY (product_id) REFERENCES CHP_ATOMIC.PRODUCT(product_id);

-- =============================================================================
-- Verification
-- =============================================================================
SHOW TABLES IN SCHEMA CHP_ATOMIC;

-- =============================================================================
-- Atomic extension tables
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_ATOMIC;

-- =============================================================================
-- MARKET_INDEX: External market price indices (normalized)
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.MARKET_INDEX (
    index_id                INTEGER         NOT NULL,
    index_name              VARCHAR(100)    NOT NULL,      -- e.g., 'Crude Oil Brent', 'Ethylene CFR NEA'
    index_code              VARCHAR(50),                   -- Standardized code
    index_date              DATE            NOT NULL,
    price_value             FLOAT           NOT NULL,
    currency                VARCHAR(10)     DEFAULT 'USD',
    unit                    VARCHAR(20)     DEFAULT 'MT',
    price_type              VARCHAR(20),                   -- SPOT, CONTRACT, FUTURES
    region                  VARCHAR(50),
    source                  VARCHAR(50),
    
    -- Price changes for trend analysis
    price_change_1d         FLOAT,                         -- 1-day change
    price_change_7d         FLOAT,                         -- 7-day change
    price_change_30d        FLOAT,                         -- 30-day change
    price_change_pct_1d     FLOAT,
    price_change_pct_7d     FLOAT,
    price_change_pct_30d    FLOAT,
    
    -- Rolling averages
    price_avg_7d            FLOAT,
    price_avg_30d           FLOAT,
    price_volatility_30d    FLOAT,                         -- 30-day standard deviation
    
    PRIMARY KEY (index_id)
);

COMMENT ON TABLE CHP_ATOMIC.MARKET_INDEX IS 'Normalized market indices with calculated trends';

-- =============================================================================
-- CONTRACT_TERM: Customer pricing contracts and formulas
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.CONTRACT_TERM (
    term_id                 INTEGER         NOT NULL,
    contract_id             VARCHAR(50)     NOT NULL,
    customer_id             VARCHAR(50)     NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    effective_date          DATE            NOT NULL,
    expiration_date         DATE,
    
    -- Pricing formula (e.g., "Index + $50/MT")
    price_formula           VARCHAR(200),                  -- Text description
    base_index_code         VARCHAR(50),                   -- Reference index
    index_adjustment        FLOAT           DEFAULT 0,     -- +/- adjustment to index
    fixed_price             FLOAT,                         -- If fixed price contract
    floor_price             FLOAT,                         -- Minimum price
    ceiling_price           FLOAT,                         -- Maximum price
    
    -- Volume commitments
    min_volume_mt           FLOAT,                         -- Minimum annual volume
    max_volume_mt           FLOAT,                         -- Maximum annual volume
    volume_tier_1_mt        FLOAT,                         -- Volume tier breakpoints
    volume_tier_1_discount  FLOAT,
    volume_tier_2_mt        FLOAT,
    volume_tier_2_discount  FLOAT,
    
    -- Payment terms
    payment_terms_days      INTEGER         DEFAULT 30,
    early_pay_discount_pct  FLOAT           DEFAULT 0,
    
    -- Contract status
    contract_status         VARCHAR(50)     DEFAULT 'ACTIVE',
    contract_type           VARCHAR(50),                   -- SPOT, ANNUAL, MULTI_YEAR
    
    PRIMARY KEY (term_id)
);

COMMENT ON TABLE CHP_ATOMIC.CONTRACT_TERM IS 'Customer contract terms with pricing formulas';

-- =============================================================================
-- FEEDSTOCK_MAPPING: Maps products to their feedstock dependencies
-- Used for cost-to-serve calculations
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.FEEDSTOCK_MAPPING (
    mapping_id              INTEGER         NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    feedstock_index_code    VARCHAR(50)     NOT NULL,      -- Link to MARKET_INDEX
    conversion_factor       FLOAT           DEFAULT 1.0,   -- Units feedstock per unit product
    cost_weight_pct         FLOAT,                         -- Percentage of total feedstock cost
    effective_date          DATE            DEFAULT CURRENT_DATE(),
    
    PRIMARY KEY (mapping_id)
);

COMMENT ON TABLE CHP_ATOMIC.FEEDSTOCK_MAPPING IS 'Maps products to feedstock indices for cost calculations';

-- =============================================================================
-- LOGISTICS_COST: Freight and logistics costs by lane
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.LOGISTICS_COST (
    cost_id                 INTEGER         NOT NULL,
    origin_site_id          VARCHAR(50)     NOT NULL,
    destination_region      VARCHAR(50)     NOT NULL,
    transport_mode          VARCHAR(50),                   -- TRUCK, RAIL, VESSEL, PIPELINE
    cost_per_mt             FLOAT           NOT NULL,
    transit_days            INTEGER,
    effective_date          DATE,
    expiration_date         DATE,
    carrier                 VARCHAR(100),
    
    PRIMARY KEY (cost_id)
);

COMMENT ON TABLE CHP_ATOMIC.LOGISTICS_COST IS 'Freight costs by origin-destination lane';

-- =============================================================================
-- DEMAND_HISTORY: Historical demand for forecasting
-- Aggregated from sales orders for ML training
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.DEMAND_HISTORY (
    demand_id               INTEGER         NOT NULL,
    demand_date             DATE            NOT NULL,      -- Weekly or monthly bucket
    product_id              VARCHAR(50)     NOT NULL,
    region                  VARCHAR(50)     NOT NULL,
    customer_segment        VARCHAR(50),
    
    -- Volume metrics
    volume_mt               FLOAT           NOT NULL,
    order_count             INTEGER,
    customer_count          INTEGER,
    
    -- Price metrics
    avg_price_per_mt        FLOAT,
    min_price_per_mt        FLOAT,
    max_price_per_mt        FLOAT,
    
    -- External factors (for ML features)
    crude_oil_price         FLOAT,                         -- Brent crude on that date
    gdp_index               FLOAT,                         -- Regional GDP indicator
    manufacturing_pmi       FLOAT,                         -- PMI indicator
    
    PRIMARY KEY (demand_id)
);

COMMENT ON TABLE CHP_ATOMIC.DEMAND_HISTORY IS 'Aggregated demand history for ML demand forecasting';

-- =============================================================================
-- MACRO_INDICATOR: monthly macro series used as demand controls
-- Synthetic by default; marketplace/use_public_data.sql re-points the
-- CHP_OPS.MACRO_* views to Snowflake Public Data (Free) instead.
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.MACRO_INDICATOR (
    price_date              DATE            NOT NULL,      -- first day of the month
    index_code              VARCHAR(50)     NOT NULL,      -- FUEL_OIL_CPI, CORE_CPI, INDUSTRIAL_PRODUCTION
    index_name              VARCHAR(100),
    index_value             FLOAT           NOT NULL,
    unit                    VARCHAR(50),
    data_source             VARCHAR(50)     DEFAULT 'SYNTHETIC',
    PRIMARY KEY (price_date, index_code)
);

COMMENT ON TABLE CHP_ATOMIC.MACRO_INDICATOR IS 'Monthly macro indicators (synthetic fuel-oil CPI, core CPI, industrial production)';

-- =============================================================================
-- DEMO_PLANTED_ELASTICITY: the price response built into the synthetic orders
-- Ground truth for checking the elasticity models (demo data only)
-- =============================================================================
CREATE TABLE IF NOT EXISTS CHP_ATOMIC.DEMO_PLANTED_ELASTICITY (
    demand_family           VARCHAR(50)     NOT NULL,      -- family whose demand responds
    price_family            VARCHAR(50)     NOT NULL,      -- family whose price moved
    elasticity              FLOAT           NOT NULL,
    PRIMARY KEY (demand_family, price_family)
);

COMMENT ON TABLE CHP_ATOMIC.DEMO_PLANTED_ELASTICITY IS 'Planted family price elasticities used by the synthetic data generator';

-- =============================================================================
-- Enable change tracking for Cortex Search
-- =============================================================================
-- ALTER TABLE CHP_RAW.MARKET_REPORTS SET CHANGE_TRACKING = TRUE;

-- =============================================================================
-- Verification
-- =============================================================================
SHOW TABLES IN SCHEMA CHP_ATOMIC;

-- =============================================================================
-- Data generator (Python stored procedure)
-- =============================================================================

CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_RAW.SP_GENERATE_DATA(DAYS INT)
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy')
  HANDLER = 'run'
  COMMENT = 'Synthetic data generator for the Chemicals Pricing solution (seeded; dates relative to today)'
  EXECUTE AS OWNER
AS $$
"""Synthetic Data Generator for Chemicals Pricing & Supply Chain Demo.

===================================================================
Generates synthetic data for the Chemicals Integrated Pricing demo:
- Products catalog (chemicals with CAS numbers)
- Market indices (synthetic feedstock price assessments)
- Sales orders (transaction history, with a planted price response)
- Macro indicators (synthetic fuel-oil CPI, core CPI, industrial production)
- Production runs (batch data with costs)
- Inventory balances
- Contract terms
- Market reports (for Cortex Search)

Usage:
    python generate_synthetic_data.py --output-dir ../data/synthetic

The generated CSV files can be loaded into Snowflake using COPY INTO commands.
"""

import random
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

# Set random seed for reproducibility
np.random.seed(42)
random.seed(42)

# Data window end date. Dates stay relative to today, but move in whole weeks from a fixed Monday so
# every run has the same weekday layout and therefore the same random draws and model results.
ANCHOR = datetime(2026, 1, 5)


def as_of() -> datetime:
    """Most recent date that is a whole number of weeks after ANCHOR."""
    today = datetime.combine(date.today(), datetime.min.time())
    return ANCHOR + timedelta(weeks=(today - ANCHOR).days // 7)


# =============================================================================
# Configuration
# =============================================================================

# Chemical Products
PRODUCTS = [
    # Olefins
    {
        "id": "ETH-001",
        "name": "Ethylene",
        "cas": "74-85-1",
        "family": "Olefins",
        "category": "Ethylene",
        "base_cost": 950,
    },
    {
        "id": "PP-001",
        "name": "Propylene Polymer Grade",
        "cas": "115-07-1",
        "family": "Olefins",
        "category": "Propylene",
        "base_cost": 1100,
    },
    {
        "id": "PP-002",
        "name": "Propylene Chemical Grade",
        "cas": "115-07-1",
        "family": "Olefins",
        "category": "Propylene",
        "base_cost": 1050,
    },
    {
        "id": "BUT-001",
        "name": "Butadiene",
        "cas": "106-99-0",
        "family": "Olefins",
        "category": "Butadiene",
        "base_cost": 1200,
    },
    # Polymers
    {
        "id": "HDPE-001",
        "name": "HDPE Film Grade",
        "cas": "9002-88-4",
        "family": "Polymers",
        "category": "Polyethylene",
        "base_cost": 1300,
    },
    {
        "id": "LDPE-001",
        "name": "LDPE Injection Grade",
        "cas": "9002-88-4",
        "family": "Polymers",
        "category": "Polyethylene",
        "base_cost": 1350,
    },
    {
        "id": "LLDPE-001",
        "name": "LLDPE C4",
        "cas": "9002-88-4",
        "family": "Polymers",
        "category": "Polyethylene",
        "base_cost": 1280,
    },
    {
        "id": "PP-HOMO",
        "name": "Polypropylene Homopolymer",
        "cas": "9003-07-0",
        "family": "Polymers",
        "category": "Polypropylene",
        "base_cost": 1400,
    },
    {
        "id": "PP-COPOLY",
        "name": "Polypropylene Copolymer",
        "cas": "9003-07-0",
        "family": "Polymers",
        "category": "Polypropylene",
        "base_cost": 1450,
    },
    {
        "id": "PS-001",
        "name": "Polystyrene GPPS",
        "cas": "9003-53-6",
        "family": "Polymers",
        "category": "Polystyrene",
        "base_cost": 1250,
    },
    {
        "id": "PVC-001",
        "name": "PVC Suspension Grade",
        "cas": "9002-86-2",
        "family": "Polymers",
        "category": "PVC",
        "base_cost": 1100,
    },
    # Aromatics
    {
        "id": "BEN-001",
        "name": "Benzene",
        "cas": "71-43-2",
        "family": "Aromatics",
        "category": "Benzene",
        "base_cost": 900,
    },
    {
        "id": "TOL-001",
        "name": "Toluene",
        "cas": "108-88-3",
        "family": "Aromatics",
        "category": "Toluene",
        "base_cost": 850,
    },
    {
        "id": "XYL-001",
        "name": "Mixed Xylenes",
        "cas": "1330-20-7",
        "family": "Aromatics",
        "category": "Xylenes",
        "base_cost": 880,
    },
    {
        "id": "STY-001",
        "name": "Styrene Monomer",
        "cas": "100-42-5",
        "family": "Aromatics",
        "category": "Styrene",
        "base_cost": 1150,
    },
    # Intermediates
    {
        "id": "MEG-001",
        "name": "Monoethylene Glycol",
        "cas": "107-21-1",
        "family": "Intermediates",
        "category": "Glycols",
        "base_cost": 750,
    },
    {
        "id": "DEG-001",
        "name": "Diethylene Glycol",
        "cas": "111-46-6",
        "family": "Intermediates",
        "category": "Glycols",
        "base_cost": 800,
    },
    {
        "id": "ACN-001",
        "name": "Acrylonitrile",
        "cas": "107-13-1",
        "family": "Intermediates",
        "category": "Acrylonitrile",
        "base_cost": 1400,
    },
    {
        "id": "MMA-001",
        "name": "Methyl Methacrylate",
        "cas": "80-62-6",
        "family": "Intermediates",
        "category": "MMA",
        "base_cost": 1600,
    },
]

# Market Indices
MARKET_INDICES = [
    {"code": "CRUDE-BRENT", "name": "Crude Oil Brent", "base_price": 75, "unit": "BBL", "region": "Global"},
    {"code": "CRUDE-WTI", "name": "Crude Oil WTI", "base_price": 72, "unit": "BBL", "region": "North America"},
    {
        "code": "NAPHTHA-CFR-NEA",
        "name": "Naphtha CFR NE Asia",
        "base_price": 650,
        "unit": "MT",
        "region": "Asia Pacific",
    },
    {"code": "NAPHTHA-CIF-NWE", "name": "Naphtha CIF NW Europe", "base_price": 620, "unit": "MT", "region": "Europe"},
    {"code": "ETH-CFR-NEA", "name": "Ethylene CFR NE Asia", "base_price": 1050, "unit": "MT", "region": "Asia Pacific"},
    {"code": "ETH-FD-NWE", "name": "Ethylene FD NW Europe", "base_price": 1000, "unit": "MT", "region": "Europe"},
    {"code": "ETH-DEL-USG", "name": "Ethylene DEL US Gulf", "base_price": 950, "unit": "MT", "region": "North America"},
    {"code": "PP-CFR-NEA", "name": "Propylene CFR NE Asia", "base_price": 1150, "unit": "MT", "region": "Asia Pacific"},
    {"code": "PP-FD-NWE", "name": "Propylene FD NW Europe", "base_price": 1100, "unit": "MT", "region": "Europe"},
    {
        "code": "PP-DEL-USG",
        "name": "Propylene DEL US Gulf",
        "base_price": 1080,
        "unit": "MT",
        "region": "North America",
    },
    {"code": "BEN-FOB-USG", "name": "Benzene FOB US Gulf", "base_price": 950, "unit": "MT", "region": "North America"},
    {"code": "BEN-CFR-NEA", "name": "Benzene CFR NE Asia", "base_price": 980, "unit": "MT", "region": "Asia Pacific"},
    {"code": "STY-CFR-NEA", "name": "Styrene CFR NE Asia", "base_price": 1200, "unit": "MT", "region": "Asia Pacific"},
    {"code": "MEG-CFR-NEA", "name": "MEG CFR NE Asia", "base_price": 800, "unit": "MT", "region": "Asia Pacific"},
]

# Regions and their characteristics
REGIONS = {
    "North America": {"demand_multiplier": 1.0, "freight_base": 50, "currency": "USD"},
    "Europe": {"demand_multiplier": 0.9, "freight_base": 80, "currency": "USD"},
    "Asia Pacific": {"demand_multiplier": 1.3, "freight_base": 100, "currency": "USD"},
    "Latin America": {"demand_multiplier": 0.5, "freight_base": 120, "currency": "USD"},
    "Middle East": {"demand_multiplier": 0.4, "freight_base": 90, "currency": "USD"},
}

# Customer Segments
CUSTOMER_SEGMENTS = ["Industrial", "Consumer", "Agricultural", "Automotive", "Construction"]
CUSTOMER_TIERS = ["Platinum", "Gold", "Silver", "Standard"]
SALES_CHANNELS = ["Direct", "Distributor", "Spot", "Contract"]

# Manufacturing Sites
SITES = [
    {
        "id": "SITE-USG-01",
        "name": "Houston Complex",
        "region": "North America",
        "type": "MANUFACTURING",
        "capacity": 500000,
    },
    {
        "id": "SITE-USG-02",
        "name": "Texas City Plant",
        "region": "North America",
        "type": "MANUFACTURING",
        "capacity": 350000,
    },
    {
        "id": "SITE-NWE-01",
        "name": "Rotterdam Terminal",
        "region": "Europe",
        "type": "MANUFACTURING",
        "capacity": 400000,
    },
    {"id": "SITE-NWE-02", "name": "Antwerp Complex", "region": "Europe", "type": "MANUFACTURING", "capacity": 450000},
    {
        "id": "SITE-NEA-01",
        "name": "Singapore Hub",
        "region": "Asia Pacific",
        "type": "MANUFACTURING",
        "capacity": 600000,
    },
    {
        "id": "SITE-NEA-02",
        "name": "Shanghai Plant",
        "region": "Asia Pacific",
        "type": "MANUFACTURING",
        "capacity": 500000,
    },
]

# Report sources and types for Cortex Search (fictional publishers)
REPORT_SOURCES = [
    "Meridian Market Analytics",
    "Harborview Commodity Research",
    "Northgate Petrochemical Review",
    "Internal Market Intelligence",
    "Crestline Trade Journal",
]
# Price assessment sources for the synthetic market indices (fictional)
INDEX_SOURCES = ["MERIDIAN", "HARBORVIEW", "EXCHANGE"]

# Planted demand response (the ground truth the elasticity models should recover).
# Rows = family whose demand responds, columns = family whose price moved:
# ln(volume) moves by ELASTICITY[demand][price] x ln(price level of the price family).
FAMILIES = ["Olefins", "Polymers", "Aromatics", "Intermediates"]
FAMILY_ELASTICITY = {
    "Olefins": {"Olefins": -1.8, "Polymers": 0.25, "Aromatics": 0.10, "Intermediates": 0.05},
    "Polymers": {"Olefins": 0.30, "Polymers": -2.5, "Aromatics": 0.05, "Intermediates": 0.10},
    "Aromatics": {"Olefins": 0.10, "Polymers": 0.05, "Aromatics": -1.6, "Intermediates": 0.20},
    "Intermediates": {"Olefins": 0.05, "Polymers": 0.10, "Aromatics": 0.25, "Intermediates": -2.2},
}
REPORT_TYPES = ["ANALYST_REPORT", "EARNINGS_CALL", "TRADE_JOURNAL", "MARKET_OUTLOOK", "SUPPLY_ANALYSIS"]


def generate_products() -> pd.DataFrame:
    """Generate product catalog."""
    print("Generating product catalog...")

    products = []
    for p in PRODUCTS:
        products.append(
            {
                "product_id": p["id"],
                "product_name": p["name"],
                "cas_number": p["cas"],
                "product_family": p["family"],
                "product_category": p["category"],
                "product_grade": random.choice(["Grade A", "Grade B", "Industrial", "Food Grade"]),
                "molecular_weight": round(random.uniform(28, 200), 2),
                "density_kg_m3": round(random.uniform(800, 1200), 1),
                "hazard_class": random.choice(["3", "4.1", "6.1", "8", "9"]),
                "un_number": f"UN{random.randint(1000, 3500)}",
                "base_unit": "MT",
                "standard_cost_per_mt": p["base_cost"],
                "target_margin_pct": random.choice([12, 15, 18, 20]),
                "min_order_quantity_mt": random.choice([1, 5, 10, 20]),
                "lead_time_days": random.randint(3, 14),
                "is_active": True,
            }
        )

    df = pd.DataFrame(products)
    print(f"Generated {len(df)} products")
    return df


def generate_customers(n_customers: int = 200) -> pd.DataFrame:
    """Generate customer master data."""
    print("Generating customer data...")

    company_prefixes = ["Global", "Pacific", "Atlantic", "United", "National", "Premier", "Advanced", "Industrial"]
    company_suffixes = ["Industries", "Manufacturing", "Chemicals", "Corp", "LLC", "Holdings", "Group", "Partners"]

    customers = []
    for i in range(n_customers):
        region = random.choice(list(REGIONS.keys()))
        segment = random.choice(CUSTOMER_SEGMENTS)
        tier = random.choices(CUSTOMER_TIERS, weights=[0.1, 0.2, 0.3, 0.4])[0]

        customers.append(
            {
                "customer_id": f"CUST-{i + 1:05d}",
                "customer_name": f"{random.choice(company_prefixes)} {random.choice(company_suffixes)}",
                "customer_segment": segment,
                "customer_tier": tier,
                "credit_limit": {"Platinum": 5000000, "Gold": 2000000, "Silver": 500000, "Standard": 100000}[tier],
                "payment_terms_days": {"Platinum": 45, "Gold": 30, "Silver": 30, "Standard": 15}[tier],
                "primary_region": region,
                "primary_contact": f"contact{i}@example.com",
                "annual_volume_mt": round(
                    np.random.exponential(500) * {"Platinum": 10, "Gold": 5, "Silver": 2, "Standard": 1}[tier], 1
                ),
                "customer_since": (as_of() - timedelta(days=random.randint(365, 3650))).strftime("%Y-%m-%d"),
                "is_active": random.random() > 0.05,
            }
        )

    df = pd.DataFrame(customers)
    print(f"Generated {len(df)} customers")
    return df


def generate_sites() -> pd.DataFrame:
    """Generate manufacturing sites."""
    print("Generating site data...")

    sites = []
    for s in SITES:
        sites.append(
            {
                "site_id": s["id"],
                "site_name": s["name"],
                "site_type": s["type"],
                "region": s["region"],
                "country": {"North America": "USA", "Europe": "Netherlands", "Asia Pacific": "Singapore"}[s["region"]],
                "city": s["name"].split()[0],
                "latitude": round(random.uniform(25, 55), 4),
                "longitude": round(random.uniform(-100, 120), 4),
                "capacity_mt_year": s["capacity"],
                "utilization_target_pct": 85,
                "storage_capacity_mt": int(s["capacity"] * 0.1),
                "is_active": True,
            }
        )

    df = pd.DataFrame(sites)
    print(f"Generated {len(df)} sites")
    return df


def generate_market_indices(days: int = 730) -> pd.DataFrame:
    """Generate historical market index data with realistic price movements.

    Includes correlations between related indices.
    """
    print("Generating market index data...")

    records = []
    record_id = 1
    end_date = as_of()
    start_date = end_date - timedelta(days=days)

    # Generate base crude oil prices first (driver for others)
    crude_prices = {}
    current_price = 75

    for day_offset in range(days):
        current_date = start_date + timedelta(days=day_offset)
        # Skip weekends
        if current_date.weekday() >= 5:
            continue

        # Random walk with mean reversion
        daily_return = np.random.normal(0, 0.02) + 0.001 * (75 - current_price)
        current_price = max(50, min(120, current_price * (1 + daily_return)))
        crude_prices[current_date.strftime("%Y-%m-%d")] = current_price

    # Generate all indices
    for idx in MARKET_INDICES:
        current_price = idx["base_price"]
        price_history = []

        for day_offset in range(days):
            current_date = start_date + timedelta(days=day_offset)
            if current_date.weekday() >= 5:
                continue

            date_str = current_date.strftime("%Y-%m-%d")

            # Price movement correlated with crude
            crude_change = 0
            if date_str in crude_prices and len(price_history) > 0:
                crude_prev = crude_prices.get(
                    (current_date - timedelta(days=1)).strftime("%Y-%m-%d"), crude_prices[date_str]
                )
                crude_change = (crude_prices[date_str] - crude_prev) / crude_prev if crude_prev else 0

            # Different correlation strengths
            correlation = 0.6 if "CRUDE" not in idx["code"] else 1.0
            daily_return = correlation * crude_change + np.random.normal(0, 0.015)

            # Mean reversion
            daily_return += 0.001 * (idx["base_price"] - current_price) / idx["base_price"]

            current_price = max(idx["base_price"] * 0.5, min(idx["base_price"] * 2, current_price * (1 + daily_return)))
            price_history.append({"date": date_str, "price": current_price})

            # Calculate moving averages and changes
            price_1d_ago = price_history[-2]["price"] if len(price_history) >= 2 else current_price
            price_7d_ago = price_history[-8]["price"] if len(price_history) >= 8 else current_price
            price_30d_ago = price_history[-31]["price"] if len(price_history) >= 31 else current_price

            prices_7d = [p["price"] for p in price_history[-7:]]
            prices_30d = [p["price"] for p in price_history[-30:]]

            records.append(
                {
                    "record_id": record_id,
                    "index_name": idx["name"],
                    "index_code": idx["code"],
                    "price_date": date_str,
                    "price_value": round(current_price, 2),
                    "price_currency": "USD",
                    "price_unit": idx["unit"],
                    "price_type": "SPOT",
                    "region": idx["region"],
                    "source": random.choice(INDEX_SOURCES),
                    "price_change_1d": round(current_price - price_1d_ago, 2),
                    "price_change_7d": round(current_price - price_7d_ago, 2),
                    "price_change_30d": round(current_price - price_30d_ago, 2),
                    "price_change_pct_1d": round((current_price - price_1d_ago) / price_1d_ago * 100, 2)
                    if price_1d_ago
                    else 0,
                    "price_change_pct_7d": round((current_price - price_7d_ago) / price_7d_ago * 100, 2)
                    if price_7d_ago
                    else 0,
                    "price_change_pct_30d": round((current_price - price_30d_ago) / price_30d_ago * 100, 2)
                    if price_30d_ago
                    else 0,
                    "price_avg_7d": round(np.mean(prices_7d), 2),
                    "price_avg_30d": round(np.mean(prices_30d), 2),
                    "price_volatility_30d": round(np.std(prices_30d), 2) if len(prices_30d) > 1 else 0,
                }
            )
            record_id += 1

    df = pd.DataFrame(records)
    print(f"Generated {len(df)} market index records")
    return df


def generate_family_price_levels(market_indices_df: pd.DataFrame, days: int = 365) -> dict:
    """Daily log price level per product family: a mean-reverting AR(1) (sd ~15%) plus a.

    small Brent component. Independent movement across families is what lets the
    elasticity models separate own-price from cross-price effects.
    """
    brent = market_indices_df[market_indices_df["index_code"] == "CRUDE-BRENT"]
    brent = dict(zip(brent["price_date"], np.log(brent["price_value"] / 75.0)))
    levels = {}
    x = {f: 0.0 for f in FAMILIES}
    end_date = as_of()
    start_date = end_date - timedelta(days=days)
    for day_offset in range(days):
        date_str = (start_date + timedelta(days=day_offset)).strftime("%Y-%m-%d")
        for f in FAMILIES:
            x[f] = 0.95 * x[f] + np.random.normal(0, 0.045)
        levels[date_str] = {f: x[f] + 0.3 * brent.get(date_str, 0.0) for f in FAMILIES}
    return levels


def generate_sales_orders(
    products_df: pd.DataFrame, customers_df: pd.DataFrame, sites_df: pd.DataFrame, family_levels: dict, days: int = 365
) -> pd.DataFrame:
    """Generate sales order history; prices follow the family price levels and volumes.

    respond to them through FAMILY_ELASTICITY.
    """
    print("Generating sales order data...")

    end_date = as_of()
    start_date = end_date - timedelta(days=days)
    dates = [start_date + timedelta(days=d) for d in range(days)]
    dates = [d for d in dates if d.weekday() < 5]
    # ~150 orders per weekday
    counts = np.random.poisson(150, len(dates))
    order_dates = np.repeat([d.strftime("%Y-%m-%d") for d in dates], counts).tolist()
    n = len(order_dates)

    prod = products_df.iloc[np.random.randint(0, len(products_df), n)].reset_index(drop=True)
    cust = customers_df.iloc[np.random.randint(0, len(customers_df), n)].reset_index(drop=True)
    sites_by_region = {r: g["site_id"].tolist() for r, g in sites_df.groupby("region")}
    all_sites = sites_df["site_id"].tolist()
    ship_from = [random.choice(sites_by_region.get(r, all_sites)) for r in cust["primary_region"]]

    # Planted price response: ln(volume) = sum_g elast[family, g] * level_g(date)
    zero = {f: 0.0 for f in FAMILIES}
    lvl = pd.DataFrame([family_levels.get(d, zero) for d in order_dates])
    elast = np.array([[FAMILY_ELASTICITY[f][g] for g in FAMILIES] for f in prod["product_family"]])
    response = np.exp((elast * lvl[FAMILIES].to_numpy()).sum(axis=1))
    own_level = lvl.to_numpy()[np.arange(n), [FAMILIES.index(f) for f in prod["product_family"]]]

    tier = cust["customer_tier"]
    base_volume = tier.map({"Platinum": 120, "Gold": 80, "Silver": 50, "Standard": 30}).to_numpy()
    quantity = np.round(base_volume * np.random.lognormal(-0.11, 0.47, n) * response, 1)

    # Price: product cost + margin, moved by the family price level, plus deal noise
    base_price = prod["standard_cost_per_mt"] * (1 + prod["target_margin_pct"] / 100)
    unit_price = np.round(base_price * np.exp(own_level) * (1 + np.random.normal(0, 0.03, n)), 2)

    discount_pct = tier.map({"Platinum": 5, "Gold": 3, "Silver": 1, "Standard": 0}).to_numpy()
    freight_base = cust["primary_region"].map({r: v["freight_base"] for r, v in REGIONS.items()}).to_numpy()
    total_amount = np.round(unit_price * quantity, 2)
    discount_amount = np.round(unit_price * quantity * discount_pct / 100, 2)
    freight_cost = np.round(freight_base * quantity / 20, 2)

    df = pd.DataFrame(
        {
            "order_id": [f"ORD-{i + 1:08d}" for i in range(n)],
            "order_line_id": 1,
            "order_date": order_dates,
            "ship_date": [
                (pd.Timestamp(d) + timedelta(days=random.randint(3, 14))).strftime("%Y-%m-%d") for d in order_dates
            ],
            "customer_id": cust["customer_id"],
            "customer_name": cust["customer_name"],
            "product_id": prod["product_id"],
            "product_name": prod["product_name"],
            "quantity_mt": quantity,
            "unit_price": unit_price,
            "total_amount": total_amount,
            "currency": "USD",
            "sales_region": cust["primary_region"],
            "sales_channel": [random.choice(SALES_CHANNELS) for _ in range(n)],
            "customer_segment": cust["customer_segment"],
            "contract_id": [f"CTR-{c[-5:]}" if random.random() > 0.3 else None for c in cust["customer_id"]],
            "discount_pct": discount_pct,
            "rebate_amount": np.round(total_amount * np.random.uniform(0, 0.02, n), 2),
            "freight_cost": freight_cost,
            "ship_from_site": ship_from,
            "ship_to_location": [f"{r} Distribution" for r in cust["primary_region"]],
            "incoterms": [random.choice(["FOB", "CIF", "DDP", "DAP"]) for _ in range(n)],
            "net_revenue": np.round(total_amount - discount_amount - freight_cost, 2),
        }
    )
    print(f"Generated {len(df)} sales orders")
    return df


def generate_production_runs(products_df: pd.DataFrame, sites_df: pd.DataFrame, days: int = 365) -> pd.DataFrame:
    """Generate production run/batch data."""
    print("Generating production run data...")

    runs = []
    run_id = 1
    end_date = as_of()
    start_date = end_date - timedelta(days=days)

    for day_offset in range(days):
        current_date = start_date + timedelta(days=day_offset)

        # Each site produces 2-4 batches per day
        for _, site in sites_df.iterrows():
            num_runs = random.randint(2, 4)

            for _ in range(num_runs):
                product = products_df.sample(1).iloc[0]

                planned_qty = random.randint(100, 500)
                yield_pct = random.uniform(0.92, 0.99)
                actual_yield = round(planned_qty * yield_pct, 1)

                feedstock_consumed = round(actual_yield * random.uniform(1.05, 1.15), 1)
                feedstock_cost = round(feedstock_consumed * product["standard_cost_per_mt"] * 0.6, 2)
                energy_cost = round(actual_yield * random.uniform(30, 60), 2)
                labor_cost = round(actual_yield * random.uniform(20, 40), 2)
                overhead_cost = round(actual_yield * random.uniform(40, 80), 2)

                total_variable = feedstock_cost + energy_cost
                total_fixed = labor_cost + overhead_cost
                cost_per_mt = round((total_variable + total_fixed) / actual_yield, 2)

                start_time = datetime.combine(current_date, datetime.min.time()) + timedelta(
                    hours=random.randint(0, 20)
                )
                end_time = start_time + timedelta(hours=random.randint(4, 12))

                runs.append(
                    {
                        "run_id": f"RUN-{run_id:08d}",
                        "site_id": site["site_id"],
                        "product_id": product["product_id"],
                        "start_time": start_time.strftime("%Y-%m-%d %H:%M:%S"),
                        "end_time": end_time.strftime("%Y-%m-%d %H:%M:%S"),
                        "planned_quantity_mt": planned_qty,
                        "actual_yield_mt": actual_yield,
                        "yield_pct": round(yield_pct * 100, 2),
                        "feedstock_consumed_mt": feedstock_consumed,
                        "feedstock_cost": feedstock_cost,
                        "energy_cost": energy_cost,
                        "labor_cost": labor_cost,
                        "overhead_cost": overhead_cost,
                        "total_variable_cost": total_variable,
                        "total_fixed_cost": total_fixed,
                        "cost_per_mt": cost_per_mt,
                        "quality_grade": random.choice(["A", "A", "A", "B"]),
                        "batch_status": "COMPLETED",
                        "carbon_footprint_kg": round(actual_yield * random.uniform(500, 1500), 0),
                    }
                )
                run_id += 1

    df = pd.DataFrame(runs)
    print(f"Generated {len(df)} production runs")
    return df


def generate_inventory_balances(products_df: pd.DataFrame, sites_df: pd.DataFrame) -> pd.DataFrame:
    """Generate current inventory balances."""
    print("Generating inventory balance data...")

    balances = []
    balance_id = 1
    snapshot_date = as_of().strftime("%Y-%m-%d")

    for _, product in products_df.iterrows():
        for _, site in sites_df.iterrows():
            quantity = round(random.uniform(100, 2000), 1)
            allocated = round(quantity * random.uniform(0.1, 0.4), 1)
            available = round(quantity - allocated, 1)

            avg_daily_demand = random.uniform(10, 50)
            days_of_supply = round(available / avg_daily_demand, 1)

            balances.append(
                {
                    "inventory_balance_id": balance_id,
                    "snapshot_date": snapshot_date,
                    "product_id": product["product_id"],
                    "site_id": site["site_id"],
                    "quantity_mt": quantity,
                    "quantity_allocated_mt": allocated,
                    "quantity_available_mt": available,
                    "inventory_value": round(quantity * product["standard_cost_per_mt"], 2),
                    "days_of_supply": days_of_supply,
                    "reorder_point_mt": round(avg_daily_demand * 14, 1),
                    "safety_stock_mt": round(avg_daily_demand * 7, 1),
                    "storage_cost_daily": round(quantity * 0.5, 2),
                    "inventory_age_days": random.randint(5, 90),
                    "quality_status": random.choice(["RELEASED", "RELEASED", "RELEASED", "QC_HOLD"]),
                }
            )
            balance_id += 1

    df = pd.DataFrame(balances)
    print(f"Generated {len(df)} inventory balances")
    return df


def generate_contract_terms(products_df: pd.DataFrame, customers_df: pd.DataFrame) -> pd.DataFrame:
    """Generate customer contract terms."""
    print("Generating contract terms...")

    terms = []
    term_id = 1

    # Generate contracts for top-tier customers
    top_customers = customers_df[customers_df["customer_tier"].isin(["Platinum", "Gold"])]

    for _, customer in top_customers.iterrows():
        # Each customer has contracts for 2-5 products
        num_products = random.randint(2, 5)
        contracted_products = products_df.sample(num_products)

        for _, product in contracted_products.iterrows():
            effective_date = as_of() - timedelta(days=random.randint(30, 365))
            expiration_date = effective_date + timedelta(days=365)

            # Pricing formula
            index_code = random.choice(["ETH-DEL-USG", "PP-DEL-USG", "BEN-FOB-USG"])
            adjustment = random.choice([30, 50, 75, 100, -25])

            min_volume = round(customer["annual_volume_mt"] * 0.1, 0)

            terms.append(
                {
                    "term_id": term_id,
                    "contract_id": f"CTR-{customer['customer_id'][-5:]}",
                    "customer_id": customer["customer_id"],
                    "product_id": product["product_id"],
                    "effective_date": effective_date.strftime("%Y-%m-%d"),
                    "expiration_date": expiration_date.strftime("%Y-%m-%d"),
                    "price_formula": f"{index_code} + ${adjustment}/MT",
                    "base_index_code": index_code,
                    "index_adjustment": adjustment,
                    "fixed_price": None,
                    "floor_price": round(product["standard_cost_per_mt"] * 1.05, 2),
                    "ceiling_price": round(product["standard_cost_per_mt"] * 1.50, 2),
                    "min_volume_mt": min_volume,
                    "max_volume_mt": min_volume * 3,
                    "volume_tier_1_mt": min_volume * 1.5,
                    "volume_tier_1_discount": 2,
                    "volume_tier_2_mt": min_volume * 2.5,
                    "volume_tier_2_discount": 4,
                    "payment_terms_days": customer["payment_terms_days"],
                    "early_pay_discount_pct": 1 if customer["customer_tier"] == "Platinum" else 0,
                    "contract_status": "ACTIVE",
                    "contract_type": random.choice(["ANNUAL", "MULTI_YEAR"]),
                }
            )
            term_id += 1

    df = pd.DataFrame(terms)
    print(f"Generated {len(df)} contract terms")
    return df


def generate_market_reports(products_df: pd.DataFrame, days: int = 180) -> pd.DataFrame:
    """Generate market intelligence reports for Cortex Search.

    Searchable by chemical name and region.
    """
    print("Generating market reports for Cortex Search...")

    reports = []
    report_id = 1
    end_date = as_of()
    start_date = end_date - timedelta(days=days)

    # Templates for report content
    supply_templates = [
        "Supply constraints for {chemical} in {region} are expected to persist through Q{quarter}. "
        "Key factors include planned maintenance at {n} major facilities and unexpected outages in "
        "the upstream naphtha supply chain. Prices have risen {pct}% week-over-week.",
        "The {region} {chemical} market is experiencing tightness due to reduced imports from Asia. "
        "Local producers are operating at {util}% capacity utilization. Spot availability is limited "
        "with premiums of ${premium}/MT over contract prices.",
        "Force majeure declared at {producer} {chemical} unit in {region} has removed approximately "
        "{capacity}kt/year of capacity from the market. Recovery is expected in {weeks} weeks. Buyers "
        "are seeking alternative sources.",
    ]

    demand_templates = [
        "Demand for {chemical} in {region} has {direction} by {pct}% compared to the same period last "
        "year. Key end-use sectors driving this trend include {sector1} and {sector2}. Inventory "
        "levels at converters remain {inv_level}.",
        "The {region} {chemical} market outlook remains {outlook} for the next quarter. Automotive "
        "and construction sectors are showing {auto_trend} demand signals. Export opportunities to "
        "{export_region} are {export_trend}.",
        "Consumer demand in {region} for {chemical}-based products has {direction} following seasonal "
        "patterns. Packaging demand is {pkg_trend} while industrial applications show {ind_trend} "
        "growth.",
    ]

    price_templates = [
        "Price assessment: {chemical} CFR {region} is trading at ${price}/MT, {direction} "
        "${change}/MT from last week. Market participants expect prices to {forecast} in the coming "
        "weeks based on feedstock movements.",
        "The spread between {chemical} and feedstock naphtha has {spread_direction} to ${spread}/MT. "
        "Producers report margins are {margin_status}. Contract negotiations for next quarter are "
        "{nego_status}.",
    ]

    for day_offset in range(0, days, random.randint(3, 7)):
        current_date = start_date + timedelta(days=day_offset)

        # Generate 2-5 reports per period
        for _ in range(random.randint(2, 5)):
            product = products_df.sample(1).iloc[0]
            region = random.choice(list(REGIONS.keys()))
            report_type = random.choice(REPORT_TYPES)
            source = random.choice(REPORT_SOURCES)

            # Generate content based on type
            if "SUPPLY" in report_type:
                template = random.choice(supply_templates)
            elif "OUTLOOK" in report_type or "ANALYSIS" in report_type:
                template = random.choice(demand_templates)
            else:
                template = random.choice(price_templates)

            content = template.format(
                chemical=product["product_name"],
                region=region,
                quarter=((current_date.month - 1) // 3) + 1,
                n=random.randint(2, 5),
                pct=round(random.uniform(-10, 15), 1),
                util=random.randint(75, 95),
                premium=random.randint(20, 100),
                producer=random.choice(["Major Producer", "Regional Supplier", "Global Chemical Co"]),
                capacity=random.randint(100, 500),
                weeks=random.randint(2, 8),
                direction=random.choice(["increased", "decreased", "remained stable"]),
                sector1=random.choice(["packaging", "automotive", "construction", "electronics"]),
                sector2=random.choice(["agriculture", "consumer goods", "textiles", "medical"]),
                inv_level=random.choice(["high", "moderate", "low"]),
                outlook=random.choice(["positive", "cautious", "challenging", "stable"]),
                auto_trend=random.choice(["strong", "weak", "mixed"]),
                export_region=random.choice(["Europe", "Asia", "Latin America"]),
                export_trend=random.choice(["expanding", "limited", "competitive"]),
                pkg_trend=random.choice(["strong", "moderate", "subdued"]),
                ind_trend=random.choice(["steady", "improving", "declining"]),
                price=random.randint(800, 2000),
                change=random.randint(-50, 80),
                forecast=random.choice(["strengthen", "soften", "remain stable"]),
                spread_direction=random.choice(["widened", "narrowed", "stabilized"]),
                spread=random.randint(150, 400),
                margin_status=random.choice(["healthy", "under pressure", "improving"]),
                nego_status=random.choice(["ongoing", "concluded", "contentious"]),
            )

            title = f"{product['product_family']} Market Update: {region} - {current_date.strftime('%B %Y')}"

            reports.append(
                {
                    "report_id": report_id,
                    "report_date": current_date.strftime("%Y-%m-%d"),
                    "report_type": report_type,
                    "report_title": title,
                    "report_source": source,
                    "chemical_name": product["product_name"],
                    "region": region,
                    "report_summary": content[:200] + "...",
                    "report_content": content,
                    "file_path": f"@MARKET_DOCUMENTS/{product['product_family']}/{current_date.strftime('%Y-%m')}.pdf",
                    "author": (
                        f"{random.choice(['John', 'Sarah', 'Michael', 'Emily'])} "
                        f"{random.choice(['Smith', 'Johnson', 'Williams', 'Chen'])}"
                    ),
                }
            )
            report_id += 1

    df = pd.DataFrame(reports)
    print(f"Generated {len(df)} market reports")
    return df


def generate_feedstock_mapping(products_df: pd.DataFrame) -> pd.DataFrame:
    """Generate feedstock to product mappings."""
    print("Generating feedstock mappings...")

    mappings = []
    mapping_id = 1

    # Mapping rules
    feedstock_rules = {
        "Olefins": [("ETH-DEL-USG", 1.1), ("NAPHTHA-CIF-NWE", 1.3)],
        "Polymers": [("ETH-DEL-USG", 1.05), ("PP-DEL-USG", 1.08)],
        "Aromatics": [("BEN-FOB-USG", 1.0), ("CRUDE-BRENT", 0.1)],
        "Intermediates": [("ETH-DEL-USG", 0.8), ("NAPHTHA-CIF-NWE", 0.5)],
    }

    for _, product in products_df.iterrows():
        rules = feedstock_rules.get(product["product_family"], [("CRUDE-BRENT", 0.05)])

        for feedstock_code, factor in rules:
            mappings.append(
                {
                    "mapping_id": mapping_id,
                    "product_id": product["product_id"],
                    "feedstock_index_code": feedstock_code,
                    "conversion_factor": factor,
                    "cost_weight_pct": round(100 / len(rules), 1),
                    "effective_date": "2024-01-01",
                }
            )
            mapping_id += 1

    df = pd.DataFrame(mappings)
    print(f"Generated {len(df)} feedstock mappings")
    return df


def generate_logistics_costs(sites_df: pd.DataFrame) -> pd.DataFrame:
    """Generate logistics cost matrix."""
    print("Generating logistics costs...")

    costs = []
    cost_id = 1

    for _, site in sites_df.iterrows():
        for region in REGIONS.keys():
            # Different transport modes
            modes = [("TRUCK", 1.0, 3), ("RAIL", 0.7, 7), ("VESSEL", 0.5, 21)]

            for mode, cost_mult, transit in modes:
                base_cost = REGIONS[region]["freight_base"] * cost_mult
                # Distance adjustment
                if site["region"] == region:
                    base_cost *= 0.5
                    transit = int(transit * 0.5)

                costs.append(
                    {
                        "cost_id": cost_id,
                        "origin_site_id": site["site_id"],
                        "destination_region": region,
                        "transport_mode": mode,
                        "cost_per_mt": round(base_cost, 2),
                        "transit_days": transit,
                        "effective_date": "2024-01-01",
                        "expiration_date": "2025-12-31",
                        "carrier": f"{mode} Carrier {random.randint(1, 5)}",
                    }
                )
                cost_id += 1

    df = pd.DataFrame(costs)
    print(f"Generated {len(df)} logistics cost records")
    return df


def generate_demand_history(sales_df: pd.DataFrame, market_indices_df: pd.DataFrame) -> pd.DataFrame:
    """Generate aggregated demand history for ML training."""
    print("Generating demand history...")

    # Aggregate sales by week/product/region (on a copy: sales_df is saved as-is)
    sales_df = sales_df.copy()
    sales_df["order_date"] = pd.to_datetime(sales_df["order_date"])
    sales_df["week_start"] = sales_df["order_date"].dt.to_period("W").dt.start_time

    agg = (
        sales_df.groupby(["week_start", "product_id", "sales_region", "customer_segment"])
        .agg(
            {"quantity_mt": "sum", "order_id": "count", "customer_id": "nunique", "unit_price": ["mean", "min", "max"]}
        )
        .reset_index()
    )

    agg.columns = [
        "demand_date",
        "product_id",
        "region",
        "customer_segment",
        "volume_mt",
        "order_count",
        "customer_count",
        "avg_price_per_mt",
        "min_price_per_mt",
        "max_price_per_mt",
    ]

    agg["demand_id"] = range(1, len(agg) + 1)
    agg["demand_date"] = agg["demand_date"].dt.strftime("%Y-%m-%d")

    # Crude price: the weekly average of the generated Brent series
    brent = market_indices_df[market_indices_df["index_code"] == "CRUDE-BRENT"].copy()
    brent["week_start"] = pd.to_datetime(brent["price_date"]).dt.to_period("W").dt.start_time
    weekly_brent = brent.groupby("week_start")["price_value"].mean().round(2)
    agg["crude_oil_price"] = pd.to_datetime(agg["demand_date"]).map(weekly_brent)
    # Other external factors (simulated noise)
    agg["gdp_index"] = agg.apply(lambda x: round(100 + random.uniform(-5, 5), 1), axis=1)
    agg["manufacturing_pmi"] = agg.apply(lambda x: round(50 + random.uniform(-5, 10), 1), axis=1)
    # Column order must match ATOMIC.DEMAND_HISTORY: the COPY in load_all_data.sql is positional
    agg = agg[
        [
            "demand_id",
            "demand_date",
            "product_id",
            "region",
            "customer_segment",
            "volume_mt",
            "order_count",
            "customer_count",
            "avg_price_per_mt",
            "min_price_per_mt",
            "max_price_per_mt",
            "crude_oil_price",
            "gdp_index",
            "manufacturing_pmi",
        ]
    ]

    print(f"Generated {len(agg)} demand history records")
    return agg


def generate_macro_indicators(market_indices_df: pd.DataFrame, months: int = 36) -> pd.DataFrame:
    """Monthly synthetic macro indicators, standing in for public CPI and industrial-production.

    series (see marketplace/use_public_data.sql to use the real ones instead).
    """
    print("Generating macro indicators...")
    brent = market_indices_df[market_indices_df["index_code"] == "CRUDE-BRENT"].copy()
    brent["month"] = pd.to_datetime(brent["price_date"]).dt.to_period("M").dt.start_time
    monthly_brent = brent.groupby("month")["price_value"].mean()
    first = pd.Timestamp(as_of()).to_period("M").start_time - pd.DateOffset(months=months - 1)
    rows, ip = [], 100.0
    for m in range(months):
        month = first + pd.DateOffset(months=m)
        crude = monthly_brent.get(month, 75.0)
        ip = 100 + 0.8 * (ip - 100) + np.random.normal(0, 0.8)
        for code, name, value, unit in [
            (
                "FUEL_OIL_CPI",
                "Fuel oil CPI (synthetic)",
                290 * (crude / 75.0) ** 0.8 * (1 + np.random.normal(0, 0.01)),
                "Index 1982-1984=100",
            ),
            (
                "CORE_CPI",
                "Core CPI (synthetic)",
                300 * 1.0025**m * (1 + np.random.normal(0, 0.001)),
                "Index 1982-1984=100",
            ),
            ("INDUSTRIAL_PRODUCTION", "Industrial production (synthetic)", ip, "Index 2017=100"),
        ]:
            rows.append(
                {
                    "price_date": month.strftime("%Y-%m-%d"),
                    "index_code": code,
                    "index_name": name,
                    "index_value": round(value, 3),
                    "unit": unit,
                    "data_source": "SYNTHETIC",
                }
            )
    df = pd.DataFrame(rows)
    print(f"Generated {len(df)} macro indicator records")
    return df


def run(session, days: int) -> str:
    """Generate every dataset and upload the CSV files to CHP_RAW.DATA_STAGE."""
    import tempfile

    np.random.seed(42)
    random.seed(42)
    output_dir = Path(tempfile.mkdtemp())
    # Generate all datasets
    products_df = generate_products()
    customers_df = generate_customers(200)
    sites_df = generate_sites()
    market_indices_df = generate_market_indices(days * 2)
    family_levels = generate_family_price_levels(market_indices_df, days)
    sales_df = generate_sales_orders(products_df, customers_df, sites_df, family_levels, days)
    production_df = generate_production_runs(products_df, sites_df, days)
    inventory_df = generate_inventory_balances(products_df, sites_df)
    contracts_df = generate_contract_terms(products_df, customers_df)
    reports_df = generate_market_reports(products_df, 180)
    feedstock_df = generate_feedstock_mapping(products_df)
    logistics_df = generate_logistics_costs(sites_df)
    demand_df = generate_demand_history(sales_df, market_indices_df)
    macro_df = generate_macro_indicators(market_indices_df)

    # Save all files
    print("\n" + "=" * 60)
    print("Saving generated data...")

    products_df.to_csv(output_dir / "products.csv", index=False)
    customers_df.to_csv(output_dir / "customers.csv", index=False)
    sites_df.to_csv(output_dir / "sites.csv", index=False)
    market_indices_df.to_csv(output_dir / "market_indices.csv", index=False)
    sales_df.to_csv(output_dir / "sales_orders.csv", index=False)
    production_df.to_csv(output_dir / "production_runs.csv", index=False)
    inventory_df.to_csv(output_dir / "inventory_balances.csv", index=False)
    contracts_df.to_csv(output_dir / "contract_terms.csv", index=False)
    reports_df.to_csv(output_dir / "market_reports.csv", index=False)
    feedstock_df.to_csv(output_dir / "feedstock_mapping.csv", index=False)
    logistics_df.to_csv(output_dir / "logistics_costs.csv", index=False)
    demand_df.to_csv(output_dir / "demand_history.csv", index=False)
    macro_df.to_csv(output_dir / "macro_indicators.csv", index=False)
    planted_df = pd.DataFrame(
        [
            {"demand_family": d, "price_family": p, "elasticity": e}
            for d, row in FAMILY_ELASTICITY.items()
            for p, e in row.items()
        ]
    )
    planted_df.to_csv(output_dir / "planted_elasticity.csv", index=False)

    session.file.put(str(output_dir / "*.csv"), "@SF_SOLUTIONS.CHP_RAW.DATA_STAGE", overwrite=True, auto_compress=True)
    return f"{len(sales_df)} sales orders, {len(demand_df)} demand rows, {len(reports_df)} market reports"
$$;
