# FieldIQ

Disclaimer: This application is not part of the Snowflake Service and is governed by the terms
in LICENSE, unless expressly agreed to in writing. You use this application at your own risk,
and Snowflake has no obligation to support your use of this application. [Learn more](../../LEGAL.md)

| Field | Value |
|-------|-------|
| Edition | Enterprise |
| Trial Account | Yes (core accelerator); No (optional SPCS add-ons) |
| Author | Rishabh Raman |

An agentic AI sales co-pilot for the field sales team of an industrial-equipment manufacturer.
A rep asks questions in plain English across CRM, ERP, installed-base and engineering-document
data, gets grounded answers, and has the agent prepare call plans, meeting agendas, customer
emails and multi-day visit routes, all on Snowflake. All data is synthetic and generated in your
account at install time, for a fictional compressor and air-treatment maker, Apex Industrial.

## Business problem and outcomes

Before a customer visit, a field rep typically pieces the account together from several places:

- Pipeline and contacts in the CRM, open orders and stock in the ERP, installed equipment and
  service history in a field-service system
- Product specs, drawings, submittals and pricing in PDFs on a shared drive
- Call plans, agendas and follow-up emails written by hand for each visit
- Route planning done separately, without knowing which other customers are nearby

| Capability | Problem it addresses | Outcome in this demo |
|---|---|---|
| **One account view** | Account facts spread across CRM, ERP and service systems | `FIQ_ANALYTICS.V_ACCOUNT_360` joins 9 tables: 120 accounts, $42.4M open pipeline, $33.1M open orders, 506 installed assets |
| **Natural-language analytics** | Reps can't write SQL | Cortex Analyst over semantic view `FIELDIQ_SEMANTIC_MODEL` answers pricing, lead-time, inventory, pipeline, order, asset and service questions |
| **Document search** | Specs and drawings buried in PDFs | Cortex Search over 262 generated documents (98 datasheets, 94 GA drawings, 56 submittals, 7 sales playbooks, 7 pricing sheets), chunked into 263 passages |
| **Service upsell signals** | At-risk equipment goes unnoticed | 104 assets flagged WARNING or CRITICAL and 201 with no service plan, surfaced per account |
| **AI-prepared visits** | Call plans, agendas and emails written by hand | Agent tools generate a sales call plan, a 60-minute meeting agenda and a customer email in any language, grounded in the account's orders, opportunities, assets and contacts |
| **Route planning** | Visits planned without knowing who is nearby | Geospatial tools find customers within N miles (12 within 50 miles of Cincinnati, OH) and plan a multi-day route ranked by pipeline |
| **Ask FieldIQ** | Answers spread across systems | One Cortex Agent, `FIELDIQ_AGENT`, with 7 tools: Analyst, Search and 5 action procedures |

The anchor account for the examples below is **Cascade Partners** (Phoenix, AZ): $4.57M open
pipeline across 2 open opportunities, $269K of open orders, 5 installed assets (2 at risk) and
6 contacts.

## Architecture

```
  SP_GENERATE_DATA (Python stored procedure)
    synthetic CRM/ERP tables ─► FIQ_ATOMIC  (accounts, contacts, products, inventory,
                                              opportunities, open orders, assets, service, docs registry)
    engineering PDFs + markdown ─► @FIQ_STAGES.DOCS
    search passages ─► FIQ_CORTEX.DOC_CHUNKS
        │
        ▼
  FIQ_ANALYTICS  (V_ACCOUNT_360, V_PIPELINE_BY_STAGE, V_ASSET_RISK, enriched views)
        │
        ▼
  FIQ_CORTEX
    semantic view FIELDIQ_SEMANTIC_MODEL ─► Cortex Analyst ─┐
    Cortex Search FIELDIQ_DOC_SEARCH ───────────────────────┼─► FIELDIQ_AGENT (Snowflake CoWork)
  FIQ_ACTIONS  (SALES_CALL_PLAN, MEETING_AGENDA, EMAIL_DRAFT,│
                NEARBY_CUSTOMERS, ROUTE_PLAN; COMPLETE) ─────┘

  Optional: web app (React + FastAPI) and voice service (GPU) in Snowpark Container Services (app/)
```

## What gets installed

| Layer | Objects |
|---|---|
| Database / warehouse | Shared `SF_SOLUTIONS` database and `SF_SOLUTIONS_WH` (LARGE) warehouse, created if missing |
| Schemas | `FIQ_ATOMIC`, `FIQ_ANALYTICS`, `FIQ_CORTEX`, `FIQ_ACTIONS`, `FIQ_STAGES` |
| Tables | 9 atomic tables in `FIQ_ATOMIC`, `FIQ_CORTEX.DOC_CHUNKS` |
| Python procedure | `FIQ_ATOMIC.SP_GENERATE_DATA` (data, documents and search passages) |
| Agent tools | `FIQ_ACTIONS.SALES_CALL_PLAN`, `MEETING_AGENDA`, `EMAIL_DRAFT`, `NEARBY_CUSTOMERS` (+ `NEARBY_CUSTOMERS_JSON` for the agent), `ROUTE_PLAN` |
| AI | Semantic view `FIQ_CORTEX.FIELDIQ_SEMANTIC_MODEL`, Cortex Search service `FIQ_CORTEX.FIELDIQ_DOC_SEARCH`, Cortex Agent `FIQ_CORTEX.FIELDIQ_AGENT` |

## Quick start

### Install with Cortex Code

```
$sf-solutions:fieldiq
```

### Install manually

Run as `ACCOUNTADMIN`, in this order:

```bash
snow sql -f scripts/setup.sql    --enable-templating NONE
snow sql -f scripts/data.sql     --enable-templating NONE
snow sql -f scripts/pipeline.sql --enable-templating NONE
```

`--enable-templating NONE` is required because the scripts contain `&` characters.

Measured on a LARGE warehouse, across three installs:

| Script | Time |
|---|---|
| `setup.sql` | about 1 min (Python package resolution) |
| `data.sql` | about 2 min |
| `pipeline.sql` | under 1 min |

**Cortex models.** The action procedures call `SNOWFLAKE.CORTEX.COMPLETE` with
`claude-sonnet-4-6`, and Cortex Search embeds with its default model. If a model isn't available
in your region, enable cross-region inference.

**Dates.** Dates in the synthetic data (orders, opportunities, service activity) are generated
relative to the install day, so they move with it; all amounts, counts and names are the same on
every install.

## Try it

- **Snowflake CoWork:** open `FIELDIQ_AGENT` and ask, for example:
  - "What is the total open pipeline for Cascade Partners?"
  - "Generate a sales call plan for Cascade Partners"
  - "Draft an email to Cascade Partners about assets without service plans, propose an inspection, in Spanish"
  - "Which customers are within 50 miles of Cincinnati, OH?"
  - "Plan a 2-day route starting with Cascade Partners next Monday"
  - "What is the full load amps for RS75i-A125?"
- **Call an action tool directly:**

  ```sql
  CALL SF_SOLUTIONS.FIQ_ACTIONS.SALES_CALL_PLAN('Cascade Partners');
  CALL SF_SOLUTIONS.FIQ_ACTIONS.NEARBY_CUSTOMERS('Cincinnati', 'OH', 50);
  ```

- **Account 360:**

  ```sql
  SELECT ACCOUNT_NAME, INDUSTRY, BILLING_CITY, OPEN_PIPELINE_USD, ASSETS_AT_RISK, ASSETS_NO_SERVICE_PLAN
  FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360
  ORDER BY OPEN_PIPELINE_USD DESC NULLS LAST
  LIMIT 10;
  ```

See [NEXT_ACTIONS.md](NEXT_ACTIONS.md) for more.

## Data scale

| Item | Count |
|---|---|
| Accounts / contacts / sales reps / states | 120 / 502 / 30 / 18 |
| Products (7 families) / inventory rows | 102 / 194 |
| Opportunities / open orders | 276 / 139 |
| Installed assets / service activities | 506 / 1,301 |
| Documents (PDF + markdown) / search passages | 262 / 263 |

## Optional add-ons (SPCS, not available on trial accounts)

- **Web app.** A React + FastAPI app with Landing, Sales Command Center, Account 360, Customer
  Map, Knowledge, Insights and Architecture pages and a chat panel for `FIELDIQ_AGENT`. It needs
  a compute pool and an image repository. See [app/README.md](app/README.md).
- **Voice service.** An open-source voice front end (Silero VAD, faster-whisper, Piper TTS) that
  lets a rep talk to the same agent. It runs on a GPU compute pool and has **not been re-tested in
  this release**. See [app/voice/README.md](app/voice/README.md).

## Key design choices

- **Generated, not shipped, data.** One Python procedure builds the CRM/ERP tables, renders the
  engineering PDFs and markdown with `reportlab`, uploads them to a stage and chunks them for
  search, so the repository contains no data files.
- **Seeded generator.** Fixed random seeds make every install produce the same accounts, amounts
  and documents.
- **Actions as SQL procedures.** Each agent action gathers the account's facts with SQL and asks
  `COMPLETE` to write the output, so answers cite real order numbers, serials and amounts.
- **Customer lookup by name.** Account names are unique; tools match a name exactly first, then
  as a substring.

## Teardown

```bash
snow sql -f scripts/teardown.sql --enable-templating NONE
```

Drops the five FIQ schemas (including the procedures, stages, search service, semantic view and
agent) and, if installed, the add-on services and compute pools. The shared `SF_SOLUTIONS`
database and `SF_SOLUTIONS_WH` warehouse are kept. Safe to run more than once.
