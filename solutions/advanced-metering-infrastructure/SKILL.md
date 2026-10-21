---
description: >
  Manage the Advanced Metering Infrastructure (AMI 2.0) solution.
  Usage: $sf-solutions:advanced-metering-infrastructure (install)
         $sf-solutions:advanced-metering-infrastructure teardown
         $sf-solutions:advanced-metering-infrastructure next
  Utility AMI accelerator: 15-minute interval reads, billing readiness, TOU charges, observability,
  Cortex ML anomaly detection and a Cortex Agent.
  Triggers: utilities, AMI, smart meter, interval data, meter data management, MDMS, billing readiness,
  TOU, time-of-use, VEE, grid anomaly, energy and utilities.
---

# Advanced Metering Infrastructure (AMI 2.0)

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- If `$ARGUMENTS` is "next" → show **Next Actions**
- Otherwise → show usage help

## Overview

- **Industry:** Energy & Utilities
- **Database:** SF_SOLUTIONS
- **Schemas:** AMI_RAW, AMI_CURATED, AMI_MART, AMI_OBSERVABILITY, AMI_ML, AMI_SHARED
- **Features:** Dynamic Tables, Data Metric Functions, Cortex ML Anomaly Detection, Cortex Analyst, Semantic View, Cortex Search, Cortex Agent, Snowflake CoWork
- **Role Required:** ACCOUNTADMIN

## Install

1. Locate the sf-mleu-solutions repository (search `$PWD`, then clone to `~/.cache/sf-solutions/`).

2. Read `solutions/advanced-metering-infrastructure/manifest.json` from the repository.

3. Query the current account info and present the installation plan:
   ```sql
   SELECT CURRENT_ORGANIZATION_NAME() AS ORG, CURRENT_ACCOUNT_NAME() AS ACCOUNT, CURRENT_REGION() AS REGION, CURRENT_ROLE() AS ROLE;
   ```
   Show to the user:
   ```
   Solution: Advanced Metering Infrastructure (AMI 2.0) v1.0.0
   Industry: Energy & Utilities
   Database: SF_SOLUTIONS
   Schemas:  AMI_RAW, AMI_CURATED, AMI_MART, AMI_OBSERVABILITY, AMI_ML, AMI_SHARED
   Role:     ACCOUNTADMIN

   Target Account:
     Organization: <ORG>
     Account:      <ACCOUNT>
     Region:       <REGION>
     Current Role: <ROLE>

   What will be created:
     - Synthetic utility hierarchy and 12 months of 15-minute interval reads
     - Rollup, TOU, billing-readiness and observability dynamic tables
     - Feeder and C&I meter anomaly models (scoring task and SLA alert created suspended)
     - Semantic view, Cortex Search service and Cortex Agent (AMI_INTELLIGENCE_AGENT)
     - Roles AMI_OWNER, AMI_ENG, AMI_ANALYST, AMI_OPS, AMI_SHARE
     - Warehouse: SF_SOLUTIONS_WH (shared, LARGE)
   ```

4. Ask the user for the scale using `ask_user_question`:
   - **100,000 meters (default)** — about 3.5 billion interval rows, roughly 300 GB of storage
   - **10,000 meters** — about 350 million interval rows
   - **1,000 meters** — about 35 million interval rows; recommended for trial accounts
   Then wait for confirmation of the plan.

5. **Delegate SQL execution to a Task subagent** (do NOT read SQL files into main context):
   ```
   task(
     subagent_type: "generalPurpose",
     description: "Execute advanced-metering-infrastructure SQL",
     prompt: """
     Execute the SQL scripts for the advanced-metering-infrastructure solution.

     Files to execute IN ORDER:
     1. <REPO_ROOT>/solutions/advanced-metering-infrastructure/scripts/setup.sql
     2. If the chosen scale is not 100000, run:
        UPDATE SF_SOLUTIONS.AMI_CURATED.AMI_CONFIG SET VALUE = '<N_METERS>' WHERE KEY = 'N_METERS';
     3. <REPO_ROOT>/solutions/advanced-metering-infrastructure/scripts/data.sql
     4. <REPO_ROOT>/solutions/advanced-metering-infrastructure/scripts/pipeline.sql

     Execution instructions:
     - Read each SQL file with the Read tool
     - Split into individual statements on semicolons BUT respect $$...$$ dollar-quoting
       (count $$ per line; odd count toggles in/out; don't split on ; inside $$ blocks)
     - Skip pure comment statements (all non-blank lines start with --)
     - Run every statement in the SAME session, in order: data.sql relies on session variables
       (SET ... / $N_METERS) set by earlier statements in the same file
     - Execute each via snowflake_sql_execute with timeout_seconds: 1200
     - For "already exists" errors: log and continue
     - For "insufficient privileges": log and stop
     - Report: statements executed, INSERT row counts, any errors
     Alternative if the Snowflake CLI is available: run
       snow sql -f <file> --enable-templating NONE
     for each file in order (templating must be off: the scripts contain '&').
     """
   )
   ```

6. Verify installation:
   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE TABLE_SCHEMA LIKE 'AMI_%'
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

7. **[MANDATORY]** Display the Snowflake CoWork Agent URL:
   ```sql
   SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
       || '/#/agents/database/SF_SOLUTIONS/schema/AMI_MART/agent/AMI_INTELLIGENCE_AGENT/details' AS AGENT_URL;
   ```
   Show:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   AMI Intelligence agent:
   <AGENT_URL>
   Snowflake CoWork:
   https://ai.snowflake.com/<org>/<account>/#/ai
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

8. Show final summary:
   ```
   Installation complete: Advanced Metering Infrastructure (AMI 2.0) v1.0.0

   Next Actions:
   1. Open the agent URL above to chat with AMI Intelligence
   2. Try: "Plot total kWh by territory in the last month"
   3. Try: "What is the outage response runbook?"
   4. Try: "Explain the billing readiness criteria"
   5. Optional: resume the scoring task and SLA alert (see NEXT_ACTIONS.md)
   6. Optional (not trial): deploy the SPCS dashboard (app/README.md)

   Teardown: $sf-solutions:advanced-metering-infrastructure teardown
   ```

## Teardown

1. Confirm with user: "This will drop the six AMI schemas, the AMI_* roles and the optional dashboard service, compute pool and integration. The shared SF_SOLUTIONS database and SF_SOLUTIONS_WH warehouse are kept. Proceed?"
2. Delegate `scripts/teardown.sql` execution to a Task subagent (same pattern as install).
3. Confirm: "Advanced Metering Infrastructure removed."

## Next Actions

Read and present `solutions/advanced-metering-infrastructure/NEXT_ACTIONS.md` from the repository.

## Usage Help

```
Usage:
  $sf-solutions:advanced-metering-infrastructure           — Install the solution
  $sf-solutions:advanced-metering-infrastructure teardown  — Remove the solution
  $sf-solutions:advanced-metering-infrastructure next      — Post-install guidance
```
