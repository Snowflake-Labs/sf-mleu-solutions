---
name: disruption-pnl
description: "Quantify the network cascade and financial exposure of an active disruption — the Real-Time P&L of the IROP — so the OCC can rank the highest-impact disruption sources and prioritize recovery spend. Use whenever someone asks 'what is this disruption costing', 'what's the revenue at risk', 'how far does this cascade', 'downstream impact of flight X', 'is this worth recovering', or wants an IROP P&L. CRITICAL: the governed figure today is revenue-at-risk, NOT operational cost — never present it as 'cost per disruption event'."
parent_skill: primary-workflow
---

# Disruption P&L — Network Impact & Financial Exposure

## When to Load
`primary-workflow` routes here to quantify the impact of a disruption `[intake job-analyze-disruption-cost]`.
The goal is to pinpoint the highest-cost disruption sources and prioritize recovery
`[intake job-analyze-disruption-cost → outcomes]`, replacing manual, lagging cost estimation
`[intake job-analyze-disruption-cost → pain_points]` — moving the financial close into the operation
`[context: irops-strategy.md §2B "Real-Time P&L of the IROP"]`.

## Prerequisites
- USAGE on `IROP_DB.ML.CALCULATE_NETWORK_IMPACT(VARCHAR)` and read on `DT_FLIGHT_RISK_REALTIME`.
- Read `../kpi-definitions/SKILL.md` KPI 4 — the cost governance state — BEFORE reporting any dollar figure.

## Workflow

### Step 1: Quantify the network cascade  ✅ GOVERNED
**Goal:** measure how far the disruption ripples.
**Actions:**
1. Call the governed downline-cascade UDF for the disrupted leg:
   ```sql
   SELECT IROP_DB.ML.CALCULATE_NETWORK_IMPACT(:flight_id) AS impact;
   ```
   It recursively walks the aircraft rotation up to 5 hops and returns `downstream_flights`,
   `max_cascade_depth`, `total_passengers_affected`, `elite_passengers_affected`, `connections_at_risk`,
   `total_revenue_exposure`, and a composite `network_impact_score`
   `[repo@15a11075 src/database/functions/calculate_network_impact.sql]`.
2. This is the "Downline Ripple Effect" — the what-if the strategy positions as the network-resilience
   engine `[context: irops-strategy.md §3A]`.

### Step 2: Report revenue at risk — correctly labelled  ⚠️ PROXY, NOT COST
**Goal:** present financial exposure without misrepresenting it.
**Actions:**
1. Report `total_revenue_exposure` (SUM of affected ticket value) explicitly as **revenue at risk**, not
   as operational cost `[repo@15a11075 …calculate_network_impact.sql]`.
2. State plainly: this excludes crew overtime, hotel, fuel-burn, and voucher costs, so it is a *different
   definition* from the KPI "Cost per disruption event" `[context: irops-strategy.md §2B]`.

MANDATORY STOPPING POINT: If the OCC asks for "cost per disruption event" as a governed dollar figure, do
NOT emit one. The operational cost feeds are NOT YET GOVERNED — only a revenue-exposure proxy exists
`[repo@15a11075 …calculate_network_impact.sql]`. Surface the gap and offer the build path.

### Step 3: Surface the cost-model gap (escalation)
**Goal:** turn the gap into a decision, not a silent proxy.
**Actions:**
1. Point to `references/disruption-cost-model.md`, which specifies the true IROP-P&L definition
   (disruption-event grain) and names the four missing feeds: crew OT, hotel, fuel-burn, vouchers.
2. Note the escalation: build the governed cost model; do NOT ship the revenue proxy as the KPI; Gate-B
   confirms data-source ownership before implementation `[WAF: security_governance — single trusted cost
   figure]`.

### Step 4: Validate
**Validation Checklist:**
- Every dollar figure reported is labelled revenue-at-risk, never "cost".
- The cascade metrics came from `CALCULATE_NETWORK_IMPACT`, not a hand-rolled join.
- The cost gap was surfaced whenever a cost question was asked.

## Stopping Points
- Before reporting any number as "cost" — stop and reclassify as revenue-at-risk.
- After presenting exposure — hand the highest-impact disruptions to `../recovery-orchestration`.

## Output
A grounded network-cascade + revenue-at-risk assessment for the disruption, with the operational-cost gap
explicitly surfaced (never a proxy passed off as the cost KPI).
