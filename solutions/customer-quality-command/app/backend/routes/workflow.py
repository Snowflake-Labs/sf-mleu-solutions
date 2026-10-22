"""Closed-loop workflow endpoints over ACTION schema (WS8)."""

from config import ACTION
from db import call_proc, run_query
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/api", tags=["workflow"])


def _safe(sql, params=None):
    try:
        return run_query(sql, params) if params else run_query(sql)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/workflow/open")
def workflow_open():
    """GET /workflow/open: return workflow open."""
    return _safe(
        f"SELECT workflow_item_id, title, pillar, severity, state, owner_id, owner_name, persona_scope, "
        f"time_window, sla_due_ts, sla_breached, sla_hours_remaining, priority_rank, model, system_group, "
        f"failure_mode, vtc_usd, pro_sif_risk, insight_issue_id, insight_alert_id, updated_ts "
        f"FROM {ACTION}.V_WORKFLOW_OPEN "
        f"ORDER BY CASE pillar WHEN 'SAFETY' THEN 1 WHEN 'PRODUCTIVITY' THEN 2 ELSE 3 END, "
        f"sla_breached DESC, priority_rank NULLS LAST LIMIT 50"
    )


@router.get("/workflow/{item_id}/timeline")
def workflow_timeline(item_id: str):
    """GET /workflow/{item_id}/timeline: return workflow timeline."""
    return _safe(
        f"SELECT event_ts, event_type, actor, from_state, to_state, note "
        f"FROM {ACTION}.V_WORKFLOW_TIMELINE WHERE workflow_item_id = %s ORDER BY event_ts",
        (item_id,),
    )


@router.get("/owners")
def owners():
    """GET /owners: return owners."""
    return _safe(
        f"SELECT owner_id, owner_name, persona_scope, open_items, breached_items, safety_items "
        f"FROM {ACTION}.V_OWNER_QUEUE ORDER BY open_items DESC"
    )


@router.get("/sla/breaches")
def sla_breaches():
    """GET /sla/breaches: return sla breaches."""
    return _safe(
        f"SELECT workflow_item_id, title, pillar, severity, state, owner_name, sla_due_ts, sla_hours_remaining "
        f"FROM {ACTION}.V_SLA_BREACHES LIMIT 50"
    )


class TransitionBody(BaseModel):
    """Request body: transition body."""

    to_state: str
    actor: str = "app_user"
    note: str = ""


@router.post("/workflow/{item_id}/transition")
def transition(item_id: str, body: TransitionBody):
    """POST /workflow/{item_id}/transition: handle transition."""
    try:
        res = call_proc(
            f"CALL {ACTION}.SP_TRANSITION_WORKFLOW(%s, %s, %s, %s)",
            (item_id, body.to_state, body.actor, body.note),
        )
        msg = res[0] if res else ""
        return {"ok": not str(msg).startswith("ERROR"), "result": msg}
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


class AssignBody(BaseModel):
    """Request body: assign body."""

    owner_id: str
    actor: str = "app_user"


@router.post("/workflow/{item_id}/assign")
def assign(item_id: str, body: AssignBody):
    """POST /workflow/{item_id}/assign: handle assign."""
    try:
        res = call_proc(
            f"CALL {ACTION}.SP_ASSIGN_WORKFLOW(%s, %s, %s)",
            (item_id, body.owner_id, body.actor),
        )
        return {"ok": True, "result": res[0] if res else None}
    except Exception as e:
        return {"_pending": True, "detail": str(e)}
