# Operations & Observability — ACCOUNT_USAGE + GitOps

**Component:** `cmp-operations-observability` (ACCOUNT_USAGE + Git integration) · traces to all six
capabilities.
**Status:** observability + change-management posture.

## Observability
- **Dynamic Table refresh monitoring** — track refresh history/lag for `DT_FLIGHT_RISK_REALTIME`
  `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]` and the net-new OTP/avg-delay
  DT (`scripts/dt_otp_delay_metrics.sql`) via `ACCOUNT_USAGE`/`INFORMATION_SCHEMA` DT metadata.
- **Query monitoring** — use `ACCOUNT_USAGE.QUERY_HISTORY` to profile Analyst/Agent queries and the
  serving reads, feeding the performance-optimization loop `[WAF: performance_optimization]`.

## Change management (GitOps)
- Version the plugin's Snowflake objects with schemachange / Git so deploys are reviewed and reversible.
- The runbook the OCC platform team follows for deploy, refresh-health checks, and query-profile review.

## The operate loop
This delivers the WAF Prepare → Implement → Operate → Improve loop `[WAF: operational_excellence]`.
Detection here is paired with proactive alerting in `alerting-notifications.md` (this reference is
observability/GitOps; the firing/routing lives there).
