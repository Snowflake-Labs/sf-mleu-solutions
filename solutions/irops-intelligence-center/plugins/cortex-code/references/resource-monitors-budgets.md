# Resource Monitors & Budgets — Cost Guardrails

**Component:** `cmp-resource-monitors-budgets` (Resource Monitors + Budgets) · traces to
`cap-predict-delay-risk`, `cap-monitor-otp-departure-rate`, `cap-monitor-avg-delay-minutes`.
**Status:** cost-control posture.

## Why here
The near-real-time serving path is the highest credit-burn surface: `DT_FLIGHT_RISK_REALTIME` refreshes at
`TARGET_LAG = '5 minutes'` `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]` and
the net-new OTP/avg-delay Dynamic Table (`scripts/dt_otp_delay_metrics.sql`) refreshes continuously.
Guard them without throttling the OCC latency SLO `[WAF: cost_optimization]`.

## Controls
1. **Resource Monitors** on the serving warehouses (e.g. `IROP_ML_WH`, the OCC read warehouse) with a
   monthly credit quota and a `SUSPEND` action at the ceiling.
2. **Budgets** for spend visibility + proactive notification on the serving/serverless surface.
3. **Serverless auto-suspend** on the Dynamic Tables, and **target-lag tuning** so refresh credits track
   the actual OCC freshness need rather than over-refreshing (`TARGET_LAG` ≤ the stated freshness SLO).
4. Warehouses set `AUTO_SUSPEND` (see `rbac-masking-governance.md`).

## The cost loop
This delivers the WAF Impact → Visibility → Control → Optimize loop: measure with Budgets, control with
Resource Monitors, optimize with target-lag/auto-suspend `[WAF: cost_optimization]`. Time Travel retention
introduced for DR is right-sized here, not left at a default `[WAF: cost_optimization]` — see
`dr-continuity-runbook.md`.
