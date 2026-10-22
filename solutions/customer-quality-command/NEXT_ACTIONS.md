# Next Actions: Customer Quality Command (CQC)

## Phase 1: Quick Exploration

1. Check the build:

   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE TABLE_SCHEMA LIKE 'CQC_%'
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

2. See the safety-gated priority list:

   ```sql
   SELECT priority_rank, title, quality_dimension, exposed_fleet_count,
          ROUND(warranty_exposure_p90) AS plan_for_exposure_usd, root_cause_summary
   FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE
   ORDER BY priority_rank
   LIMIT 10;
   ```

3. Follow the anchor defect (LX-950 fuel-system power loss on supplier lot L-4480):

   ```sql
   SELECT title, priority_rank, exposed_fleet_count, root_cause_summary,
          ROUND(warranty_exposure_p50) AS likely_usd, ROUND(warranty_exposure_p90) AS plan_for_usd,
          ROUND(warranty_exposure_cvar) AS bad_case_usd, data_confidence_band
   FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE
   WHERE model = 'LX-950' AND system_group = 'ENGINE_FUEL';
   ```

4. Open Snowflake CoWork, pick **CUSTOMER_QUALITY_AGENT** and try:
   - "What's our biggest safety-priority quality issue and why?"
   - "Why are LX-950 units disproportionately affected by the fuel-system issue?"
   - "What is the warranty exposure if the LX-950 fuel-system issue spreads?"
   - "Which customers are most hurt by the fuel-system issue and how do we reach them?"
   - "What should we do in the next 72 hours?"
5. Look at the failure-risk watchlist:

   ```sql
   SELECT risk_band, COUNT(*) AS machines, ROUND(AVG(failure_risk_90d), 3) AS avg_risk
   FROM SF_SOLUTIONS.CQC_ML.MACHINE_FAILURE_RISK
   GROUP BY risk_band
   ORDER BY avg_risk DESC;
   ```

## Phase 2: Customize with Your Data

1. Map your source systems to the `CQC_RAW` landing tables: machine registration and genealogy,
   dealer service records, warranty claims, technical-assistance cases, inspections, fluid
   analysis, telematics faults and health, plant MES, supplier incoming and corrective actions,
   VOC surveys, customer cases, safety incidents, field campaigns and technical documents.
   `machine_sn` is the join key across feeds.
2. Replace the seeded vocabularies in `CQC_STAGING` (`REF_*` code sets and `MAP_*` crosswalks,
   for example `MAP_SERVICE_3C` and `MAP_DIAGNOSTIC_CODE`) with your own codes.
3. Replace the illustrative customer archetypes (`CQC_ATOMIC.REF_ACCOUNT_ARCHETYPE`) with your
   own customer segmentation.
4. Load your service bulletins and procedures into `CQC_RAW.RAW_DOC_TECH`; the
   `TECH_DOC_SEARCH` service refreshes within its 1-day target lag.
5. The synthetic history ends on 2026-07-15, which the build treats as "today". When you load
   real data, update `OBS_DATE` in `CQC_RAW.SP_GENERATE_RAW` and `OBS` / `CUT` in
   `CQC_ML.SP_ML_FAILURE_RISK` (both in `scripts/setup.sql`), and the `DATE '2026-07-15'`
   literals in `scripts/data.sql`.

## Phase 3: Tune the Model

1. Adjust the Weibull, detection and failure-risk settings in the Python procedures
   (`CQC_ML.SP_ML_RELIABILITY`, `SP_ML_EMERGING`, `SP_ML_FAILURE_RISK`) and re-run
   `scripts/pipeline.sql`.
2. Tune the safety gate and the S/P/E classification rules in
   `CQC_ATOMIC.MAP_QUALITY_DIMENSION`, and the prioritization scoring in
   `CQC_ANALYTICS.CUSTOMER_IMPACT_SCORE` (module 6, `scripts/pipeline.sql`).
3. Extend the semantic view `CQC_ML.CUSTOMER_QUALITY_MODEL` (source YAML in
   `semantic/customer_quality_model.yaml`) and the agent instructions in
   `CQC_ML.CUSTOMER_QUALITY_AGENT`.
4. Use the 12-question eval set in `CQC_ML.EVAL_DATASET_CUSTOMER_QUALITY_AGENT` to check agent
   answers after changes.

## Phase 4: Production Deployment

1. Schedule the pipeline (for example a task graph calling the ML procedures and rebuilding
   INSIGHTS) and give it its own right-sized warehouse.
2. Wire `CQC_ML.TASK_AGENT_EVAL_WEEKLY` to `EXECUTE_AI_EVALUATION` with a judge model and resume
   it to track agent quality over time.
3. Create business roles for each persona (dealer, product, manufacturing, supply chain,
   executive) with read access to `CQC_INSIGHTS` and execute access to the `CQC_ACTION`
   workflow procedures.
4. Optionally deploy the CQC app on SPCS (`app/README.md`).
