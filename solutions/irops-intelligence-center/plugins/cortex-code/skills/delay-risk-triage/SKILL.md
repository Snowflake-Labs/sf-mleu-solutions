---
name: delay-risk-triage
description: "Rank the flight legs most likely to be delayed and EXPLAIN each score so the OCC trusts it and can intervene before the delay materializes. Use whenever the VP of Flight Ops / OCC says 'which flights are at risk', 'rank the risky legs', 'what should we watch tonight', 'why did this flight score high', 'show me the hidden risks', or is triaging a building disruption — even if they don't say 'risk score'. This is classical predictive scoring over the governed ML stack, kept distinct from the generative agent."
parent_skill: primary-workflow
---

# Delay Risk Triage

## When to Load
`primary-workflow` routes here when the OCC needs to rank at-risk legs or understand *why* a leg is risky
`[intake job-predict-delay-risk]`. The driving outcome is proactive intervention on high-risk flights
before the delay happens `[intake job-predict-delay-risk → outcomes]`, replacing reactive, not-predictive
visibility `[intake job-predict-delay-risk → pain_points]`.

## Prerequisites
- Read access to `IROP_DB.DATA_MART.DT_FLIGHT_RISK_REALTIME` (the governed serving table).
- The Dynamic Table is refreshing (TARGET_LAG = '5 minutes'); if refresh is stale, see
  `references/flight-risk-realtime-pipeline.md` and the alerting reference before trusting the ranking.
- Familiarity with the score's meaning — **Load** `../kpi-definitions/SKILL.md` (KPI 1) if unsure.

## Workflow

### Step 1: Frame the window and scope
**Goal:** bound the triage so the read is cheap and relevant.
**Actions:**
1. Confirm the scope with the OCC: a hub (origin/destination), a time window
   (`SCHEDULED_DEPARTURE`), or the whole network.
2. Default to the near-term operating window rather than a full-table scan.

### Step 2: Rank at-risk legs
**Goal:** produce the ranked worklist from the governed column.
**Actions:**
1. Query `DT_FLIGHT_RISK_REALTIME`, ordering by `REALTIME_RISK_SCORE DESC` (ML score + MEL add-on),
   or `PROPAGATED_RISK_SCORE DESC` when upstream ripple should be included
   `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]`.
2. Read the governed column — do NOT recompute the score by hand. Example shape:
   ```sql
   SELECT flight_id, flight_number, origin_airport, destination_airport, status,
          realtime_risk_score, propagated_risk_score, is_hidden_risk,
          crew_timeout_risk, weather_severity, active_mel_count, elite_passengers
   FROM IROP_DB.DATA_MART.DT_FLIGHT_RISK_REALTIME
   WHERE scheduled_departure BETWEEN :window_start AND :window_end
   ORDER BY realtime_risk_score DESC
   LIMIT 25;
   ```
3. Always include the hidden-risk cut: legs where `IS_HIDDEN_RISK = TRUE` read ON_TIME but carry a
   dispatch hold, high dest-weather severity, crew timeout, or >30 min inherited delay
   `[repo@e74f234b …dt_flight_risk_realtime.sql]`.

### Step 3: Explain each high score (OCC trust)
**Goal:** satisfy the explainability constraint so the OCC acts on the score
`[use_case_spec cap-predict-delay-risk → constraints: explainability]`.
**Actions:**
1. For each top leg, decompose the drivers from the surfaced columns: `MEL_RISK_ADDON` (maintenance),
   `CREW_TIMEOUT_RISK` (FAR Part 117 duty), `WEATHER_SEVERITY` / `WEATHER_CONDITIONS`,
   `INHERITED_DELAY_MINUTES` + `BUFFER_EROSION` (upstream ripple), and `RISKY_CONNECTIONS` / `ELITE_PASSENGERS`
   (guest exposure) `[repo@e74f234b …dt_flight_risk_realtime.sql]`.
2. State the score as a composed, auditable figure, not a black box — the model is XGBoost
   `FLIGHT_RISK_SCORER` over 26 features `[repo@fbc59639 src/database/functions/score_flight_risk.sql]`.
   See `references/flight-risk-model.md` for the feature contract.

### Step 4: Validate before acting
**Validation Checklist:**
- The ranking read `DT_FLIGHT_RISK_REALTIME`, not a raw base table.
- `COMPUTED_AT` is within the refresh SLO (not stale).
- Each recommended leg has an explained driver, not just a number.

**If validation fails:** return to Step 2 with a corrected window, or flag the pipeline freshness gap.
**If validation succeeds:** hand the ranked, explained worklist forward — typically to `../disruption-pnl`
(quantify) or `../recovery-orchestration` (act).

## Stopping Points
- After Step 3, before recommending any operational action — the OCC owns the intervention decision;
  present the ranked+explained list and stop.
- If the score cannot be explained from the surfaced columns, do not invent a rationale — say so.

## Output
A ranked, explained worklist of at-risk legs (including hidden risks) from the governed serving table,
ready for impact quantification or recovery.
