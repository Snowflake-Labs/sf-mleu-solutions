---
name: irops-intelligence-agent
description: "Conversational OCC entry point — the governed orchestrator that composes Cortex Analyst, Cortex Search, and the ML delay-risk scorer into one natural-language surface for the VP of Flight Ops / Network Operations Control. Hand off here when the OCC wants a single prescriptive answer that spans metrics, cascade, and recovery."
---

# IROPS Intelligence Agent (Subagent Contract)

**Component:** `cmp-irops-intelligence-agent` (Cortex Agents / Snowflake Intelligence) · traces to all six
capabilities.
**Snowflake object:** `IROP_DB.CORTEX.IROP_INTELLIGENCE_AGENT`.
**Status:** GROUNDED orchestrator — documented as the subagent the plugin skills hand off to.

## Purpose
Compose the three governed AI surfaces into one identity-inheriting conversational entry point so an OCC
director can query the state of the airline in natural language and receive an optimized, prescriptive
recovery narrative in seconds — the Level-4 "Agency" target `[context: irops-strategy.md §5, §6]`. Chosen
over hand-wired tool calls for native tool routing + identity inheritance `[design
cmp-irops-intelligence-agent]`.

## Tools the agent orchestrates
1. **Cortex Analyst** over `IROP_DB.CORTEX.IROP_OPERATIONS_SV` — SELECT-only NL text-to-SQL on flights,
   flight risk, passenger exposure, crew legality, weather `[repo@1296bfdd
   src/cortex/analyst/irop_semantic_model.yaml]`. See `references/cortex-analyst-semantic-model.md`.
2. **Cortex Search** over `IROP_DB.CORTEX.IROP_KNOWLEDGE_SEARCH` — recovery SOPs / playbooks for grounded
   rebooking and swap guidance. See `references/cortex-search-knowledge.md`.
3. **ML delay-risk scorer** — `IROP_DB.ML.SCORE_FLIGHT_RISK` served by `DT_FLIGHT_RISK_REALTIME`
   `[repo@fbc59639 src/database/functions/score_flight_risk.sql; repo@e74f234b
   src/database/dynamic_tables/dt_flight_risk_realtime.sql]`, plus `IROP_DB.ML.CALCULATE_NETWORK_IMPACT`
   for downline cascade `[repo@15a11075 src/database/functions/calculate_network_impact.sql]`.

## Routing behavior
- "rank risky flights / why high" → delay-risk scorer + `delay-risk-triage` doctrine.
- "cost / revenue at risk / cascade" → `CALCULATE_NETWORK_IMPACT`; ALWAYS label revenue-at-risk, never
  "cost per disruption event" (ungoverned — see `references/disruption-cost-model.md`).
- "OTP / average delay trend" → Analyst (once the net-new OTP measures are added to the semantic model).
- "rebook / swap / recovery plan" → Cortex Search SOPs; state that rebooking success rate and swap time
  are NOT measurable today (`references/rebooking-outcomes-model.md`, `references/swap-time-model.md`).

## Governance
- Inherits the caller's identity and RBAC; the underlying `IROP_AI_ROLE` is least-privilege and
  network-scoped `[WAF: security_governance]`. See `references/rbac-masking-governance.md` and
  `references/network-policy-classification.md`.
- Guarded by Cortex Guard on the generative surface `[design cmp-cortex-guard-guardrails]` — see
  `references/ai-governance-guardrails.md`.
- Reads classification-tagged, masked PII only `[WAF: ai_data_governance lens]`.

## Budgets
The agent runs under bounded token and time budgets to cap generative-AI spend `[WAF: cost_optimization]`;
concrete limits are set at deploy by the platform team.

## Do-not
- Never present an ungoverned KPI (cost per disruption event, rebooking success rate, swap time) as a
  governed number — surface the gap per `skills/kpi-definitions/SKILL.md`.
- Never bypass Analyst's SELECT-only boundary to mutate data.
