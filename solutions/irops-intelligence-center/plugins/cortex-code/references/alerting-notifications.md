# Alerting & Notifications — Proactive Failure Routing

**Component:** `cmp-alerting-notifications` (Alerts + Notification Integration) · traces to
`cap-predict-delay-risk`, `cap-monitor-otp-departure-rate`, `cap-monitor-avg-delay-minutes`.
**Status:** proactive-alerting posture (closes the detection-only gap).

## Why here (the WAF Op-Ex fix)
The prior posture (`data-quality-dmf.md` + `operations-observability.md`) was **detection-only** — DMFs
and ACCOUNT_USAGE *record* breaches but nothing *fires*. Snowflake Alerts evaluate on a schedule and, via
a Notification Integration, PUSH to the OCC platform on-call `[WAF: operational_excellence — proactive
failure alerting closes the detection-only gap]`.

## The three fire conditions
1. **DMF threshold breach** — stale `STATUS` / null `delay_minutes` on the raw flight feed (per
   `data-quality-dmf.md`).
2. **DT refresh-lag SLO breach** — a serving Dynamic Table's refresh lag exceeds its `TARGET_LAG` SLO
   (`DT_FLIGHT_RISK_REALTIME` at 5 min `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]`;
   the net-new OTP/avg-delay DT).
3. **DT refresh FAILURE** — a refresh errors out.

## Routing
Alerts route through a Notification Integration (email / webhook) to the OCC platform on-call. Native
Alerts + Notification chosen over a bespoke poller: server-side, grounded in ACCOUNT_USAGE / DT metadata,
no extra app tier, inherits existing RBAC `[WAF: operational_excellence, reliability]`.

## Residual (Gate-B, non-blocking)
The concrete recipient/escalation list and an alert de-duplication / suppression policy (to prevent alert
fatigue on the continuously-refreshing DTs) are left to implementation `[WAF: operational_excellence]`.
