# DR & Continuity Runbook — Time Travel + Replication / Failover

**Component:** `cmp-dr-continuity-runbook` (Time Travel + Replication / Failover Groups) · traces to
`cap-predict-delay-risk`, `cap-monitor-otp-departure-rate`, `cap-monitor-avg-delay-minutes`.
**Status:** reliability / DR posture (closes the previously-undefined DR gap).

## Why here (the WAF Reliability fix)
DR was previously undefined (carried only as a deferred gap). This component defines continuity for the
near-real-time serving path `[WAF: reliability]`.

## The three DR checklist items
1. **Time Travel retention** — set retention on the raw flight feeds (`raw_flights` `[repo@9a0c2105
   src/database/migrations/V1.0.0__create_raw_tables.sql]`) and the serving Dynamic Tables
   (`DT_FLIGHT_RISK_REALTIME` `[repo@e74f234b src/database/dynamic_tables/dt_flight_risk_realtime.sql]`
   and the net-new `scripts/dt_otp_delay_metrics.sql` DT) for point-in-time recovery from a bad refresh or
   corruption. Retention is right-sized against cost — see `resource-monitors-budgets.md`.
2. **Documented + periodically-tested recovery runbook** — rebuild-from-source for the declarative Dynamic
   Tables (they are reproducible from base tables) plus a Time Travel restore drill.
3. **Cross-region Replication / Failover Groups** — for the governed objects, with an explicitly accepted
   RTO/RPO owned by the platform team.

## Native platform DR over app-tier backups
Chosen because it covers the WAF reliability continuity checklist (replication, Time Travel retention,
documented + tested recovery) natively `[WAF: reliability]`.

## Honest-posture waiver
If the platform team elects not to fund cross-region replication, the runbook records an **explicit written
waiver** with the accepted RTO/RPO so the posture stays honest rather than silently gapped.

## Residual (Gate-B, non-blocking)
Concrete numeric RTO/RPO values and the fund-vs-waive decision are recorded by the platform team at Gate B
`[WAF: reliability]`.
