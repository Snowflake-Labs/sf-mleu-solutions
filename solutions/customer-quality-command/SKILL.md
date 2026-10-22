---
description: >
  Manage the Customer Quality Command (CQC) solution.
  Usage: $sf-solutions:customer-quality-command (install)
         $sf-solutions:customer-quality-command teardown
         $sf-solutions:customer-quality-command next
  Customer-quality command-and-response accelerator for equipment manufacturers and dealer networks:
  early detection, safety-gated prioritization, lot-level root cause, exposure simulation,
  closed-loop actions and a Cortex Agent.
  Triggers: customer quality, field quality, warranty analytics, quality issue, emerging issue,
  root cause, supplier lot, warranty exposure, dealer network, heavy equipment, manufacturing quality.
---

# Customer Quality Command (CQC)

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- If `$ARGUMENTS` is "next" → show **Next Actions**
- Otherwise → show usage help

## Overview

- **Industry:** Manufacturing
- **Database:** SF_SOLUTIONS
- **Schemas:** CQC_RAW, CQC_STAGING, CQC_ATOMIC, CQC_FEATURE_STORE, CQC_ML, CQC_ANALYTICS, CQC_INSIGHTS, CQC_ACTION, CQC_DOCS
- **Features:** Snowpark Python Stored Procedures, Model Registry, Cortex AI Functions, Cortex Analyst, Semantic View, Cortex Search, Cortex Agent, Snowflake CoWork
- **Role Required:** ACCOUNTADMIN

## Install

1. Locate the sf-mleu-solutions repository (search `$PWD`, then clone to `~/.cache/sf-solutions/`).

2. Read `solutions/customer-quality-command/manifest.json` from the repository.

3. Query the current account info and present the installation plan:
   ```sql
   SELECT CURRENT_ORGANIZATION_NAME() AS ORG, CURRENT_ACCOUNT_NAME() AS ACCOUNT, CURRENT_REGION() AS REGION, CURRENT_ROLE() AS ROLE;
   ```
   Show to the user:
   ```
   Solution: Customer Quality Command (CQC) v1.0.0
   Industry: Manufacturing
   Database: SF_SOLUTIONS
   Schemas:  CQC_RAW, CQC_STAGING, CQC_ATOMIC, CQC_FEATURE_STORE, CQC_ML,
             CQC_ANALYTICS, CQC_INSIGHTS, CQC_ACTION, CQC_DOCS
   Role:     ACCOUNTADMIN

   Target Account:
     Organization: <ORG>
     Account:      <ACCOUNT>
     Region:       <REGION>
     Current Role: <ROLE>

   What will be created:
     - Synthetic quality data for 40,800 machines (fictional manufacturer Acme Industrial)
     - Python stored procedures for the data generator and the ML suite
     - Two Model Registry models (FAILURE_RISK_MODEL, EXPOSURE_SIMULATOR)
     - INSIGHTS issue hub, ACTION workflow, semantic view, two Cortex Search services
     - Cortex Agent CUSTOMER_QUALITY_AGENT (Ask CQC)
     - Warehouse: SF_SOLUTIONS_WH (shared, LARGE)
   Expected time on a LARGE warehouse: about 15 minutes.
   ```
   Wait for confirmation.

4. **Delegate SQL execution to a Task subagent** (do NOT read SQL files into main context):
   ```
   task(
     subagent_type: "generalPurpose",
     description: "Execute customer-quality-command SQL",
     prompt: """
     Execute the SQL scripts for the customer-quality-command solution.

     Files to execute IN ORDER:
     1. <REPO_ROOT>/solutions/customer-quality-command/scripts/setup.sql
     2. <REPO_ROOT>/solutions/customer-quality-command/scripts/data.sql
     3. <REPO_ROOT>/solutions/customer-quality-command/scripts/pipeline.sql

     Preferred: if the Snowflake CLI is available, run for each file in order:
       snow sql -f <file> --enable-templating NONE
     (templating must be off: the scripts contain '&').

     Otherwise:
     - Read each SQL file with the Read tool
     - Split into individual statements on semicolons BUT respect $$...$$ dollar-quoting
       (count $$ per line; odd count toggles in/out; don't split on ; inside $$ blocks).
       The Python procedures in setup.sql and the semantic-view YAML in pipeline.sql are
       long $$ blocks: keep each as one statement
     - Skip pure comment statements (all non-blank lines start with --)
     - Run every statement in the SAME session, in order (some files use USE SCHEMA and
       session variables set by earlier statements)
     - Execute each via snowflake_sql_execute with timeout_seconds: 1200
     - For "already exists" errors: log and continue
     - For "insufficient privileges": log and stop
     - Report: statements executed, any errors
     """
   )
   ```

5. Verify installation:
   ```sql
   SELECT TABLE_SCHEMA, COUNT(*) AS TABLES, SUM(ROW_COUNT) AS ROWS
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE TABLE_SCHEMA LIKE 'CQC_%' AND TABLE_TYPE = 'BASE TABLE'
   GROUP BY TABLE_SCHEMA
   ORDER BY TABLE_SCHEMA;
   ```
   Expect 141 rows in `SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE`.

6. **[MANDATORY]** Display the Snowflake CoWork Agent URL:
   ```sql
   SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
       || '/#/agents/database/SF_SOLUTIONS/schema/CQC_ML/agent/CUSTOMER_QUALITY_AGENT/details' AS AGENT_URL;
   ```
   Show:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Ask CQC agent:
   <AGENT_URL>
   Snowflake CoWork:
   https://ai.snowflake.com/<org>/<account>/#/ai
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

7. Show final summary:
   ```
   Installation complete: Customer Quality Command (CQC) v1.0.0

   Next Actions:
   1. Open the agent URL above to chat with Ask CQC
   2. Try: "What's our biggest safety-priority quality issue and why?"
   3. Try: "Why are LX-950 units disproportionately affected by the fuel-system issue?"
   4. Try: "What should we do in the next 72 hours?"
   5. Optional (not trial): deploy the CQC app on SPCS (app/README.md)

   Teardown: $sf-solutions:customer-quality-command teardown
   ```

## Teardown

1. Confirm with user: "This will drop the nine CQC schemas (including models, search services, semantic view and agent) and the optional app service and compute pool. The shared SF_SOLUTIONS database and SF_SOLUTIONS_WH warehouse are kept. Proceed?"
2. Delegate `scripts/teardown.sql` execution to a Task subagent (same pattern as install).
3. Confirm: "Customer Quality Command removed."

## Next Actions

Read and present `solutions/customer-quality-command/NEXT_ACTIONS.md` from the repository.

## Usage Help

```
Usage:
  $sf-solutions:customer-quality-command           — Install the solution
  $sf-solutions:customer-quality-command teardown  — Remove the solution
  $sf-solutions:customer-quality-command next      — Post-install guidance
```
