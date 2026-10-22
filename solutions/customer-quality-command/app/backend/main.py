"""Customer Quality Command backend (FastAPI).

Serves the INSIGHTS/ACTION consumption contract, the Ask assistant (Cortex Agent SSE), and the
Quality Review Board debate SSE. Dual local/SPCS auth via config.get_connection.
"""

import logging

import config
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes import (
    actions,
    agent,
    alerts,
    archetype,
    command,
    emerging,
    explorer,
    issues,
    personas,
    readiness,
    reviewboard,
    workflow,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cqc")

app = FastAPI(title=f"{config.PRODUCT_NAME} — {config.COMPANY_NAME}", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (
    command,
    issues,
    personas,
    alerts,
    actions,
    agent,
    reviewboard,
    readiness,
    emerging,
    explorer,
    workflow,
    archetype,
):
    app.include_router(r.router)


@app.get("/health")
def health():
    """GET /health: return health."""
    return {"status": "ok", "app": "cqc", "spcs": config.IS_SPCS}


@app.get("/api/config")
def get_config():
    """GET /api/config: return get config."""
    return {
        "app": config.PRODUCT_SHORT,
        "product_name": config.PRODUCT_NAME,
        "subtitle": f"{config.COMPANY_NAME} Customer Quality",
        "company": config.COMPANY_NAME,
        "business_unit": config.BUSINESS_UNIT,
        "anchor_model": config.ANCHOR_MODEL,
        "database": config.DATABASE,
        "agent": config.AGENT_FQN,
        "anchor_machine": config.ANCHOR_MACHINE,
        "spcs": config.IS_SPCS,
        "personas": ["dealer", "product", "manufacturing", "supply_chain", "executive"],
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
