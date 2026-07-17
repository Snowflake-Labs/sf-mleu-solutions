# Network Policy & Data Classification — Zero-Trust Perimeter (Horizon)

**Component:** `cmp-network-policy-classification` (Network Policies + Data Classification/Tagging) ·
traces to `cap-predict-delay-risk`, `cap-analyze-disruption-cost`, `cap-optimize-rebooking-success`.
**Status:** security posture · sibling to `rbac-masking-governance.md` (which is unchanged).

## Why here (the WAF Security fix)
`rbac-masking-governance.md` covers RBAC + masking but did NOT cover two checklist controls; this
component adds them `[WAF: security_governance]`.

## Control (a): Network Policy — zero-trust perimeter
An explicit Network Policy scopes OCC / AI role access to sanctioned corporate/OCC egress ranges. This is
the zero-trust perimeter the WAF security checklist requires and that was previously absent. The
`IROP_AI_ROLE` (Analyst / Search / Agent identity) is network-scoped so the generative surface cannot be
reached from outside the sanctioned ranges.

## Control (b): Horizon auto-classification + tagging
Auto-classify and tag passenger-exposure tables (`FACT_PASSENGER_EXPOSURE`, `raw_passenger_manifest`
`[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql → raw_passenger_manifest]`) so the
masking / row-access policies in `rbac-masking-governance.md` attach **by classification tag** rather than
by hand-enumerated columns. That makes PII coverage complete, drift-resistant across schema change, and
provable / auditable.

## Why native Horizon over manual lists
Classification-driven coverage survives schema evolution and DRIVES the existing masking policies, instead
of a brittle hand-maintained column list.

## WAF posture
- **Security/governance** — network-policy zero-trust perimeter + classification-driven, provable PII
  masking coverage `[WAF: security_governance]`.
- **AI data governance lens** — the AI role is network-scoped and reads classification-tagged, masked data.
