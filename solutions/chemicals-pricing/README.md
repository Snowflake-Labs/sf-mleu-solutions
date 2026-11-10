# Chemicals Pricing & Margin Intelligence

Disclaimer: This application is not part of the Snowflake Service and is governed by the terms
in LICENSE, unless expressly agreed to in writing. You use this application at your own risk,
and Snowflake has no obligation to support your use of this application. [Learn more](../../LEGAL.md)

| Field | Value |
|-------|-------|
| Edition | Enterprise |
| Trial Account | Yes |
| Author | Rishabh Raman |

Pricing and margin intelligence for a chemicals producer selling olefins, polymers, aromatics and
intermediates in five regions. Sales, cost, feedstock, inventory and contract data come together in
Snowflake. Python stored procedures estimate how demand responds to price, recommend
profit-maximising prices within margin and price-change limits, and forecast demand. Cortex Analyst,
Cortex Search and a Cortex Agent answer questions in plain English. All data is synthetic and
generated in your account at install time, for a fictional producer.

## Business problem and outcomes

- Feedstock costs move daily while many customer prices are fixed by contract or set by habit
- Pricing teams can't see cost-to-serve (feedstock + conversion + freight) per deal
- Price changes are made without an estimate of how much volume they will cost
- Cross-product effects (a polymer price rise shifting demand to another family) are ignored
- Market commentary sits in documents nobody can query

| Capability | Outcome in this demo |
|---|---|
| **Margin analysis** | `MARGIN_ANALYZER` classifies 38,691 deals: 97.3% on target, 857 below target, 149 underpriced and 27 at a loss |
| **Cost-to-serve** | `COST_TO_SERVE` and `PRICE_GUIDANCE` compute feedstock, conversion and freight cost per MT and a floor / target price per product and region |
| **Price elasticity** | The synthetic orders contain a known (planted) price response. The SUR model recovers it: own-price elasticities estimated at -1.55 / -2.26 / -2.18 / -2.84 (Aromatics / Intermediates / Olefins / Polymers) against planted -1.6 / -2.2 / -1.8 / -2.5, standard errors 0.12-0.14 |
| **Price optimisation** | With a 15% minimum margin and at most ±10% price change, the optimiser lowers Polymers prices 10% (+41% volume) and raises the other three families 10%; 30-day contribution margin rises from $409.6M to $450.1M at the estimated elasticities |
| **Demand forecast** | XGBoost weekly forecasts for 95 product × region series, 4 weeks ahead; weighted absolute percentage error on an 8-week holdout is 37.5%, typical for noisy weekly series at this grain |
| **Crude-oil lag analysis** | Correlation of weekly demand with Brent 0-8 weeks earlier, per series, measured on the data (no lag is planted) |
| **Ask in plain English** | Cortex Analyst over a semantic view (margins, market trends, inventory, forecasts, optimal prices, elasticities), Cortex Search over 161 market reports, and a Cortex Agent combining both |

The elasticity and optimisation results describe the synthetic data, not real markets. With
constant-elasticity demand the optimum usually sits on a price bound, so the recommendation is a
direction and a cap, not a precise price.

## Architecture

```
CHP_RAW.SP_GENERATE_DATA (Python) ──► CSV files on CHP_RAW.DATA_STAGE ──► CHP_RAW / CHP_ATOMIC tables
                                                                              │
CHP_OPS views     MARGIN_ANALYZER, COST_TO_SERVE, PRICE_GUIDANCE, INVENTORY_HEALTH,
                  MARGIN_LEAKAGE, MARKET_TRENDS, MACRO_* indicators
                                                                              │
CHP_OPS Python    SP_RUN_ML_PIPELINE: price elasticity · SUR elasticity matrix ·
procedures        price optimisation · XGBoost demand forecast · lagged correlation
                                                                              │
CHP_OPS Cortex    semantic view CHEMICALS_PRICING_MODEL · MARKET_INTEL_SEARCH · CHEMICALS_PRICING_AGENT
                                                                              │
Streamlit app CHEMICALS_PRICING_APP (7 pages)        notebooks/  the same techniques, step by step
```

## What gets installed

| Layer | Objects |
|---|---|
| Database / warehouse | Shared `SF_SOLUTIONS` database and `SF_SOLUTIONS_WH` (LARGE) warehouse, created if missing |
| Schemas | `CHP_RAW`, `CHP_ATOMIC`, `CHP_OPS` |
| Data | 19 products, 200 customers, 6 sites, 14 market indices, about 39,000 sales orders over 12 months, production runs, inventory, contracts, 161 market reports |
| Python procedures | `CHP_RAW.SP_GENERATE_DATA`; `CHP_OPS.SP_ESTIMATE_PRICE_ELASTICITY`, `SP_ESTIMATE_ELASTICITY_MATRIX`, `SP_OPTIMIZE_PRICES`, `SP_FORECAST_DEMAND`, `SP_ANALYZE_LAGGED_CORRELATION`, and `SP_RUN_ML_PIPELINE` (runs them all) |
| AI | Semantic view `CHP_OPS.CHEMICALS_PRICING_MODEL`, Cortex Search service `CHP_OPS.MARKET_INTEL_SEARCH`, Cortex Agent `CHP_OPS.CHEMICALS_PRICING_AGENT` |
| App | Streamlit app `CHP_OPS.CHEMICALS_PRICING_APP` |

## Quick start

### Install with Cortex Code

```
$sf-solutions:chemicals-pricing
```

### Install manually

Run as `ACCOUNTADMIN` from this directory, in this order:

```bash
snow sql -f scripts/setup.sql    --enable-templating NONE
snow sql -f scripts/data.sql     --enable-templating NONE
snow sql -f scripts/pipeline.sql --enable-templating NONE

# Streamlit app files, then the app
STAGE=@SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE
snow sql -q "PUT 'file://$PWD/streamlit/streamlit_app.py' $STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
snow sql -q "PUT 'file://$PWD/streamlit/environment.yml' $STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
snow sql -q "PUT 'file://$PWD/streamlit/pages/*.py' $STAGE/pages/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
snow sql -q "PUT 'file://$PWD/streamlit/utils/*.py' $STAGE/utils/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
snow sql -f scripts/streamlit.sql --enable-templating NONE
```

`--enable-templating NONE` is required because the scripts contain `&` characters.

Measured on a LARGE warehouse, across three installs:

| Script | Time |
|---|---|
| `setup.sql` | under 1 min |
| `data.sql` | about 1 min |
| `pipeline.sql` | about 3 min (the ML procedures run once) |
| App upload and `streamlit.sql` | under 1 min |

**Cortex models.** The Ask Cortex page calls `SNOWFLAKE.CORTEX.COMPLETE` with `mistral-large2`,
Cortex Search embeds with `snowflake-arctic-embed-m-v1.5`, and the agent uses automatic model
selection. If a model isn't available in your region, enable cross-region inference.

**Dates and reproducibility.** The data covers the 12 months up to the most recent Monday before
the install. The generator is seeded and the window moves in whole weeks, so every install produces the
same orders, prices and volumes and the figures above. The monthly macro indicators are aligned to
calendar months, so model results can move slightly between installs in different months.

## Try it

**Streamlit app** (Projects » Streamlit » `CHEMICALS_PRICING_APP`):

| Page | What it shows |
|---|---|
| Margin Command | Price-vs-cost spread, margin leakage waterfall, regional margins, underpriced deals |
| Pricing Desk | Floor / target price, cost breakdown and contract terms for a customer and product |
| Data Science Workbench | Planted vs estimated elasticity matrix, per-product elasticity, forecast vs actual, forecast drivers, lag analysis, what-if |
| Market Intelligence | Cortex Search over market reports |
| Ask Cortex | Natural-language questions answered with `COMPLETE` and the data-mart context |
| Market Data | Macro indicators (fuel-oil CPI, core CPI, industrial production) and their data source |
| Pricing Optimizer | Interactive optimisation using the estimated elasticity matrix |

**Agent** (Snowflake CoWork » `CHEMICALS_PRICING_AGENT`):

- "Show me the average margin for Olefins products in Europe vs North America"
- "What price does the optimizer recommend for Polymers?"
- "How price sensitive is demand for each product family?"
- "What does the market intelligence say about supply constraints for Propylene in Asia?"
- "Which products have critical inventory levels?"

**Models in SQL:**

```sql
CALL SF_SOLUTIONS.CHP_OPS.SP_OPTIMIZE_PRICES(0.20, 0.05);  -- 20% minimum margin, ±5% price change
CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();            -- recompute everything with defaults
```

## Notebooks

`notebooks/` walks through the same techniques interactively. Import them into a Snowflake
Workspace and run them with `SF_SOLUTIONS_WH`:

| Notebook | Technique |
|---|---|
| `01_data_preparation` | Weekly features and the mix-free price index |
| `02_linear_elasticity` | Per-product log-log elasticity with macro and seasonal controls |
| `03_sur_elasticity` | The cross-family elasticity system (seemingly unrelated regressions) |
| `04_optimal_pricing` | Constrained profit maximisation |
| `CHEMICALS_PRICING_ML_WORKBOOK` | All of the above in one notebook |

The notebooks read the same tables as the stored procedures; the procedures are what the install
runs.

## Data scale

| Table | Rows |
|---|---|
| `CHP_ATOMIC.PRODUCT` / `CUSTOMER` / `SITE` | 19 / 200 / 6 |
| `CHP_ATOMIC.SALES_ORDER` | 38,691 |
| `CHP_ATOMIC.DEMAND_HISTORY` (weekly product × region × segment) | 19,133 |
| `CHP_ATOMIC.MARKET_INDEX` (14 indices, 2 years of weekdays) | 7,280 |
| `CHP_ATOMIC.PRODUCTION_RUN` | 6,553 |
| `CHP_ATOMIC.INVENTORY_BALANCE` / `CONTRACT_TERM` | 114 / 211 |
| `CHP_ATOMIC.MACRO_INDICATOR` (3 series × 36 months) | 108 |
| `CHP_RAW.MARKET_REPORTS` | 161 |

## Optional: public macro data

The models use monthly fuel-oil CPI, core CPI and an industrial-production index as controls. They
are synthetic by default. To use the public BLS and Federal Reserve series from the free Snowflake
Public Data (Free) Marketplace listing instead, see [marketplace/README.md](marketplace/README.md).

## Key design choices

- **Generated, not shipped, data.** A Python procedure generates the data in your account, writes
  CSV files to a stage and the install loads them with `COPY`, so the repository contains no data.
- **A known answer to recover.** Order volumes respond to price through a planted elasticity
  matrix (`CHP_ATOMIC.DEMO_PLANTED_ELASTICITY`), so the Data Science Workbench can show how close
  the estimate gets.
- **Mix-free price index.** Elasticities are estimated on `ln(price / product mean price)`, so
  product mix within a family doesn't masquerade as a price effect.
- **Models as stored procedures.** Every model is a Python procedure writing to a table; the app,
  semantic view and agent only read results. The notebooks explain the same techniques.

## Teardown

```bash
snow sql -f scripts/teardown.sql --enable-templating NONE
```

Drops the three CHP schemas (including the tables, procedures, stages, semantic view, search
service, agent and Streamlit app). The shared `SF_SOLUTIONS` database and `SF_SOLUTIONS_WH`
warehouse are kept. Safe to run more than once.
