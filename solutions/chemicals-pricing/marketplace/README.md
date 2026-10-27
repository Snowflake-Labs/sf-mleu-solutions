# Optional: Snowflake Public Data for the macro indicators

The pricing models use three monthly macro indicators as demand controls: fuel-oil CPI, core CPI
and an industrial-production index. By default the install generates **synthetic** series for these
(`CHP_ATOMIC.MACRO_INDICATOR`), so the demo needs no external data.

To use public US series instead (BLS CPI and Federal Reserve industrial production), get the free
**Snowflake Public Data (Free)** listing from the Snowflake Marketplace and re-point the views:

1. In Snowsight, open **Data Products > Marketplace**, search for **Snowflake Public Data (Free)** and
   select **Get**. Keep the database name `SNOWFLAKE_PUBLIC_DATA_FREE` (or edit the script). Review the
   listing's terms before using the data.
2. Run:

   ```bash
   snow sql -f marketplace/use_public_data.sql --enable-templating NONE
   ```

3. Recompute the models: `CALL SF_SOLUTIONS.CHP_OPS.SP_RUN_ML_PIPELINE();`

| View | Public series |
|---|---|
| `CHP_OPS.MACRO_FUEL_OIL_CPI` | `CUSRSEHE01E011982-84.M`: CPI fuel oil, monthly, seasonally adjusted |
| `CHP_OPS.MACRO_CORE_CPI` | `CUSRSA0L1EL1E1982-84.M`: CPI all items less food and energy |
| `CHP_OPS.MACRO_INDUSTRIAL_PRODUCTION` | `G17_IP.N32411D.S_SA`: industrial production, distillate fuel oil |

The synthetic order data was generated with the synthetic indicators, so swapping in public series
changes the control variables, not the planted price response; elasticity estimates move only
slightly. To switch back, re-run `ddl/core/005_CHEMICAL_OPS_MART.sql`.
