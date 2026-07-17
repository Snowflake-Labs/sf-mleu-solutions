# Rebooking Outcomes Model — NET-NEW Definition (build gap)

**Component:** `cmp-rebooking-outcomes-model` (Streams + Tasks) · traces to `cap-optimize-rebooking-success`.
**Status:** NET-NEW · **no repo provenance** · DEFINITION + escalation, not a runnable script — the source
is an open gap.

## The metric this must eventually govern
**Rebooking success rate** — percent, disruption-event grain, direction up
`[intake job-optimize-irops-recovery → kpi "Rebooking success rate"]`. Increase the share of disrupted
passengers successfully rebooked, so recovery is outcome-driven rather than ad hoc
`[use_case_spec cap-optimize-rebooking-success]`.

## Why it is not governed today
The value is a **hardcoded constant (0.85 / 0.65, `ml_backed=False`)** in the FastAPI app — not data-backed
— and **no rebooking-outcomes table exists** to compute a true rate `[repo@e0ba7c4e api/app/main.py]`.

## Required capture (instrument before the KPI is real)
1. A **rebooking-outcomes** event feed: per disrupted PNR, the rebooking attempt and its resolution
   (rebooked-confirmed / declined / stranded), timestamped, keyed to the disruption-event.
   `raw_pnr_trips` (`pnr_id`, `rebook_flexibility_index`, `pnr_reaccom_complexity_score`) is the itinerary
   anchor but carries no *outcome* `[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql →
   raw_pnr_trips]`.
2. **Streams + Tasks** instrumentation to capture outcome events incrementally as recovery actions land,
   then aggregate to disruption-event grain.

## Target definition (once captured)
`rebooking_success_rate = successfully_rebooked_pax / disrupted_pax` at disruption-event grain.

## Escalation
Instrument outcome capture; treat the KPI as net-new / unmeasurable until the outcomes table lands. Do not
report the FastAPI literal as a rate `[WAF: reliability — trustworthy outcome capture required before the
KPI is real]`. Consumed by the `recovery-orchestration` skill.
