---
description: >
  Manage the Predictive Maintenance solution.
  Usage: $sf-solutions:predictive-maintenance (install)
         $sf-solutions:predictive-maintenance teardown
         $sf-solutions:predictive-maintenance next
  IoT-powered predictive maintenance with Snowflake CoWork.
  Triggers: manufacturing, predictive maintenance, IoT, sensor, equipment health, OEE, SPCS.
---

# Predictive Maintenance

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- If `$ARGUMENTS` is "next" → show **Next Actions**
- Otherwise → show usage help

## Overview

- **Industry:** Manufacturing
- **Database:** SF_SOLUTIONS
- **Schemas:** MPM_BRONZE, MPM_SILVER, MPM_GOLD
- **Features:** Snowflake CoWork, Cortex Analyst, Semantic View, Streamlit in Snowflake, SPCS
- **Role Required:** ACCOUNTADMIN
- **Source:** [sfguide-getting-started-with-predictive-maintenance](https://github.com/Snowflake-Labs/sfguide-getting-started-with-predictive-maintenance)

## Install

1. Locate the sf-mleu-solutions repository (search `~/project`, `$PWD`, then clone to `~/.cache/sf-solutions/`).

2. Read `solutions/predictive-maintenance/manifest.json` from the repository.

3. Query the current account info and present the installation plan:
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
     - ~160K+ telemetry records across 18 assets and 2 plants
     - Dimensional star schema (fact + dimension tables)
     - Semantic View for Cortex Analyst natural language queries
     - Cortex Agent (PREDICTIVE_MAINTENANCE_ASSISTANT) for Snowflake CoWork
     - Warehouses: SF_SOLUTIONS_WH, SF_SOLUTIONS_STREAMLIT_WH

   Proceed with installation?
   ```

4. Wait for user confirmation.

5. **Delegate SQL execution to a Task subagent** (do NOT read SQL files into main context):
   ```
   task(
     subagent_type: "generalPurpose",
     description: "Execute predictive-maintenance SQL",
     prompt: """
     Execute the SQL scripts for the predictive-maintenance solution.

     Files to execute IN ORDER:
     1. <REPO_ROOT>/solutions/predictive-maintenance/scripts/setup.sql
     2. <REPO_ROOT>/solutions/predictive-maintenance/scripts/data.sql

     Execution instructions:
     - Read each SQL file with the Read tool
     - Split into individual statements on semicolons BUT respect $$...$$ dollar-quoting
       (count $$ per line; odd count toggles in/out; don't split on ; inside $$ blocks)
     - Skip pure comment statements (all non-blank lines start with --)
     - Execute each via snowflake_sql_execute with timeout_seconds: 600
     - For "already exists" errors: log and continue
     - For "insufficient privileges": log and stop
     - Report: statements executed, INSERT row counts, any errors
     """
   )
   ```

6. Verify installation:
   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE TABLE_SCHEMA IN ('MPM_BRONZE', 'MPM_SILVER', 'MPM_GOLD')
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

7. **[MANDATORY]** Display the Snowflake CoWork Agent URL:
   ```sql
   SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME()) AS BASE_URL;
   ```
   Show:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Snowflake CoWork:
   <BASE_URL>/#/cortex-agents
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

8. Show final summary:
   ```
   Installation complete: Predictive Maintenance v1.0.0

   Next Actions:
   1. Open Snowflake CoWork URL above to chat with the agent
   2. Try: "Show me the trend of OEE vs maintenance cost over the last 12 months"
   3. Try: "Which assets have the highest failure probability?"
   4. Try: "What was the total financial impact of unplanned downtime last month?"

   Teardown: $sf-solutions:predictive-maintenance teardown
   ```

## Teardown

1. Confirm with user: "This will drop the SF_SOLUTIONS database, warehouses, and role. Proceed?"
2. Delegate teardown.sql execution to a Task subagent (same pattern as install).
3. Confirm: "Predictive Maintenance removed."

## Next Actions

Read and present `solutions/predictive-maintenance/NEXT_ACTIONS.md` from the repository.

## Usage Help

```
Usage:
  $sf-solutions:predictive-maintenance           — Install the solution
  $sf-solutions:predictive-maintenance teardown  — Remove the solution
  $sf-solutions:predictive-maintenance next      — Post-install guidance
```
