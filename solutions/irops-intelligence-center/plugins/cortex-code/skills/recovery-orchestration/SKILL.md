---
name: recovery-orchestration
description: "Guide irregular-ops recovery — rebooking disrupted passengers and executing crew/aircraft swaps — using owned, tunable, auditable logic (Algorithmic Sovereignty) grounded in the airline's own SOPs and playbooks. Use whenever the OCC says 'rebook these passengers', 'swap the tail', 'crew will time out', 'recovery plan', 'what's the play for this cancellation', or is executing recovery — even without the word recovery. CRITICAL: rebooking success rate and swap time are NOT yet measurable (hardcoded literals); consult the net-new outcome/log models, never the placeholders."
parent_skill: primary-workflow
---

# Recovery Orchestration

## When to Load
`primary-workflow` routes here to guide rebooking and crew/aircraft swaps `[intake
job-optimize-irops-recovery]`. The goal is faster recovery to normal ops `[intake
job-optimize-irops-recovery → outcomes]`, replacing manual, ad hoc swap decisions
`[intake job-optimize-irops-recovery → pain_points]` with logic the airline owns and can tune in minutes
— Algorithmic Sovereignty, not a vendor black box `[context: irops-strategy.md §2A "Algorithmic
Sovereignty"]`.

## Prerequisites
- Read on `IROP_DB.CORTEX.IROP_KNOWLEDGE_SEARCH` (recovery SOPs / playbooks).
- **Load** `../kpi-definitions/SKILL.md` (KPIs 5 & 6) — both recovery KPIs are UNGOVERNED. Do not report
  a rate or a duration as if it were measured.

## Workflow

### Step 1: Ground the play in owned procedure (not model priors)
**Goal:** recovery guidance must cite the airline's own SOPs.
**Actions:**
1. Retrieve the relevant playbook from `IROP_DB.CORTEX.IROP_KNOWLEDGE_SEARCH` (rebooking / tail-swap /
   crew-continuity SOPs) so guidance is grounded in owned procedure, not generative priors
   `[design cmp-cortex-search; context: irops-strategy.md §2A]`.
2. Prioritize high-LTV / Mosaic guests per the loyalty-shield posture when sequencing re-accommodation
   `[context: irops-strategy.md §3C "High-Value Guest Recovery"]`.

### Step 2: Respect crew legality before any swap
**Goal:** never recommend a swap that busts duty limits.
**Actions:**
1. Check `legality_status` / `remaining_duty_minutes` / `timeout_probability` (FAR Part 117) before a crew
   move — the Time-Out Guardrail `[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql →
   raw_crew_duty_periods; context: irops-strategy.md §3B]`.
2. Use the downline ripple from `disruption-pnl` (`CALCULATE_NETWORK_IMPACT`) to compare candidate swaps by
   network impact `[repo@15a11075 src/database/functions/calculate_network_impact.sql]`.

MANDATORY STOPPING POINT: A swap or rebooking is a mutating operational action. Present the ranked options
with their legality and downline-ripple consequences and let the OCC decide — do not auto-execute.

### Step 3: Handle the measurement gaps honestly  🔴 UNGOVERNED
**Goal:** never fabricate the recovery KPIs.
**Actions:**
1. **Rebooking success rate** — the current value is a hardcoded constant (0.85 / 0.65, `ml_backed=False`)
   in the FastAPI app; no rebooking-outcomes table exists `[repo@e0ba7c4e api/app/main.py]`. Treat as
   unmeasurable; consult `references/rebooking-outcomes-model.md` for the outcome-capture model needed to
   make it real.
2. **Crew/aircraft swap time** — static literals (45 / 30 min) in the FastAPI app; no historical swap log
   exists `[repo@e0ba7c4e api/app/main.py]`. Treat as unmeasurable; consult
   `references/swap-time-model.md` for the swap-event log needed to measure true durations.
3. Frame the fix as escalation: capture the outcome/log feeds, then migrate the recovery math out of the
   FastAPI black box into governed, tested dbt models `[design cmp-algorithmic-sovereignty-dbt; context:
   irops-strategy.md §2A]`. See `references/algorithmic-sovereignty-dbt.md`.

### Step 4: Validate
**Validation Checklist:**
- Every recommendation cites a retrieved SOP, not a model prior.
- No crew move violates duty legality.
- Neither recovery KPI was reported as a measured number.
- Any mutating action was presented for OCC approval, never auto-run.

## Stopping Points
- Before any swap/rebooking recommendation is executed — OCC approval required.
- Whenever asked for rebooking success rate or swap time — surface the gap, do not emit a literal.

## Output
An SOP-grounded, legality-checked recovery plan with candidate swaps ranked by downline ripple, and the
two recovery KPIs honestly flagged as not-yet-measurable with their build path.
