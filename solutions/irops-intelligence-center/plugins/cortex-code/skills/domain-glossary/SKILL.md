---
name: domain-glossary
description: "Shared OCC / aviation vocabulary for the IROPS Intelligence Center so every Analyst prompt, skill step, and metric uses one consistent term and grain. Use whenever anyone asks 'what does <term> mean', is unsure of a grain (flight-leg vs route-day vs ATC-event vs swap-event), or mentions OTP, IROP, tail swap, MEL, duty legality / FAR Part 117, downline ripple, hidden risk, elite / Mosaic guest, network impact, or hub. Load this before writing SQL to avoid the FACT_ATC_EVENTS vs flight-leg grain trap."
---

# IROPS Domain Glossary

## When to Use
Load whenever a term or grain is ambiguous, before an Analyst NL query, or when reconciling two people who
mean different things by the same word. A shared vocabulary is what prevents mis-grained queries — the
single most common OCC analysis error `[WAF: operational_excellence]`.

## Terms

- **IROP (Irregular Operations)** — any deviation from the published schedule (delay, cancellation,
  diversion, ground stop) requiring active recovery. The strategy frames the OCC's job as moving from a
  "Monitoring Loop" to "Predictive Orchestration" over IROPs `[context: irops-strategy.md §1 POV]`.

- **OTP (On-Time Performance) / On-Time Departure Rate** — share of departures with `STATUS = 'ON_TIME'`.
  Governed grain for this plugin is **route-day** `[intake job-monitor-otp-trends → kpi "On-time departure
  rate"]`. Status enum values are ON_TIME / DELAYED / CANCELLED `[repo@9a0c2105
  src/database/migrations/V1.0.0__create_raw_tables.sql → raw_flights.status]`.

- **Delay minutes** — per-flight lateness in minutes, `raw_flights.delay_minutes` (0 if on-time). Governed
  KPI grain is **flight-leg** `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_flights.delay_minutes]`.
  Do NOT confuse with `raw_atc_events.avg_delay_minutes`, which is **ATC-event** grain (EDCT/GDP/AFP) — a
  different metric `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_atc_events]`.

- **Flight-leg** — one scheduled origin→destination operation of a single flight_id. The grain for delay
  risk score and average delay minutes.

- **Route-day** — one (origin, destination, flight_date) combination. The grain for OTP rate.

- **Disruption-event** — a single operational disruption (e.g. a ground stop or a cancellation cascade).
  The grain for cost per disruption event and rebooking success rate `[intake job-analyze-disruption-cost,
  job-optimize-irops-recovery]`.

- **Swap-event** — one crew or aircraft swap action, with a start and complete time. The grain for
  crew/aircraft swap time — currently uncaptured `[intake job-optimize-irops-recovery]`.

- **Delay risk score** — 0–1 probability a leg is delayed, from `IROP_DB.ML.SCORE_FLIGHT_RISK` served by
  `DT_FLIGHT_RISK_REALTIME` `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql;
  repo@fbc59639 src/database/functions/score_flight_risk.sql]`.

- **Hidden risk** — a flight that reads ON_TIME but carries a high destination-weather severity, a
  maintenance dispatch hold, high crew timeout probability, or >30 min inherited upstream delay; surfaced
  as `IS_HIDDEN_RISK` `[repo@e74f234b …dt_flight_risk_realtime.sql]`.

- **Downline ripple / propagation** — the cascade of a disruption onto downstream legs of the same tail
  and connecting passengers, quantified recursively (up to 5 hops) by
  `IROP_DB.ML.CALCULATE_NETWORK_IMPACT` `[repo@15a11075 src/database/functions/calculate_network_impact.sql]`
  and the "Downline Ripple Effect" what-if concept `[context: irops-strategy.md §3A]`.

- **MEL (Minimum Equipment List) / dispatch hold** — a maintenance deferral on a tail; `affects_dispatch`
  and severity drive a risk add-on `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_maintenance_flags;
  repo@e74f234b …dt_flight_risk_realtime.sql → mel_risk_addon]`.

- **Duty legality / FAR Part 117** — crew duty-time limits; `remaining_duty_minutes` and
  `timeout_probability` yield `legality_status` (LEGAL / WARNING / CRITICAL). The "Time-Out Guardrail"
  concept `[repo@9a0c2105 …V1.0.0__create_raw_tables.sql → raw_crew_duty_periods; context:
  irops-strategy.md §3B]`.

- **Tail swap** — reassigning a different aircraft (tail) to a flight during recovery; the canonical
  Algorithmic-Sovereignty use case the airline should own and tune `[context: irops-strategy.md §2A, §4]`.

- **Elite / Mosaic guest (high-LTV)** — high-loyalty-tier passengers (Diamond/Platinum/Gold) prioritized
  in recovery; counted as `elite_passengers` `[repo@e74f234b …dt_flight_risk_realtime.sql;
  context: irops-strategy.md §3C "High-Value Guest Recovery"]`.

- **Revenue at risk vs cost** — `total_revenue_exposure` (ticket value of affected pax) is NOT operational
  cost. A true IROP P&L adds crew OT + hotel + fuel + vouchers `[repo@15a11075
  …calculate_network_impact.sql; context: irops-strategy.md §2B]`. See `kpi-definitions` KPI 4.

- **Hub** — a connecting airport; origin/dest-is-hub is a model feature (ATL, DTW, MSP, SLC, SEA, LAX,
  JFK, BOS) `[repo@e74f234b …dt_flight_risk_realtime.sql]`.

## Output
The canonical definition and grain for the requested term, with the governed object or repo evidence that
backs it — so downstream queries use one consistent vocabulary.
