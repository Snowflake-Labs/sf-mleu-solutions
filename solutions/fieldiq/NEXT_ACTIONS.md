# Next Actions: FieldIQ

## Phase 1: Quick Exploration

1. Check the build:

   ```sql
   SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
   FROM SF_SOLUTIONS.INFORMATION_SCHEMA.TABLES
   WHERE STARTSWITH(TABLE_SCHEMA, 'FIQ_')
   ORDER BY TABLE_SCHEMA, TABLE_NAME;
   ```

2. See the accounts with the most open pipeline and at-risk equipment:

   ```sql
   SELECT ACCOUNT_NAME, INDUSTRY, BILLING_CITY, BILLING_STATE, ACCOUNT_OWNER,
          OPEN_PIPELINE_USD, ASSETS_AT_RISK, ASSETS_NO_SERVICE_PLAN
   FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360
   ORDER BY OPEN_PIPELINE_USD DESC NULLS LAST
   LIMIT 10;
   ```

3. Run the agent tools directly for the anchor account:

   ```sql
   CALL SF_SOLUTIONS.FIQ_ACTIONS.SALES_CALL_PLAN('Cascade Partners');
   CALL SF_SOLUTIONS.FIQ_ACTIONS.MEETING_AGENDA('Cascade Partners');
   CALL SF_SOLUTIONS.FIQ_ACTIONS.EMAIL_DRAFT('Cascade Partners', 'assets without a service plan, propose an inspection', 'Spanish');
   CALL SF_SOLUTIONS.FIQ_ACTIONS.NEARBY_CUSTOMERS('Cincinnati', 'OH', 50);
   ```

4. Open Snowflake CoWork, pick **FIELDIQ_AGENT** and try:
   - "Key contacts at Cascade Partners"
   - "Open orders, opportunities, and assets for Cascade Partners"
   - "What is the full load amps for RS75i-A125?"
   - "How to sell a 10HP diesel reciprocating compressor?"
   - "Plan a 2-day route starting with Cascade Partners next Monday"

5. Search the engineering documents:

   ```sql
   SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
     'SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_DOC_SEARCH',
     '{"query": "RS110i-A125 maximum operating pressure", "columns": ["DOC_TITLE", "DOC_TYPE"], "limit": 3}'
   )):results AS results;
   ```

## Phase 2: Customize with Your Data

1. Map your CRM and ERP to the `FIQ_ATOMIC` tables: `ACCOUNTS`, `CONTACTS`, `OPPORTUNITIES`
   (CRM); `PRODUCTS`, `INVENTORY`, `OPEN_ORDERS` (ERP); `ASSETS` and `SERVICE_ACTIVITIES`
   (installed base and field service). `ACCOUNT_ID` and `PRODUCT_ID` are the join keys.
2. Keep account names unique, or change the name lookup in the `FIQ_ACTIONS` procedures to an
   ID: the tools resolve a customer by name.
3. Load your datasheets, drawings, submittals, playbooks and price lists to
   `@SF_SOLUTIONS.FIQ_STAGES.DOCS`, register them in `FIQ_ATOMIC.DOCS_REGISTRY`, and write their
   text passages to `FIQ_CORTEX.DOC_CHUNKS`; `FIELDIQ_DOC_SEARCH` refreshes within its 1-hour
   target lag.
4. Replace the `ApexCare` service-plan values and the product families with your own.

## Phase 3: Tune the Agent

1. Extend the semantic view `FIQ_CORTEX.FIELDIQ_SEMANTIC_MODEL` (source YAML in
   `semantic/fieldiq_semantic_model.yaml`) with your metrics, synonyms and verified queries.
2. Edit the prompts in the `FIQ_ACTIONS` procedures (call plan sections, agenda timeline, email
   tone), or switch their `COMPLETE` model.
3. Adjust the agent's routing rules and sample questions in the `CREATE AGENT` statement in
   `scripts/pipeline.sql`.

## Phase 4: Production Deployment

1. Load CRM and ERP data on a schedule (for example Openflow or dynamic tables) and give the
   agent its own right-sized warehouse.
2. Create a sales-rep role with read access to `FIQ_ANALYTICS`, usage on the agent, and a row
   access policy on `ACCOUNT_OWNER` so each rep sees their own accounts.
3. Optionally deploy the web app or the voice service on SPCS (`app/README.md`).
