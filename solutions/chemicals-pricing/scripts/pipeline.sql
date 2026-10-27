-- =============================================================================
-- Solution: Chemicals Pricing & Margin Intelligence - pipeline
-- Database: SF_SOLUTIONS
-- Schemas:  CHP_RAW, CHP_ATOMIC, CHP_OPS
-- Data mart, ML procedures (run once), semantic view, search service, agent.
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
-- Data mart views
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

-- =============================================================================
-- MARGIN_ANALYZER: Pre-computed profitability per transaction
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.MARGIN_ANALYZER AS
SELECT
    so.order_id,
    so.order_line_id,
    so.order_date,
    DATE_TRUNC('month', so.order_date) AS order_month,
    DATE_TRUNC('quarter', so.order_date) AS order_quarter,
    YEAR(so.order_date) AS order_year,
    
    -- Customer dimensions
    so.customer_id,
    c.customer_name,
    c.customer_segment,
    c.customer_tier,
    
    -- Product dimensions
    so.product_id,
    p.product_name,
    p.product_family,
    p.product_category,
    p.product_grade,
    
    -- Geography
    so.sales_region AS region,
    so.sales_channel,
    so.site_id AS ship_from_site,
    
    -- Volume
    so.quantity_mt AS sales_volume_mt,
    
    -- Revenue breakdown
    so.unit_price AS selling_price_per_mt,
    so.total_revenue AS gross_revenue,
    so.discount_amount,
    so.rebate_amount,
    so.freight_cost,
    so.net_revenue,
    
    -- Cost breakdown (from most recent production run)
    pr.cost_per_mt AS manufacturing_cost_per_mt,
    pr.feedstock_cost / NULLIF(pr.actual_yield_mt, 0) AS feedstock_cost_per_mt,
    pr.energy_cost / NULLIF(pr.actual_yield_mt, 0) AS energy_cost_per_mt,
    (pr.labor_cost + pr.overhead_cost) / NULLIF(pr.actual_yield_mt, 0) AS conversion_cost_per_mt,
    
    -- Total cost
    COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt AS total_product_cost,
    so.freight_cost AS total_freight_cost,
    (COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost AS total_cost,
    
    -- Margin calculations
    so.net_revenue - ((COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost) AS gross_margin,
    CASE 
        WHEN so.net_revenue > 0 
        THEN ((so.net_revenue - ((COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost)) / so.net_revenue) * 100 
        ELSE 0 
    END AS gross_margin_pct,
    
    -- Margin vs target
    p.target_margin_pct,
    CASE 
        WHEN so.net_revenue > 0 
        THEN ((so.net_revenue - ((COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost)) / so.net_revenue) * 100 - p.target_margin_pct
        ELSE -p.target_margin_pct 
    END AS margin_variance_to_target,
    
    -- Deal classification
    CASE 
        WHEN so.net_revenue < ((COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost) THEN 'LOSS'
        WHEN ((so.net_revenue - ((COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost)) / NULLIF(so.net_revenue, 0)) * 100 < p.target_margin_pct * 0.5 THEN 'UNDERPRICED'
        WHEN ((so.net_revenue - ((COALESCE(pr.cost_per_mt, p.standard_cost_per_mt) * so.quantity_mt) + so.freight_cost)) / NULLIF(so.net_revenue, 0)) * 100 < p.target_margin_pct THEN 'BELOW_TARGET'
        ELSE 'ON_TARGET'
    END AS margin_status
    
FROM CHP_ATOMIC.SALES_ORDER so
LEFT JOIN CHP_ATOMIC.CUSTOMER c ON so.customer_id = c.customer_id
LEFT JOIN CHP_ATOMIC.PRODUCT p ON so.product_id = p.product_id
LEFT JOIN (
    -- Get most recent production cost for each product
    SELECT * FROM CHP_ATOMIC.PRODUCTION_RUN
    QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY end_time DESC) = 1
) pr ON so.product_id = pr.product_id;

COMMENT ON VIEW CHP_OPS.MARGIN_ANALYZER IS 'Pre-computed profitability per transaction';

-- =============================================================================
-- COST_TO_SERVE: Real-time cost breakdown for pricing decisions
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.COST_TO_SERVE AS
SELECT
    p.product_id,
    p.product_name,
    p.product_family,
    p.product_category,
    s.site_id,
    s.site_name,
    s.region AS manufacturing_region,
    
    -- Current feedstock cost (from latest market index)
    fm.feedstock_index_code,
    mi.price_value AS current_feedstock_price,
    mi.price_change_pct_7d AS feedstock_7d_change_pct,
    mi.price_value * fm.conversion_factor AS feedstock_cost_per_mt,
    
    -- Manufacturing costs (from latest production)
    pr.energy_cost / NULLIF(pr.actual_yield_mt, 0) AS energy_cost_per_mt,
    (pr.labor_cost + pr.overhead_cost) / NULLIF(pr.actual_yield_mt, 0) AS conversion_cost_per_mt,
    
    -- Total manufacturing cost
    (mi.price_value * fm.conversion_factor) + 
    (pr.energy_cost / NULLIF(pr.actual_yield_mt, 0)) + 
    ((pr.labor_cost + pr.overhead_cost) / NULLIF(pr.actual_yield_mt, 0)) AS total_manufacturing_cost_per_mt,
    
    -- Logistics costs by destination
    lc.destination_region,
    lc.cost_per_mt AS freight_cost_per_mt,
    lc.transit_days,
    
    -- Total cost to serve
    (mi.price_value * fm.conversion_factor) + 
    (pr.energy_cost / NULLIF(pr.actual_yield_mt, 0)) + 
    ((pr.labor_cost + pr.overhead_cost) / NULLIF(pr.actual_yield_mt, 0)) +
    lc.cost_per_mt AS total_cost_to_serve_per_mt,
    
    -- Suggested floor price (cost + min margin)
    ((mi.price_value * fm.conversion_factor) + 
    (pr.energy_cost / NULLIF(pr.actual_yield_mt, 0)) + 
    ((pr.labor_cost + pr.overhead_cost) / NULLIF(pr.actual_yield_mt, 0)) +
    lc.cost_per_mt) * (1 + 0.05) AS floor_price_per_mt,  -- 5% minimum margin
    
    -- Suggested target price (cost + target margin)
    ((mi.price_value * fm.conversion_factor) + 
    (pr.energy_cost / NULLIF(pr.actual_yield_mt, 0)) + 
    ((pr.labor_cost + pr.overhead_cost) / NULLIF(pr.actual_yield_mt, 0)) +
    lc.cost_per_mt) * (1 + p.target_margin_pct/100) AS target_price_per_mt,
    
    -- Data freshness
    mi.index_date AS feedstock_price_date,
    pr.end_time AS production_cost_date
    
FROM CHP_ATOMIC.PRODUCT p
CROSS JOIN CHP_ATOMIC.SITE s
LEFT JOIN CHP_ATOMIC.FEEDSTOCK_MAPPING fm ON p.product_id = fm.product_id
LEFT JOIN (
    -- Latest feedstock prices
    SELECT * FROM CHP_ATOMIC.MARKET_INDEX
    QUALIFY ROW_NUMBER() OVER (PARTITION BY index_code ORDER BY index_date DESC) = 1
) mi ON fm.feedstock_index_code = mi.index_code
LEFT JOIN (
    -- Latest production costs
    SELECT * FROM CHP_ATOMIC.PRODUCTION_RUN
    QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, site_id ORDER BY end_time DESC) = 1
) pr ON p.product_id = pr.product_id AND s.site_id = pr.site_id
LEFT JOIN CHP_ATOMIC.LOGISTICS_COST lc ON s.site_id = lc.origin_site_id
WHERE s.site_type = 'MANUFACTURING' AND p.is_active = TRUE;

COMMENT ON VIEW CHP_OPS.COST_TO_SERVE IS 'Real-time cost-to-serve calculation for pricing decisions';

-- =============================================================================
-- PRICE_GUIDANCE: Pricing recommendations with market context
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.PRICE_GUIDANCE AS
SELECT
    cts.product_id,
    cts.product_name,
    cts.product_family,
    cts.site_id,
    cts.destination_region,
    
    -- Cost components
    cts.feedstock_cost_per_mt,
    cts.energy_cost_per_mt,
    cts.conversion_cost_per_mt,
    cts.freight_cost_per_mt,
    cts.total_cost_to_serve_per_mt,
    
    -- Price recommendations
    cts.floor_price_per_mt,
    cts.target_price_per_mt,
    
    -- Market context
    cts.feedstock_7d_change_pct,
    CASE 
        WHEN cts.feedstock_7d_change_pct > 5 THEN 'RISING'
        WHEN cts.feedstock_7d_change_pct < -5 THEN 'FALLING'
        ELSE 'STABLE'
    END AS feedstock_trend,
    
    -- Historical pricing (from recent sales)
    hist.avg_selling_price_30d,
    hist.min_selling_price_30d,
    hist.max_selling_price_30d,
    hist.sales_volume_30d_mt,
    
    -- Price drivers narrative
    CASE 
        WHEN cts.feedstock_7d_change_pct > 5 THEN 'Feedstock prices up ' || ROUND(cts.feedstock_7d_change_pct, 1) || '% - consider price increase'
        WHEN cts.feedstock_7d_change_pct < -5 THEN 'Feedstock prices down ' || ROUND(ABS(cts.feedstock_7d_change_pct), 1) || '% - competitive pricing opportunity'
        ELSE 'Feedstock prices stable - maintain current pricing'
    END AS pricing_recommendation
    
FROM CHP_OPS.COST_TO_SERVE cts
LEFT JOIN (
    -- 30-day sales history by product/region
    SELECT 
        product_id,
        region,
        AVG(selling_price_per_mt) AS avg_selling_price_30d,
        MIN(selling_price_per_mt) AS min_selling_price_30d,
        MAX(selling_price_per_mt) AS max_selling_price_30d,
        SUM(sales_volume_mt) AS sales_volume_30d_mt
    FROM CHP_OPS.MARGIN_ANALYZER
    WHERE order_date >= DATEADD(day, -30, CURRENT_DATE())
    GROUP BY product_id, region
) hist ON cts.product_id = hist.product_id AND cts.destination_region = hist.region;

COMMENT ON VIEW CHP_OPS.PRICE_GUIDANCE IS 'Pricing recommendations with cost drivers and market context';

-- =============================================================================
-- INVENTORY_HEALTH: Inventory analysis with days of supply
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.INVENTORY_HEALTH AS
SELECT
    ib.snapshot_date,
    ib.product_id,
    p.product_name,
    p.product_family,
    ib.site_id,
    s.site_name,
    s.region,
    
    -- Inventory levels
    ib.quantity_mt AS total_inventory_mt,
    ib.quantity_allocated_mt,
    ib.quantity_available_mt,
    ib.inventory_value,
    
    -- Days of supply
    ib.days_of_supply,
    ib.reorder_point_mt,
    ib.safety_stock_mt,
    
    -- Status classification
    CASE 
        WHEN ib.quantity_available_mt <= ib.safety_stock_mt THEN 'CRITICAL'
        WHEN ib.quantity_available_mt <= ib.reorder_point_mt THEN 'LOW'
        WHEN ib.days_of_supply > 60 THEN 'EXCESS'
        ELSE 'HEALTHY'
    END AS inventory_status,
    
    -- Working capital impact
    ib.inventory_value AS working_capital_tied,
    ib.storage_cost_daily * ib.days_of_supply AS storage_cost_exposure,
    
    -- Aging
    ib.inventory_age_days,
    CASE 
        WHEN ib.inventory_age_days > 90 THEN 'AGED'
        WHEN ib.inventory_age_days > 60 THEN 'MATURING'
        ELSE 'FRESH'
    END AS age_status

FROM CHP_ATOMIC.INVENTORY_BALANCE ib
LEFT JOIN CHP_ATOMIC.PRODUCT p ON ib.product_id = p.product_id
LEFT JOIN CHP_ATOMIC.SITE s ON ib.site_id = s.site_id
WHERE ib.snapshot_date = (SELECT MAX(snapshot_date) FROM CHP_ATOMIC.INVENTORY_BALANCE);

COMMENT ON VIEW CHP_OPS.INVENTORY_HEALTH IS 'Inventory health analysis with days of supply and working capital';

-- =============================================================================
-- MARGIN_LEAKAGE: Analysis of margin leakage sources
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.MARGIN_LEAKAGE AS
SELECT
    order_month,
    product_family,
    region,
    customer_segment,
    
    -- Revenue waterfall
    SUM(gross_revenue) AS gross_revenue,
    SUM(discount_amount) AS total_discounts,
    SUM(rebate_amount) AS total_rebates,
    SUM(freight_cost) AS total_freight,
    SUM(net_revenue) AS net_revenue,
    
    -- Cost waterfall  
    SUM(total_product_cost) AS total_product_cost,
    SUM(total_freight_cost) AS total_freight_cost,
    SUM(total_cost) AS total_cost,
    
    -- Margin
    SUM(gross_margin) AS total_margin,
    AVG(gross_margin_pct) AS avg_margin_pct,
    
    -- Leakage analysis
    SUM(discount_amount) / NULLIF(SUM(gross_revenue), 0) * 100 AS discount_leakage_pct,
    SUM(rebate_amount) / NULLIF(SUM(gross_revenue), 0) * 100 AS rebate_leakage_pct,
    SUM(freight_cost) / NULLIF(SUM(gross_revenue), 0) * 100 AS freight_leakage_pct,
    
    -- Deal quality
    COUNT(*) AS total_deals,
    SUM(CASE WHEN margin_status = 'LOSS' THEN 1 ELSE 0 END) AS loss_deals,
    SUM(CASE WHEN margin_status = 'UNDERPRICED' THEN 1 ELSE 0 END) AS underpriced_deals,
    SUM(CASE WHEN margin_status = 'ON_TARGET' THEN 1 ELSE 0 END) AS on_target_deals
    
FROM CHP_OPS.MARGIN_ANALYZER
GROUP BY order_month, product_family, region, customer_segment;

COMMENT ON VIEW CHP_OPS.MARGIN_LEAKAGE IS 'Margin leakage analysis by source (discounts, rebates, freight)';

-- =============================================================================
-- MARKET_TRENDS: Market index trends and analysis
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.MARKET_TRENDS AS
SELECT
    index_name,
    index_code,
    index_date,
    price_value AS current_price,
    currency,
    region,
    
    -- Trends
    price_change_1d,
    price_change_7d,
    price_change_30d,
    price_change_pct_1d,
    price_change_pct_7d,
    price_change_pct_30d,
    
    -- Moving averages
    price_avg_7d,
    price_avg_30d,
    price_volatility_30d,
    
    -- Trend classification
    CASE 
        WHEN price_change_pct_7d > 10 THEN 'SPIKE'
        WHEN price_change_pct_7d > 5 THEN 'RISING'
        WHEN price_change_pct_7d < -10 THEN 'CRASH'
        WHEN price_change_pct_7d < -5 THEN 'FALLING'
        ELSE 'STABLE'
    END AS price_trend,
    
    -- Volatility classification
    CASE 
        WHEN price_volatility_30d > price_avg_30d * 0.15 THEN 'HIGH'
        WHEN price_volatility_30d > price_avg_30d * 0.08 THEN 'MODERATE'
        ELSE 'LOW'
    END AS volatility_level

FROM CHP_ATOMIC.MARKET_INDEX
WHERE index_date >= DATEADD(day, -90, CURRENT_DATE())
ORDER BY index_name, index_date DESC;

COMMENT ON VIEW CHP_OPS.MARKET_TRENDS IS 'Market index trends and volatility analysis';

-- =============================================================================
-- MACRO_* views: monthly macro indicators used by the ML training view and the
-- Market Data page. These read the synthetic CHP_ATOMIC.MACRO_INDICATOR table; run
-- marketplace/use_public_data.sql to read Snowflake Public Data (Free) instead.
-- =============================================================================
CREATE OR REPLACE VIEW CHP_OPS.MACRO_FUEL_OIL_CPI AS
SELECT price_date, index_code, index_value, unit, data_source
FROM CHP_ATOMIC.MACRO_INDICATOR WHERE index_code = 'FUEL_OIL_CPI';

CREATE OR REPLACE VIEW CHP_OPS.MACRO_CORE_CPI AS
SELECT price_date, index_code, index_value, unit, data_source
FROM CHP_ATOMIC.MACRO_INDICATOR WHERE index_code = 'CORE_CPI';

CREATE OR REPLACE VIEW CHP_OPS.MACRO_INDUSTRIAL_PRODUCTION AS
SELECT price_date, index_code, index_value, unit, data_source
FROM CHP_ATOMIC.MACRO_INDICATOR WHERE index_code = 'INDUSTRIAL_PRODUCTION';

CREATE OR REPLACE VIEW CHP_OPS.MACRO_ECONOMIC_INDICATORS AS
SELECT price_date, index_code, index_value, data_source FROM CHP_OPS.MACRO_FUEL_OIL_CPI
UNION ALL
SELECT price_date, index_code, index_value, data_source FROM CHP_OPS.MACRO_CORE_CPI
UNION ALL
SELECT price_date, index_code, index_value, data_source FROM CHP_OPS.MACRO_INDUSTRIAL_PRODUCTION;

-- MARGIN_ANALYZER with the latest energy-cost context
CREATE OR REPLACE VIEW CHP_OPS.MARGIN_ANALYZER_ENHANCED AS
WITH latest_fuel_cpi AS (
    SELECT index_value AS fuel_oil_cpi FROM CHP_OPS.MACRO_FUEL_OIL_CPI
    ORDER BY price_date DESC LIMIT 1
),
latest_core_cpi AS (
    SELECT index_value AS core_cpi FROM CHP_OPS.MACRO_CORE_CPI
    ORDER BY price_date DESC LIMIT 1
),
fuel_trend AS (
    SELECT
        AVG(CASE WHEN price_date >= DATEADD(day, -30, max_date) THEN index_value END) AS avg_30d,
        AVG(CASE WHEN price_date >= DATEADD(day, -90, max_date) THEN index_value END) AS avg_90d
    FROM CHP_OPS.MACRO_FUEL_OIL_CPI,
         (SELECT MAX(price_date) AS max_date FROM CHP_OPS.MACRO_FUEL_OIL_CPI)
)
SELECT
    ma.*,
    lf.fuel_oil_cpi AS current_fuel_cpi,
    lc.core_cpi AS current_core_cpi,
    ft.avg_30d AS fuel_cpi_30d_avg,
    ft.avg_90d AS fuel_cpi_90d_avg,
    CASE
        WHEN ft.avg_30d > ft.avg_90d * 1.03 THEN 'RISING'
        WHEN ft.avg_30d < ft.avg_90d * 0.97 THEN 'FALLING'
        ELSE 'STABLE'
    END AS energy_cost_trend
FROM CHP_OPS.MARGIN_ANALYZER ma
CROSS JOIN latest_fuel_cpi lf
CROSS JOIN latest_core_cpi lc
CROSS JOIN fuel_trend ft;

COMMENT ON VIEW CHP_OPS.MARGIN_ANALYZER_ENHANCED IS 'Margin analysis with the latest macro energy-cost context';

-- =============================================================================
-- Verification
-- =============================================================================
SHOW VIEWS IN SCHEMA CHP_OPS;

-- =============================================================================
-- Model output tables
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

-- =============================================================================
-- DEMAND_FORECAST: ML prediction of sales volume
-- =============================================================================
CREATE OR REPLACE TABLE CHP_OPS.DEMAND_FORECAST (
    forecast_id             INTEGER         NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    region                  VARCHAR(50)     NOT NULL,
    customer_segment        VARCHAR(50),
    
    -- Forecast period
    forecast_date           DATE            NOT NULL,      -- Date forecast was generated
    forecast_period_start   DATE            NOT NULL,      -- Start of forecast period
    forecast_period_end     DATE            NOT NULL,      -- End of forecast period
    forecast_horizon        VARCHAR(20),                   -- WEEKLY, MONTHLY, QUARTERLY
    
    -- Forecast values
    predicted_volume_mt     FLOAT           NOT NULL,
    prediction_lower_bound  FLOAT,                         -- 95% CI lower
    prediction_upper_bound  FLOAT,                         -- 95% CI upper
    prediction_confidence   FLOAT,                         -- Model confidence score
    
    -- Comparison to history
    historical_avg_volume   FLOAT,
    forecast_vs_history_pct FLOAT,                         -- % change vs historical
    
    -- Key drivers (feature importance)
    top_driver_1            VARCHAR(100),                  -- e.g., 'CRUDE_OIL_PRICE'
    top_driver_1_impact     FLOAT,                         -- Contribution to forecast
    top_driver_2            VARCHAR(100),
    top_driver_2_impact     FLOAT,
    top_driver_3            VARCHAR(100),
    top_driver_3_impact     FLOAT,
    
    -- Model metadata
    model_name              VARCHAR(100)    DEFAULT 'DEMAND_XGBOOST',
    model_version           VARCHAR(50)     DEFAULT 'v1.0',
    model_mape              FLOAT,                         -- Mean Absolute Percentage Error
    
    PRIMARY KEY (forecast_id)
);

COMMENT ON TABLE CHP_OPS.DEMAND_FORECAST IS 'ML demand predictions by product/region';

-- =============================================================================
-- PRICE_ELASTICITY: Calculated elasticity coefficients
-- =============================================================================
CREATE OR REPLACE TABLE CHP_OPS.PRICE_ELASTICITY (
    elasticity_id           INTEGER         NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    region                  VARCHAR(50)     NOT NULL,
    customer_segment        VARCHAR(50),
    
    -- Calculation period
    calculation_date        DATE            NOT NULL,
    period_start            DATE,
    period_end              DATE,
    data_points             INTEGER,                       -- Number of observations
    
    -- Elasticity metrics
    elasticity_coefficient  FLOAT           NOT NULL,      -- Price elasticity of demand
    elasticity_std_error    FLOAT,
    elasticity_p_value      FLOAT,
    r_squared               FLOAT,                         -- Model fit
    
    -- Interpretation
    elasticity_category     VARCHAR(20),                   -- ELASTIC, UNIT_ELASTIC, INELASTIC
    
    -- Cross-price elasticity (optional)
    substitute_product_id   VARCHAR(50),
    cross_elasticity        FLOAT,
    
    -- Model metadata
    model_name              VARCHAR(100)    DEFAULT 'ELASTICITY_LINEAR_REGRESSION',
    model_version           VARCHAR(50)     DEFAULT 'v1.0',
    
    PRIMARY KEY (elasticity_id)
);

COMMENT ON TABLE CHP_OPS.PRICE_ELASTICITY IS 'Price elasticity coefficients by product/region';

-- =============================================================================
-- LAGGED_CORRELATION: correlation of demand with lagged crude prices
-- =============================================================================
CREATE OR REPLACE TABLE CHP_OPS.LAGGED_CORRELATION (
    correlation_id          INTEGER         NOT NULL,
    product_id              VARCHAR(50)     NOT NULL,
    region                  VARCHAR(50)     NOT NULL,
    
    -- Correlation analysis
    analysis_date           DATE            NOT NULL,
    demand_metric           VARCHAR(50),                   -- e.g., 'WEEKLY_VOLUME'
    driver_metric           VARCHAR(50),                   -- e.g., 'CRUDE_OIL_BRENT'
    
    -- Lag analysis (1-8 weeks)
    lag_weeks               INTEGER         NOT NULL,
    correlation_coefficient FLOAT           NOT NULL,
    correlation_p_value     FLOAT,
    is_significant          BOOLEAN,                       -- p < 0.05
    
    -- Best lag identification
    is_optimal_lag          BOOLEAN         DEFAULT FALSE,
    
    -- Business impact
    predicted_demand_change_pct FLOAT,                     -- If driver changes by 10%
    inventory_positioning_days  INTEGER,                   -- Lead time for inventory
    
    PRIMARY KEY (correlation_id)
);

COMMENT ON TABLE CHP_OPS.LAGGED_CORRELATION IS 'Correlation of weekly demand with lagged Brent';

-- =============================================================================
-- Create indexes for performance
-- =============================================================================
-- CREATE INDEX idx_demand_forecast_product ON CHP_OPS.DEMAND_FORECAST(product_id, region, forecast_period_start);
-- CREATE INDEX idx_lagged_correlation_product ON CHP_OPS.LAGGED_CORRELATION(product_id, region, lag_weeks);

-- =============================================================================
-- Verification
-- =============================================================================
SHOW TABLES IN SCHEMA CHP_OPS;

-- =============================================================================
-- ML feature views and tables
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

-- =============================================================================
-- VIEW 1: ML_TRAINING_DATA
-- Unified dataset joining sales, products, costs, and market indicators
-- =============================================================================

CREATE OR REPLACE VIEW ML_TRAINING_DATA AS
WITH 
-- Aggregate daily sales by product and region
daily_sales AS (
    SELECT 
        so.order_date,
        so.product_id,
        p.product_name,
        p.product_family,
        p.product_category,
        so.sales_region AS region,
        COUNT(DISTINCT so.order_id) AS num_orders,
        COUNT(DISTINCT so.customer_id) AS num_customers,
        SUM(so.quantity_mt) AS total_quantity_mt,
        SUM(so.total_revenue) AS total_revenue,
        AVG(so.unit_price) AS avg_price_per_mt,
        STDDEV(so.unit_price) AS price_stddev
    FROM SF_SOLUTIONS.CHP_ATOMIC.SALES_ORDER so
    JOIN SF_SOLUTIONS.CHP_ATOMIC.PRODUCT p ON so.product_id = p.product_id
    GROUP BY 
        so.order_date, so.product_id, p.product_name, 
        p.product_family, p.product_category, so.sales_region
),

-- Get variable costs by product
product_costs AS (
    SELECT 
        product_id,
        AVG(total_cost_to_serve_per_mt) AS avg_variable_cost
    FROM SF_SOLUTIONS.CHP_OPS.COST_TO_SERVE
    GROUP BY product_id
),

-- Get market indicators with forward fill for missing dates
market_indicators AS (
    SELECT DISTINCT
        f.price_date,
        f.index_value AS fuel_oil_cpi,
        c.index_value AS core_cpi,
        i.index_value AS industrial_production
    FROM MACRO_FUEL_OIL_CPI f
    LEFT JOIN MACRO_CORE_CPI c ON f.price_date = c.price_date
    LEFT JOIN MACRO_INDUSTRIAL_PRODUCTION i ON f.price_date = i.price_date
),

-- Compute lagged prices for each product (30-day rolling average)
price_lags AS (
    SELECT 
        order_date,
        product_id,
        AVG(avg_price_per_mt) OVER (
            PARTITION BY product_id 
            ORDER BY order_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS price_avg_30d,
        AVG(avg_price_per_mt) OVER (
            PARTITION BY product_id 
            ORDER BY order_date 
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        ) AS price_avg_7d
    FROM daily_sales
)

SELECT 
    -- Identifiers
    ds.order_date,
    ds.product_id,
    ds.product_name,
    ds.product_family,
    ds.product_category,
    ds.region,
    
    -- Volume metrics
    ds.num_orders,
    ds.num_customers,
    ds.total_quantity_mt,
    ds.total_revenue,
    
    -- Price metrics
    ds.avg_price_per_mt,
    ds.price_stddev,
    pl.price_avg_7d,
    pl.price_avg_30d,
    
    -- Log transforms for elasticity estimation
    LN(NULLIF(ds.total_quantity_mt, 0)) AS ln_quantity,
    LN(NULLIF(ds.avg_price_per_mt, 0)) AS ln_price,
    -- Mix-free price index: price relative to the product's own average, so family-level
    -- aggregates move with price changes rather than with the day's product mix
    LN(NULLIF(ds.avg_price_per_mt, 0)
       / NULLIF(AVG(ds.avg_price_per_mt) OVER (PARTITION BY ds.product_id), 0)) AS ln_price_index,
    
    -- Price relatives
    ds.avg_price_per_mt / NULLIF(pl.price_avg_30d, 0) AS price_vs_avg_30d,
    (ds.avg_price_per_mt - pl.price_avg_7d) / NULLIF(pl.price_avg_7d, 0) AS price_change_7d_pct,
    
    -- Cost metrics
    pc.avg_variable_cost,
    ds.avg_price_per_mt - pc.avg_variable_cost AS margin_per_mt,
    (ds.avg_price_per_mt - pc.avg_variable_cost) / NULLIF(ds.avg_price_per_mt, 0) AS margin_pct,
    
    -- Market indicators (join to closest available date)
    mi.fuel_oil_cpi,
    mi.core_cpi,
    mi.industrial_production,
    
    -- Temporal features
    MONTH(ds.order_date) AS month,
    QUARTER(ds.order_date) AS quarter,
    YEAR(ds.order_date) AS year,
    DAYOFWEEK(ds.order_date) AS day_of_week,
    CASE WHEN QUARTER(ds.order_date) = 4 THEN 1 ELSE 0 END AS is_q4,
    CASE WHEN MONTH(ds.order_date) IN (12, 1, 2) THEN 1 ELSE 0 END AS is_winter
    
FROM daily_sales ds
LEFT JOIN product_costs pc ON ds.product_id = pc.product_id
LEFT JOIN price_lags pl ON ds.order_date = pl.order_date AND ds.product_id = pl.product_id
LEFT JOIN market_indicators mi ON DATE_TRUNC('month', ds.order_date) = DATE_TRUNC('month', mi.price_date)
WHERE ds.total_quantity_mt > 0
  AND ds.avg_price_per_mt > 0
ORDER BY ds.order_date, ds.product_id;

-- =============================================================================
-- TABLE 2: PRICE_ELASTICITY_LINEAR
-- Stores per-product elasticity from linear regression
-- =============================================================================

CREATE OR REPLACE TABLE PRICE_ELASTICITY_LINEAR (
    model_version VARCHAR(50) NOT NULL,
    estimation_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    product_id VARCHAR(50) NOT NULL,
    product_name VARCHAR(100),
    product_family VARCHAR(50),
    
    -- Elasticity estimates
    own_elasticity FLOAT,
    own_elasticity_se FLOAT,
    own_elasticity_tstat FLOAT,
    own_elasticity_pvalue FLOAT,
    
    -- Control variable coefficients
    cpi_coefficient FLOAT,
    cpi_pvalue FLOAT,
    ip_coefficient FLOAT,
    ip_pvalue FLOAT,
    
    -- Model diagnostics
    n_observations INT,
    r_squared FLOAT,
    adj_r_squared FLOAT,
    rmse FLOAT,
    aic FLOAT,
    
    -- Metadata
    training_start_date DATE,
    training_end_date DATE,
    
    PRIMARY KEY (model_version, product_id)
);

-- =============================================================================
-- TABLE 3: ELASTICITY_MATRIX
-- Stores cross-price elasticity matrix from SUR model
-- =============================================================================

CREATE OR REPLACE TABLE ELASTICITY_MATRIX (
    model_version VARCHAR(50) NOT NULL,
    estimation_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    -- Matrix cell identifier
    demand_product_id VARCHAR(50) NOT NULL,    -- Row: whose demand changes
    demand_product_name VARCHAR(100),
    price_product_id VARCHAR(50) NOT NULL,     -- Column: whose price changed
    price_product_name VARCHAR(100),
    
    -- Elasticity estimate
    elasticity FLOAT,
    std_error FLOAT,
    t_statistic FLOAT,
    p_value FLOAT,
    
    -- Interpretation flags
    is_own_price BOOLEAN,                       -- Diagonal element
    is_significant BOOLEAN,                     -- p < 0.05
    relationship_type VARCHAR(20),              -- 'own', 'substitute', 'complement', 'independent'
    
    PRIMARY KEY (model_version, demand_product_id, price_product_id)
);

-- =============================================================================
-- TABLE 4: OPTIMAL_PRICING
-- Stores optimization results
-- =============================================================================

CREATE OR REPLACE TABLE OPTIMAL_PRICING (
    scenario_id VARCHAR(50) NOT NULL,
    run_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    -- Product info
    product_id VARCHAR(50) NOT NULL,
    product_name VARCHAR(100),
    region VARCHAR(50),
    
    -- Current state
    current_price FLOAT,
    current_volume FLOAT,
    current_revenue FLOAT,
    current_margin FLOAT,
    
    -- Optimal recommendations
    optimal_price FLOAT,
    predicted_volume FLOAT,
    predicted_revenue FLOAT,
    predicted_margin FLOAT,
    
    -- Changes
    price_change_dollars FLOAT,
    price_change_pct FLOAT,
    volume_change_pct FLOAT,
    margin_change_pct FLOAT,
    
    -- Constraint status
    is_at_floor BOOLEAN,
    is_at_ceiling BOOLEAN,
    is_margin_binding BOOLEAN,
    binding_constraints ARRAY,
    
    PRIMARY KEY (scenario_id, product_id, region)
);

-- =============================================================================
-- TABLE 6: MODEL_METADATA
-- Tracks model versions and training metadata
-- =============================================================================

CREATE OR REPLACE TABLE MODEL_METADATA (
    model_version VARCHAR(50) PRIMARY KEY,
    model_type VARCHAR(50) NOT NULL,            -- 'linear', 'sur', '2sls', 'blp'
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    created_by VARCHAR(100),
    
    -- Training info
    training_start_date DATE,
    training_end_date DATE,
    n_products INT,
    n_observations INT,
    
    -- Model quality
    avg_r_squared FLOAT,
    avg_rmse FLOAT,
    
    -- Features used
    features_used ARRAY,
    market_indicators_used ARRAY,
    
    -- Status
    is_active BOOLEAN DEFAULT FALSE,
    is_production BOOLEAN DEFAULT FALSE,
    
    -- Notes
    description VARCHAR(1000),
    notes VARCHAR(2000)
);

-- =============================================================================
-- VERIFY CREATION
-- =============================================================================

SELECT 'ML_TRAINING_DATA' AS object_name, 'VIEW' AS object_type, COUNT(*) AS row_count 
FROM ML_TRAINING_DATA
UNION ALL
SELECT 'PRICE_ELASTICITY_LINEAR', 'TABLE', 0
UNION ALL
SELECT 'ELASTICITY_MATRIX', 'TABLE', 0
UNION ALL
SELECT 'OPTIMAL_PRICING', 'TABLE', 0
UNION ALL
SELECT 'MODEL_METADATA', 'TABLE', 0;

-- =============================================================================
-- ML stored procedures
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

-- -----------------------------------------------------------------------------
-- Per-product own-price elasticity (notebook 02)
-- ln(Q) = a + b ln(P) + c1 fuel_cpi + c2 industrial_production + month dummies
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_OPS.SP_ESTIMATE_PRICE_ELASTICITY()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy', 'statsmodels')
HANDLER = 'run'
COMMENT = 'Per-product log-log OLS price elasticity -> PRICE_ELASTICITY_LINEAR and PRICE_ELASTICITY'
EXECUTE AS OWNER
AS
$$
import datetime as dt

import numpy as np
import pandas as pd
import statsmodels.api as sm

OPS = "SF_SOLUTIONS.CHP_OPS"


def _std(s):
    s = s.fillna(s.mean())
    return (s - s.mean()) / s.std() if s.std() > 0 else s * 0


def _load(session, df, table, cols):
    tmp = "TMP_" + table.split(".")[-1]
    session.write_pandas(df[cols], tmp, auto_create_table=True, table_type="temporary", overwrite=True)
    session.sql(f"DELETE FROM {table}").collect()
    session.sql(f"INSERT INTO {table} ({', '.join(cols)}) SELECT {', '.join(cols)} FROM {tmp}").collect()


def run(session):
    df = session.sql(f"""
        SELECT product_id, product_name, product_family, order_date, ln_quantity, ln_price,
               fuel_oil_cpi, industrial_production, month
        FROM {OPS}.ML_TRAINING_DATA
        WHERE ln_quantity IS NOT NULL AND ln_price IS NOT NULL
    """).to_pandas()
    version = "linear_v1_" + dt.date.today().strftime("%Y%m%d")
    rows = []
    for pid, g in df.groupby("PRODUCT_ID"):
        if len(g) < 30:
            continue
        X = pd.DataFrame({"const": 1.0, "ln_price": g["LN_PRICE"].astype(float)}, index=g.index)
        X["fuel_cpi"] = _std(g["FUEL_OIL_CPI"].astype(float))
        X["ip"] = _std(g["INDUSTRIAL_PRODUCTION"].astype(float))
        X = pd.concat([X, pd.get_dummies(g["MONTH"].astype(int), prefix="m", drop_first=True, dtype=float)], axis=1)
        m = sm.OLS(g["LN_QUANTITY"].astype(float), X).fit()
        rows.append({
            "MODEL_VERSION": version, "PRODUCT_ID": pid, "PRODUCT_NAME": g["PRODUCT_NAME"].iloc[0],
            "PRODUCT_FAMILY": g["PRODUCT_FAMILY"].iloc[0], "N_OBSERVATIONS": int(m.nobs),
            "OWN_ELASTICITY": float(m.params["ln_price"]), "OWN_ELASTICITY_SE": float(m.bse["ln_price"]),
            "OWN_ELASTICITY_TSTAT": float(m.tvalues["ln_price"]), "OWN_ELASTICITY_PVALUE": float(m.pvalues["ln_price"]),
            "CPI_COEFFICIENT": float(m.params["fuel_cpi"]), "CPI_PVALUE": float(m.pvalues["fuel_cpi"]),
            "IP_COEFFICIENT": float(m.params["ip"]), "IP_PVALUE": float(m.pvalues["ip"]),
            "R_SQUARED": float(m.rsquared), "ADJ_R_SQUARED": float(m.rsquared_adj),
            "RMSE": float(np.sqrt(m.mse_resid)), "AIC": float(m.aic),
            "TRAINING_START_DATE": str(g["ORDER_DATE"].min()), "TRAINING_END_DATE": str(g["ORDER_DATE"].max()),
        })
    res = pd.DataFrame(rows)
    _load(session, res, f"{OPS}.PRICE_ELASTICITY_LINEAR", list(res.columns))

    e = res["OWN_ELASTICITY"].abs()
    pe = pd.DataFrame({
        "ELASTICITY_ID": range(1, len(res) + 1), "PRODUCT_ID": res["PRODUCT_ID"], "REGION": "All regions",
        "CALCULATION_DATE": str(dt.date.today()), "PERIOD_START": res["TRAINING_START_DATE"],
        "PERIOD_END": res["TRAINING_END_DATE"], "DATA_POINTS": res["N_OBSERVATIONS"],
        "ELASTICITY_COEFFICIENT": res["OWN_ELASTICITY"], "ELASTICITY_STD_ERROR": res["OWN_ELASTICITY_SE"],
        "ELASTICITY_P_VALUE": res["OWN_ELASTICITY_PVALUE"], "R_SQUARED": res["R_SQUARED"],
        "ELASTICITY_CATEGORY": np.where(e > 1.1, "ELASTIC", np.where(e < 0.9, "INELASTIC", "UNIT_ELASTIC")),
        "MODEL_NAME": "ELASTICITY_LINEAR_REGRESSION", "MODEL_VERSION": version,
    })
    _load(session, pe, f"{OPS}.PRICE_ELASTICITY", list(pe.columns))
    session.sql(f"DELETE FROM {OPS}.MODEL_METADATA WHERE model_type = 'linear'").collect()
    session.sql(f"""
        INSERT INTO {OPS}.MODEL_METADATA (model_version, model_type, created_by, training_start_date,
            training_end_date, n_products, n_observations, avg_r_squared, avg_rmse, is_active, description)
        SELECT ?, 'linear', CURRENT_USER(), ?, ?, ?, ?, ?, ?, TRUE,
               'Per-product log-log OLS with fuel-oil CPI, industrial production and month controls'
    """, params=[version, str(df["ORDER_DATE"].min()), str(df["ORDER_DATE"].max()), len(res),
                 int(res["N_OBSERVATIONS"].sum()), float(res["R_SQUARED"].mean()), float(res["RMSE"].mean())]).collect()
    return {"model_version": version, "products": len(res),
            "median_own_elasticity": round(float(res["OWN_ELASTICITY"].median()), 3)}
$$;

-- -----------------------------------------------------------------------------
-- Family cross-price elasticity matrix (notebook 03)
-- One equation per family: ln(Q_f) on the ln price index of every family plus
-- macro controls. Every equation has the same regressors, so equation-by-
-- equation OLS gives the SUR (GLS) point estimates.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_OPS.SP_ESTIMATE_ELASTICITY_MATRIX()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy', 'statsmodels')
HANDLER = 'run'
COMMENT = 'Seemingly unrelated regressions over product families -> ELASTICITY_MATRIX'
EXECUTE AS OWNER
AS
$$
import datetime as dt

import numpy as np
import pandas as pd
import statsmodels.api as sm

OPS = "SF_SOLUTIONS.CHP_OPS"


def run(session):
    df = session.sql(f"""
        SELECT order_date, region, product_family,
               SUM(total_quantity_mt) AS quantity,
               AVG(ln_price_index) AS ln_price_index,
               AVG(fuel_oil_cpi) AS fuel_cpi,
               AVG(industrial_production) AS ip
        FROM {OPS}.ML_TRAINING_DATA
        WHERE ln_quantity IS NOT NULL
        GROUP BY order_date, region, product_family
    """).to_pandas()
    fams = sorted(df["PRODUCT_FAMILY"].unique())
    key = ["ORDER_DATE", "REGION"]
    q = df.pivot_table(index=key, columns="PRODUCT_FAMILY", values="QUANTITY", aggfunc="sum")
    p = df.pivot_table(index=key, columns="PRODUCT_FAMILY", values="LN_PRICE_INDEX", aggfunc="mean")
    c = df.groupby(key)[["FUEL_CPI", "IP"]].mean()
    data = pd.concat([np.log(q.clip(lower=0.01)).add_prefix("LNQ_"), p.add_prefix("LNP_"), c], axis=1).dropna()
    for col in ("FUEL_CPI", "IP"):
        sd = data[col].std()
        data[col] = (data[col] - data[col].mean()) / sd if sd > 0 else 0.0
    X = sm.add_constant(data[[f"LNP_{f}" for f in fams] + ["FUEL_CPI", "IP"]].astype(float))

    version = "sur_v1_" + dt.date.today().strftime("%Y%m%d")
    rows = []
    for d in fams:
        m = sm.OLS(data[f"LNQ_{d}"].astype(float), X).fit()
        for pf in fams:
            col = f"LNP_{pf}"
            e, pv = float(m.params[col]), float(m.pvalues[col])
            own = d == pf
            rel = "own_price" if own else ("substitute" if e > 0 and pv < 0.05 else
                                           "complement" if e < 0 and pv < 0.05 else "independent")
            rows.append({
                "MODEL_VERSION": version, "DEMAND_PRODUCT_ID": d.upper(), "DEMAND_PRODUCT_NAME": d,
                "PRICE_PRODUCT_ID": pf.upper(), "PRICE_PRODUCT_NAME": pf, "ELASTICITY": e,
                "STD_ERROR": float(m.bse[col]), "T_STATISTIC": float(m.tvalues[col]), "P_VALUE": pv,
                "IS_OWN_PRICE": own, "IS_SIGNIFICANT": pv < 0.05, "RELATIONSHIP_TYPE": rel,
            })
    res = pd.DataFrame(rows)
    cols = list(res.columns)
    session.write_pandas(res, "TMP_ELASTICITY_MATRIX", auto_create_table=True, table_type="temporary", overwrite=True)
    session.sql(f"DELETE FROM {OPS}.ELASTICITY_MATRIX").collect()
    session.sql(f"INSERT INTO {OPS}.ELASTICITY_MATRIX ({', '.join(cols)}) "
                f"SELECT {', '.join(cols)} FROM TMP_ELASTICITY_MATRIX").collect()
    session.sql(f"DELETE FROM {OPS}.MODEL_METADATA WHERE model_type = 'sur'").collect()
    session.sql(f"""
        INSERT INTO {OPS}.MODEL_METADATA (model_version, model_type, created_by, n_products, n_observations,
            is_active, description)
        SELECT ?, 'sur', CURRENT_USER(), ?, ?, TRUE,
               'Family-level SUR on daily x region aggregates; mix-free ln price index; CPI and IP controls'
    """, params=[version, len(fams), len(data)]).collect()
    diag = {r["DEMAND_PRODUCT_NAME"]: round(r["ELASTICITY"], 3) for r in rows if r["IS_OWN_PRICE"]}
    return {"model_version": version, "observations": len(data), "own_price_elasticities": diag}
$$;

-- -----------------------------------------------------------------------------
-- Constrained profit maximisation over family prices (notebook 04)
-- Demand: Q_i(P) = Q0_i * exp(sum_j E_ij ln(P_j / P0_j)); maximise sum (P_i - C_i) Q_i
-- subject to a minimum margin and a maximum price change.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_OPS.SP_OPTIMIZE_PRICES(
    MIN_MARGIN_PCT FLOAT DEFAULT 0.15, MAX_PRICE_CHANGE_PCT FLOAT DEFAULT 0.10)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy', 'scipy')
HANDLER = 'run'
COMMENT = 'Profit-maximising family prices from ELASTICITY_MATRIX (SLSQP) -> OPTIMAL_PRICING'
EXECUTE AS OWNER
AS
$$
import datetime as dt
import json

import numpy as np
import pandas as pd
from scipy.optimize import minimize

OPS = "SF_SOLUTIONS.CHP_OPS"


def run(session, min_margin_pct, max_price_change_pct):
    el = session.sql(f"""
        SELECT demand_product_id, price_product_id, elasticity FROM {OPS}.ELASTICITY_MATRIX
        WHERE model_version = (SELECT MAX(model_version) FROM {OPS}.ELASTICITY_MATRIX)
    """).to_pandas()
    if el.empty:
        return {"error": "ELASTICITY_MATRIX is empty; run SP_ESTIMATE_ELASTICITY_MATRIX first"}
    E = el.pivot(index="DEMAND_PRODUCT_ID", columns="PRICE_PRODUCT_ID", values="ELASTICITY")
    fams = list(E.index)
    E = E.loc[fams, fams].to_numpy(dtype=float)

    cur = session.sql(f"""
        SELECT UPPER(product_family) AS family, ANY_VALUE(product_family) AS family_name,
               SUM(total_revenue) / NULLIF(SUM(total_quantity_mt), 0) AS current_price,
               SUM(avg_variable_cost * total_quantity_mt) / NULLIF(SUM(total_quantity_mt), 0) AS variable_cost,
               SUM(total_quantity_mt) AS quantity
        FROM {OPS}.ML_TRAINING_DATA
        WHERE order_date > DATEADD(day, -30, (SELECT MAX(order_date) FROM {OPS}.ML_TRAINING_DATA))
        GROUP BY 1
    """).to_pandas().set_index("FAMILY").loc[fams]
    P0 = cur["CURRENT_PRICE"].to_numpy(dtype=float)
    C = cur["VARIABLE_COST"].to_numpy(dtype=float)
    Q0 = cur["QUANTITY"].to_numpy(dtype=float)

    def demand(P):
        return Q0 * np.exp(E @ np.log(P / P0))

    def neg_profit(P):
        return -np.sum((P - C) * demand(P))

    floor_margin = C / (1 - min_margin_pct)
    lower = np.maximum(P0 * (1 - max_price_change_pct), floor_margin)
    upper = np.maximum(P0 * (1 + max_price_change_pct), lower)
    x0 = np.clip(P0, lower, upper)
    r = minimize(neg_profit, x0=x0, method="SLSQP", bounds=list(zip(lower, upper)),
                 options={"maxiter": 1000, "ftol": 1e-9})
    P = r.x
    Q = demand(P)
    scenario = "opt_" + dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    rows = []
    for i, f in enumerate(fams):
        at_floor = bool(np.isclose(P[i], lower[i], rtol=1e-4))
        at_ceiling = bool(np.isclose(P[i], upper[i], rtol=1e-4))
        margin_binding = bool(at_floor and np.isclose(lower[i], floor_margin[i], rtol=1e-4))
        binding = [b for b, on in (("price_floor", at_floor and not margin_binding),
                                   ("min_margin", margin_binding), ("price_ceiling", at_ceiling)) if on]
        cm, pm = (P0[i] - C[i]) * Q0[i], (P[i] - C[i]) * Q[i]
        rows.append({
            "SCENARIO_ID": scenario, "PRODUCT_ID": f, "PRODUCT_NAME": cur["FAMILY_NAME"].iloc[i], "REGION": "ALL",
            "CURRENT_PRICE": P0[i], "CURRENT_VOLUME": Q0[i], "CURRENT_REVENUE": P0[i] * Q0[i], "CURRENT_MARGIN": cm,
            "OPTIMAL_PRICE": P[i], "PREDICTED_VOLUME": Q[i], "PREDICTED_REVENUE": P[i] * Q[i], "PREDICTED_MARGIN": pm,
            "PRICE_CHANGE_DOLLARS": P[i] - P0[i], "PRICE_CHANGE_PCT": (P[i] / P0[i] - 1) * 100,
            "VOLUME_CHANGE_PCT": (Q[i] / Q0[i] - 1) * 100,
            "MARGIN_CHANGE_PCT": (pm / cm - 1) * 100 if cm else None,
            "IS_AT_FLOOR": at_floor, "IS_AT_CEILING": at_ceiling, "IS_MARGIN_BINDING": margin_binding,
            "BINDING_JSON": json.dumps(binding),
        })
    res = pd.DataFrame(rows)
    cols = [c for c in res.columns if c != "BINDING_JSON"]
    session.write_pandas(res, "TMP_OPTIMAL_PRICING", auto_create_table=True, table_type="temporary", overwrite=True)
    session.sql(f"DELETE FROM {OPS}.OPTIMAL_PRICING").collect()
    session.sql(f"INSERT INTO {OPS}.OPTIMAL_PRICING ({', '.join(cols)}, BINDING_CONSTRAINTS) "
                f"SELECT {', '.join(cols)}, PARSE_JSON(BINDING_JSON)::ARRAY FROM TMP_OPTIMAL_PRICING").collect()
    total_cur = float(np.sum((P0 - C) * Q0))
    total_opt = float(np.sum((P - C) * Q))
    return {"scenario_id": scenario, "solver_success": bool(r.success), "min_margin_pct": min_margin_pct,
            "max_price_change_pct": max_price_change_pct,
            "margin_30d_current": round(total_cur), "margin_30d_optimal": round(total_opt),
            "margin_change_pct": round((total_opt / total_cur - 1) * 100, 2) if total_cur else None,
            "price_change_pct": {f: round(float(P[i] / P0[i] - 1) * 100, 2) for i, f in enumerate(fams)}}
$$;

-- -----------------------------------------------------------------------------
-- Weekly demand forecast per product x region (XGBoost on lags, price and Brent)
-- The last 8 weeks are held out to measure accuracy; the model is then refit on
-- all weeks and rolled forward 4 weeks with price and Brent held at last values.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_OPS.SP_FORECAST_DEMAND(HORIZON_WEEKS INT DEFAULT 4)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy', 'xgboost', 'scikit-learn')
HANDLER = 'run'
COMMENT = 'XGBoost weekly demand forecast per product and region -> DEMAND_FORECAST'
EXECUTE AS OWNER
AS
$$
import datetime as dt

import numpy as np
import pandas as pd
from xgboost import XGBRegressor

OPS = "SF_SOLUTIONS.CHP_OPS"
CHP_ATOMIC = "SF_SOLUTIONS.CHP_ATOMIC"
FEATURES = ["LAG_1", "LAG_2", "LAG_4", "ROLL_4", "LN_PRICE_INDEX", "BRENT", "WEEK_OF_YEAR", "PRODUCT_CODE", "REGION_CODE"]
LABELS = {"LAG_1": "VOLUME_LAST_WEEK", "LAG_2": "VOLUME_2_WEEKS_AGO", "LAG_4": "VOLUME_4_WEEKS_AGO",
          "ROLL_4": "VOLUME_4_WEEK_AVG", "LN_PRICE_INDEX": "PRICE_LEVEL", "BRENT": "CRUDE_OIL_BRENT",
          "WEEK_OF_YEAR": "SEASONALITY", "PRODUCT_CODE": "PRODUCT", "REGION_CODE": "REGION"}


def _features(w):
    w = w.sort_values(["PRODUCT_ID", "REGION", "WEEK"]).copy()
    g = w.groupby(["PRODUCT_ID", "REGION"])["VOLUME"]
    w["LAG_1"], w["LAG_2"], w["LAG_4"] = g.shift(1), g.shift(2), g.shift(4)
    w["ROLL_4"] = g.transform(lambda s: s.shift(1).rolling(4).mean())
    w["WEEK_OF_YEAR"] = pd.to_datetime(w["WEEK"]).dt.isocalendar().week.astype(int)
    return w


def run(session, horizon_weeks):
    w = session.sql(f"""
        WITH weekly AS (
            SELECT DATE_TRUNC('week', order_date) AS week, product_id, region,
                   SUM(total_quantity_mt) AS volume, AVG(ln_price_index) AS ln_price_index
            FROM {OPS}.ML_TRAINING_DATA GROUP BY 1, 2, 3
        ), brent AS (
            SELECT DATE_TRUNC('week', index_date) AS week, AVG(price_value) AS brent
            FROM {CHP_ATOMIC}.MARKET_INDEX WHERE index_code = 'CRUDE-BRENT' GROUP BY 1
        )
        SELECT w.*, b.brent FROM weekly w LEFT JOIN brent b USING (week)
        WHERE w.week < (SELECT DATE_TRUNC('week', MAX(order_date)) FROM {OPS}.ML_TRAINING_DATA)
    """).to_pandas()
    w["WEEK"] = pd.to_datetime(w["WEEK"])
    for c in ("VOLUME", "LN_PRICE_INDEX", "BRENT"):
        w[c] = w[c].astype(float)
    products, regions = sorted(w["PRODUCT_ID"].unique()), sorted(w["REGION"].unique())
    w["PRODUCT_CODE"] = w["PRODUCT_ID"].map({p: i for i, p in enumerate(products)})
    w["REGION_CODE"] = w["REGION"].map({r: i for i, r in enumerate(regions)})
    f = _features(w).dropna(subset=FEATURES)

    weeks = sorted(f["WEEK"].unique())
    cutoff = weeks[-8]
    train, test = f[f["WEEK"] < cutoff], f[f["WEEK"] >= cutoff]
    params = dict(n_estimators=300, max_depth=4, learning_rate=0.05, subsample=0.8, random_state=42)
    m = XGBRegressor(**params).fit(train[FEATURES], train["VOLUME"])
    pred = np.clip(m.predict(test[FEATURES]), 0, None)
    wape = float(np.abs(pred - test["VOLUME"]).sum() / test["VOLUME"].sum())
    rel_sd = float(np.std((test["VOLUME"] - pred) / np.maximum(pred, 1)))

    m = XGBRegressor(**params).fit(f[FEATURES], f["VOLUME"])
    imp = pd.Series(m.feature_importances_, index=FEATURES).sort_values(ascending=False)
    top = [(LABELS[k], float(v)) for k, v in imp.head(3).items()]

    hist = w[["PRODUCT_ID", "REGION", "WEEK", "VOLUME", "LN_PRICE_INDEX", "BRENT", "PRODUCT_CODE", "REGION_CODE"]].copy()
    last_week = hist["WEEK"].max()
    hist_avg = hist[hist["WEEK"] > last_week - pd.Timedelta(weeks=12)].groupby(["PRODUCT_ID", "REGION"])["VOLUME"].mean()
    last = hist[hist["WEEK"] == last_week].set_index(["PRODUCT_ID", "REGION"])
    out = []
    for h in range(1, horizon_weeks + 1):
        week = last_week + pd.Timedelta(weeks=h)
        nxt = last[["LN_PRICE_INDEX", "BRENT", "PRODUCT_CODE", "REGION_CODE"]].reset_index()
        nxt["WEEK"], nxt["VOLUME"] = week, np.nan
        fx = _features(pd.concat([hist, nxt], ignore_index=True))
        fx = fx[fx["WEEK"] == week].dropna(subset=[c for c in FEATURES if c != "LN_PRICE_INDEX"])
        fx["VOLUME"] = np.clip(m.predict(fx[FEATURES]), 0, None)
        hist = pd.concat([hist, fx[hist.columns]], ignore_index=True)
        out.append(fx)
    fc = pd.concat(out, ignore_index=True)
    today = dt.date.today()
    hist_key = list(zip(fc["PRODUCT_ID"], fc["REGION"]))
    havg = np.array([hist_avg.get(k, np.nan) for k in hist_key])
    res = pd.DataFrame({
        "FORECAST_ID": range(1, len(fc) + 1), "PRODUCT_ID": fc["PRODUCT_ID"], "REGION": fc["REGION"],
        "CUSTOMER_SEGMENT": "All segments", "FORECAST_DATE": str(today),
        "FORECAST_PERIOD_START": fc["WEEK"].dt.strftime("%Y-%m-%d"),
        "FORECAST_PERIOD_END": (fc["WEEK"] + pd.Timedelta(days=6)).dt.strftime("%Y-%m-%d"),
        "FORECAST_HORIZON": "WEEKLY", "PREDICTED_VOLUME_MT": fc["VOLUME"],
        "PREDICTION_LOWER_BOUND": np.clip(fc["VOLUME"] * (1 - 1.96 * rel_sd), 0, None),
        "PREDICTION_UPPER_BOUND": fc["VOLUME"] * (1 + 1.96 * rel_sd),
        "PREDICTION_CONFIDENCE": max(0.0, 1 - wape), "HISTORICAL_AVG_VOLUME": havg,
        "FORECAST_VS_HISTORY_PCT": (fc["VOLUME"].to_numpy() / havg - 1) * 100,
        "TOP_DRIVER_1": top[0][0], "TOP_DRIVER_1_IMPACT": top[0][1],
        "TOP_DRIVER_2": top[1][0], "TOP_DRIVER_2_IMPACT": top[1][1],
        "TOP_DRIVER_3": top[2][0], "TOP_DRIVER_3_IMPACT": top[2][1],
        "MODEL_NAME": "DEMAND_XGBOOST", "MODEL_VERSION": "xgb_v1_" + today.strftime("%Y%m%d"),
        "MODEL_MAPE": wape * 100,
    })
    cols = list(res.columns)
    session.write_pandas(res, "TMP_DEMAND_FORECAST", auto_create_table=True, table_type="temporary", overwrite=True)
    session.sql(f"DELETE FROM {OPS}.DEMAND_FORECAST").collect()
    session.sql(f"INSERT INTO {OPS}.DEMAND_FORECAST ({', '.join(cols)}) "
                f"SELECT {', '.join(cols)} FROM TMP_DEMAND_FORECAST").collect()
    return {"forecasts": len(res), "series": int(fc.groupby(["PRODUCT_ID", "REGION"]).ngroups),
            "holdout_weeks": 8, "holdout_wape_pct": round(wape * 100, 1), "top_drivers": [t[0] for t in top]}
$$;

-- -----------------------------------------------------------------------------
-- Lagged correlation of weekly demand with Brent, lags 0-8 weeks
-- Measures what the data shows; no lag is planted in the synthetic data.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_OPS.SP_ANALYZE_LAGGED_CORRELATION(MAX_LAG_WEEKS INT DEFAULT 8)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'numpy', 'scipy')
HANDLER = 'run'
COMMENT = 'Correlation of weekly demand with lagged Brent per product and region -> LAGGED_CORRELATION'
EXECUTE AS OWNER
AS
$$
import datetime as dt

import numpy as np
import pandas as pd
from scipy import stats

OPS = "SF_SOLUTIONS.CHP_OPS"
CHP_ATOMIC = "SF_SOLUTIONS.CHP_ATOMIC"


def run(session, max_lag_weeks):
    d = session.sql(f"""
        SELECT DATE_TRUNC('week', order_date) AS week, product_id, region, SUM(total_quantity_mt) AS volume
        FROM {OPS}.ML_TRAINING_DATA
        WHERE order_date < (SELECT DATE_TRUNC('week', MAX(order_date)) FROM {OPS}.ML_TRAINING_DATA)
        GROUP BY 1, 2, 3
    """).to_pandas()
    b = session.sql(f"""
        SELECT DATE_TRUNC('week', index_date) AS week, AVG(price_value) AS brent
        FROM {CHP_ATOMIC}.MARKET_INDEX WHERE index_code = 'CRUDE-BRENT' GROUP BY 1
    """).to_pandas()
    d["WEEK"], b["WEEK"] = pd.to_datetime(d["WEEK"]), pd.to_datetime(b["WEEK"])
    brent = b.set_index("WEEK")["BRENT"].astype(float).sort_index()
    rows = []
    for (pid, region), g in d.groupby(["PRODUCT_ID", "REGION"]):
        s = g.set_index("WEEK")["VOLUME"].astype(float).sort_index()
        best = None
        for lag in range(max_lag_weeks + 1):
            x = brent.shift(lag, freq="7D").reindex(s.index)
            ok = x.notna() & (s > 0)
            if ok.sum() < 20:
                continue
            r, p = stats.pearsonr(np.log(x[ok]), np.log(s[ok]))
            slope = stats.linregress(np.log(x[ok]), np.log(s[ok])).slope
            row = {"PRODUCT_ID": pid, "REGION": region, "LAG_WEEKS": lag, "CORRELATION_COEFFICIENT": float(r),
                   "CORRELATION_P_VALUE": float(p), "IS_SIGNIFICANT": bool(p < 0.05),
                   "PREDICTED_DEMAND_CHANGE_PCT": float(slope * 10), "INVENTORY_POSITIONING_DAYS": lag * 7}
            rows.append(row)
            if best is None or abs(r) > abs(best["CORRELATION_COEFFICIENT"]):
                best = row
        if best is not None:
            best["IS_OPTIMAL_LAG"] = True
    res = pd.DataFrame(rows)
    res["IS_OPTIMAL_LAG"] = res.get("IS_OPTIMAL_LAG", False)
    res["IS_OPTIMAL_LAG"] = res["IS_OPTIMAL_LAG"].fillna(False).astype(bool)
    res.insert(0, "CORRELATION_ID", range(1, len(res) + 1))
    res["ANALYSIS_DATE"] = str(dt.date.today())
    res["DEMAND_METRIC"], res["DRIVER_METRIC"] = "WEEKLY_VOLUME", "CRUDE_OIL_BRENT"
    cols = list(res.columns)
    session.write_pandas(res, "TMP_LAGGED_CORRELATION", auto_create_table=True, table_type="temporary", overwrite=True)
    session.sql(f"DELETE FROM {OPS}.LAGGED_CORRELATION").collect()
    session.sql(f"INSERT INTO {OPS}.LAGGED_CORRELATION ({', '.join(cols)}) "
                f"SELECT {', '.join(cols)} FROM TMP_LAGGED_CORRELATION").collect()
    opt = res[res["IS_OPTIMAL_LAG"]]
    return {"series": len(opt), "rows": len(res),
            "significant_series": int(opt["IS_SIGNIFICANT"].sum()),
            "median_abs_best_correlation": round(float(opt["CORRELATION_COEFFICIENT"].abs().median()), 3)}
$$;

-- -----------------------------------------------------------------------------
-- Run the whole ML pipeline in dependency order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE()
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'Runs elasticity, elasticity matrix, price optimisation, demand forecast and lag analysis'
EXECUTE AS OWNER
AS
$$
DECLARE
    linear VARIANT;
    matrix VARIANT;
    optimal VARIANT;
    forecast VARIANT;
    lagged VARIANT;
BEGIN
    CALL SF_SOLUTIONS.CHP_OPS.SP_ESTIMATE_PRICE_ELASTICITY() INTO :linear;
    CALL SF_SOLUTIONS.CHP_OPS.SP_ESTIMATE_ELASTICITY_MATRIX() INTO :matrix;
    CALL SF_SOLUTIONS.CHP_OPS.SP_OPTIMIZE_PRICES(0.15, 0.10) INTO :optimal;
    CALL SF_SOLUTIONS.CHP_OPS.SP_FORECAST_DEMAND(4) INTO :forecast;
    CALL SF_SOLUTIONS.CHP_OPS.SP_ANALYZE_LAGGED_CORRELATION(8) INTO :lagged;
    RETURN OBJECT_CONSTRUCT('price_elasticity', :linear, 'elasticity_matrix', :matrix,
                            'optimal_pricing', :optimal, 'demand_forecast', :forecast,
                            'lagged_correlation', :lagged);
END;
$$;

-- =============================================================================
-- Run the ML pipeline
-- =============================================================================

CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();

-- =============================================================================
-- Semantic view for Cortex Analyst
-- =============================================================================

DROP SEMANTIC VIEW IF EXISTS SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_MODEL;
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'SF_SOLUTIONS.CHP_OPS',
  $$
# Cortex Analyst Semantic Model - Chemicals Pricing & Supply Chain
# Matches actual table/view structure in SF_SOLUTIONS

name: chemicals_pricing_model
description: >
  Semantic model for Chemicals Integrated Pricing & Supply Chain analytics.
  Enables natural language queries about margins, pricing, demand, and market trends.

tables:
  # ==========================================================================
  # MARGIN_ANALYZER - Pre-computed profitability per transaction
  # ==========================================================================
  - name: margin_analyzer
    description: Pre-computed profitability analysis per sales transaction with full cost breakdown.
    base_table:
      database: SF_SOLUTIONS
      schema: CHP_OPS
      table: MARGIN_ANALYZER
    
    dimensions:
      - name: order_id
        expr: ORDER_ID
        data_type: TEXT
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: product_name
        synonyms: ["product", "chemical"]
        description: Product name
        expr: PRODUCT_NAME
        data_type: TEXT
      - name: product_family
        synonyms: ["family", "product type", "chemical family"]
        description: Product family (Olefins, Polymers, Aromatics, Intermediates)
        expr: PRODUCT_FAMILY
        data_type: TEXT
        sample_values: ["Olefins", "Polymers", "Aromatics", "Intermediates"]
      - name: product_category
        synonyms: ["category"]
        description: Product category
        expr: PRODUCT_CATEGORY
        data_type: TEXT
      - name: customer_id
        expr: CUSTOMER_ID
        data_type: TEXT
      - name: customer_name
        synonyms: ["customer"]
        description: Customer name
        expr: CUSTOMER_NAME
        data_type: TEXT
      - name: customer_segment
        synonyms: ["segment"]
        description: Customer segment
        expr: CUSTOMER_SEGMENT
        data_type: TEXT
        sample_values: ["Industrial", "Consumer", "Agricultural", "Automotive", "Construction"]
      - name: customer_tier
        synonyms: ["tier"]
        description: Customer tier
        expr: CUSTOMER_TIER
        data_type: TEXT
        sample_values: ["Platinum", "Gold", "Silver", "Standard"]
      - name: region
        synonyms: ["sales region", "geography"]
        description: Sales region
        expr: REGION
        data_type: TEXT
        sample_values: ["North America", "Europe", "Asia Pacific", "Latin America", "Middle East"]
      - name: sales_channel
        synonyms: ["channel"]
        description: Sales channel
        expr: SALES_CHANNEL
        data_type: TEXT
        sample_values: ["Direct", "Distributor", "Spot", "Contract"]
      - name: margin_status
        synonyms: ["deal status", "pricing status"]
        description: Margin classification (LOSS, UNDERPRICED, BELOW_TARGET, ON_TARGET)
        expr: MARGIN_STATUS
        data_type: TEXT
        sample_values: ["LOSS", "UNDERPRICED", "BELOW_TARGET", "ON_TARGET"]

    time_dimensions:
      - name: order_date
        synonyms: ["date", "transaction date"]
        description: Order date
        expr: ORDER_DATE
        data_type: DATE
      - name: order_month
        description: Order month
        expr: ORDER_MONTH
        data_type: DATE
      - name: order_quarter
        description: Order quarter
        expr: ORDER_QUARTER
        data_type: DATE

    facts:
      - name: sales_volume_mt
        synonyms: ["volume", "quantity", "tons"]
        description: Sales volume in metric tons
        expr: SALES_VOLUME_MT
        data_type: NUMBER
      - name: selling_price_per_mt
        synonyms: ["price", "ASP", "selling price"]
        description: Selling price per metric ton
        expr: SELLING_PRICE_PER_MT
        data_type: NUMBER
      - name: gross_revenue
        synonyms: ["revenue"]
        description: Gross revenue before discounts
        expr: GROSS_REVENUE
        data_type: NUMBER
      - name: net_revenue
        description: Net revenue after discounts and rebates
        expr: NET_REVENUE
        data_type: NUMBER
      - name: discount_amount
        synonyms: ["discounts"]
        description: Discount amount
        expr: DISCOUNT_AMOUNT
        data_type: NUMBER
      - name: rebate_amount
        synonyms: ["rebates"]
        description: Rebate amount
        expr: REBATE_AMOUNT
        data_type: NUMBER
      - name: freight_cost
        synonyms: ["freight", "logistics cost"]
        description: Freight cost
        expr: FREIGHT_COST
        data_type: NUMBER
      - name: feedstock_cost_per_mt
        synonyms: ["feedstock cost", "raw material cost"]
        description: Feedstock cost per metric ton
        expr: FEEDSTOCK_COST_PER_MT
        data_type: NUMBER
      - name: total_cost
        description: Total cost
        expr: TOTAL_COST
        data_type: NUMBER
      - name: gross_margin
        synonyms: ["margin", "profit"]
        description: Gross margin in dollars
        expr: GROSS_MARGIN
        data_type: NUMBER
      - name: gross_margin_pct
        synonyms: ["margin percent", "margin %"]
        description: Gross margin percentage
        expr: GROSS_MARGIN_PCT
        data_type: NUMBER
      - name: margin_variance_to_target
        synonyms: ["variance"]
        description: Margin variance to target
        expr: MARGIN_VARIANCE_TO_TARGET
        data_type: NUMBER

    metrics:
      - name: total_revenue
        description: Total net revenue
        expr: SUM(margin_analyzer.NET_REVENUE)
      - name: total_volume
        description: Total volume in metric tons
        expr: SUM(margin_analyzer.SALES_VOLUME_MT)
      - name: total_margin
        description: Total gross margin
        expr: SUM(margin_analyzer.GROSS_MARGIN)
      - name: avg_margin_pct
        description: Average margin percentage
        expr: AVG(margin_analyzer.GROSS_MARGIN_PCT)
      - name: avg_selling_price
        description: Average selling price per MT
        expr: AVG(margin_analyzer.SELLING_PRICE_PER_MT)
      - name: deal_count
        description: Number of deals
        expr: COUNT(DISTINCT margin_analyzer.ORDER_ID)
      - name: underpriced_deals
        description: Number of underpriced deals
        expr: SUM(CASE WHEN margin_analyzer.MARGIN_STATUS IN ('LOSS', 'UNDERPRICED') THEN 1 ELSE 0 END)

  # ==========================================================================
  # MARKET_TRENDS - Market index trends
  # ==========================================================================
  - name: market_trends
    description: Market index price trends and volatility analysis.
    base_table:
      database: SF_SOLUTIONS
      schema: CHP_OPS
      table: MARKET_TRENDS
    
    dimensions:
      - name: index_name
        synonyms: ["index", "feedstock"]
        description: Market index name
        expr: INDEX_NAME
        data_type: TEXT
      - name: index_code
        description: Index code
        expr: INDEX_CODE
        data_type: TEXT
      - name: region
        description: Index region
        expr: REGION
        data_type: TEXT
      - name: price_trend
        synonyms: ["trend"]
        description: Price trend classification
        expr: PRICE_TREND
        data_type: TEXT
        sample_values: ["SPIKE", "RISING", "STABLE", "FALLING", "CRASH"]
      - name: volatility_level
        description: Volatility classification
        expr: VOLATILITY_LEVEL
        data_type: TEXT
        sample_values: ["HIGH", "MODERATE", "LOW"]

    time_dimensions:
      - name: index_date
        synonyms: ["date"]
        description: Price date
        expr: INDEX_DATE
        data_type: DATE

    facts:
      - name: current_price
        synonyms: ["price"]
        description: Current price
        expr: CURRENT_PRICE
        data_type: NUMBER
      - name: price_change_7d
        synonyms: ["weekly change"]
        description: 7-day price change
        expr: PRICE_CHANGE_7D
        data_type: NUMBER
      - name: price_change_pct_7d
        synonyms: ["weekly change %"]
        description: 7-day price change percentage
        expr: PRICE_CHANGE_PCT_7D
        data_type: NUMBER
      - name: price_change_30d
        synonyms: ["monthly change"]
        description: 30-day price change
        expr: PRICE_CHANGE_30D
        data_type: NUMBER
      - name: price_volatility_30d
        synonyms: ["volatility"]
        description: 30-day price volatility
        expr: PRICE_VOLATILITY_30D
        data_type: NUMBER

  # ==========================================================================
  # INVENTORY_HEALTH - Inventory analysis
  # ==========================================================================
  - name: inventory_health
    description: Inventory health status with days of supply analysis.
    base_table:
      database: SF_SOLUTIONS
      schema: CHP_OPS
      table: INVENTORY_HEALTH
    
    dimensions:
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: product_name
        synonyms: ["product"]
        description: Product name
        expr: PRODUCT_NAME
        data_type: TEXT
      - name: product_family
        description: Product family
        expr: PRODUCT_FAMILY
        data_type: TEXT
      - name: site_id
        expr: SITE_ID
        data_type: TEXT
      - name: site_name
        synonyms: ["site", "location"]
        description: Site name
        expr: SITE_NAME
        data_type: TEXT
      - name: region
        description: Region
        expr: REGION
        data_type: TEXT
      - name: inventory_status
        synonyms: ["status"]
        description: Inventory status
        expr: INVENTORY_STATUS
        data_type: TEXT
        sample_values: ["CRITICAL", "LOW", "HEALTHY", "EXCESS"]
      - name: age_status
        description: Inventory age status
        expr: AGE_STATUS
        data_type: TEXT
        sample_values: ["FRESH", "MATURING", "AGED"]

    facts:
      - name: total_inventory_mt
        synonyms: ["inventory", "stock"]
        description: Total inventory in metric tons
        expr: TOTAL_INVENTORY_MT
        data_type: NUMBER
      - name: quantity_available_mt
        synonyms: ["available"]
        description: Available quantity
        expr: QUANTITY_AVAILABLE_MT
        data_type: NUMBER
      - name: days_of_supply
        synonyms: ["DOS", "days supply"]
        description: Days of supply
        expr: DAYS_OF_SUPPLY
        data_type: NUMBER
      - name: inventory_value
        synonyms: ["value"]
        description: Inventory value
        expr: INVENTORY_VALUE
        data_type: NUMBER
      - name: working_capital_tied
        synonyms: ["working capital"]
        description: Working capital tied up
        expr: WORKING_CAPITAL_TIED
        data_type: NUMBER

    metrics:
      - name: total_inventory_value
        description: Total inventory value
        expr: SUM(inventory_health.INVENTORY_VALUE)
      - name: avg_days_of_supply
        description: Average days of supply
        expr: AVG(inventory_health.DAYS_OF_SUPPLY)
      - name: critical_inventory_count
        description: Count of products with critical inventory
        expr: SUM(CASE WHEN inventory_health.INVENTORY_STATUS = 'CRITICAL' THEN 1 ELSE 0 END)

  # ==========================================================================
  # DEMAND_FORECAST - ML predictions
  # ==========================================================================
  - name: demand_forecast
    description: ML demand forecasts by product and region.
    base_table:
      database: SF_SOLUTIONS
      schema: CHP_OPS
      table: DEMAND_FORECAST
    
    dimensions:
      - name: product_id
        expr: PRODUCT_ID
        data_type: TEXT
      - name: region
        description: Forecast region
        expr: REGION
        data_type: TEXT
      - name: customer_segment
        description: Customer segment
        expr: CUSTOMER_SEGMENT
        data_type: TEXT
      - name: forecast_horizon
        description: Forecast horizon (WEEKLY, MONTHLY, QUARTERLY)
        expr: FORECAST_HORIZON
        data_type: TEXT
      - name: top_driver_1
        synonyms: ["main driver"]
        description: Top demand driver
        expr: TOP_DRIVER_1
        data_type: TEXT

    time_dimensions:
      - name: forecast_date
        description: Date forecast was generated
        expr: FORECAST_DATE
        data_type: DATE
      - name: forecast_period_start
        description: Forecast period start
        expr: FORECAST_PERIOD_START
        data_type: DATE

    facts:
      - name: predicted_volume_mt
        synonyms: ["forecast volume", "predicted demand"]
        description: Predicted volume in metric tons
        expr: PREDICTED_VOLUME_MT
        data_type: NUMBER
      - name: prediction_confidence
        synonyms: ["confidence"]
        description: Prediction confidence score
        expr: PREDICTION_CONFIDENCE
        data_type: NUMBER
      - name: forecast_vs_history_pct
        description: Forecast vs historical average percentage change
        expr: FORECAST_VS_HISTORY_PCT
        data_type: NUMBER

  # ==========================================================================
  # OPTIMAL_PRICING - Price recommendations (SP_OPTIMIZE_PRICES)
  # ==========================================================================
  - name: optimal_pricing
    description: >-
      Profit-maximising price recommendation per product family from the latest optimisation run
      (minimum 15% margin, at most +/-10% price change). REGION is 'ALL'.
    base_table:
      database: SF_SOLUTIONS
      schema: CHP_OPS
      table: OPTIMAL_PRICING

    dimensions:
      - name: product_family
        synonyms: ["product family", "family"]
        description: Product family (Olefins, Polymers, Aromatics, Intermediates)
        expr: PRODUCT_NAME
        data_type: TEXT
        sample_values: ["Olefins", "Polymers", "Aromatics", "Intermediates"]
      - name: scenario_id
        description: Optimisation run identifier
        expr: SCENARIO_ID
        data_type: TEXT

    time_dimensions:
      - name: run_date
        description: When the optimisation ran
        expr: RUN_DATE
        data_type: TIMESTAMP

    facts:
      - name: current_price
        synonyms: ["current price"]
        description: Volume-weighted price per MT over the last 30 days
        expr: CURRENT_PRICE
        data_type: NUMBER
      - name: optimal_price
        synonyms: ["optimal price", "recommended price"]
        description: Recommended price per MT
        expr: OPTIMAL_PRICE
        data_type: NUMBER
      - name: price_change_pct
        description: Recommended price change in percent
        expr: PRICE_CHANGE_PCT
        data_type: NUMBER
      - name: volume_change_pct
        description: Predicted volume change in percent at the recommended price
        expr: VOLUME_CHANGE_PCT
        data_type: NUMBER
      - name: current_margin
        description: Contribution margin over the last 30 days at current prices
        expr: CURRENT_MARGIN
        data_type: NUMBER
      - name: predicted_margin
        description: Predicted contribution margin at the recommended price
        expr: PREDICTED_MARGIN
        data_type: NUMBER

  # ==========================================================================
  # ELASTICITY_MATRIX - Cross-price elasticities between families (SUR)
  # ==========================================================================
  - name: elasticity_matrix
    description: >-
      Estimated price elasticities between product families. A row says how demand for
      DEMAND_FAMILY changes (in %) when the price of PRICE_FAMILY rises 1%. Own-price rows have
      IS_OWN_PRICE = TRUE; positive cross-price values mean substitutes.
    base_table:
      database: SF_SOLUTIONS
      schema: CHP_OPS
      table: ELASTICITY_MATRIX

    dimensions:
      - name: demand_family
        description: Family whose demand responds
        expr: DEMAND_PRODUCT_NAME
        data_type: TEXT
        sample_values: ["Olefins", "Polymers", "Aromatics", "Intermediates"]
      - name: price_family
        description: Family whose price changed
        expr: PRICE_PRODUCT_NAME
        data_type: TEXT
      - name: relationship_type
        description: own_price, substitute, complement or independent
        expr: RELATIONSHIP_TYPE
        data_type: TEXT
      - name: is_own_price
        description: TRUE for own-price elasticity
        expr: IS_OWN_PRICE
        data_type: BOOLEAN

    facts:
      - name: elasticity
        synonyms: ["price elasticity", "price sensitivity"]
        description: Estimated elasticity
        expr: ELASTICITY
        data_type: NUMBER
      - name: std_error
        description: Standard error of the estimate
        expr: STD_ERROR
        data_type: NUMBER
      - name: p_value
        description: p-value of the estimate
        expr: P_VALUE
        data_type: NUMBER

# ==========================================================================
# Verified Queries
# ==========================================================================
verified_queries:
  - name: margin_by_region_quarter
    question: "Show me the average margin for Ethylene products in Europe vs North America for Q3"
    use_as_onboarding_question: true
    sql: |
      SELECT REGION, AVG(GROSS_MARGIN_PCT) as AVG_MARGIN_PCT, SUM(GROSS_MARGIN) as TOTAL_MARGIN
      FROM __margin_analyzer
      WHERE PRODUCT_FAMILY = 'Olefins' 
        AND REGION IN ('Europe', 'North America')
        AND QUARTER(ORDER_DATE) = 3
      GROUP BY REGION
      ORDER BY AVG_MARGIN_PCT DESC

  - name: underpriced_deals
    question: "How many deals were underpriced this month?"
    use_as_onboarding_question: true
    sql: |
      SELECT MARGIN_STATUS, COUNT(*) as DEAL_COUNT, SUM(GROSS_MARGIN) as TOTAL_MARGIN_IMPACT
      FROM __margin_analyzer
      WHERE ORDER_DATE >= DATE_TRUNC('month', CURRENT_DATE())
      GROUP BY MARGIN_STATUS
      ORDER BY CASE MARGIN_STATUS WHEN 'LOSS' THEN 1 WHEN 'UNDERPRICED' THEN 2 WHEN 'BELOW_TARGET' THEN 3 ELSE 4 END

  - name: feedstock_trend
    question: "What is the trend in Propylene prices this week?"
    use_as_onboarding_question: true
    sql: |
      SELECT INDEX_NAME, CURRENT_PRICE, PRICE_CHANGE_PCT_7D, PRICE_TREND
      FROM __market_trends
      WHERE INDEX_NAME LIKE '%Propylene%'
      ORDER BY INDEX_DATE DESC
      LIMIT 5

  - name: inventory_at_risk
    question: "Which products have critical inventory levels?"
    use_as_onboarding_question: true
    sql: |
      SELECT PRODUCT_NAME, SITE_NAME, QUANTITY_AVAILABLE_MT, DAYS_OF_SUPPLY, INVENTORY_STATUS
      FROM __inventory_health
      WHERE INVENTORY_STATUS IN ('CRITICAL', 'LOW')
      ORDER BY DAYS_OF_SUPPLY ASC

  - name: margin_by_customer_segment
    question: "What is the margin by customer segment?"
    sql: |
      SELECT CUSTOMER_SEGMENT, AVG(GROSS_MARGIN_PCT) as AVG_MARGIN_PCT, 
             SUM(SALES_VOLUME_MT) as TOTAL_VOLUME, SUM(GROSS_MARGIN) as TOTAL_MARGIN
      FROM __margin_analyzer
      GROUP BY CUSTOMER_SEGMENT
      ORDER BY TOTAL_MARGIN DESC

  - name: top_products_by_margin
    question: "What are the top products by margin?"
    sql: |
      SELECT PRODUCT_NAME, PRODUCT_FAMILY, SUM(GROSS_MARGIN) as TOTAL_MARGIN,
             AVG(GROSS_MARGIN_PCT) as AVG_MARGIN_PCT, SUM(SALES_VOLUME_MT) as TOTAL_VOLUME
      FROM __margin_analyzer
      GROUP BY PRODUCT_NAME, PRODUCT_FAMILY
      ORDER BY TOTAL_MARGIN DESC
      LIMIT 10

  - name: pricing_recommendation
    question: "What should we charge for Polymers?"
    sql: |
      SELECT PRODUCT_FAMILY, CURRENT_PRICE, OPTIMAL_PRICE, PRICE_CHANGE_PCT, VOLUME_CHANGE_PCT,
             CURRENT_MARGIN, PREDICTED_MARGIN
      FROM __optimal_pricing
      WHERE PRODUCT_FAMILY = 'Polymers'

  - name: own_price_elasticity
    question: "How price sensitive is demand for each product family?"
    sql: |
      SELECT DEMAND_FAMILY, ELASTICITY, STD_ERROR
      FROM __elasticity_matrix
      WHERE IS_OWN_PRICE = TRUE
      ORDER BY ELASTICITY

custom_instructions: >
  This semantic model covers Chemicals Pricing & Supply Chain operations.
  Key entities: Products (chemicals by CAS number), Customers (by segment/tier), Sales Orders, Production Runs.
  Measures: Gross_Margin, Sales_Volume_MT, Avg_Selling_Price, Feedstock_Cost.
  Dimensions: Product_Family (Olefins, Polymers, Aromatics, Intermediates), Region, Customer_Segment, Sales_Channel.
  Margin status: LOSS (negative margin), UNDERPRICED (<50% of target), BELOW_TARGET, ON_TARGET.
  Price trends: SPIKE (>10%), RISING (>5%), STABLE, FALLING (<-5%), CRASH (<-10%).
  Use MARGIN_ANALYZER for profitability analysis. Use MARKET_TRENDS for feedstock prices.
  Use INVENTORY_HEALTH for stock analysis. Use OPTIMAL_PRICING for price recommendations
  and ELASTICITY_MATRIX for price sensitivity.
$$
);

-- =============================================================================
-- Cortex Search over market reports
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

-- =============================================================================
-- 1. CREATE DOCUMENT CHUNKS TABLE
-- =============================================================================
-- Rebuilt on every run so re-deploying does not duplicate passages
CREATE OR REPLACE TABLE MARKET_REPORT_CHUNKS (
    chunk_id NUMBER AUTOINCREMENT PRIMARY KEY,
    report_id INTEGER,
    report_date DATE,
    report_type VARCHAR(100),
    report_title VARCHAR(500),
    report_source VARCHAR(100),
    chemical_name VARCHAR(100),
    region VARCHAR(50),
    chunk VARCHAR(16000),
    chunk_index INTEGER,
    language VARCHAR(50) DEFAULT 'English',
    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Enable change tracking for search service
ALTER TABLE MARKET_REPORT_CHUNKS SET CHANGE_TRACKING = TRUE;

-- =============================================================================
-- 2. POPULATE CHUNKS FROM CHP_RAW MARKET REPORTS
-- =============================================================================
INSERT INTO MARKET_REPORT_CHUNKS (
    report_id, report_date, report_type, report_title, report_source,
    chemical_name, region, chunk, chunk_index
)
SELECT 
    report_id,
    TO_DATE(report_date),
    report_type,
    report_title,
    report_source,
    chemical_name,
    region,
    -- Combine title, summary, and content into searchable chunk
    report_title || '\n\n' ||
    'Source: ' || report_source || ' | Date: ' || report_date || ' | Region: ' || region || '\n\n' ||
    'Chemical: ' || chemical_name || '\n\n' ||
    'Summary: ' || report_summary || '\n\n' ||
    'Full Report:\n' || report_content AS chunk,
    1 AS chunk_index
FROM CHP_RAW.MARKET_REPORTS;

-- =============================================================================
-- 3. CREATE CORTEX SEARCH SERVICE
-- Service name: MARKET_INTEL_SEARCH
-- Sample prompt: "What are the supply constraints for Propylene in Asia reported in the last month?"
-- =============================================================================
CREATE OR REPLACE CORTEX SEARCH SERVICE MARKET_INTEL_SEARCH
    ON chunk
    ATTRIBUTES chemical_name, region, report_date, report_type, report_source
    WAREHOUSE = SF_SOLUTIONS_WH
    TARGET_LAG = '1 hour'
    EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'
AS (
    SELECT 
        chunk_id,
        chunk,
        chemical_name,
        region,
        report_date,
        report_type,
        report_source,
        report_title
    FROM MARKET_REPORT_CHUNKS
);

-- =============================================================================
-- 4. VERIFY DEPLOYMENT
-- =============================================================================
SELECT 'MARKET_REPORT_CHUNKS' as table_name, COUNT(*) as row_count FROM MARKET_REPORT_CHUNKS;

SELECT chemical_name, region, COUNT(*) as report_count 
FROM MARKET_REPORT_CHUNKS 
GROUP BY chemical_name, region
ORDER BY report_count DESC
LIMIT 20;

-- =============================================================================
-- 5. TEST SEARCH (uncomment after service is ready ~5 mins)
-- =============================================================================
-- Sample query: "What are the supply constraints for Propylene in Asia reported in the last month?"
/*
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'SF_SOLUTIONS.CHP_OPS.MARKET_INTEL_SEARCH',
        '{
            "query": "supply constraints for Propylene in Asia", 
            "columns": ["chunk", "chemical_name", "region", "report_date", "report_source"], 
            "filter": {"@gte": {"report_date": "2024-12-01"}},
            "limit": 5
        }'
    )
)['results'] AS search_results;
*/

-- =============================================================================
-- 6. GRANTS
-- =============================================================================
GRANT SELECT ON TABLE MARKET_REPORT_CHUNKS TO ROLE PUBLIC;
-- Note: Search service permissions are managed separately

SHOW CORTEX SEARCH SERVICES IN SCHEMA CHP_OPS;

SELECT 'Cortex Search service MARKET_INTEL_SEARCH deployed successfully!' AS status;

-- =============================================================================
-- Cortex Agent
-- =============================================================================

USE DATABASE SF_SOLUTIONS;
USE SCHEMA CHP_OPS;

CREATE OR REPLACE AGENT SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_AGENT
  COMMENT = 'Intelligent Chemicals Pricing & Supply Chain Agent. Provides natural language analytics over margins, pricing guidance, demand forecasts, market intelligence, and inventory health. Helps pricing managers, supply chain planners, and commercial teams optimize profitability and make data-driven pricing decisions.'
  FROM SPECIFICATION $$
{
  "models": {
    "orchestration": "auto"
  },
  "instructions": {
    "response": "**Format Guidelines:**\n1. **Lead with direct answers**: State key findings in the first sentence\n2. **Provide context**: Include relevant time periods, products, regions, and metrics\n3. **Use chemicals industry metrics**: Margins (%), Volume (MT), Price ($/MT), Feedstock costs\n4. **Highlight risks**: Call out LOSS and UNDERPRICED deals explicitly\n5. **Suggest follow-ups**: Recommend deeper analysis when appropriate\n\n**Response Structure:**\n```\n[Direct Answer]\n- Key Finding 1 with metric\n- Key Finding 2 with metric\n- Key Finding 3 with metric\n\n[Context & Analysis]\nBrief interpretation of results and commercial implications.\n\n[Action Items] (if margin issues identified)\nRecommended pricing adjustments or interventions.\n```\n\n**Tone:** Professional, concise, data-driven. Use chemicals industry terminology appropriately. Focus on actionable insights for pricing decisions.\n\n**Confidence Indicators:** If data is incomplete or assumptions are made, explicitly state limitations.",
    "orchestration": "**Business Context:**\nThis is a chemicals manufacturing company producing olefins, polymers, aromatics, and intermediates. Products are sold globally across North America, Europe, Asia Pacific, Latin America, and Middle East. Customer segments include Industrial, Consumer, Agricultural, Automotive, and Construction.\n\n**Tool Routing Logic:**\n\n1. **Route to Chemicals_Pricing_Analyst** when questions mention:\n   - Margins, profitability, gross margin, margin percent\n   - Sales volume, revenue, pricing, ASP\n   - Products, chemicals, product families (Olefins, Polymers, Aromatics)\n   - Customers, customer segments, customer tiers\n   - Regions, sales channels (Direct, Distributor, Spot, Contract)\n   - Market indices, feedstock prices, price trends\n   - Inventory, days of supply, stock levels\n   - Underpriced deals, LOSS status, margin leakage\n   - DO NOT use for: market report text, analyst commentary, news\n\n2. **Route to Market_Intel_Search** when questions mention:\n   - Market reports, analyst commentary, market outlook\n   - Industry news, supply/demand dynamics\n   - Price forecasts, market sentiment\n   - Competitor intelligence, market share\n   - Regional market conditions, trade flows\n   - DO NOT use for: structured data queries, exact numbers, transaction data\n\n**Multi-Tool Queries:**\nFor comprehensive analysis (e.g., \"Why are Ethylene margins declining and what does the market say?\"):\n1. Query Chemicals_Pricing_Analyst for margin trends and transaction data\n2. Query Market_Intel_Search for market context and analyst insights\n3. Synthesize findings into actionable pricing recommendations\n\n**Data Schema Reference:**\n\n**Product Families:** Olefins, Polymers, Aromatics, Intermediates\n**Regions:** North America, Europe, Asia Pacific, Latin America, Middle East\n**Customer Segments:** Industrial, Consumer, Agricultural, Automotive, Construction\n**Customer Tiers:** Platinum, Gold, Silver, Standard\n**Sales Channels:** Direct, Distributor, Spot, Contract\n**Margin Status:** LOSS (negative), UNDERPRICED (<50% of target), BELOW_TARGET, ON_TARGET\n**Price Trends:** SPIKE (>10%), RISING (>5%), STABLE, FALLING (<-5%), CRASH (<-10%)\n**Inventory Status:** CRITICAL, LOW, HEALTHY, EXCESS\n\n**Key Metrics:**\n- gross_margin_pct: Target is 30%+ for most products\n- sales_volume_mt: Volume in metric tons\n- selling_price_per_mt: Price per metric ton in USD\n- feedstock_cost_per_mt: Raw material cost per MT\n- days_of_supply: Inventory coverage (target: 15-30 days)\n\n**Temporal Context:**\n- Transaction data: Rolling 24 months\n- Market indices: Daily updates\n- Demand forecasts: Weekly/Monthly/Quarterly horizons",
    "sample_questions": [
      {
        "question": "Show me the average margin for Ethylene products in Europe vs North America for Q3"
      },
      {
        "question": "How many deals were underpriced this month?"
      },
      {
        "question": "What is the trend in Propylene prices?"
      },
      {
        "question": "Which products have critical inventory levels?"
      },
      {
        "question": "What is the margin by customer segment?"
      },
      {
        "question": "What price does the optimizer recommend for Polymers?"
      },
      {
        "question": "What is the market outlook for polyethylene?"
      },
      {
        "question": "Show me top products by margin contribution"
      },
      {
        "question": "How price sensitive is demand for each product family?"
      }
    ]
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "Chemicals_Pricing_Analyst",
        "description": "Query structured operational data for chemicals pricing and supply chain. Use for: margins and profitability (gross margin, margin %, revenue), sales transactions (volume MT, price per MT, discounts), products (by family, category, CAS number), customers (segments, tiers), regional analysis, feedstock costs, inventory health (days of supply, stock levels), price guidance, demand forecasts, optimal prices by product family and price elasticities. DO NOT use for: unstructured market reports, analyst commentary, news articles."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "Market_Intel_Search",
        "description": "Search market intelligence reports and analyst commentary. Use for: market outlook, price forecasts, supply/demand dynamics, regional market conditions, competitor intelligence, industry trends, and market sentiment. DO NOT use for: structured transaction data, exact margin numbers, inventory counts."
      }
    }
  ],
  "tool_resources": {
    "Chemicals_Pricing_Analyst": {
      "semantic_view": "SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_MODEL",
      "execution_environment": {"type": "warehouse", "warehouse": "SF_SOLUTIONS_WH"}
    },
    "Market_Intel_Search": {
      "search_service": "SF_SOLUTIONS.CHP_OPS.MARKET_INTEL_SEARCH",
      "id_column": "CHUNK_ID",
      "max_results": 10,
      "title_column": "CHEMICAL_NAME"
    }
  }
}
$$;

-- Make the agent visible in Snowflake Intelligence / CoWork for every role
GRANT USAGE ON AGENT SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_AGENT TO ROLE PUBLIC;

SHOW AGENTS IN SCHEMA SF_SOLUTIONS.CHP_OPS;
