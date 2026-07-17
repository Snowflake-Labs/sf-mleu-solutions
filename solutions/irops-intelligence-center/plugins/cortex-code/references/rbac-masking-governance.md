# RBAC, Masking & Row Access — Least-Privilege Governance

**Component:** `cmp-rbac-masking-governance` (Dynamic Data Masking + Row Access Policies + RBAC) · traces
to `cap-predict-delay-risk`, `cap-analyze-disruption-cost`, `cap-optimize-rebooking-success`.
**Status:** governance posture (Horizon-native).

## Principle
Least privilege first: the risk, cost, and rebooking flows all read passenger-exposure PII, so protect it
with native Horizon controls rather than app-tier auth (lower blast radius, inherited by Analyst and the
Agent) `[WAF: security_governance — masking + least privilege + classification before pipeline]`.

## Role model (least privilege)
- Provision custom roles via **SYSADMIN**, **never ACCOUNTADMIN**.
- `IROP_OCC_ROLE` — read on the serving Dynamic Tables and semantic view for the OCC persona.
- `IROP_AI_ROLE` — the identity the Analyst / Search / Agent inherit; scoped to the modeled objects only,
  network-scoped per `network-policy-classification.md`.
- Grant object access to roles, roles to users — no direct grants.

## Dynamic Data Masking (PII)
Apply masking policies to passenger-identifying and revenue columns surfaced through the models —
e.g. `passenger_hash`, loyalty tier, ticket value in `FACT_PASSENGER_EXPOSURE` and `raw_passenger_manifest`
`[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql → raw_passenger_manifest]`. Unmasked
values only for roles with a demonstrated need; the AI role reads masked data.

## Row Access Policies
Scope row visibility (e.g. by operating carrier / business unit) so a role sees only its own operation.

## Coverage driven by classification
Attach masking/row-access **by Horizon classification tag**, not by hand-enumerated columns, so PII
coverage is complete and drift-resistant — see `network-policy-classification.md`.

## WAF posture
- **Security/governance** — RBAC least-privilege + PII masking `[WAF: security_governance]`.
- **AI data governance lens** — models read masked, classification-tagged data.
- Warehouses set `AUTO_SUSPEND` for cost `[WAF: cost_optimization]` (see `resource-monitors-budgets.md`).
