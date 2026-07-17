---
description: >
  Show next actions after installing IROPS Intelligence Center.
  Guides the user from exploration to production deployment.
  Triggers: what next, next steps, what can I do, how to use this, customize.
---

# Next Actions: IROPS Intelligence Center

## Phase 1: Quick Exploration

1. **Browse the solution objects**
   - Snowsight: Data > Databases > SF_SOLUTIONS > IROPS_DATA_MART
   - Review Dynamic Tables: `DT_AVG_DELAY_FLIGHT_LEG`, `DT_OTP_RATE_ROUTE_DAY`

2. **Try OTP and delay queries**

   ```sql
   -- Route-day on-time performance
   SELECT origin_airport, destination_airport, flight_date,
          otp_departure_rate_pct, avg_delay_minutes_route_day
   FROM SF_SOLUTIONS.IROPS_DATA_MART.DT_OTP_RATE_ROUTE_DAY
   ORDER BY otp_departure_rate_pct ASC
   LIMIT 10;
   ```

   ```sql
   -- Highest-risk flights right now
   SELECT flight_id, flight_date, origin_airport, destination_airport,
          realtime_risk_score, revenue_at_risk
   FROM SF_SOLUTIONS.IROPS_DATA_MART.DT_FLIGHT_RISK_REALTIME
   WHERE realtime_risk_score > 0.6
   ORDER BY revenue_at_risk DESC
   LIMIT 10;
   ```

3. **Query with natural language via Cortex Analyst**

   ```sql
   SELECT SNOWFLAKE.CORTEX.COMPLETE(
       'mistral-large2',
       'What routes have the worst on-time performance?'
   );
   ```

## Phase 2: Use the Skills

Run the skills for guided OCC workflows:

```
$sf-mleu-solutions:irops-intelligence-center:primary-workflow
$sf-mleu-solutions:irops-intelligence-center:delay-risk-triage
$sf-mleu-solutions:irops-intelligence-center:otp-trend-monitor
$sf-mleu-solutions:irops-intelligence-center:disruption-pnl
$sf-mleu-solutions:irops-intelligence-center:recovery-orchestration
```

## Phase 3: Connect Real Data

1. **Load operational flight data** into `SF_SOLUTIONS.IROPS_RAW.RAW_FLIGHTS`
   - Match the schema: `flight_id`, `flight_date`, `airline_code`, `status`, `delay_minutes`
   - Use Snowpipe Streaming for real-time ingestion

2. **Connect a real ML risk scorer**
   - Replace `DT_FLIGHT_RISK_REALTIME` view with a Dynamic Table fed by your ML model
   - Reference the `IROP_DB.ML.SCORE_FLIGHT_RISK` pattern from the reference docs

3. **Update Dynamic Table refresh lag**
   - Adjust `TARGET_LAG` based on your OTP freshness SLO (current: 60 minutes)

## Phase 4: Production Deployment

1. **Create a dedicated warehouse** for production OCC workload
2. **Set up row access policies** to scope airline data by operating role
3. **Add Cortex Search Service** over SOP documents for recovery orchestration
4. **Configure alerting** when `otp_departure_rate_pct` drops below threshold
5. **Grant `IROPS_OCC_ROLE`** to your OCC service user:
   ```sql
   GRANT ROLE IROPS_OCC_ROLE TO USER <occ_service_user>;
   ```
