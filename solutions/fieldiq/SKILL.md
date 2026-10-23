---
description: >
  Manage the FieldIQ solution.
  Usage: $sf-solutions:fieldiq (install)
         $sf-solutions:fieldiq teardown
         $sf-solutions:fieldiq next
  Agentic AI sales co-pilot for an industrial-equipment manufacturer's field sales team:
  natural-language analytics over CRM and ERP data, engineering-document search, and
  AI-prepared call plans, meeting agendas, emails and visit routes from a Cortex Agent.
  Triggers: sales co-pilot, field sales, account 360, call plan, meeting agenda, sales email,
  route planning, CRM analytics, industrial equipment sales, compressor, manufacturing sales.
---

# FieldIQ

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- If `$ARGUMENTS` is "next" → show **Next Actions**
- Otherwise → show usage help

## Overview

- **Industry:** Manufacturing
- **Database:** SF_SOLUTIONS
- **Schemas:** FIQ_ATOMIC, FIQ_ANALYTICS, FIQ_CORTEX, FIQ_ACTIONS, FIQ_STAGES
- **Features:** Snowpark Python Stored Procedures, Cortex AI Functions, Cortex Analyst, Semantic View, Cortex Search, Cortex Agent, Snowflake CoWork, Geospatial
- **Role Required:** ACCOUNTADMIN

## Install

1. Locate the sf-mleu-solutions repository (search `$PWD`, then clone to `~/.cache/sf-solutions/`).

2. Read `solutions/fieldiq/manifest.json` from the repository.

3. Query the current account info and present the installation plan:
   ```sql
   SELECT CURRENT_ORGANIZATION_NAME() AS ORG, CURRENT_ACCOUNT_NAME() AS ACCOUNT, CURRENT_REGION() AS REGION, CURRENT_ROLE() AS ROLE;
   ```
   Show to the user:
   ```
   Solution: FieldIQ v1.0.0
   Industry: Manufacturing
   Database: SF_SOLUTIONS
   Schemas:  FIQ_ATOMIC, FIQ_ANALYTICS, FIQ_CORTEX, FIQ_ACTIONS, FIQ_STAGES
   Role:     ACCOUNTADMIN

   Target Account:
     Organization: <ORG>
     Account:      <ACCOUNT>
     Region:       <REGION>
     Current Role: <ROLE>

   What will be created:
     - Synthetic CRM/ERP data for 120 accounts (fictional manufacturer Apex Industrial)
     - 262 generated engineering documents (PDF + markdown) on a stage, chunked for search
     - Python stored procedure for the data and document generator
     - 5 agent-tool procedures (call plan, meeting agenda, email, nearby customers, route plan)
     - Semantic view, Cortex Search service and Cortex Agent FIELDIQ_AGENT
     - Warehouse: SF_SOLUTIONS_WH (shared, LARGE)
   Expected time on a LARGE warehouse: about 4 minutes.

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
     description: "Execute fieldiq SQL",
     prompt: """
     Execute the SQL scripts for the fieldiq solution.

     Files to execute IN ORDER:
     1. <REPO_ROOT>/solutions/fieldiq/scripts/setup.sql
     2. <REPO_ROOT>/solutions/fieldiq/scripts/data.sql
     3. <REPO_ROOT>/solutions/fieldiq/scripts/pipeline.sql

     Preferred: if the Snowflake CLI is available, run for each file in order:
       snow sql -f <file> --enable-templating NONE
     (templating must be off: the scripts contain '&').

     Otherwise:
     - Read each SQL file with the Read tool
     - Split into individual statements on semicolons BUT respect $$...$$ dollar-quoting
       (count $$ per line; odd count toggles in/out; don't split on ; inside $$ blocks).
       The Python procedure and action procedures in setup.sql, and the semantic-view YAML and
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

5. Verify installation:
   ```sql
   SELECT TABLE_SCHEMA, COUNT(*) AS TABLES, SUM(ROW_COUNT) AS ROWS
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE STARTSWITH(TABLE_SCHEMA, 'FIQ_') AND TABLE_TYPE = 'BASE TABLE'
   GROUP BY TABLE_SCHEMA
   ORDER BY TABLE_SCHEMA;
   ```
   Expect 9 tables in `FIQ_ATOMIC` (120 rows in `ACCOUNTS`) and 263 rows in `FIQ_CORTEX.DOC_CHUNKS`.

6. **[MANDATORY]** Display the Snowflake CoWork Agent URL:
   ```sql
   SELECT 'https://app.snowflake.com/' || LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || LOWER(CURRENT_ACCOUNT_NAME())
       || '/#/agents/database/SF_SOLUTIONS/schema/FIQ_CORTEX/agent/FIELDIQ_AGENT/details' AS AGENT_URL;
   ```
   Show:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   FieldIQ agent:
   <AGENT_URL>
   Snowflake CoWork:
   https://ai.snowflake.com/<org>/<account>/#/ai
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

7. Show final summary:
   ```
   Installation complete: FieldIQ v1.0.0

   Next Actions:
   1. Open the agent URL above to chat with FieldIQ
   2. Try: "What is the total open pipeline for Cascade Partners?"
   3. Try: "Generate a sales call plan for Cascade Partners"
   4. Try: "Which customers are within 50 miles of Cincinnati, OH?"
   5. Optional (not trial): deploy the web app or voice service on SPCS (app/README.md)

   Teardown: $sf-solutions:fieldiq teardown
   ```

## Teardown

1. Confirm with user: "This will drop the five FIQ schemas (including procedures, stages, search service, semantic view and agent) and the optional web-app and voice services and compute pools. The shared SF_SOLUTIONS database and SF_SOLUTIONS_WH warehouse are kept. Proceed?"
2. Delegate `scripts/teardown.sql` execution to a Task subagent (same pattern as install).
3. Confirm: "FieldIQ removed."

## Next Actions

Read and present `solutions/fieldiq/NEXT_ACTIONS.md` from the repository.

## Usage Help

```
Usage:
  $sf-solutions:fieldiq           — Install the solution
  $sf-solutions:fieldiq teardown  — Remove the solution
  $sf-solutions:fieldiq next      — Post-install guidance
```
