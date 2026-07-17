---
name: otp-trend-monitor
description: "Continuous, current visibility into On-Time Departure rate (route-day) and Average Delay Minutes (flight-leg) across the network, so degrading trends surface early instead of in stale reports. Use whenever the OCC asks 'how is OTP trending', 'on-time rate by route', 'where is delay concentrating', 'average delay minutes', 'which routes are getting worse', or wants a network trend view — even without the word OTP. Enforces route-day grain for OTP and flight-leg grain for average delay; never the ATC-event grain."
parent_skill: primary-workflow
---

# OTP & Delay Trend Monitor

## When to Load
`primary-workflow` routes here for continuous OTP-rate and average-delay-minutes trend watch
`[intake job-monitor-otp-trends]`. The goal is trend visibility across the network
`[intake job-monitor-otp-trends → outcomes]`, replacing stale/infrequent OTP reporting
`[intake job-monitor-otp-trends → pain_points]`.

## Prerequisites
- These are **NET-NEW governed** metrics: they come from the Dynamic Table built by
  `scripts/dt_otp_delay_metrics.sql`. Confirm it is deployed and refreshing before reporting a trend.
- **Load** `../kpi-definitions/SKILL.md` (KPIs 2 & 3) to confirm grain before writing SQL.

## Workflow

### Step 1: Confirm the metric and grain
**Goal:** avoid the grain trap that corrupts OTP reporting.
**Actions:**
1. On-Time Departure rate → **route-day** grain; percent; higher is better
   `[intake job-monitor-otp-trends → kpi "On-time departure rate"]`.
2. Average delay minutes → **flight-leg** grain; minutes; lower is better
   `[intake job-monitor-otp-trends → kpi "Average delay minutes"]`.
3. Do NOT use `raw_atc_events.avg_delay_minutes` — that is ATC-event grain, a different KPI
   `[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql → raw_atc_events]`.

### Step 2: Read the governed trend, not raw tables
**Goal:** report from the modeled object at the consistent grain.
**Actions:**
1. Query the Dynamic Table produced by `scripts/dt_otp_delay_metrics.sql`, which computes OTP as the share
   of departures with `STATUS = 'ON_TIME'` at route-day grain and averages `DELAY_MINUTES` at flight-leg
   grain from `raw_flights` `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_flights.status,
   raw_flights.delay_minutes]`.
2. For NL trend questions, prefer Cortex Analyst over `IROP_OPERATIONS_SV` — but note the net-new OTP /
   avg-delay measures must be added to that semantic model first (see
   `references/cortex-analyst-semantic-model.md`) before they are answerable there.

<!-- Cost/Runtime checkpoint -->
MANDATORY STOPPING POINT: A network-wide, all-history trend scan can be expensive.
- Scope: all routes × full date range.
- Alternatives: a specific hub/route, a bounded date window, or the pre-aggregated Dynamic Table
  (already incremental).
Proceed? (Yes / Narrow scope / No)

### Step 3: Surface degradation
**Goal:** turn the trend into an early signal.
**Actions:**
1. Rank routes by worsening OTP or rising average delay over the window.
2. Cross-check freshness: if the underlying feed is stale, the trend is untrustworthy — see
   `references/data-quality-dmf.md` and `references/alerting-notifications.md` (DMF breach / refresh-lag
   alerts) `[WAF: reliability]`.

### Step 4: Validate
**Validation Checklist:**
- OTP reported at route-day, average delay at flight-leg — no grain mixing.
- Numbers read from the governed Dynamic Table / semantic view, not raw base tables.
- Freshness confirmed within the trend-freshness SLO.

## Stopping Points
- Before a full-network historical scan — offer a narrower scope.
- If the net-new metrics are not yet deployed — report the gap, do not hand-aggregate inconsistently.

## Output
A grain-correct, fresh OTP and average-delay trend view with degrading routes surfaced early.
