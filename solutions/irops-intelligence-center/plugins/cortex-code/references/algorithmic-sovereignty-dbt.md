# Algorithmic Sovereignty — dbt on Snowflake (recovery logic migration)

**Component:** `cmp-algorithmic-sovereignty-dbt` (dbt on Snowflake) · traces to
`cap-optimize-rebooking-success`, `cap-accelerate-crew-aircraft-swaps`, `cap-analyze-disruption-cost`.
**Status:** NET-NEW pattern · **no repo provenance** · reference pattern (depends on the net-new
outcome/log/cost feeds being captured first).

## The problem
Scenario and network-impact recovery logic lives in FastAPI application code (`api/app/main.py`), with no
dbt project `[repo@e0ba7c4e api/app/main.py]`. That is a "Black Box" the airline cannot audit or tune —
the exact anti-pattern the strategy attacks. Algorithmic Sovereignty means the airline builds and OWNS its
recovery logic and can change a priority (sustainability, high-value partner) in minutes, not through a
multi-year vendor roadmap `[context: irops-strategy.md §2A]`.

## The migration pattern
1. Stand up a dbt project on Snowflake for the recovery domain (staging → intermediate → marts) so the
   recovery math is version-controlled, tested, and lineage-tracked.
2. Move the network-impact / rebooking / swap-prioritization logic out of the app tier into dbt models and
   the governed UDFs (`CALCULATE_NETWORK_IMPACT` already exists in-database `[repo@15a11075
   src/database/functions/calculate_network_impact.sql]`).
3. Add dbt tests (not-null, accepted-values on `status`, relationship tests) on the recovery inputs.

## Sequencing (dependency)
This is sequenced AFTER the net-new sources are captured: the cost feeds (`disruption-cost-model.md`),
rebooking outcomes (`rebooking-outcomes-model.md`), and swap-event log (`swap-time-model.md`). Migrating
logic without those feeds would encode the same ungoverned KPIs in a new place.

## WAF posture
- **Operational excellence** — GitOps, tested transformations, no black-box app logic `[WAF:
  operational_excellence]`.
- **Reliability** — dbt lineage + schema integrity across the recovery models `[WAF: reliability]`.
