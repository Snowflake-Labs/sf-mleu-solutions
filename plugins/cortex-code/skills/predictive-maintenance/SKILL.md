---
name: predictive-maintenance
description: >
  Install or teardown the Predictive Maintenance solution.
  Usage: $sf-mleu-solutions:predictive-maintenance | $sf-mleu-solutions:predictive-maintenance teardown
  Triggers: manufacturing, predictive maintenance, IoT, sensor, equipment health, OEE, SPCS.
tools:
  - snowflake_sql_execute
  - snowflake_object_search
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
---

# Predictive Maintenance

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- Otherwise → show usage help

## Overview

- **Industry:** Manufacturing
- **Database:** SF_SOLUTIONS
- **Schemas:** MPM_BRONZE, MPM_SILVER, MPM_GOLD
- **Features:** Snowflake CoWork, Cortex Analyst, Semantic View, Streamlit in Snowflake, SPCS
- **Role Required:** ACCOUNTADMIN
- **Source:** [sfguide-getting-started-with-predictive-maintenance](https://github.com/Snowflake-Labs/sfguide-getting-started-with-predictive-maintenance)

## Install

1. Locate the sf-mleu-solutions repository:
   - Check `~/project/sf-mleu-solutions/`
   - Check current working directory
   - If not found: `git clone https://github.com/Snowflake-Labs/sf-mleu-solutions.git /tmp/sf-mleu-solutions`

2. Read `solutions/predictive-maintenance/manifest.json`.

3. Query the current account info and present the installation plan together:
   ```sql
   SELECT CURRENT_ORGANIZATION_NAME() AS ORG, CURRENT_ACCOUNT_NAME() AS ACCOUNT, CURRENT_REGION() AS REGION, CURRENT_ROLE() AS ROLE;
   ```
   Show to the user:
   ```
   Solution: Predictive Maintenance v1.0.0
   Industry: Manufacturing
   Database: SF_SOLUTIONS
   Schemas:  MPM_BRONZE, MPM_SILVER, MPM_GOLD
   Role:     ACCOUNTADMIN

   Target Account:
     Organization: <ORG>
     Account:      <ACCOUNT>
     Region:       <REGION>
     Current Role: <ROLE>

   What will be created:
     - Medallion architecture (Bronze/Silver/Gold) with IoT telemetry data
     - ~160K+ telemetry records across 18 assets and 3 facilities
     - Dimensional star schema (fact + dimension tables)
     - Semantic View for Cortex Analyst natural language queries
     - Cortex Agent (PREDICTIVE_MAINTENANCE_ASSISTANT) for Snowflake CoWork
     - Warehouses: SF_SOLUTIONS_WH, SF_SOLUTIONS_STREAMLIT_WH

   Proceed with installation?
   ```

4. Wait for user confirmation.

5. Read `solutions/predictive-maintenance/scripts/setup.sql` and execute statement by statement using `snowflake_sql_execute`.
   - This file contains DDL only (schema, tables, views, agent creation)
   - Log progress after each major section (Bronze, Silver, Gold, Semantic View, Agent)

6. Read `solutions/predictive-maintenance/scripts/data.sql` and execute statement by statement using `snowflake_sql_execute`.
   - This file contains sample data INSERT statements
   - Data generation may take several minutes: use `timeout_seconds: 600`

7. Verify:
   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE TABLE_SCHEMA IN ('MPM_BRONZE', 'MPM_SILVER', 'MPM_GOLD')
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

8. **[MANDATORY — DO NOT SKIP]** Retrieve and display the Snowflake CoWork Agent URL.
   Execute this query to get the correct URLs for the current account:
   ```sql
   SELECT
       CASE
           WHEN CURRENT_ORGANIZATION_NAME() IS NOT NULL AND CURRENT_ORGANIZATION_NAME() != ''
           THEN 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
           ELSE 'https://app.snowflake.com/' || LOWER(REPLACE(REPLACE(REPLACE(CURRENT_REGION(), 'AWS_', ''), 'AZURE_', ''), '_', '-')) || '/' || LOWER(CURRENT_ACCOUNT())
       END AS BASE_URL;
   ```
   Use the BASE_URL to construct both URLs and display them:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Snowflake Agent:
   <BASE_URL>/#/agents/database/SNOWFLAKE_INTELLIGENCE/schema/AGENTS/agent/PREDICTIVE_MAINTENANCE_ASSISTANT/details

   Snowflake CoWork:
   https://ai.snowflake.com/<org_or_region>/<account>/#/ai
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   For CoWork URL: replace `app.snowflake.com` with `ai.snowflake.com` and use path `/#/ai`.

   This step is NON-OPTIONAL. The user must always see both URLs after install.

9. Show final summary:
   ```
   Installation complete: Predictive Maintenance v1.0.0

   Next Actions:
   1. Open Snowflake CoWork URL above to chat with the agent
   2. Try: "Show me assets with health scores below 70"
   3. Try: "What are the total maintenance costs this month?"
   4. Try: "Which assets are predicted to fail in the next 30 days?"
   5. (Optional) Deploy Streamlit dashboard from source repo

   Teardown: $sf-mleu-solutions:predictive-maintenance teardown
   ```

## Teardown

If `$ARGUMENTS` is "teardown":

1. Confirm with user: "This will drop the SF_SOLUTIONS database, warehouses, and role. Proceed?"
2. Read and execute `solutions/predictive-maintenance/scripts/teardown.sql` statement by statement.
3. Confirm: "Predictive Maintenance removed."

## Next Actions

If the user asks "what next?", "what can I do?", or "how to customize":

Read and present the content from `NEXT_ACTIONS.md` (located in this skill's directory).
Present the relevant section based on user intent:
- Just exploring → Quick Exploration section
- Wants to use own data → Customize with Your Data section
- Wants to extend → Extend the Solution section
- Ready for production → Production Deployment section

## Usage Help

```
Usage:
  $sf-mleu-solutions:predictive-maintenance           — Install the solution
  $sf-mleu-solutions:predictive-maintenance teardown   — Remove the solution
```
