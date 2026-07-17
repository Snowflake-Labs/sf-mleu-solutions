# Data Quality — Data Metric Functions (DMFs)

**Component:** `cmp-dmf-data-quality` (Data Metric Functions) · traces to `cap-monitor-otp-departure-rate`,
`cap-monitor-avg-delay-minutes`, `cap-predict-delay-risk`.
**Status:** data-quality posture (Horizon-native DMFs).

## Why here
Degrading input data silently corrupts a trend the OCC acts on: a stale `STATUS` enum or missing
`delay_minutes` would poison both the net-new OTP/avg-delay metrics and the delay-risk features
`[repo@9a0c2105 src/database/migrations/V1.0.0__create_raw_tables.sql → raw_flights]`. Catch it at the
source with native, scheduled DMFs rather than bespoke checks `[WAF: reliability]`.

## DMFs to attach
1. **Freshness** on the raw flight feed and on the serving Dynamic Tables — flag when the latest
   `load_timestamp` / `COMPUTED_AT` exceeds the freshness SLO.
2. **NULL_COUNT** on `raw_flights.delay_minutes` and `raw_flights.status` — a spike means the OTP/avg-delay
   metrics are unreliable.
3. **ROW_COUNT** on the net-new OTP/avg-delay Dynamic Table (`scripts/dt_otp_delay_metrics.sql`) — detect a
   dropped or empty refresh.

## Detection → action
DMFs are ACCOUNT_USAGE-visible on a schedule, but detection alone is not enough. A breach must FIRE — see
`alerting-notifications.md`, which wires DMF threshold breaches to the OCC platform on-call. Freshness/
completeness validation here + notification there is the reliability pairing `[WAF: reliability,
operational_excellence]`.
