---
description: >
  Manage the Chemicals Pricing & Margin Intelligence solution.
  Usage: $sf-solutions:chemicals-pricing (install)
         $sf-solutions:chemicals-pricing teardown
         $sf-solutions:chemicals-pricing next
  Pricing and margin intelligence for a chemicals producer: margin and cost-to-serve analysis,
  price elasticity from order history, constrained price optimisation, demand forecasts, market
  report search and a Cortex Agent, with a Streamlit app and walkthrough notebooks.
  Triggers: chemicals pricing, price elasticity, price optimization, margin analysis, cost to serve,
  petrochemicals, polymers, olefins, demand forecast, pricing desk, commodity chemicals.
---

# Chemicals Pricing & Margin Intelligence

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- If `$ARGUMENTS` is "next" → show **Next Actions**
- Otherwise → show usage help

## Overview

- **Industry:** Manufacturing
- **Database:** SF_SOLUTIONS
- **Schemas:** CHP_RAW, CHP_ATOMIC, CHP_OPS
- **Features:** Snowpark Python Stored Procedures, Cortex Analyst, Semantic View, Cortex Search, Cortex Agent, Cortex AI Functions, Snowflake CoWork, Streamlit in Snowflake, Notebooks
- **Role Required:** ACCOUNTADMIN

## Install

1. Locate the sf-mleu-solutions repository (search `$PWD`, then clone to `~/.cache/sf-solutions/`).

2. Read `solutions/chemicals-pricing/manifest.json` from the repository.

3. Query the current account info and present the installation plan:
   ```sql
   SELECT CURRENT_ORGANIZATION_NAME() AS ORG, CURRENT_ACCOUNT_NAME() AS ACCOUNT, CURRENT_REGION() AS REGION, CURRENT_ROLE() AS ROLE;
   ```
   Show to the user:
   ```
   Solution: Chemicals Pricing & Margin Intelligence v1.0.0
   Industry: Manufacturing
   Database: SF_SOLUTIONS
   Schemas:  CHP_RAW, CHP_ATOMIC, CHP_OPS
   Role:     ACCOUNTADMIN

   Target Account:
     Organization: <ORG>
     Account:      <ACCOUNT>
     Region:       <REGION>
     Current Role: <ROLE>

   What will be created:
     - Synthetic data for a fictional chemicals producer (19 products, 200 customers,
       about 39,000 sales orders over 12 months, market indices, market reports)
     - Python stored procedures: data generator, price elasticity, elasticity matrix,
       price optimiser, demand forecast, lagged correlation (run once at install)
     - Data mart views (margins, cost-to-serve, price guidance, inventory health)
     - Semantic view, Cortex Search service and Cortex Agent CHEMICALS_PRICING_AGENT
     - Streamlit app CHEMICALS_PRICING_APP (7 pages)
     - Warehouse: SF_SOLUTIONS_WH (shared, LARGE)
   Expected time on a LARGE warehouse: about 8 minutes.

   Disclaimer: This application is not part of the Snowflake Service and is
   governed by the terms in LICENSE, unless expressly agreed to in writing. You use
   this application at your own risk, and Snowflake has no obligation to support
   your use of this application.
   ```
   Wait for confirmation (the user's confirmation also acknowledges the disclaimer).

4. **Delegate SQL execution to a Task subagent** (do NOT read SQL files into main context):
   ```
   task(
     subagent_type: "generalPurpose",
     description: "Execute chemicals-pricing SQL",
     prompt: """
     Execute the SQL scripts for the chemicals-pricing solution.

     Files to execute IN ORDER:
     1. <REPO_ROOT>/solutions/chemicals-pricing/scripts/setup.sql
     2. <REPO_ROOT>/solutions/chemicals-pricing/scripts/data.sql
     3. <REPO_ROOT>/solutions/chemicals-pricing/scripts/pipeline.sql

     Preferred: if the Snowflake CLI is available, run for each file in order:
       snow sql -f <file> --enable-templating NONE
     (templating must be off: the scripts contain '&').

     Otherwise:
     - Read each SQL file with the Read tool
     - Split into individual statements on semicolons BUT respect $$...$$ dollar-quoting
       (count $$ per line; odd count toggles in/out; don't split on ; inside $$ blocks).
       The Python procedures in setup.sql and pipeline.sql, and the semantic-view YAML and
       agent specification in pipeline.sql, are long $$ blocks: keep each as one statement
     - Skip pure comment statements (all non-blank lines start with --)
     - Run every statement in the SAME session, in order (the files use USE statements)
     - Execute each via snowflake_sql_execute with timeout_seconds: 1200
     - For "already exists" errors: log and continue
     - For "insufficient privileges": log and stop
     - Report: statements executed, any errors
     """
   )
   ```

5. Upload the Streamlit app files (run each PUT with `snowflake_sql_execute`, or
   `snow sql -q "<PUT ...>"`; replace `<REPO_ROOT>` with the absolute path):
   ```sql
   PUT 'file://<REPO_ROOT>/solutions/chemicals-pricing/streamlit/streamlit_app.py' @SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   PUT 'file://<REPO_ROOT>/solutions/chemicals-pricing/streamlit/environment.yml' @SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   PUT 'file://<REPO_ROOT>/solutions/chemicals-pricing/streamlit/pages/*.py' @SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE/pages/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   PUT 'file://<REPO_ROOT>/solutions/chemicals-pricing/streamlit/utils/*.py' @SF_SOLUTIONS.CHP_OPS.STREAMLIT_STAGE/utils/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   ```
   Then execute `<REPO_ROOT>/solutions/chemicals-pricing/scripts/streamlit.sql` (same method as step 4).

6. Verify installation:
   ```sql
   SELECT 'sales orders' AS ITEM, COUNT(*) AS N FROM SF_SOLUTIONS.CHP_ATOMIC.SALES_ORDER
   UNION ALL SELECT 'elasticity matrix cells', COUNT(*) FROM SF_SOLUTIONS.CHP_OPS.ELASTICITY_MATRIX
   UNION ALL SELECT 'optimal prices', COUNT(*) FROM SF_SOLUTIONS.CHP_OPS.OPTIMAL_PRICING
   UNION ALL SELECT 'forecast rows', COUNT(*) FROM SF_SOLUTIONS.CHP_OPS.DEMAND_FORECAST
   UNION ALL SELECT 'search passages', COUNT(*) FROM SF_SOLUTIONS.CHP_OPS.MARKET_REPORT_CHUNKS;
   ```
   Expect about 39,000 sales orders, 16 matrix cells, 4 optimal prices, 380 forecast rows and
   about 160-180 search passages (exact counts depend on the install date).

7. **[MANDATORY]** Display the app and agent URLs:
   ```sql
   SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
       || '/#/streamlit-apps/SF_SOLUTIONS.CHP_OPS.CHEMICALS_PRICING_APP' AS APP_URL,
          'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
       || '/#/agents/database/SF_SOLUTIONS/schema/CHP_OPS/agent/CHEMICALS_PRICING_AGENT/details' AS AGENT_URL;
   ```
   Show:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Streamlit app:
   <APP_URL>
   Chemicals pricing agent:
   <AGENT_URL>
   Snowflake CoWork:
   https://ai.snowflake.com/<org>/<account>/#/ai
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

8. Show final summary:
   ```
   Installation complete: Chemicals Pricing & Margin Intelligence v1.0.0

   Next Actions:
   1. Open the Streamlit app: Data Science Workbench shows planted vs estimated elasticities
   2. Open the agent and try: "What price does the optimizer recommend for Polymers?"
   3. Try: "What does the market intelligence say about supply constraints for Propylene in Asia?"
   4. Import the notebooks in solutions/chemicals-pricing/notebooks/ to walk through the techniques

   Teardown: $sf-solutions:chemicals-pricing teardown
   ```

## Teardown

1. Confirm with user: "This will drop the CHP_RAW, CHP_ATOMIC and CHP_OPS schemas (including tables, procedures, stages, semantic view, search service, agent and Streamlit app). The shared SF_SOLUTIONS database and SF_SOLUTIONS_WH warehouse are kept. Proceed?"
2. Delegate `scripts/teardown.sql` execution to a Task subagent (same pattern as install).
3. Confirm: "Chemicals Pricing & Margin Intelligence removed."

## Next Actions

Read and present `solutions/chemicals-pricing/NEXT_ACTIONS.md` from the repository.

## Usage Help

```
Usage:
  $sf-solutions:chemicals-pricing           — Install the solution
  $sf-solutions:chemicals-pricing teardown  — Remove the solution
  $sf-solutions:chemicals-pricing next      — Post-install guidance
```
