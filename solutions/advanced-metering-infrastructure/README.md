# Advanced Metering Infrastructure (AMI 2.0)

Disclaimer: This application is not part of the Snowflake Service and is governed by the terms
in LICENSE, unless expressly agreed to in writing. You use this application at your own risk,
and Snowflake has no obligation to support your use of this application. [Learn more](../../LEGAL.md)

| Field | Value |
|-------|-------|
| Edition | Enterprise |
| Trial Account | Yes (core accelerator); No (optional SPCS dashboard add-on) |
| Author | Rishabh Raman |

A Snowflake-native Advanced Metering Infrastructure (AMI) accelerator for utility metering, billing,
grid-operations and revenue-assurance teams: 15-minute meter reads go from streaming ingest to
billing-ready, TOU-priced, quality-checked data with anomaly detection and natural-language Q&A,
all on Snowflake. All data is synthetic and generated in your account at install time.

## Business problem and outcomes

Utilities running AMI collect billions of 15-minute interval reads a year. That data typically
lives across head-end systems, a meter data management system (MDMS), billing (CIS) and ad-hoc
analytics tools, which leads to:

- Bills held because nobody can quickly show which accounts have complete, validated reads
- Time-of-use (TOU) charges computed outside the data platform and hard to trace back to intervals
- No shared, near-real-time view of ingestion SLAs and data quality
- Outages, theft-like load spikes and voltage sags found after the fact

| Capability | Problem it addresses | Outcome in this demo |
|---|---|---|
| **15-minute streaming ingestion** | Batch head-end loads leave operations hours behind | Reads land as VARIANT and are normalized by a dynamic table with a 1-minute target lag; late arrivals and replays are deduplicated (last write wins). Use the optional streaming producer to see it live |
| **Interval rollups and billing aggregation** | Billing waits on manual completeness and VEE checks | Hourly → daily → monthly rollups plus a per-period `IS_BILLING_READY` flag (≥ 99% complete and ≥ 97% VEE pass); about 54% of periods are billing-ready in the generated data, so held periods are easy to find |
| **TOU charge calculator** | TOU charges hard to compute and audit at interval grain | Every interval tagged to its rate window (flat, 3-tier TOU, critical peak) with energy and demand charges; a reconciliation view compares interval totals with CIS-billed kWh once you load CIS data |
| **Observability and SLA** | No shared view of ingestion SLA or data quality | Daily SLA and data-quality metrics by territory, `ROW_COUNT` and `FRESHNESS` data metric functions every 15 minutes, and an SLA-breach alert |
| **Anomaly detection** | Grid and revenue issues found late | Feeder-level and C&I meter-level Cortex ML anomaly models, scored at install and by a 30-minute task once resumed; seeded storm-outage, load-spike and voltage-sag scenarios to explore |
| **AMI Intelligence** | Answers spread across SQL, runbooks and tariff documents | A Cortex Agent that answers quantitative questions through a semantic view and operational questions from a searchable runbook and tariff knowledge base |

Governance is built in: a territory row-access policy, masking of CIS account IDs, and secure views
for sharing with CIS, CRM or regulators.

## Architecture

```
  [ Meters / MDMS / Head-End ]
               │
               ▼
   Streaming producer (optional, ingest/)
               │
               ▼
  AMI_RAW.INTERVAL_READ_15MIN_RAW  (VARIANT)
               │
               │   DT_NEW_READS_NORMALIZED  (target lag 1 min)
               ▼
  AMI_CURATED.INTERVAL_READ_15MIN  (canonical, clustered on READ_TS, METER_ID)
  AMI_CURATED.INTERVAL_READ_CHANNEL (channel-keyed long form)
               │
    ┌──────────┼────────────────────────────────┐
    ▼          ▼                                ▼
 Rollup      TOU tag + charge line           SLA + DQ metrics
 DT chain    (DT_INTERVAL_TOU_TAGGED,        (DT_INGESTION_SLA_METRICS,
 (hour→day   DT_INTERVAL_CHARGE_LINE)        DT_DATA_QUALITY_METRICS)
  →month)    │                                ▼
    │        ▼                              DMFs, SLA breach alert
    ▼     DT_BILLING_PERIOD_CONSUMPTION
  AMI_MART  → AMI_SHARED secure views
    │
    ├──▶ Cortex ML anomaly detection (per feeder + per C&I meter)
    │      → AMI_ANOMALY_EVENTS, AMI_METER_ANOMALY_EVENTS
    │
    └──▶ AMI_SEMANTIC_VIEW (Cortex Analyst) + AMI_KB_SEARCH (Cortex Search)
           → AMI_INTELLIGENCE_AGENT (Snowflake CoWork)
```

## What gets installed

| Layer | Objects |
|---|---|
| Database / warehouse | Shared `SF_SOLUTIONS` database and `SF_SOLUTIONS_WH` (LARGE) warehouse, created if missing |
| Schemas | `AMI_RAW`, `AMI_CURATED`, `AMI_MART`, `AMI_OBSERVABILITY`, `AMI_ML`, `AMI_SHARED` |
| Roles | `AMI_OWNER` (owns the six AMI schemas), `AMI_ENG`, `AMI_ANALYST`, `AMI_OPS`, `AMI_SHARE` |
| Dynamic tables | `DT_NEW_READS_NORMALIZED`, `DT_HOURLY_ROLLUP`, `DT_DAILY_ROLLUP`, `DT_MONTHLY_ROLLUP`, `DT_CHANNEL_HOURLY_ROLLUP`, `DT_CHANNEL_DAILY_ROLLUP`, `DT_INTERVAL_TOU_TAGGED`, `DT_INTERVAL_CHARGE_LINE`, `DT_BILLING_PERIOD_CONSUMPTION`, `DT_INGESTION_SLA_METRICS`, `DT_DATA_QUALITY_METRICS` |
| Cortex ML | `AMI_ML.AMI_FEEDER_ANOM_MODEL`, `AMI_ML.AMI_CNI_METER_ANOM_MODEL`, scoring task `T_SCORE_FEEDER_ANOMALIES` (created suspended) |
| Observability | `ROW_COUNT` / `FRESHNESS` data metric functions, alert `AMI_SLA_BREACH` (created suspended), pipeline audit table |
| Governance | Row access policy `RAP_TERRITORY`, masking policy `MP_CIS_ACCOUNT`, 3 secure views in `AMI_SHARED` |
| AI | Semantic view `AMI_MART.AMI_SEMANTIC_VIEW`, Cortex Search service `AMI_ML.AMI_KB_SEARCH`, Cortex Agent `AMI_MART.AMI_INTELLIGENCE_AGENT` |

## Quick start

### Install with Cortex Code

```
$sf-solutions:advanced-metering-infrastructure
```

### Install manually

Run as `ACCOUNTADMIN`, in this order:

```bash
snow sql -f scripts/setup.sql    --enable-templating NONE
snow sql -f scripts/data.sql     --enable-templating NONE
snow sql -f scripts/pipeline.sql --enable-templating NONE
```

`--enable-templating NONE` is required because the scripts contain `&` characters.

**Scale.** The default is 100,000 meters (about 3.5 billion interval rows and 10.6 billion
channel rows; roughly 300 GB of storage once all dynamic tables have refreshed). To build a
smaller demo, for example on a trial account, change the meter count after `setup.sql` and
before `data.sql`:

```sql
UPDATE SF_SOLUTIONS.AMI_CURATED.AMI_CONFIG SET VALUE = '1000' WHERE KEY = 'N_METERS';
```

Measured on a LARGE warehouse:

| Script | 1,000 meters | Default (100,000 meters) |
|---|---|---|
| `setup.sql` | < 1 min | < 1 min |
| `data.sql` | about 4 min | about 10 min |
| `pipeline.sql` | about 9 min | not measured; expect longer, because the dynamic tables refresh over billions of rows |

### Start the scheduled jobs (optional)

The scoring task and SLA alert are created suspended so they don't run the shared warehouse
until you want them to:

```sql
ALTER TASK  SF_SOLUTIONS.AMI_ML.T_SCORE_FEEDER_ANOMALIES RESUME;   -- every 30 minutes
ALTER ALERT SF_SOLUTIONS.AMI_OBSERVABILITY.AMI_SLA_BREACH RESUME;  -- every 15 minutes
```

## Try it

- **Snowflake CoWork:** open the `AMI_INTELLIGENCE_AGENT` agent and ask, for example,
  "Plot total kWh by territory in the last month", "What is the outage response runbook?" or
  "Explain the billing readiness criteria".
- **Cortex Analyst:** query the semantic view directly:

  ```sql
  SELECT * FROM SEMANTIC_VIEW(
    SF_SOLUTIONS.AMI_MART.AMI_SEMANTIC_VIEW
    DIMENSIONS daily_rollup.territory
    METRICS    daily_rollup.total_kwh, daily_rollup.meter_count
  );
  ```

- **Validation:** `scripts/validate.sql` runs checks T1–T9 (dimension counts, interval volume, VEE
  distribution, rollups, TOU, billing readiness, observability, anomalies, streaming).
- **Snowsight dashboard:** `scripts/snowsight_dashboard.sql` has ready-made queries for
  ingestion, data quality, billing readiness and anomaly tiles.

See [NEXT_ACTIONS.md](NEXT_ACTIONS.md) for more.

## Data scale (default build)

| Table | Rows |
|---|---|
| Substations / Feeders / Transformers | 50 / 2,000 / 20,000 |
| Service points / Meters | 100,000 / 100,000 |
| `TIME_DIM` (15-minute grain, last 365 days) | 35,136 |
| `CHANNEL_CATALOG` / `METER_CHANNEL` | 11 / about 303,000 |
| `INTERVAL_READ_15MIN` (wide fact) | about 3.5 billion |
| `INTERVAL_READ_CHANNEL` (canonical, long form) | about 10.6 billion |
| `DT_HOURLY_ROLLUP` / `DT_DAILY_ROLLUP` / `DT_MONTHLY_ROLLUP` | about 878 million / 36.6 million / 1.3 million |

Dates are relative to the install day, so the history always covers the last 12 months.

## Optional add-ons

### Streaming producer

`ingest/snowpipe_streaming_producer.py` streams synthetic reads for a subset of meters into
`AMI_RAW.INTERVAL_READ_15MIN_RAW` so you can watch `DT_NEW_READS_NORMALIZED` pick them up within
its 1-minute target lag:

```bash
pip install snowflake-connector-python
SNOWFLAKE_CONNECTION_NAME=<connection> python3 ingest/snowpipe_streaming_producer.py \
    --meter-count 200 --interval-seconds 5 --duration-minutes 30
```

### Operations dashboard (SPCS, not available on trial accounts)

A React + Express dashboard (ingestion, data quality, billing, TOU, transformers, map, events,
anomalies, observability and an Intelligence chat page) that runs in Snowpark Container Services.
It needs a compute pool, an image repository and an external access integration, which trial
accounts can't create. See [app/README.md](app/README.md).

## Key design choices

- **Channel-keyed grain.** `INTERVAL_READ_CHANNEL` is keyed on `(METER_ID, CHANNEL_ID, READ_TS)`.
  New channels (kVArh, reactive demand, per-phase voltage) are added as rows in `CHANNEL_CATALOG`
  and `METER_CHANNEL`, not by altering the schema.
- **One canonical grain, many marts.** Every rollup, TOU output, observability metric and anomaly
  mart reads from the same canonical fact.
- **Declarative freshness.** Dynamic tables with target lags from 1 minute to 1 hour replace
  hand-rolled orchestration.
- **Layered anomaly detection.** A per-feeder model for grid-level anomalies plus a per-meter model
  on a sampled C&I cohort.
- **Security by default.** Row access by territory, masking on CIS account IDs, and secure views in
  a share-ready schema.

## Teardown

```bash
snow sql -f scripts/teardown.sql --enable-templating NONE
```

Drops the six AMI schemas, the `AMI_*` roles and, if installed, the dashboard service, compute pool
and external access integration. The shared `SF_SOLUTIONS` database and `SF_SOLUTIONS_WH`
warehouse are kept. Safe to run more than once.
