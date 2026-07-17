# Cortex Analyst — IROP_OPERATIONS_SV Semantic Model

**Component:** `cmp-cortex-analyst` (Cortex Analyst) · traces to `cap-predict-delay-risk`,
`cap-analyze-disruption-cost`, `cap-monitor-otp-departure-rate`, `cap-monitor-avg-delay-minutes`.
**Status:** GROUNDED text-to-SQL surface over an existing semantic model.

## What it is
A natural-language query surface for the OCC over the semantic view `IROP_DB.CORTEX.IROP_OPERATIONS_SV`,
backed by the semantic model `src/cortex/analyst/irop_semantic_model.yaml` (`name: irop_flight_operations`)
`[repo@1296bfdd src/cortex/analyst/irop_semantic_model.yaml]`. It lets an OCC director query the state of
the airline in natural language and get an answer in seconds `[context: irops-strategy.md §6]`.

## Modeled tables (read these, never raw base tables)
- `flights` → `IROP_DB.ATOMIC.FLIGHTS_CLEANSED` (status, delay_minutes, schedule).
- `flight_risk` → `IROP_DB.DATA_MART.DT_FLIGHT_RISK_REALTIME` (risk_score, is_hidden_risk, revenue_at_risk,
  elite_passengers).
- `passenger_exposure` → `FACT_PASSENGER_EXPOSURE`; `crew_legality` → `FACT_CREW_LEGALITY`;
  `weather_forecasts` → `WEATHER_FORECASTS` `[repo@1296bfdd …irop_semantic_model.yaml]`.
The model ships verified queries (highest-risk flights, hidden-risk flights, revenue at risk, crew timeout
risk, network impact) `[repo@1296bfdd …irop_semantic_model.yaml → verified_queries]`.

## Net-new metrics must be added here to be answerable
The net-new OTP rate and average delay minutes (`scripts/dt_otp_delay_metrics.sql`) are NOT yet in this
semantic model. Until a `flights`-side route-day OTP measure and a flight-leg average-delay measure are
added to `irop_semantic_model.yaml`, Analyst cannot answer OTP-trend questions. See `otp-trend-monitor`.

## WAF posture
- **Security/governance** — Cortex Analyst is SELECT-only by design and inherits the caller's RBAC; this
  is the governance boundary for the generative layer `[WAF: security_governance]`.
- **AI data governance lens** — the operational data joins to passenger PII, so the model reads the
  classification-tagged, masked columns per `rbac-masking-governance.md` and
  `network-policy-classification.md`; the surface is guarded by Cortex Guard (`ai-governance-guardrails.md`).
