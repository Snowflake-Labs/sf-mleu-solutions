# Customer Quality Command (CQC)

Disclaimer: This application is not part of the Snowflake Service and is governed by the terms
in LICENSE, unless expressly agreed to in writing. You use this application at your own risk,
and Snowflake has no obligation to support your use of this application. [Learn more](../../LEGAL.md)

| Field | Value |
|-------|-------|
| Edition | Enterprise |
| Trial Account | Yes (core accelerator); No (optional SPCS app add-on) |
| Author | Rishabh Raman |

A customer-quality command-and-response accelerator for equipment manufacturers and their dealer
networks: quality, product, manufacturing, supply-chain and dealer teams see a field defect early,
rank it by customer impact with safety first, trace it to a supplier lot, size the financial
exposure and route the response to an owner, all on Snowflake. All data is synthetic and
generated in your account at install time, for a fictional heavy-equipment maker, Acme Industrial.

## Business problem and outcomes

Field-quality signals for a machine population are spread across dealer service records, warranty
claims, technical-assistance cases, inspections, fluid analysis, telematics, plant MES and
supplier quality. Typically:

- A defect is found weeks after the first precursor faults, when warranty claims pile up
- Issues are ranked by warranty dollars, so a safety risk with no repair cost can sit below a
  costly nuisance
- Linking field failures back to a supplier lot or build plant is a manual investigation
- Nobody can say quickly how many machines are exposed or what the defect could cost
- Responses are tracked in email and spreadsheets, with no owner, SLA or audit trail

| Capability | Problem it addresses | Outcome in this demo |
|---|---|---|
| **One quality-event spine** | Nine source feeds with different codes and grains | Every feed conformed into `FACT_QUALITY_EVENT` with a shared Safety / Productivity / Experience classification; 141 governable issues (model × system × failure mode) |
| **Early detection** | Defects found after claims pile up | EWMA, CUSUM, change-point and isolation-forest detectors; the planted LX-950 fuel-system defect alarms from 2024-08, its change-point month |
| **Safety-gated prioritization** | Dollar-ranked lists bury safety risks | Lexicographic ranking: the LX-950 sudden-shutdown safety issue ranks #4 with $0 repair-cost value, above a $4.2M productivity issue |
| **Lot-level root cause** | Manual supplier and plant investigations | Genealogy-based attribution names supplier lot L-4480 built at South Plant with 4.3× failure lift |
| **Exposure simulation** | No forward view of what a defect could cost | Weibull failure projection plus a Gaussian-copula Monte Carlo per issue: for the anchor defect, 63 exposed machines, likely $174K, plan-for $237K, bad-case $264K |
| **Failure-risk scoring** | No ranked fleet watchlist | XGBoost 90-day failure-risk model scored for all 40,800 machines (test AUC about 0.79), logged to the Model Registry |
| **Customer-back view** | The same defect hurts customers differently | Four illustrative customer archetypes: the 63 exposed machines split 2 Enterprise / 11 National / 34 Local / 16 Independent, with felt-pain share and the channel to reach each |
| **Closed-loop actions** | Responses tracked in email | Time-windowed recommended actions, owners, SLA and audited workflow state transitions in `CQC_ACTION` |
| **Ask CQC** | Answers spread across systems | A Cortex Agent with 7 tools: semantic view, two Cortex Search services, and procedures for detection, exposure what-ifs, actions and resource allocation |

Prioritization uses three metrics defined by the accelerator: SIP (serious-injury potential, a
Bayesian estimate from safety events), VTC (value to customer, in USD) and CEI (customer
experience impact).

## Architecture

```
  Synthetic source feeds (dealer service, warranty, technical assistance, inspection,
  fluid analysis, telematics, plant MES, supplier, VOC, safety, campaigns, tech docs)
        │   SP_GENERATE_RAW (Python stored procedure) + in-warehouse telematics SQL
        ▼
  CQC_RAW ─► CQC_STAGING ─► CQC_ATOMIC ─► CQC_FEATURE_STORE
  (landing)   (conform, DQ,   (dims, FACT_QUALITY_EVENT,
               crosswalks)     lot genealogy, archetypes)
        │
        ▼
  CQC_ML  (Python stored procedures + SQL)
    1 Weibull reliability   2 emerging-issue detection   3 XGBoost failure risk (Model Registry)
    4 issue clustering (AI_EMBED, AI_COMPLETE)   5 lot / plant root cause
    6 safety-gated prioritization   7 Monte-Carlo exposure (Model Registry)   8 actions
        │
        ▼
  CQC_ANALYTICS (ISSUE) ─► CQC_INSIGHTS (issue hub + satellites, narratives) ─► CQC_ACTION
        │
        ▼
  Semantic view CUSTOMER_QUALITY_MODEL + Cortex Search (insight evidence, tech docs)
        └──► CUSTOMER_QUALITY_AGENT (Ask CQC, Snowflake CoWork)

  Optional: React + FastAPI app in Snowpark Container Services (app/)
```

## What gets installed

| Layer | Objects |
|---|---|
| Database / warehouse | Shared `SF_SOLUTIONS` database and `SF_SOLUTIONS_WH` (LARGE) warehouse, created if missing |
| Schemas | `CQC_RAW`, `CQC_STAGING`, `CQC_ATOMIC`, `CQC_FEATURE_STORE`, `CQC_ML`, `CQC_ANALYTICS`, `CQC_INSIGHTS`, `CQC_ACTION`, `CQC_DOCS` |
| Python procedures | `CQC_RAW.SP_GENERATE_RAW`, `CQC_ML.SP_ML_RELIABILITY`, `SP_ML_EMERGING`, `SP_ML_FAILURE_RISK`, `SP_ML_ISSUE_CLUSTERING`, `SP_ML_EXPOSURE` |
| Models | `CQC_ML.FAILURE_RISK_MODEL`, `CQC_ML.EXPOSURE_SIMULATOR` (Model Registry) |
| Agent tools | `SP_DETECT_EMERGING_ISSUES`, `SP_SIMULATE_EXPOSURE`, `SP_RECOMMEND_ACTIONS`, `SP_ALLOCATE_RESOURCES` |
| Workflow | `CQC_ACTION` tables, views and procedures for promote, assign, transition, forward and SLA checks |
| AI | Semantic view `CQC_ML.CUSTOMER_QUALITY_MODEL`, Cortex Search services `CQC_INSIGHTS.INSIGHT_EVIDENCE_SEARCH` and `CQC_DOCS.TECH_DOC_SEARCH`, Cortex Agent `CQC_ML.CUSTOMER_QUALITY_AGENT` |
| Evaluation | Agent eval dataset `CQC_ML.EVAL_DATASET_CUSTOMER_QUALITY_AGENT` (12 questions) and task `TASK_AGENT_EVAL_WEEKLY` (created suspended; a placeholder until you wire it to `EXECUTE_AI_EVALUATION`) |

## Quick start

### Install with Cortex Code

```
$sf-solutions:customer-quality-command
```

### Install manually

Run as `ACCOUNTADMIN`, in this order:

```bash
snow sql -f scripts/setup.sql    --enable-templating NONE
snow sql -f scripts/data.sql     --enable-templating NONE
snow sql -f scripts/pipeline.sql --enable-templating NONE
```

`--enable-templating NONE` is required because the scripts contain `&` characters.

Measured on a LARGE warehouse at the default scale (40,800 machines), across three installs:

| Script | Time |
|---|---|
| `setup.sql` | about 1-2 min (Python package resolution) |
| `data.sql` | about 3-5 min |
| `pipeline.sql` | about 8-10 min |

**Scale.** The default of 40,800 machines is the size the demo story and the numbers above are
written for. For a quicker build, set a smaller count after `setup.sql` and before `data.sql`;
issue counts, rankings and dollar figures will then differ from this README:

```sql
UPDATE SF_SOLUTIONS.CQC_RAW.CQC_CONFIG SET VALUE = '5000' WHERE KEY = 'N_MACHINES';
```

**Cortex models.** The build calls `AI_EMBED` (`snowflake-arctic-embed-m-v1.5`) and `AI_COMPLETE`
(`llama3.1-8b`, `mistral-large2`); the optional app's review board uses `claude-sonnet-4-6`. If a
model isn't available in your region, enable cross-region inference.

## Try it

- **Snowflake CoWork:** open `CUSTOMER_QUALITY_AGENT` and ask, for example:
  - "What's our biggest safety-priority quality issue and why?"
  - "Why are LX-950 units disproportionately affected by the fuel-system issue?"
  - "What is the warranty exposure if the LX-950 fuel-system issue spreads?"
  - "What should we do in the next 72 hours?"
- **Cortex Analyst:** query the semantic view directly (it exposes facts and dimensions):

  ```sql
  SELECT * FROM SEMANTIC_VIEW(
    SF_SOLUTIONS.CQC_ML.CUSTOMER_QUALITY_MODEL
    FACTS insight_issue.priority_rank, insight_issue.exposed_fleet_count,
          insight_issue.warranty_exposure_p90
  )
  ORDER BY priority_rank
  LIMIT 10;
  ```

- **Top issues, safety first:**

  ```sql
  SELECT priority_rank, title, quality_dimension, exposed_fleet_count,
         ROUND(warranty_exposure_p90) AS plan_for_exposure_usd, root_cause_summary
  FROM SF_SOLUTIONS.CQC_INSIGHTS.INSIGHT_ISSUE
  ORDER BY priority_rank
  LIMIT 10;
  ```

See [NEXT_ACTIONS.md](NEXT_ACTIONS.md) for more.

## Data scale (default build)

| Item | Count |
|---|---|
| Machines / models / build plants | 40,800 / 12 / 6 |
| Dealers / customer accounts | 180 / 2,500 |
| Genealogy rows (component installs) | 489,600 |
| Observed failures (Weibull-sampled) | 78,266 |
| Telematics health and fault rows (RAW) | about 7.5 million |
| Quality events (`FACT_QUALITY_EVENT`) | 246,752 |
| Governable issues | 141 |

## Optional add-on: CQC app (SPCS, not available on trial accounts)

A React + FastAPI app with Quality Command, Emerging Issues, Quality Alerts, Issue Detail,
Explainability, Impacted Fleet, Persona Views, a three-agent Review Board, Resolution Tracker,
Data Explorer, Data Readiness and Ask CQC pages, plus a guided Story Mode. It runs in Snowpark
Container Services and needs a compute pool and an image repository, which trial accounts can't
create. See [app/README.md](app/README.md).

## Key design choices

- **Failure physics, not hand-placed rows.** The generator samples latent Weibull lifetimes per
  component, model and failure mode, plants one lot-concentrated defect (the anchor scenario) and
  propagates each failure into correlated service, warranty, telematics and fluid-analysis records,
  so the ML recovers a known truth.
- **Fixed observation date.** The synthetic history ends on 2026-07-15, the "today" of the demo,
  so every build reproduces the same issues, ranks and dollar figures regardless of install day.
- **Safety-gated, lexicographic ranking.** Safety issues always sort ahead of productivity and
  experience issues; archetype weighting only re-ranks within the non-safety tiers.
- **Explainability as data.** Evidence, rationale and data confidence are stored with each insight,
  so the agent and the app quote the same materialized numbers.
- **Re-running the pipeline.** Model Registry versions are named `V1`; on a re-run without teardown
  the existing versions are kept (logged as non-fatal) while all scored tables are refreshed.

## Teardown

```bash
snow sql -f scripts/teardown.sql --enable-templating NONE
```

Drops the nine CQC schemas (including the models, search services, semantic view, agent and task)
and, if installed, the app service and compute pool. The shared `SF_SOLUTIONS` database and
`SF_SOLUTIONS_WH` warehouse are kept. Safe to run more than once.
