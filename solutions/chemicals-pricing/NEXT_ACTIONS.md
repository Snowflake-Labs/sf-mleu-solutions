# Next Actions: Chemicals Pricing & Margin Intelligence

## Phase 1: Quick Exploration

1. Check the build:

   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE STARTSWITH(TABLE_SCHEMA, 'CHP_') AND TABLE_TYPE = 'BASE TABLE'
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

2. Margin health across all deals:

   ```sql
   SELECT MARGIN_STATUS, COUNT(*) AS DEALS, ROUND(SUM(GROSS_MARGIN) / 1e6, 1) AS GROSS_MARGIN_USD_M
   FROM SF_SOLUTIONS.CHP_OPS.MARGIN_ANALYZER
   GROUP BY 1 ORDER BY 2 DESC;
   ```

3. Did the model recover the price response planted in the data?

   ```sql
   SELECT m.DEMAND_PRODUCT_NAME AS FAMILY,
          ROUND(m.ELASTICITY, 2) AS ESTIMATED, ROUND(m.STD_ERROR, 2) AS STD_ERROR, p.ELASTICITY AS PLANTED
   FROM SF_SOLUTIONS.CHP_OPS.ELASTICITY_MATRIX m
   JOIN SF_SOLUTIONS.CHP_ATOMIC.DEMO_PLANTED_ELASTICITY p
     ON p.DEMAND_FAMILY = m.DEMAND_PRODUCT_NAME AND p.PRICE_FAMILY = m.PRICE_PRODUCT_NAME
   WHERE m.IS_OWN_PRICE
   ORDER BY 1;
   ```

4. Optimiser recommendations (15% minimum margin, at most ±10% price change):

   ```sql
   SELECT PRODUCT_NAME, ROUND(CURRENT_PRICE) AS CURRENT_PRICE, ROUND(OPTIMAL_PRICE) AS OPTIMAL_PRICE,
          ROUND(PRICE_CHANGE_PCT, 1) AS PRICE_CHANGE_PCT, ROUND(VOLUME_CHANGE_PCT, 1) AS VOLUME_CHANGE_PCT,
          ROUND(CURRENT_MARGIN / 1e6, 1) AS MARGIN_NOW_M, ROUND(PREDICTED_MARGIN / 1e6, 1) AS MARGIN_OPT_M,
          BINDING_CONSTRAINTS
   FROM SF_SOLUTIONS.CHP_OPS.OPTIMAL_PRICING
   ORDER BY PRODUCT_NAME;
   ```

5. Open the Streamlit app **CHEMICALS_PRICING_APP** (Projects » Streamlit) and visit:
   - **Margin Command** (home): price-vs-cost spread and margin leakage
   - **Pricing Desk**: floor and target price for a customer and product
   - **Data Science Workbench**: planted vs estimated elasticities, forecasts, lag analysis
   - **Pricing Optimizer**: change the margin floor and price limits and re-optimise

6. Open Snowflake CoWork, pick **CHEMICALS_PRICING_AGENT** and try:
   - "Show me the average margin for Olefins products in Europe vs North America"
   - "What price does the optimizer recommend for Polymers?"
   - "How price sensitive is demand for each product family?"
   - "What does the market intelligence say about supply constraints for Propylene in Asia?"
   - "Which products have critical inventory levels?"

## Phase 2: Go Deeper

1. Re-run the models with different settings (minimum margin, maximum price change, forecast horizon):

   ```sql
   CALL SF_SOLUTIONS.CHP_OPS.SP_OPTIMIZE_PRICES(0.20, 0.05);
   CALL SF_SOLUTIONS.CHP_OPS.SP_FORECAST_DEMAND(8);
   CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();   -- everything, default settings
   ```

2. Walk through the techniques in the notebooks (`notebooks/`): import them into a Snowflake
   Workspace (Projects » Workspaces » Add » Upload files) and run them with `SF_SOLUTIONS_WH`:
   - `01_data_preparation`: weekly features and the mix-free price index
   - `02_linear_elasticity`: per-product log-log elasticity
   - `03_sur_elasticity`: the cross-family elasticity system
   - `04_optimal_pricing`: constrained profit maximisation
   - `CHEMICALS_PRICING_ML_WORKBOOK`: all of the above in one notebook

3. Search the market reports directly:

   ```sql
   SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
       'SF_SOLUTIONS.CHP_OPS.MARKET_INTEL_SEARCH',
       '{"query": "polymer demand outlook in Europe", "columns": ["chunk", "chemical_name", "region"], "limit": 3}'
   ))['results'] AS RESULTS;
   ```

4. Optional: use public BLS and Federal Reserve series for the macro indicators instead of the
   synthetic ones (requires the free Snowflake Public Data listing); see `marketplace/README.md`.

## Phase 3: Make It Yours

- Replace the synthetic tables in `CHP_ATOMIC` with your ERP orders, product costs and contracts,
  keeping the column names, then run `CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();`
- Add your own market commentary to `CHP_RAW.MARKET_REPORTS` and refresh the search table
- Extend the semantic view with your own metrics and verified queries

## Teardown

```
$sf-solutions:chemicals-pricing teardown
```
