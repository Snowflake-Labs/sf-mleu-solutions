---
name: primary-workflow
description: "The end-to-end OCC IROPS triage runbook and router for the Network Operations Control persona: detect a degrading operational signal, rank the at-risk flight legs, quantify the network/financial impact, then orchestrate recovery. Use this whenever someone in the OCC says 'we have a disruption', 'ATL is going down', 'what should we do about the weather in the hub', 'walk me through the irregular ops', or asks for an end-to-end recovery plan — even if they name only one piece. Routes to the domain sub-skills; complete ONE before starting the next."
---

# IROPS Triage — Primary OCC Workflow (Router)

## When to Use
Use when the VP of Flight Ops / OCC needs the full irregular-operations loop rather than a single metric:
a weather cell is building over a hub, a ground stop just landed, a tail is AOG, or the daily brief shows
OTP degrading. This router owns intent detection and hand-off; the actual work lives in the domain
sub-skills `[intake jobs: predict-delay-risk, analyze-disruption-cost, monitor-otp-trends,
optimize-irops-recovery]`.

## The OCC Loop
Detect degrading signal → **Rank** at-risk legs → **Quantify** network + financial impact → **Orchestrate**
recovery. This mirrors the strategy's Agency Maturity Model: move the OCC from Descriptive/Diagnostic to
Predictive and Prescriptive `[context: irops-strategy.md §5 "Agency Maturity Model"]`.

## Routing Table

| User Says | Route To |
|-----------|----------|
| "rank the risky flights", "which legs will delay", "why did this score high", "explain the risk" | `../delay-risk-triage/SKILL.md` |
| "what's this disruption costing", "revenue at risk", "IROP P&L", "cost of the ground stop" | `../disruption-pnl/SKILL.md` |
| "how's OTP trending", "on-time rate by route", "average delay minutes", "is the network degrading" | `../otp-trend-monitor/SKILL.md` |
| "rebook these passengers", "swap the tail", "crew is going to time out", "recovery plan" | `../recovery-orchestration/SKILL.md` |
| "what does <term> mean", "define OTP / MEL / duty legality / downline ripple" | `../domain-glossary/SKILL.md` |
| "is this metric real", "how is <KPI> defined", "can I trust this number" | `../kpi-definitions/SKILL.md` |

## Workflow

User Request → Detect Intent → **Load** the matching sub-skill → Execute to its stopping point → return here.

**Key principle:** complete ONE sub-skill workflow at a time. During an active disruption the natural
chain is delay-risk-triage → disruption-pnl → recovery-orchestration, but only advance when the current
step's stopping point is satisfied and the OCC confirms.

## Conversational entry point
For natural-language questions that span several tools, hand off to the governed orchestrator
`IROP_DB.CORTEX.IROP_INTELLIGENCE_AGENT`, which composes Cortex Analyst (`IROP_OPERATIONS_SV`), Cortex
Search (`IROP_KNOWLEDGE_SEARCH`) and the ML scorer behind one identity-inheriting surface
`[context: irops-strategy.md §6 "Why Snowflake Wins"]`. See `agents/irops-intelligence-agent.md`.

## Stopping Points
- After intent detection, if the request is ambiguous (e.g. "handle ATL") — ask which loop stage they
  want (rank / quantify / recover) before loading a sub-skill.
- After any sub-skill that touches an UNGOVERNED KPI (cost, rebooking, swap) — surface the gap per
  `kpi-definitions` rather than reporting a fabricated number.
- After 2+ sub-skills in one disruption — offer to hand the running context to the agent for a single
  prescriptive recovery narrative.

## Output
A routed, sequenced IROPS response: the right domain sub-skill executed to its halting state, with the
governance state of every metric it touched made explicit.
