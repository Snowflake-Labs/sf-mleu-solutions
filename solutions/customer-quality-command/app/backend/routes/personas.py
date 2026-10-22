"""Persona view endpoints (reads INSIGHT_PERSONA_VIEW). See docs 5 & 7."""

from config import INSIGHTS
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/personas", tags=["personas"])

PERSONAS = ["DEALER", "PRODUCT", "MANUFACTURING", "SUPPLY_CHAIN", "EXECUTIVE"]


def _safe(sql, params=None):
    try:
        return run_query(sql, params)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("")
def personas():
    """GET : return personas."""
    return {"personas": PERSONAS}


@router.get("/{persona}/issue/{issue_id}")
def persona_view(persona: str, issue_id: str):
    """GET /{persona}/issue/{issue_id}: return persona view."""
    return _safe(
        f"SELECT * FROM {INSIGHTS}.INSIGHT_PERSONA_VIEW WHERE persona = %s AND issue_id = %s",
        (persona.upper(), issue_id),
    )


@router.get("/issue/{issue_id}")
def all_persona_views(issue_id: str):
    """The 5-view fan-out for a single issue."""
    return _safe(
        f"SELECT persona, view_level, diagnose_question, diagnose_answer_text, primary_metric_name, "
        f"primary_metric_value, primary_metric_target, action_summary "
        f"FROM {INSIGHTS}.INSIGHT_PERSONA_VIEW WHERE issue_id = %s "
        f"ORDER BY CASE persona WHEN 'DEALER' THEN 1 WHEN 'PRODUCT' THEN 2 WHEN 'MANUFACTURING' THEN 3 "
        f"WHEN 'SUPPLY_CHAIN' THEN 4 ELSE 5 END",
        (issue_id,),
    )
