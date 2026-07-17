# Cortex Search — IROP_KNOWLEDGE_SEARCH (Recovery Playbooks)

**Component:** `cmp-cortex-search` (Cortex Search) · traces to `cap-optimize-rebooking-success`,
`cap-accelerate-crew-aircraft-swaps`.
**Status:** GROUNDED RAG surface over the airline's owned recovery corpus.

## What it is
`IROP_DB.CORTEX.IROP_KNOWLEDGE_SEARCH` is a Cortex Search index over recovery SOPs and playbooks
(rebooking rules, tail-swap procedure, crew-continuity guardrails, high-value-guest re-accommodation). It
grounds the `recovery-orchestration` skill so swap/rebooking guidance cites *owned procedure* rather than
model priors `[design cmp-cortex-search]`.

## Why retrieval, not generation
This is the "Algorithmic Sovereignty" principle applied to knowledge: the airline's own recovery doctrine
is the authority, retrieved and cited, not invented by an LLM `[context: irops-strategy.md §2A]`. It is a
distinct AI surface from the ML delay-risk scorer.

## Usage pattern
1. `recovery-orchestration` issues a search over the corpus for the disruption type (e.g. "hub ground stop
   rebooking priority").
2. The retrieved SOP passages are cited in the recovery recommendation, and high-LTV / Mosaic guest
   prioritization follows the loyalty-shield doctrine `[context: irops-strategy.md §3C]`.

## Governance
- **Operational excellence** — playbook grounding gives repeatable, auditable recovery guidance
  `[WAF: operational_excellence]`.
- **AI data governance lens** — retrieval is scoped to the governed corpus; the search service inherits
  RBAC and sits behind the same Cortex Guard / network-policy perimeter as the other AI surfaces
  (`ai-governance-guardrails.md`, `network-policy-classification.md`).
