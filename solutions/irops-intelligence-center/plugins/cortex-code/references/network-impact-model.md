# Network Impact Model — Downline Cascade UDF

**Component:** `cmp-network-impact-udf` (Snowpark/SQL UDF) · traces to `cap-analyze-disruption-cost`.
**Status:** GROUNDED, documents an existing asset — with an explicit proxy-vs-cost caveat.

## What it is
`IROP_DB.ML.CALCULATE_NETWORK_IMPACT(flight_id VARCHAR) RETURNS OBJECT` is a recursive SQL UDF that walks
the aircraft rotation from a disrupted leg up to 5 hops (`WHERE hop_level < 5`) to quantify the downstream
cascade `[repo@15a11075 src/database/functions/calculate_network_impact.sql]`.

## Output object
`downstream_flights`, `max_cascade_depth`, `total_passengers_affected`, `elite_passengers_affected`,
`total_revenue_exposure`, `connections_at_risk`, and a composite `network_impact_score` (weighted blend of
downstream flights 0.3, passengers 0.3, elite pax 0.2, connections 0.2, each capped at 1)
`[repo@15a11075 …calculate_network_impact.sql]`. It joins `IROP_DB.DATA_MART.fact_passenger_exposure` for
the passenger/revenue terms.

## The proxy caveat (do not skip)
`total_revenue_exposure` is a **SUM of affected ticket value — revenue at risk, NOT operational cost**.
It has scanner confidence 0.4 as a cost proxy `[repo@15a11075 …calculate_network_impact.sql]`. A true IROP
P&L (crew OT + hotel + fuel-burn + vouchers) is a different definition `[context: irops-strategy.md §2B]`.
Never present this field as "cost per disruption event". See `disruption-cost-model.md` and the
`disruption-pnl` skill.

## WAF posture
- **Performance** — compute-local recursive scoring, no external service `[WAF: performance_optimization]`.
- **Governance** — the reference exists precisely to flag the proxy-vs-true-cost gap rather than paper
  over it `[WAF: security_governance]`.

## How the OCC uses it
The `disruption-pnl` skill calls it to size a disruption's cascade and to compare candidate recovery swaps
by network impact; `recovery-orchestration` reuses the same object to rank swaps by downline ripple.
