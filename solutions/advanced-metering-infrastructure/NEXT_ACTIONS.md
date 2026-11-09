# Next Actions: Advanced Metering Infrastructure (AMI 2.0)

## Phase 1: Quick Exploration

1. Check the build:

   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE TABLE_SCHEMA LIKE 'AMI_%'
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

2. Run the validation suite: `snow sql -f scripts/validate.sql --enable-templating NONE`.
3. Open Snowflake CoWork, pick **AMI Intelligence** and try:
   - "Plot total kWh by territory in the last month"
   - "Show me a chart of billing readiness over time"
   - "What is the outage response runbook?"
   - "Compare TOU bucket charges as a bar chart"
4. Find the billing periods that are being held:

   ```sql
   SELECT BILLING_PERIOD_ID, METER_ID, COMPLETENESS_PCT, VEE_PASS_PCT
   FROM SF_SOLUTIONS.AMI_MART.DT_BILLING_PERIOD_CONSUMPTION
   WHERE NOT IS_BILLING_READY
   ORDER BY COMPLETENESS_PCT
   LIMIT 20;
   ```

5. Look at the seeded scenarios (storm outage, load spike, voltage sag) through the anomaly marts:

   ```sql
   SELECT FEEDER_ID, TS, KWH, FORECAST, UPPER_BOUND, DISTANCE
   FROM SF_SOLUTIONS.AMI_MART.AMI_ANOMALY_EVENTS
   ORDER BY DISTANCE DESC
   LIMIT 20;
   ```

## Phase 2: Customize with Your Data

1. Land head-end or MDMS reads as VARIANT in `SF_SOLUTIONS.AMI_RAW.INTERVAL_READ_15MIN_RAW`
   (Snowpipe, Snowpipe Streaming or `COPY INTO` from `AMI_RAW.LANDING_STAGE`); try
   `ingest/snowpipe_streaming_producer.py` first to see the flow end to end.
2. Replace the synthetic dimensions (`SUBSTATION`, `FEEDER`, `TRANSFORMER`, `SERVICE_POINT`,
   `METER`, `CUSTOMER`) in `AMI_CURATED` with your asset and customer data.
3. Load your tariffs into `TOU_RATE_PLAN` and `TOU_RATE_WINDOW`.
4. Load CIS-billed kWh into `BILLING_PERIOD.CIS_BILLED_KWH` to use the
   `V_BILLING_RECONCILIATION` view.
5. Add your own runbooks and tariff documents to `AMI_ML.AMI_KNOWLEDGE_BASE`; the Cortex Search
   service picks them up within its 1-hour target lag.

## Phase 3: Tune the Model

1. Retrain the feeder and C&I meter anomaly models on your data (`AMI_ML.V_FEEDER_TRAINING_DATA`
   and `AMI_ML.CNI_METER_TRAINING`), and label known events in `AMI_CURATED.LABELED_ANOMALIES`
   to measure precision.
2. Adjust the billing-readiness thresholds (99% complete, 97% VEE pass) in
   `DT_BILLING_PERIOD_CONSUMPTION` to match your billing rules.
3. Extend the semantic view `AMI_MART.AMI_SEMANTIC_VIEW` with your own metrics and synonyms, and
   update the agent instructions in `AMI_MART.AMI_INTELLIGENCE_AGENT`.

## Phase 4: Production Deployment

1. Resume the scheduled jobs:

   ```sql
   ALTER TASK  SF_SOLUTIONS.AMI_ML.T_SCORE_FEEDER_ANOMALIES RESUME;
   ALTER ALERT SF_SOLUTIONS.AMI_OBSERVABILITY.AMI_SLA_BREACH RESUME;
   ```

2. Review dynamic table target lags against your SLAs and give the pipeline its own right-sized
   warehouse.
3. Map business roles to territories in `AMI_CURATED.ROLE_TERRITORY_MAP` for the `RAP_TERRITORY`
   row access policy, and grant the `AMI_*` roles to users.
4. Share `AMI_SHARED` secure views with CIS, CRM or regulators (see the commented share scaffold
   in `scripts/pipeline.sql`).
5. Optionally deploy the operations dashboard on SPCS (`app/README.md`).
