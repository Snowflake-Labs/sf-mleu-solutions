-- =============================================================================
-- Solution: Chemicals Pricing & Margin Intelligence - data
-- Database: SF_SOLUTIONS
-- Schemas:  CHP_RAW, CHP_ATOMIC, CHP_OPS
-- Generates the synthetic data and loads it.
-- Run order: setup.sql -> data.sql -> pipeline.sql -> (upload app files) -> streamlit.sql
--
-- Disclaimer: This application is not part of the Snowflake Service and is governed by the terms in
-- LICENSE, unless expressly agreed to in writing. You use this application at your own
-- risk, and Snowflake has no obligation to support your use of this application.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;


-- =============================================================================
-- Generate
-- =============================================================================

-- Clear the stage first: COPY matches file-name prefixes, so stale files would be loaded too
REMOVE @SF_SOLUTIONS.CHP_RAW.DATA_STAGE;
CALL SF_SOLUTIONS.CHP_RAW.SP_GENERATE_DATA(365);

-- =============================================================================
-- Load
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;

-- =============================================================================
-- Step 1: Create file formats
-- =============================================================================
CREATE OR REPLACE FILE FORMAT CHP_RAW.CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL = TRUE;

-- Clear the targets so re-running the deploy replaces the data instead of appending.
-- TRUNCATE also resets COPY load history, so unchanged files are loaded again.
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.PRODUCT;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.CUSTOMER;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.SITE;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.MARKET_INDEX;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.PRODUCTION_RUN;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.INVENTORY_BALANCE;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.CONTRACT_TERM;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.FEEDSTOCK_MAPPING;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.LOGISTICS_COST;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.DEMAND_HISTORY;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.MACRO_INDICATOR;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.DEMO_PLANTED_ELASTICITY;
TRUNCATE TABLE IF EXISTS CHP_ATOMIC.SALES_ORDER;
TRUNCATE TABLE IF EXISTS CHP_RAW.ERP_SALES_ORDERS;
TRUNCATE TABLE IF EXISTS CHP_RAW.MARKET_REPORTS;

-- =============================================================================
-- Step 2: Load CHP_ATOMIC layer tables
-- =============================================================================

-- Products
COPY INTO CHP_ATOMIC.PRODUCT (
    product_id, product_name, cas_number, product_family, product_category,
    product_grade, molecular_weight, density_kg_m3, hazard_class, un_number,
    base_unit, standard_cost_per_mt, target_margin_pct, min_order_quantity_mt,
    lead_time_days, is_active
)
FROM @CHP_RAW.DATA_STAGE/products.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Customers
COPY INTO CHP_ATOMIC.CUSTOMER (
    customer_id, customer_name, customer_segment, customer_tier, credit_limit,
    payment_terms_days, primary_region, primary_contact, annual_volume_mt,
    customer_since, is_active
)
FROM @CHP_RAW.DATA_STAGE/customers.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Sites
COPY INTO CHP_ATOMIC.SITE (
    site_id, site_name, site_type, region, country, city, latitude, longitude,
    capacity_mt_year, utilization_target_pct, storage_capacity_mt, is_active
)
FROM @CHP_RAW.DATA_STAGE/sites.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Market Index (extension)
COPY INTO CHP_ATOMIC.MARKET_INDEX (
    index_id, index_name, index_code, index_date, price_value, currency, unit,
    price_type, region, source, price_change_1d, price_change_7d, price_change_30d,
    price_change_pct_1d, price_change_pct_7d, price_change_pct_30d,
    price_avg_7d, price_avg_30d, price_volatility_30d
)
FROM @CHP_RAW.DATA_STAGE/market_indices.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Production Runs
COPY INTO CHP_ATOMIC.PRODUCTION_RUN (
    run_id, site_id, product_id, start_time, end_time, planned_quantity_mt,
    actual_yield_mt, yield_pct, feedstock_consumed_mt, feedstock_cost,
    energy_cost, labor_cost, overhead_cost, total_variable_cost, total_fixed_cost,
    cost_per_mt, quality_grade, batch_status, carbon_footprint_kg
)
FROM @CHP_RAW.DATA_STAGE/production_runs.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Inventory Balances
COPY INTO CHP_ATOMIC.INVENTORY_BALANCE (
    inventory_balance_id, snapshot_date, product_id, site_id, quantity_mt,
    quantity_allocated_mt, quantity_available_mt, inventory_value, days_of_supply,
    reorder_point_mt, safety_stock_mt, storage_cost_daily, inventory_age_days,
    quality_status
)
FROM @CHP_RAW.DATA_STAGE/inventory_balances.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Contract Terms
COPY INTO CHP_ATOMIC.CONTRACT_TERM (
    term_id, contract_id, customer_id, product_id, effective_date, expiration_date,
    price_formula, base_index_code, index_adjustment, fixed_price, floor_price,
    ceiling_price, min_volume_mt, max_volume_mt, volume_tier_1_mt, volume_tier_1_discount,
    volume_tier_2_mt, volume_tier_2_discount, payment_terms_days, early_pay_discount_pct,
    contract_status, contract_type
)
FROM @CHP_RAW.DATA_STAGE/contract_terms.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Feedstock Mapping
COPY INTO CHP_ATOMIC.FEEDSTOCK_MAPPING (
    mapping_id, product_id, feedstock_index_code, conversion_factor,
    cost_weight_pct, effective_date
)
FROM @CHP_RAW.DATA_STAGE/feedstock_mapping.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Logistics Costs
COPY INTO CHP_ATOMIC.LOGISTICS_COST (
    cost_id, origin_site_id, destination_region, transport_mode, cost_per_mt,
    transit_days, effective_date, expiration_date, carrier
)
FROM @CHP_RAW.DATA_STAGE/logistics_costs.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Demand History
COPY INTO CHP_ATOMIC.DEMAND_HISTORY (
    demand_id, demand_date, product_id, region, customer_segment, volume_mt,
    order_count, customer_count, avg_price_per_mt, min_price_per_mt,
    max_price_per_mt, crude_oil_price, gdp_index, manufacturing_pmi
)
FROM @CHP_RAW.DATA_STAGE/demand_history.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Macro Indicators (synthetic monthly series)
COPY INTO CHP_ATOMIC.MACRO_INDICATOR (
    price_date, index_code, index_name, index_value, unit, data_source
)
FROM @CHP_RAW.DATA_STAGE/macro_indicators.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Planted elasticities (ground truth for the demo's elasticity models)
COPY INTO CHP_ATOMIC.DEMO_PLANTED_ELASTICITY (demand_family, price_family, elasticity)
FROM @CHP_RAW.DATA_STAGE/planted_elasticity.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- =============================================================================
-- Step 3: Load CHP_RAW layer tables
-- =============================================================================

-- Sales Orders (to CHP_RAW first, then transform to CHP_ATOMIC)
COPY INTO CHP_RAW.ERP_SALES_ORDERS (
    order_id, order_line_id, order_date, ship_date, customer_id, customer_name,
    product_id, product_name, quantity_mt, unit_price, total_amount, currency,
    sales_region, sales_channel, customer_segment, contract_id, discount_pct,
    rebate_amount, freight_cost, ship_from_site, ship_to_location, incoterms
)
FROM @CHP_RAW.DATA_STAGE/sales_orders.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- Market Reports (for Cortex Search)
COPY INTO CHP_RAW.MARKET_REPORTS (
    report_id, report_date, report_type, report_title, report_source,
    chemical_name, region, report_summary, report_content, file_path, author
)
FROM @CHP_RAW.DATA_STAGE/market_reports.csv
FILE_FORMAT = CHP_RAW.CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- =============================================================================
-- Step 4: Transform CHP_RAW sales orders to CHP_ATOMIC
-- =============================================================================
INSERT INTO CHP_ATOMIC.SALES_ORDER (
    order_id, order_line_id, order_date, ship_date, customer_id, product_id,
    site_id, quantity_mt, unit_price, total_revenue, discount_amount,
    rebate_amount, freight_cost, net_revenue, sales_region, sales_channel,
    contract_id, order_status
)
SELECT
    order_id,
    order_line_id,
    TO_DATE(order_date),
    TO_DATE(ship_date),
    customer_id,
    product_id,
    ship_from_site,
    quantity_mt,
    unit_price,
    total_amount,
    total_amount * discount_pct / 100,
    rebate_amount,
    freight_cost,
    total_amount - (total_amount * discount_pct / 100) - rebate_amount,
    sales_region,
    sales_channel,
    contract_id,
    'COMPLETED'
FROM CHP_RAW.ERP_SALES_ORDERS;

-- =============================================================================
-- Step 5: Verification
-- =============================================================================
SELECT 'CHP_ATOMIC.PRODUCT' AS table_name, COUNT(*) AS row_count FROM CHP_ATOMIC.PRODUCT
UNION ALL
SELECT 'CHP_ATOMIC.CUSTOMER', COUNT(*) FROM CHP_ATOMIC.CUSTOMER
UNION ALL
SELECT 'CHP_ATOMIC.SITE', COUNT(*) FROM CHP_ATOMIC.SITE
UNION ALL
SELECT 'CHP_ATOMIC.MARKET_INDEX', COUNT(*) FROM CHP_ATOMIC.MARKET_INDEX
UNION ALL
SELECT 'CHP_ATOMIC.PRODUCTION_RUN', COUNT(*) FROM CHP_ATOMIC.PRODUCTION_RUN
UNION ALL
SELECT 'CHP_ATOMIC.INVENTORY_BALANCE', COUNT(*) FROM CHP_ATOMIC.INVENTORY_BALANCE
UNION ALL
SELECT 'CHP_ATOMIC.CONTRACT_TERM', COUNT(*) FROM CHP_ATOMIC.CONTRACT_TERM
UNION ALL
SELECT 'CHP_ATOMIC.SALES_ORDER', COUNT(*) FROM CHP_ATOMIC.SALES_ORDER
UNION ALL
SELECT 'CHP_ATOMIC.FEEDSTOCK_MAPPING', COUNT(*) FROM CHP_ATOMIC.FEEDSTOCK_MAPPING
UNION ALL
SELECT 'CHP_ATOMIC.LOGISTICS_COST', COUNT(*) FROM CHP_ATOMIC.LOGISTICS_COST
UNION ALL
SELECT 'CHP_ATOMIC.DEMAND_HISTORY', COUNT(*) FROM CHP_ATOMIC.DEMAND_HISTORY
UNION ALL
SELECT 'CHP_ATOMIC.MACRO_INDICATOR', COUNT(*) FROM CHP_ATOMIC.MACRO_INDICATOR
UNION ALL
SELECT 'CHP_RAW.MARKET_REPORTS', COUNT(*) FROM CHP_RAW.MARKET_REPORTS
ORDER BY table_name;

SELECT 'Data loading complete!' AS status;
