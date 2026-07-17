---
name: kpi-definitions
description: "The OCC metric contract for the IROPS Intelligence Center — which flight-ops KPIs are GOVERNED (trustworthy, backed by a Snowflake object) versus NET-NEW / UNGOVERNED (must be built or elicited, never fabricated). Use whenever anyone in Network Operations Control asks 'what is the delay risk score', 'how do we measure on-time performance', 'what's the cost of this disruption', 'what's our rebooking success rate', or 'how long do swaps take' — even if they don't say the word KPI. Load this BEFORE writing any metric SQL so a proxy is never mistaken for the governed figure."
---

# IROPS KPI Definitions — the OCC Metric Contract

## When to Use
Load this skill whenever the VP of Flight Ops / OCC persona (or any analyst on their behalf) asks how a
disruption, delay, on-time, cost, rebooking, or swap metric is defined, or is about to write SQL that
computes one. This is the single source of truth for what is real and what is not yet real. If a metric
is not listed as GOVERNED here, do not present a number as authoritative — surface the gap.

## The Governance Ladder (read this first)
Every KPI below is tagged with one of three states:

- **GOVERNED** — a Snowflake object computes it and the definition is pinned to repo evidence. Safe to
  query and report.
- **NET-NEW (governable)** — the source columns exist but no governed aggregate exists yet; a declarative
  pipeline in this plugin builds it at the correct grain. Report only after that pipeline is deployed.
- **UNGOVERNED (elicit / do not invent)** — the number today is a hardcoded literal or a different-definition
  proxy. There is NO data-backed value. Never emit a formula that implies otherwise; escalate per the
  disruption-pnl / recovery-orchestration skills.

## KPI 1 — Delay Risk Score  ✅ GOVERNED
- **Intent / grain:** flight-leg; lower is better; a 0–1 probability the leg will be delayed
  `[intake job-predict-delay-risk → kpi "Delay risk score"]`.
- **Governed source:** `IROP_DB.ML.SCORE_FLIGHT_RISK(...)`, a Python/XGBoost UDF that runs the registered
  `FLIGHT_RISK_SCORER` model over 26 flight features
  `[repo@fbc59639 src/database/functions/score_flight_risk.sql]`, materialized per leg by the serving
  Dynamic Table `IROP_DB.DATA_MART.DT_FLIGHT_RISK_REALTIME` (TARGET_LAG = '5 minutes')
  `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]`.
- **Report from:** `DT_FLIGHT_RISK_REALTIME.REALTIME_RISK_SCORE` (ML score + MEL add-on, capped at 1.0),
  or `PROPAGATED_RISK_SCORE` when you need upstream (aircraft/crew) ripple included. Do NOT recompute the
  score by hand — read the governed column.
- **Explainability:** the score is composed, not a black box — `MEL_RISK_ADDON`, `IS_HIDDEN_RISK`,
  `INHERITED_DELAY_MINUTES`, `CREW_TIMEOUT_RISK` and `WEATHER_SEVERITY` are all surfaced columns so the OCC
  can see *why* a leg scored high `[repo@e74f234b …dt_flight_risk_realtime.sql]`. See `delay-risk-triage`.

## KPI 2 — On-Time Departure Rate  🟡 NET-NEW (governable)
- **Intent / grain:** route-day; higher is better; percent `[intake job-monitor-otp-trends → kpi
  "On-time departure rate"]`.
- **Gap:** there is NO governed OTP aggregate. Only the raw per-flight `STATUS` enum
  (ON_TIME/DELAYED/CANCELLED) and `DELAY_MINUTES` exist `[repo@9a0c2105
  src/database/migrations/V1.0.0__create_raw_tables.sql → raw_flights]`.
- **This plugin's build:** `scripts/dt_otp_delay_metrics.sql` defines OTP rate at route-day grain as the
  share of departures with `STATUS = 'ON_TIME'` (CANCELLED excluded from the numerator). Report only from
  that Dynamic Table once deployed — never hand-aggregate raw_flights inconsistently.
- **Trap:** do NOT substitute `FACT_ATC_EVENTS.avg_delay_minutes` or any ATC-event metric — that is a
  different grain `[intake job-monitor-otp-trends]`. See `otp-trend-monitor`.

## KPI 3 — Average Delay Minutes  🟡 NET-NEW (governable)
- **Intent / grain:** flight-leg; lower is better; minutes `[intake job-monitor-otp-trends → kpi
  "Average delay minutes"]`.
- **Gap:** only the raw per-flight `DELAY_MINUTES` column exists; no governed flight/network aggregate
  `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_flights.delay_minutes]`.
- **This plugin's build:** `scripts/dt_otp_delay_metrics.sql` averages `DELAY_MINUTES` at the flight-leg
  grain. Do NOT reuse `raw_atc_events.avg_delay_minutes` — it is ATC-event grain, a different KPI
  `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_atc_events.avg_delay_minutes]`.

## KPI 4 — Cost per Disruption Event  🔴 UNGOVERNED (elicit / do not invent)
- **Intent / grain:** disruption-event; lower is better; USD `[intake job-analyze-disruption-cost → kpi
  "Cost per disruption event"]`.
- **Why ungoverned:** the only related governed figure is `total_revenue_exposure`, a SUM of ticket value
  emitted by `IROP_DB.ML.CALCULATE_NETWORK_IMPACT(...)` `[repo@15a11075
  src/database/functions/calculate_network_impact.sql]`. That is **revenue at risk, not operational cost**
  — it excludes crew overtime, hotel, fuel-burn, and voucher costs required for a true IROP P&L
  `[context: irops-strategy.md §2B "Real-Time P&L of the IROP"]`.
- **Rule:** never present `total_revenue_exposure` as "cost per disruption event". Report the proxy
  explicitly labelled as revenue-at-risk, and escalate the missing cost feeds. Definition target lives in
  `references/disruption-cost-model.md`. See `disruption-pnl`.

## KPI 5 — Rebooking Success Rate  🔴 UNGOVERNED (elicit / do not invent)
- **Intent / grain:** disruption-event; higher is better; percent `[intake job-optimize-irops-recovery →
  kpi "Rebooking success rate"]`.
- **Why ungoverned:** the value is a hardcoded constant (0.85 / 0.65, `ml_backed=False`) in the FastAPI
  app; no rebooking-outcomes table exists to compute a true rate `[repo@e0ba7c4e api/app/main.py]`.
- **Rule:** treat as unmeasurable until outcome capture is instrumented
  (`references/rebooking-outcomes-model.md`). See `recovery-orchestration`.

## KPI 6 — Crew/Aircraft Swap Time  🔴 UNGOVERNED (elicit / do not invent)
- **Intent / grain:** swap-event; lower is better; minutes `[intake job-optimize-irops-recovery → kpi
  "Crew/aircraft swap time"]`.
- **Why ungoverned:** static literals (45 / 30 min) in the FastAPI app; no historical swap log exists to
  measure actual durations `[repo@e0ba7c4e api/app/main.py]`.
- **Rule:** treat as unmeasurable until a swap-event log is captured (`references/swap-time-model.md`).
  See `recovery-orchestration`.

## Generating SQL for a governed metric (mandatory method)
When asked to compute any metric:
1. Confirm its state above. If GOVERNED or NET-NEW-deployed, read the **modeled object** (the Dynamic
   Table or the semantic view `IROP_OPERATIONS_SV`) — never a raw base table `[WAF: operational_excellence]`.
2. Use the governed grain exactly (flight-leg vs route-day vs disruption-event). A grain mismatch is the
   most common OCC reporting error.
3. If any term in the request is UNGOVERNED, STOP: return the governed portion and flag the ungoverned
   portion as non-conformant. Do not fill the gap with a proxy or a literal.

MANDATORY STOPPING POINT: If the user asks for KPI 4, 5, or 6 as a governed number, do not produce one —
explain it is ungoverned, name the missing source, and offer the build path.

## Output
A precise, grain-correct metric definition with its governance state and the governed object to read (or
the named gap and escalation when it is not yet real).
