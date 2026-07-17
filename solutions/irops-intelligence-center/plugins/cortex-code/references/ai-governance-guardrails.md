# AI Governance Guardrails — Cortex Guard

**Component:** `cmp-cortex-guard-guardrails` (Cortex Guard) · traces to all six capabilities.
**Status:** AI safety posture on the generative surface.

## Principle
The Analyst and Agent expose natural-language access to operational data joined to passenger PII. Cortex
Guard is the native LLM safety layer that filters unsafe prompts/responses (OWASP LLM Top 10 class of
risks) on that conversational surface — chosen over bespoke prompt-side filtering `[design
cmp-cortex-guard-guardrails; WAF: security_governance]`.

## Where it applies
- The Cortex Analyst NL surface over `IROP_OPERATIONS_SV` (`cortex-analyst-semantic-model.md`).
- The `IROP_INTELLIGENCE_AGENT` orchestrator (`agents/irops-intelligence-agent.md`).
- Retrieval responses from `IROP_KNOWLEDGE_SEARCH` (`cortex-search-knowledge.md`).

## Layered with the other AI defenses
Cortex Guard is one layer of the AI data-governance lens, combined with: classification-driven masking /
row-access on the data read (`rbac-masking-governance.md`, `network-policy-classification.md`), a network
policy scoping the AI role, SELECT-only Analyst, and a least-privilege AI role that inherits the caller's
identity `[WAF: ai_data_governance lens; security_governance]`.

## WAF posture
- **Security/governance** — LLM guardrails bound the generative outputs `[WAF: security_governance]`.
- **AI data governance lens** — generative outputs are constrained so NL access to PII-adjacent data is
  guarded.
