# Flight Risk Realtime Pipeline — Serving Dynamic Table

**Component:** `cmp-flight-risk-realtime-dt` (Dynamic Tables) · traces to `cap-predict-delay-risk`.
**Status:** GROUNDED, documents an existing declarative pipeline.

## What it is
`IROP_DB.DATA_MART.DT_FLIGHT_RISK_REALTIME` is a serverless Dynamic Table that materializes a scored,
OCC-ready row per flight leg for low-latency reads. It is defined with `TARGET_LAG = '5 minutes'` on
`WAREHOUSE = IROP_ML_WH` `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]`.

## What it assembles
It joins the cleansed flight feed to crew metrics (min/avg duty, timeout prob, at-risk count from
`crew_assignments`), passenger exposure (loyalty-tier counts, revenue, risky connections from
`fact_passenger_exposure`), origin/destination weather (severity, wind, visibility, ceiling from
`weather_forecasts`), aircraft-rotation features (downstream flights, min turn time from `aircraft_legs`),
and MEL flags (`raw_maintenance_flags`), then calls `IROP_DB.ML.SCORE_FLIGHT_RISK` per leg
`[repo@e74f234b …dt_flight_risk_realtime.sql]`.

## Served columns the OCC reads
- `REALTIME_RISK_SCORE` — ML score + `MEL_RISK_ADDON`, capped at 1.0.
- `PROPAGATED_RISK_SCORE` — adds upstream aircraft + crew propagation (`INHERITED_DELAY_MINUTES`,
  `BUFFER_EROSION`).
- `IS_HIDDEN_RISK` — ON_TIME legs carrying dispatch hold / severe dest weather / crew timeout / >30 min
  inherited delay.
- `COMPUTED_AT` — freshness stamp `[repo@e74f234b …dt_flight_risk_realtime.sql]`.

## WAF posture
- **Reliability** — serverless Dynamic Table gives auto-recovering incremental refresh; chosen over
  Streams+Tasks for declarative simplicity `[WAF: reliability]`.
- **Performance** — pre-materialized serving for the OCC read pattern. **Clustering-key guidance:** cluster
  the serving DT on `scheduled_departure` date / route so OCC filter predicates prune micro-partitions
  `[WAF: performance_optimization]`.
- **Cost** — serverless auto-suspend; tune `TARGET_LAG` to the OCC freshness SLO so refresh credits track
  the real freshness need rather than over-refreshing `[WAF: cost_optimization]`. See
  `resource-monitors-budgets.md` and `dr-continuity-runbook.md` (Time Travel retention on this DT).
