# Swap Time Model — NET-NEW Definition (build gap)

**Component:** `cmp-swap-time-model` (Streams + Tasks) · traces to `cap-accelerate-crew-aircraft-swaps`.
**Status:** NET-NEW · **no repo provenance** · DEFINITION + escalation, not a runnable script — the source
is an open gap.

## The metric this must eventually govern
**Crew/aircraft swap time** — minutes, swap-event grain, direction down
`[intake job-optimize-irops-recovery → kpi "Crew/aircraft swap time"]`. Reduce the time to execute crew
and aircraft swaps so the network stabilizes faster `[use_case_spec cap-accelerate-crew-aircraft-swaps]`.

## Why it is not governed today
Swap time is represented by **static literals (45 / 30 min)** in the FastAPI app, and **no historical
swap log exists** to measure actual durations `[repo@e0ba7c4e api/app/main.py]`.

## Required capture (instrument before the KPI is real)
1. A **swap-event log**: one row per crew or aircraft swap with `swap_start_ts` and `swap_complete_ts`,
   swap type (crew / tail), the flights involved, and the outcome. The aircraft-rotation chain
   (`raw_aircraft_rotation`: `aircraft_tail`, `next_flight_id`, `previous_flight_id`) gives the swap
   *context* but records no swap timing `[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql
   → raw_aircraft_rotation]`.
2. **Streams + Tasks** to capture swap start/complete events as they occur and aggregate to swap-event
   grain.

## Target definition (once captured)
`swap_time_minutes = DATEDIFF('minute', swap_start_ts, swap_complete_ts)` at swap-event grain; report
percentiles, not just the mean.

## Escalation
Capture the swap-event log; the KPI stays net-new / unmeasurable until then. Do not report the FastAPI
literals as durations `[WAF: reliability — event log needed before the duration KPI is measurable]`.
Consumed by the `recovery-orchestration` skill, whose swap logic should move into governed dbt models
(`algorithmic-sovereignty-dbt.md`).
