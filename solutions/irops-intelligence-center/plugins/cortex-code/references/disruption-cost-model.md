# Disruption Cost Model — NET-NEW Governed Definition (build gap)

**Component:** `cmp-disruption-cost-model` (Semantic Views) · traces to `cap-analyze-disruption-cost`.
**Status:** NET-NEW · **no repo provenance** · this is a DEFINITION + escalation, not a runnable script,
because the source data is an open gap.

## The metric this must eventually govern
**Cost per disruption event** — USD, disruption-event grain, direction down
`[intake job-analyze-disruption-cost → kpi "Cost per disruption event"]`. This is the "Real-Time P&L of
the IROP": move the financial close into the operation by joining fuel burn, crew overtime, voucher
issuance, and estimated churn in real time `[context: irops-strategy.md §2B]`.

## Why it is not governed today
The only related governed figure is `total_revenue_exposure` from
`IROP_DB.ML.CALCULATE_NETWORK_IMPACT` — a SUM of ticket value (revenue at risk), scanner cost-proxy
confidence 0.4 `[repo@15a11075 src/database/functions/calculate_network_impact.sql]`. Revenue-at-risk and
operational cost are **two different definitions**; the proxy must not be shipped as the KPI.

## Required-but-missing feeds (elicit / source before building)
A true operational cost per disruption event needs four feeds that are **NOT YET GOVERNED**:
1. **Crew overtime** cost (from duty/pay systems).
2. **Hotel / accommodation** cost for stranded crew and passengers.
3. **Fuel-burn** cost delta from re-routing/holding.
4. **Voucher / compensation** issuance (a partial signal exists in
   `raw_pnr_trips.estimated_voucher_cost_usd` `[repo@9a0c2105
   src/database/migrations/V1.0.0__create_raw_tables.sql → raw_pnr_trips]`, but it is an estimate, not
   actual issuance).

## Target definition (once feeds land)
A semantic view measure at disruption-event grain:
`cost_per_disruption_event = crew_ot_cost + hotel_cost + fuel_burn_delta_cost + voucher_cost` — read only
modeled cost tables, never raw base tables, and enumerate columns (never `SELECT *`).

## Escalation
Build the governed cost model; do NOT ship the revenue proxy as the KPI. Board / Gate-B confirms
data-source ownership for the four feeds before implementation `[WAF: security_governance — single trusted
cost figure]`. Until then, `disruption-pnl` reports revenue-at-risk explicitly labelled, and flags this
gap.
