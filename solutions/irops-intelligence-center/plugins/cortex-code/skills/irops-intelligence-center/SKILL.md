---
name: irops-intelligence-center
description: >
  Install or teardown the IROPS Intelligence Center for Network Operations Control.
  Usage: $sf-mleu-solutions:irops-intelligence-center | $sf-mleu-solutions:irops-intelligence-center teardown
  Triggers: irops, irops intelligence, flight operations, occ, delay risk, network operations control, airline irops.
tools:
  - snowflake_sql_execute
  - snowflake_object_search
  - Bash
  - Read
  - Glob
  - Grep
---

# IROPS Intelligence Center for Network Operations Control

Parse the action from `$ARGUMENTS`:

- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- Otherwise → show usage help

## Overview

- **Industry:** Airlines & Transportation
- **Database:** SF_SOLUTIONS
- **Schemas:** IROPS_RAW, IROPS_DATA_MART, IROPS_CORTEX
- **Features:** Dynamic Tables, Cortex Analyst, Semantic View, Least-privilege RBAC
- **Role Required:** ACCOUNTADMIN

## Install

### Step 1: Locate repository and read manifest

Locate the `sf-mleu-solutions` repository:

- Check `~/project/sf-mleu-solutions/`
- Check current working directory
- If not found: `git clone https://github.com/Snowflake-Labs/sf-mleu-solutions.git /tmp/sf-mleu-solutions`

Read `solutions/irops-intelligence-center/manifest.json`.

### Step 2: Present installation plan

Query the current account and show the plan:

```sql
SELECT CURRENT_ORGANIZATION_NAME() AS ORG,
       CURRENT_ACCOUNT_NAME()      AS ACCOUNT,
       CURRENT_REGION()            AS REGION,
       CURRENT_ROLE()              AS ROLE;
```

Display to the user:

```
Solution: IROPS Intelligence Center for Network Operations Control v0.1.0
Industry: Airlines & Transportation
Database: SF_SOLUTIONS
Schemas:  IROPS_RAW, IROPS_DATA_MART, IROPS_CORTEX
Role:     ACCOUNTADMIN

Target Account:
  Organization: <ORG>
  Account:      <ACCOUNT>
  Region:       <REGION>
  Current Role: <ROLE>

What will be created:
  - RAW_FLIGHTS table with 35 demo flight records
  - DT_FLIGHT_RISK_REALTIME view (delay risk and revenue-at-risk proxy)
  - DT_AVG_DELAY_FLIGHT_LEG Dynamic Table (60-min refresh, flight-leg grain)
  - DT_OTP_RATE_ROUTE_DAY Dynamic Table (60-min refresh, route-day grain)
  - IROP_OPERATIONS_SV Semantic View for Cortex Analyst
  - IROPS_OCC_ROLE (least-privilege analytics role)

Proceed with installation? (yes/no)
```

Wait for user confirmation before continuing.

### Step 3: Execute setup.sql in batches

Read `solutions/irops-intelligence-center/scripts/setup.sql`.

Execute in batches to minimize round-trips:

**Batch 1 — Shared infrastructure + schema creation:**

```sql
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS SF_SOLUTIONS;
CREATE WAREHOUSE IF NOT EXISTS SF_SOLUTIONS_WH
    WITH WAREHOUSE_SIZE = 'LARGE' AUTO_SUSPEND = 300 AUTO_RESUME = TRUE;
USE DATABASE SF_SOLUTIONS;
USE WAREHOUSE SF_SOLUTIONS_WH;
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.IROPS_RAW;
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.IROPS_DATA_MART;
CREATE SCHEMA IF NOT EXISTS SF_SOLUTIONS.IROPS_CORTEX;
```

**Batch 2 — RAW_FLIGHTS table + DT_FLIGHT_RISK_REALTIME view:**

Execute Section 2 and Section 3 of setup.sql together (table DDL + view DDL).

**Batch 3 — Dynamic Tables** (`timeout_seconds: 300`):

Execute Section 4 of setup.sql (DT_AVG_DELAY_FLIGHT_LEG and DT_OTP_RATE_ROUTE_DAY).
Dynamic Tables require extra time to initialize their first refresh.

**Batch 4 — Semantic View + grants:**

Execute Sections 5 and 6 of setup.sql together (IROP_OPERATIONS_SV creation + all GRANT statements).

### Step 4: Load demo data

Read and execute `solutions/irops-intelligence-center/scripts/data.sql`.

This inserts 35 synthetic flight records across UA/DL/AA carriers.

```sql
USE ROLE ACCOUNTADMIN;
USE DATABASE SF_SOLUTIONS;
USE SCHEMA SF_SOLUTIONS.IROPS_RAW;
-- [data.sql content]
```

### Step 5: Verify installation

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('IROPS_RAW', 'IROPS_DATA_MART', 'IROPS_CORTEX')
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

Confirm that the following objects exist:

- `IROPS_RAW.RAW_FLIGHTS` (BASE TABLE)
- `IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME` (VIEW)
- `IROPS_DATA_MART.DT_AVG_DELAY_FLIGHT_LEG` (DYNAMIC TABLE)
- `IROPS_DATA_MART.DT_OTP_RATE_ROUTE_DAY` (DYNAMIC TABLE)
- `IROPS_CORTEX.IROP_OPERATIONS_SV` (SEMANTIC VIEW)

Also verify row count in the demo data:

```sql
SELECT COUNT(*) AS flight_count FROM SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS;
```

Expected: 35 rows.

### Step 6: Show Snowsight URL (MANDATORY — DO NOT SKIP)

```sql
SELECT 'https://app.snowflake.com/'
    || LOWER(CURRENT_ORGANIZATION_NAME()) || '/'
    || LOWER(CURRENT_ACCOUNT_NAME())
    || '/#/data/databases/SF_SOLUTIONS/schemas/IROPS_CORTEX' AS SOLUTION_URL;
```

Display the result exactly like this:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IROPS Intelligence Center — Installed

Solution Objects:
  https://app.snowflake.com/<org>/<account>/#/data/databases/SF_SOLUTIONS/schemas/IROPS_CORTEX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

This step is NON-OPTIONAL. The user must always see a clickable URL after install.

### Step 7: Show summary and next actions

```
Installation complete: IROPS Intelligence Center v0.1.0

Objects created:
  SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS              (35 demo records)
  SF_SOLUTIONS.IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME
  SF_SOLUTIONS.IROPS_DATA_MART.DT_AVG_DELAY_FLIGHT_LEG
  SF_SOLUTIONS.IROPS_DATA_MART.DT_OTP_RATE_ROUTE_DAY
  SF_SOLUTIONS.IROPS_CORTEX.IROP_OPERATIONS_SV
  Role: IROPS_OCC_ROLE

Next — try these skills:
  $sf-mleu-solutions:irops-intelligence-center:primary-workflow
  $sf-mleu-solutions:irops-intelligence-center:delay-risk-triage
  $sf-mleu-solutions:irops-intelligence-center:otp-trend-monitor

Or query directly:
  SELECT * FROM SF_SOLUTIONS.IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME
  WHERE realtime_risk_score > 0.6 ORDER BY revenue_at_risk DESC LIMIT 10;

Teardown: $sf-mleu-solutions:irops-intelligence-center teardown
```

## Teardown

If `$ARGUMENTS` is "teardown":

1. Confirm with user:

   ```
   This will drop:
     - SF_SOLUTIONS.IROPS_RAW (and all tables)
     - SF_SOLUTIONS.IROPS_DATA_MART (and all Dynamic Tables/Views)
     - SF_SOLUTIONS.IROPS_CORTEX (and Semantic View)
     - Role: IROPS_OCC_ROLE

   The shared SF_SOLUTIONS database and SF_SOLUTIONS_WH warehouse will NOT be dropped.
   Proceed? (yes/no)
   ```

2. Read and execute `solutions/irops-intelligence-center/scripts/teardown.sql`.

3. Verify removal:

   ```sql
   SELECT COUNT(*) AS remaining
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.SCHEMATA
   WHERE SCHEMA_NAME IN ('IROPS_RAW', 'IROPS_DATA_MART', 'IROPS_CORTEX');
   ```

   Expected: 0

4. Confirm: "IROPS Intelligence Center removed. SF_SOLUTIONS database and SF_SOLUTIONS_WH warehouse preserved."

## Next Actions

If the user asks "what next?", "what can I do?", "how do I use this?":

Read and present the relevant section from `NEXT_ACTIONS.md` in this skill's directory.

- Just installed / exploring → Phase 1: Quick Exploration
- Wants to run OCC workflows → Phase 2: Use the Skills
- Wants to load real data → Phase 3: Connect Real Data
- Ready for production → Phase 4: Production Deployment

## Error Recovery

| Error | Action |
|-------|--------|
| Dynamic Table creation fails | Check warehouse size (must be LARGE or above); retry Batch 3 |
| Semantic View creation fails | Run `USE SCHEMA SF_SOLUTIONS.IROPS_CORTEX;` first; ensure IROPS_RAW and IROPS_DATA_MART schemas exist |
| GRANT fails on Semantic View | Semantic Views require the schema to exist; verify Section 4 completed first |
| data.sql row count is 0 | Re-run `scripts/data.sql` after verifying `RAW_FLIGHTS` table exists |
| `IROPS_OCC_ROLE` already exists | Safe to continue — `CREATE ROLE IF NOT EXISTS` is idempotent |

## Usage Help

```
Usage:
  $sf-mleu-solutions:irops-intelligence-center           — Install the solution
  $sf-mleu-solutions:irops-intelligence-center teardown  — Remove the solution
```
