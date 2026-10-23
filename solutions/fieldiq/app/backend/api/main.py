"""FieldIQ by Apex Industrial — FastAPI backend.

Endpoints
---------
GET    /health                            health check
GET    /api/info                          build info
POST   /api/chat/stream                   SSE — Cortex Agent streaming
GET    /api/portfolio/summary             rep dashboard KPIs
GET    /api/accounts                      account list (with KPIs)
GET    /api/accounts/{account_id}         single account 360
GET    /api/accounts/{account_id}/contacts
GET    /api/accounts/{account_id}/orders
GET    /api/accounts/{account_id}/opportunities
GET    /api/accounts/{account_id}/assets
GET    /api/accounts/{account_id}/services
GET    /api/products                      product catalog (search-able)
GET    /api/products/{product_id}
GET    /api/inventory                     inventory rows (search-able)
GET    /api/docs                          recent documents
GET    /api/morning-brief                 personalized brief for a rep
GET    /api/nearby?city=&state=&radius_mi=
GET    /api/agents/specs                  the 14 feature prompts (for landing page)
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from ..services.cortex_agent_client import get_cortex_agent_client
from ..services.fieldiq_service import get_fieldiq_service

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("fieldiq")

app = FastAPI(title="FieldIQ API", description="FieldIQ by Apex Industrial — AI sales co-pilot", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:3001", "http://localhost:5173", "*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =====================================================================
# Lazy singletons
# =====================================================================
def get_sf():
    """Get sf."""
    return get_fieldiq_service()


def get_agent():
    """Get agent."""
    return get_cortex_agent_client()


# =====================================================================
# Health / info
# =====================================================================
@app.get("/health")
def health():
    """GET /health: return health."""
    return {"status": "ok", "ts": datetime.utcnow().isoformat()}


@app.get("/api/info")
def info():
    """GET /api/info: return info."""
    return {
        "app": "FieldIQ by Apex Industrial",
        "version": "1.0.0",
        "agent": "SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_AGENT",
        "search": "SF_SOLUTIONS.FIQ_CORTEX.FIELDIQ_DOC_SEARCH",
        "is_spcs": os.path.exists("/snowflake/session/token"),
    }


# =====================================================================
# 14 Features — quick-start prompts shown on the landing screen
# =====================================================================
FIELDIQ_FEATURES = [
    {
        "id": "product_specs",
        "icon": "file-text",
        "label": "Product Specs & Sales Training",
        "prompts": [
            "How to sell a 10HP diesel reciprocating compressor — list documents",
            "How to sell Air Quality services — list playbooks",
        ],
    },
    {
        "id": "drawings",
        "icon": "file-image",
        "label": "Find Drawing / Engineering Data Links / Submittals",
        "prompts": ["Drawing for C750 GA", "RS75i submittal documents"],
    },
    {
        "id": "data_sheets",
        "icon": "layers",
        "label": "Engineering Data Sheets",
        "prompts": ["What is full-load amps for RS75i-A125?", "Specific power for C1000-GA"],
    },
    {
        "id": "pricing",
        "icon": "tag",
        "label": "Pricing",
        "prompts": ["Price for RS37i-A110", "Price list for the centrifugal C-Series"],
    },
    {
        "id": "lead_times",
        "icon": "clock",
        "label": "Lead Times",
        "prompts": ["Lead time for TS15M models", "What is the lead time for RS75i-A125?"],
    },
    {
        "id": "barn_units",
        "icon": "box",
        "label": "Barn Units (Stock Inventory)",
        "prompts": ["Barn units for RS45", "Inventory across all distribution centers for the AQ-250"],
    },
    {
        "id": "contacts",
        "icon": "users",
        "label": "Find Customer Contacts",
        "prompts": ["Key contacts at Cascade Partners", "Who is the procurement decision-maker at Beacon Pharma?"],
    },
    {
        "id": "call_plan",
        "icon": "clipboard",
        "label": "Sales Call Plan",
        "prompts": ["Generate a sales call plan for Cascade Partners", "Prep me for a visit to Beacon Pharma"],
    },
    {
        "id": "open_recs",
        "icon": "search",
        "label": "Open Orders / Opportunities / Assets / Service",
        "prompts": [
            "Provide details about open orders, opportunities, assets, and service activities for Cascade Partners",
            "What is the asset health summary for Beacon Pharma?",
        ],
    },
    {
        "id": "meeting_agenda",
        "icon": "calendar",
        "label": "Meeting Agenda",
        "prompts": [
            "Write a detailed meeting agenda for Cascade Partners",
            "Build an actionable agenda for Sentinel Plastics",
        ],
    },
    {
        "id": "nearby",
        "icon": "map-pin",
        "label": "Find Nearby Customers",
        "prompts": [
            "Are there any other customers close to Fairfield, OH?",
            "Customers within 60 miles of Indianapolis, IN",
        ],
    },
    {
        "id": "route_plan",
        "icon": "map",
        "label": "Route Planning",
        "prompts": [
            "I'm visiting Cascade Partners on May 12 — plan a 2-day agenda factoring 1h visits "
            "with nearby customers and travel times",
            "Plan a 3-day route starting at Beacon Pharma",
        ],
    },
    {
        "id": "email_drafting",
        "icon": "mail",
        "label": "Email Drafting",
        "prompts": [
            "Draft an email to Cascade Partners about assets without ApexCare service plans, propose an inspection",
            "Write a follow-up email to Beacon Pharma about their RS75i opportunity",
        ],
    },
    {
        "id": "multilingual",
        "icon": "globe",
        "label": "Multilingual Support",
        "prompts": [
            "Draft an email to Cascade Partners about an upcoming visit, in Spanish",
            "Write a meeting agenda for Sentinel Plastics in German",
        ],
    },
]


@app.get("/api/agents/specs")
def get_agent_specs():
    """GET /api/agents/specs: return get agent specs."""
    return {"features": FIELDIQ_FEATURES}


# =====================================================================
# Account / portfolio endpoints
# =====================================================================
@app.get("/api/portfolio/summary")
def portfolio_summary(rep: str | None = Query(None, description="Filter to a sales rep")):
    """GET /api/portfolio/summary: return portfolio summary."""
    where, params = "WHERE 1=1", []
    if rep:
        where += " AND ACCOUNT_OWNER = %s"
        params.append(rep)
    rows = get_sf().execute_query(
        f"""
        SELECT
          COUNT(*)                                                AS account_count,
          SUM(OPEN_PIPELINE_USD)                                  AS pipeline_total,
          SUM(OPEN_ORDER_VALUE_USD)                               AS open_orders_total,
          SUM(INSTALLED_ASSET_COUNT)                              AS installed_assets,
          SUM(ASSETS_AT_RISK)                                     AS assets_at_risk,
          SUM(ASSETS_NO_SERVICE_PLAN)                             AS assets_no_plan,
          SUM(SERVICE_SPEND_LTM_USD)                              AS service_spend_ltm
        FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 {where}
    """,
        params,
    )
    pipeline_by_stage = get_sf().execute_query("""
        SELECT STAGE, OPP_COUNT, TOTAL_AMOUNT_USD, AVG_PROBABILITY_PCT, WEIGHTED_AMOUNT_USD
        FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_PIPELINE_BY_STAGE
        ORDER BY ARRAY_POSITION(STAGE::VARIANT,
                ARRAY_CONSTRUCT('Prospecting','Qualification','Proposal','Negotiation',
                                'Closed Won','Closed Lost')::VARIANT)
    """)
    return {"summary": rows[0] if rows else {}, "pipeline_by_stage": pipeline_by_stage}


@app.get("/api/accounts")
def list_accounts(
    q: str | None = Query(None),
    industry: str | None = Query(None),
    state: str | None = Query(None),
    tier: str | None = Query(None),
    owner: str | None = Query(None),
    stage: str | None = Query(None),
    limit: int = Query(200),
):
    """GET /api/accounts: return list accounts."""
    where, params = ["1=1"], []
    if q:
        where.append("a.ACCOUNT_NAME ILIKE %s")
        params.append(f"%{q}%")
    for col, val in (
        ("INDUSTRY", industry),
        ("BILLING_STATE", state),
        ("ACCOUNT_TIER", tier),
        ("ACCOUNT_OWNER", owner),
    ):
        if val:
            where.append(f"a.{col} = %s")
            params.append(val)
    join_clause = ""
    if stage:
        join_clause = """
        INNER JOIN (
          SELECT DISTINCT ACCOUNT_ID FROM SF_SOLUTIONS.FIQ_ATOMIC.OPPORTUNITIES
          WHERE STAGE = %s AND STAGE NOT IN ('Closed Won','Closed Lost')
        ) opp_filter ON opp_filter.ACCOUNT_ID = a.ACCOUNT_ID"""
        params.insert(0, stage)  # the join precedes the WHERE clause
    rows = get_sf().execute_query(
        f"""
      SELECT a.ACCOUNT_ID, a.ACCOUNT_NAME, a.INDUSTRY, a.SEGMENT, a.ACCOUNT_TIER, a.SERVICE_PLAN,
             a.ACCOUNT_OWNER, a.BILLING_CITY, a.BILLING_STATE, a.LATITUDE, a.LONGITUDE,
             a.OPEN_PIPELINE_USD, a.OPEN_ORDER_VALUE_USD,
             a.INSTALLED_ASSET_COUNT, a.ASSETS_AT_RISK, a.ASSETS_NO_SERVICE_PLAN,
             a.SERVICE_SPEND_LTM_USD, a.LAST_ACTIVITY_DATE
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 a
      {join_clause}
      WHERE {" AND ".join(where)}
      ORDER BY a.OPEN_PIPELINE_USD DESC NULLS LAST
      LIMIT {limit}
    """,
        params,
    )
    return {"accounts": rows, "count": len(rows)}


@app.get("/api/accounts/{account_id}")
def account_detail(account_id: str):
    """GET /api/accounts/{account_id}: return account detail."""
    rows = get_sf().execute_query(
        """
      SELECT * FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360
      WHERE ACCOUNT_ID = %s LIMIT 1
    """,
        [account_id],
    )
    if not rows:
        raise HTTPException(404, "Account not found")
    return {"account": rows[0]}


@app.get("/api/accounts/{account_id}/contacts")
def account_contacts(account_id: str):
    """GET /api/accounts/{account_id}/contacts: return account contacts."""
    rows = get_sf().execute_query(
        """
      SELECT CONTACT_ID, FIRST_NAME, LAST_NAME, TITLE, DEPARTMENT, EMAIL, PHONE,
             IS_PRIMARY, DECISION_ROLE, LAST_CONTACTED
      FROM SF_SOLUTIONS.FIQ_ATOMIC.CONTACTS
      WHERE ACCOUNT_ID = %s
      ORDER BY IS_PRIMARY DESC, LAST_NAME
    """,
        [account_id],
    )
    return {"contacts": rows}


@app.get("/api/accounts/{account_id}/orders")
def account_orders(account_id: str):
    """GET /api/accounts/{account_id}/orders: return account orders."""
    rows = get_sf().execute_query(
        """
      SELECT * FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_OPEN_ORDERS_ENRICHED
      WHERE ACCOUNT_ID = %s
      ORDER BY ORDER_DATE DESC
    """,
        [account_id],
    )
    return {"orders": rows}


@app.get("/api/accounts/{account_id}/opportunities")
def account_opps(account_id: str):
    """GET /api/accounts/{account_id}/opportunities: return account opps."""
    rows = get_sf().execute_query(
        """
      SELECT * FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_OPPORTUNITIES_ENRICHED
      WHERE ACCOUNT_ID = %s
      ORDER BY (CASE WHEN STAGE IN ('Closed Won','Closed Lost') THEN 1 ELSE 0 END), CLOSE_DATE
    """,
        [account_id],
    )
    return {"opportunities": rows}


@app.get("/api/accounts/{account_id}/assets")
def account_assets(account_id: str):
    """GET /api/accounts/{account_id}/assets: return account assets."""
    rows = get_sf().execute_query(
        """
      SELECT * FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ASSET_RISK
      WHERE ACCOUNT_ID = %s
      ORDER BY (CASE ALERT_LEVEL WHEN 'CRITICAL' THEN 0 WHEN 'WARNING' THEN 1 WHEN 'WATCH' THEN 2 ELSE 3 END),
               HEALTH_SCORE
    """,
        [account_id],
    )
    return {"assets": rows}


@app.get("/api/accounts/{account_id}/services")
def account_services(account_id: str):
    """GET /api/accounts/{account_id}/services: return account services."""
    rows = get_sf().execute_query(
        """
      SELECT * FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_SERVICE_ACTIVITIES_ENRICHED
      WHERE ACCOUNT_ID = %s
      ORDER BY ACTIVITY_DATE DESC LIMIT 50
    """,
        [account_id],
    )
    return {"services": rows}


# =====================================================================
# Products / Inventory
# =====================================================================
@app.get("/api/products")
def products(q: str | None = Query(None), family: str | None = Query(None), limit: int = Query(200)):
    """GET /api/products: return products."""
    where, params = ["1=1"], []
    if q:
        where.append("(PRODUCT_ID ILIKE %s OR MODEL_CODE ILIKE %s OR DESCRIPTION ILIKE %s)")
        params += [f"%{q}%"] * 3
    if family:
        where.append("PRODUCT_FAMILY = %s")
        params.append(family)
    rows = get_sf().execute_query(
        f"""
      SELECT PRODUCT_ID, MODEL_CODE, PRODUCT_FAMILY, PRODUCT_LINE, DESCRIPTION,
             HORSEPOWER, KW, VOLTAGE, FULL_LOAD_AMPS, CAPACITY_CFM, PRESSURE_PSI,
             LIST_PRICE_USD, LEAD_TIME_WEEKS, STATUS, CAGI_CERTIFIED
      FROM SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS
      WHERE {" AND ".join(where)}
      ORDER BY PRODUCT_FAMILY, PRODUCT_ID
      LIMIT {limit}
    """,
        params,
    )
    return {"products": rows, "count": len(rows)}


@app.get("/api/products/{product_id}")
def product_detail(product_id: str):
    """GET /api/products/{product_id}: return product detail."""
    p = get_sf().execute_query(
        """
      SELECT * FROM SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS WHERE PRODUCT_ID = %s LIMIT 1
    """,
        [product_id],
    )
    if not p:
        raise HTTPException(404, "product not found")
    inv = get_sf().execute_query(
        """
      SELECT LOCATION, QTY_ON_HAND, QTY_RESERVED, QTY_AVAILABLE, AVG_DAYS_IN_STOCK, LAST_RECEIVED_DATE
      FROM SF_SOLUTIONS.FIQ_ATOMIC.INVENTORY WHERE PRODUCT_ID = %s ORDER BY LOCATION
    """,
        [product_id],
    )
    docs = get_sf().execute_query(
        """
      SELECT DOC_ID, DOC_TITLE, DOC_TYPE, STAGE_PATH, FILE_FORMAT
      FROM SF_SOLUTIONS.FIQ_ATOMIC.DOCS_REGISTRY WHERE PRODUCT_ID = %s
      ORDER BY DOC_TYPE
    """,
        [product_id],
    )
    return {"product": p[0], "inventory": inv, "docs": docs}


@app.get("/api/inventory")
def inventory(q: str | None = Query(None), location: str | None = Query(None), limit: int = Query(200)):
    """GET /api/inventory: return inventory."""
    where, params = ["1=1"], []
    if q:
        where.append("(PRODUCT_ID ILIKE %s OR MODEL_CODE ILIKE %s OR DESCRIPTION ILIKE %s)")
        params += [f"%{q}%"] * 3
    if location:
        where.append("LOCATION = %s")
        params.append(location)
    rows = get_sf().execute_query(
        f"""
      SELECT * FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_INVENTORY_ENRICHED
      WHERE {" AND ".join(where)}
      ORDER BY QTY_AVAILABLE DESC
      LIMIT {limit}
    """,
        params,
    )
    return {"inventory": rows}


# =====================================================================
# Docs
# =====================================================================
@app.get("/api/docs")
def docs(q: str | None = Query(None), doc_type: str | None = Query(None), limit: int = Query(50)):
    """GET /api/docs: return docs."""
    where, params = ["1=1"], []
    if q:
        where.append("(DOC_TITLE ILIKE %s OR PRODUCT_ID ILIKE %s)")
        params += [f"%{q}%"] * 2
    if doc_type:
        where.append("DOC_TYPE = %s")
        params.append(doc_type)
    rows = get_sf().execute_query(
        f"""
      SELECT DOC_ID, DOC_TITLE, DOC_TYPE, PRODUCT_FAMILY, PRODUCT_ID,
             STAGE_PATH, FILE_FORMAT, PUBLISHED_DATE
      FROM SF_SOLUTIONS.FIQ_ATOMIC.DOCS_REGISTRY
      WHERE {" AND ".join(where)}
      ORDER BY PUBLISHED_DATE DESC NULLS LAST
      LIMIT {limit}
    """,
        params,
    )
    return {"docs": rows}


# =====================================================================
# Nearby customers (geospatial)
# =====================================================================
@app.get("/api/nearby")
def nearby(city: str, state: str, radius_mi: float = 60.0):
    """GET /api/nearby: return nearby."""
    rows = get_sf().execute_query(
        "CALL SF_SOLUTIONS.FIQ_ACTIONS.NEARBY_CUSTOMERS(%s, %s, %s)",
        [city, state, radius_mi],
    )
    return {"customers": rows}


# =====================================================================
# Morning brief (LLM-summarized for the rep)
# =====================================================================
@app.get("/api/morning-brief")
def morning_brief(rep: str | None = Query(None)):
    """GET /api/morning-brief: return morning brief."""
    where, params = "WHERE 1=1", []
    if rep:
        where += " AND ACCOUNT_OWNER = %s"
        params.append(rep)
    summary = get_sf().execute_query(
        f"""
      SELECT
        COUNT(*) AS account_count,
        SUM(OPEN_PIPELINE_USD) AS pipeline,
        SUM(ASSETS_AT_RISK) AS assets_at_risk,
        SUM(ASSETS_NO_SERVICE_PLAN) AS assets_no_plan,
        SUM(OPEN_ORDER_VALUE_USD) AS open_order_value
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 {where}
    """,
        params,
    )
    top_pipeline = get_sf().execute_query(
        f"""
      SELECT ACCOUNT_NAME, OPEN_PIPELINE_USD
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360 {where}
      ORDER BY OPEN_PIPELINE_USD DESC NULLS LAST LIMIT 5
    """,
        params,
    )
    risky = get_sf().execute_query(
        f"""
      SELECT a.ACCOUNT_NAME, COUNT(*) AS RISKY_COUNT
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS s JOIN SF_SOLUTIONS.FIQ_ATOMIC.ACCOUNTS a USING (ACCOUNT_ID)
      WHERE s.ALERT_LEVEL IN ('WARNING','CRITICAL')
      {"AND a.ACCOUNT_OWNER = %s" if rep else ""}
      GROUP BY a.ACCOUNT_NAME ORDER BY RISKY_COUNT DESC LIMIT 5
    """,
        params,
    )
    return {"summary": summary[0] if summary else {}, "top_pipeline": top_pipeline, "risky_accounts": risky, "rep": rep}


# =====================================================================
# Insights — aggregations to power the Insights dashboard
# =====================================================================
@app.get("/api/insights/pipeline_funnel")
def insights_funnel():
    """GET /api/insights/pipeline_funnel: return insights funnel."""
    rows = get_sf().execute_query("""
      SELECT STAGE, OPP_COUNT, TOTAL_AMOUNT_USD, WEIGHTED_AMOUNT_USD
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_PIPELINE_BY_STAGE
      ORDER BY ARRAY_POSITION(STAGE::VARIANT,
              ARRAY_CONSTRUCT('Prospecting','Qualification','Proposal','Negotiation',
                                'Closed Won','Closed Lost')::VARIANT)
    """)
    return {"rows": rows}


@app.get("/api/insights/top_accounts")
def insights_top_accounts(limit: int = 10):
    """GET /api/insights/top_accounts: return insights top accounts."""
    rows = get_sf().execute_query(f"""
      SELECT ACCOUNT_NAME, INDUSTRY, OPEN_PIPELINE_USD, OPEN_ORDER_VALUE_USD,
             INSTALLED_ASSET_COUNT, ASSETS_AT_RISK
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360
      WHERE OPEN_PIPELINE_USD > 0
      ORDER BY OPEN_PIPELINE_USD DESC
      LIMIT {limit}
    """)
    return {"rows": rows}


@app.get("/api/insights/asset_risk")
def insights_asset_risk():
    """GET /api/insights/asset_risk: return insights asset risk."""
    rows = get_sf().execute_query("""
      SELECT ALERT_LEVEL, COUNT(*) AS ASSETS,
             COUNT(CASE WHEN SERVICE_PLAN='None' THEN 1 END) AS WITHOUT_PLAN
      FROM SF_SOLUTIONS.FIQ_ATOMIC.ASSETS
      GROUP BY ALERT_LEVEL
      ORDER BY ARRAY_POSITION(ALERT_LEVEL::VARIANT,
              ARRAY_CONSTRUCT('OK','WATCH','WARNING','CRITICAL')::VARIANT)
    """)
    return {"rows": rows}


@app.get("/api/insights/service_spend_trend")
def insights_service_spend_trend():
    """GET /api/insights/service_spend_trend: return insights service spend trend."""
    rows = get_sf().execute_query("""
      SELECT TO_CHAR(DATE_TRUNC('MONTH', ACTIVITY_DATE),'YYYY-MM') AS MONTH,
             SUM(LABOR_COST_USD + PARTS_COST_USD)::FLOAT AS SERVICE_SPEND,
             COUNT(*)                            AS ACTIVITIES
      FROM SF_SOLUTIONS.FIQ_ATOMIC.SERVICE_ACTIVITIES
      WHERE ACTIVITY_DATE >= DATEADD('MONTH', -18, CURRENT_DATE)
      GROUP BY 1 ORDER BY 1
    """)
    return {"rows": rows}


@app.get("/api/insights/lead_time_vs_price")
def insights_lt_price():
    """GET /api/insights/lead_time_vs_price: return insights lt price."""
    rows = get_sf().execute_query("""
      SELECT PRODUCT_FAMILY, MODEL_CODE,
             LIST_PRICE_USD::FLOAT  AS PRICE,
             LEAD_TIME_WEEKS::FLOAT AS LEAD_WEEKS,
             HORSEPOWER::FLOAT      AS HP
      FROM SF_SOLUTIONS.FIQ_ATOMIC.PRODUCTS
      WHERE LIST_PRICE_USD IS NOT NULL AND LEAD_TIME_WEEKS IS NOT NULL
    """)
    return {"rows": rows}


@app.get("/api/insights/state_concentration")
def insights_state():
    """GET /api/insights/state_concentration: return insights state."""
    rows = get_sf().execute_query("""
      SELECT BILLING_STATE AS STATE,
             COUNT(*) AS ACCOUNTS,
             SUM(OPEN_PIPELINE_USD)::FLOAT AS PIPELINE
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360
      WHERE BILLING_STATE IS NOT NULL
      GROUP BY 1 ORDER BY PIPELINE DESC NULLS LAST
    """)
    return {"rows": rows}


@app.get("/api/insights/industry_mix")
def insights_industry():
    """GET /api/insights/industry_mix: return insights industry."""
    rows = get_sf().execute_query("""
      SELECT INDUSTRY,
             COUNT(*) AS ACCOUNTS,
             SUM(OPEN_PIPELINE_USD)::FLOAT AS PIPELINE,
             SUM(INSTALLED_ASSET_COUNT) AS ASSETS
      FROM SF_SOLUTIONS.FIQ_ANALYTICS.V_ACCOUNT_360
      GROUP BY 1 ORDER BY PIPELINE DESC NULLS LAST
    """)
    return {"rows": rows}


# =====================================================================
# Chat / Cortex Agent SSE
# =====================================================================
class ChatRequest(BaseModel):
    """Request body: chat request."""

    message: str
    history: list[dict[str, str]] | None = None
    thread_id: str | None = None


@app.post("/api/chat/stream")
async def chat_stream(req: ChatRequest):
    """SSE stream from Cortex Agent."""
    messages = req.history or []
    messages.append({"role": "user", "content": req.message})

    async def event_gen():
        """Event gen."""
        try:
            async for event in get_agent().run_agent_stream(messages, conversation_id=req.thread_id):
                yield f"data: {json.dumps(event)}\n\n"
        except Exception as e:
            logger.exception("agent stream error")
            yield f"data: {json.dumps({'type': 'error', 'content': str(e)})}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_gen(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )
