# Flight Risk Model — Invocation Contract

**Component:** `cmp-flight-risk-model` (Model Registry) · traces to `cap-predict-delay-risk`.
**Status:** GROUNDED, documents an existing asset — this is a reference, not a build.

## What it is
`FLIGHT_RISK_SCORER` is a registered XGBoost classifier that outputs a 0–1 probability that a flight leg
will be delayed. It is exposed to SQL as the UDF `IROP_DB.ML.SCORE_FLIGHT_RISK(...)`, a Python UDF
(`RUNTIME_VERSION 3.11`, packages `snowflake-ml-python, pandas, xgboost`) that loads the model from the
Snowflake Model Registry (`Registry(database=IROP_DB, schema=ML).get_model("FLIGHT_RISK_SCORER").default`)
and calls `predict_proba` `[repo@fbc59639 src/database/functions/score_flight_risk.sql]`.

## Feature contract (26 inputs, in order)
`scheduled_duration_minutes, turn_buffer_minutes, departure_hour, day_of_week, origin_is_hub, dest_is_hub,
min_crew_duty_remaining, avg_crew_duty_remaining, max_crew_timeout_prob, crew_at_risk_count,
reserve_crew_count, total_passengers, connecting_pax, tight_connection_pax, elite_pax, avg_ticket_value,
origin_weather_severity, origin_wind_speed, origin_visibility, origin_ceiling, dest_weather_severity,
dest_wind_speed, dest_visibility, dest_ceiling, downstream_flights, min_turn_time`
`[repo@fbc59639 …score_flight_risk.sql]`. Each has a null-safe default (e.g. duty 480 min, ticket $300),
so a partial feature row still scores.

## Explainability notes (why this matters to the OCC)
The score is not consumed raw. The serving Dynamic Table decomposes it into auditable drivers
(`mel_risk_addon`, `crew_timeout_risk`, `weather_severity`, `inherited_delay_minutes`, `is_hidden_risk`)
so the OCC can see *why* a leg scored high — the explainability constraint the capability requires
`[use_case_spec cap-predict-delay-risk → constraints]`. On any scoring exception the UDF returns a neutral
0.5 `[repo@fbc59639 …score_flight_risk.sql]`.

## Governance & performance
- **Versioned model** — served through the Registry `.default` alias so the model can be re-trained and
  promoted without changing the UDF signature `[WAF: reliability]`.
- **UDF inference pushed to compute** — scoring runs where the data lives, no external serving tier
  `[WAF: performance_optimization]`.

## AI-vs-ML boundary
This is classical predictive ML, deliberately kept distinct from the generative surfaces (Analyst /
Search / Agent). The agent may *invoke* this scorer as a tool, but the score itself is not generative.
