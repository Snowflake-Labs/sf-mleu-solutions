"""Quality Alerts feed over ACTION.V_ALERT_INBOX + closed-loop transitions (WS8)."""

from config import ACTION
from db import call_proc, run_query
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/api/alerts", tags=["alerts"])


def _safe(sql, params=None):
    try:
        return run_query(sql, params) if params else run_query(sql)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("")
def alert_feed(pillar: str | None = None, limit: int = 50):
    """GET : return alert feed."""
    where = "WHERE pillar = %s" if pillar else ""
    params = (pillar,) if pillar else None
    return _safe(
        f"SELECT alert_id, issue_id, severity, headline, body, pillar, priority_rank, "
        f"workflow_item_id, workflow_state, owner_id, owner_name, sla_due_ts, sla_breached, alert_ts "
        f"FROM {ACTION}.V_ALERT_INBOX "
        f"{where} "
        f"ORDER BY CASE severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MED' THEN 3 ELSE 4 END, "
        f"alert_ts DESC "
        f"LIMIT {int(limit)}",
        params,
    )


class ForwardBody(BaseModel):
    """Request body: forward body."""

    owner_id: str = "OWN-MFG"
    actor: str = "app_user"
    channel: str = "IN_APP"


@router.post("/{alert_id}/forward")
def forward_alert(alert_id: str, body: ForwardBody):
    """POST /{alert_id}/forward: handle forward alert."""
    try:
        row = call_proc(
            f"CALL {ACTION}.SP_FORWARD_ALERT(%s, %s, %s, %s)",
            (alert_id, body.owner_id, body.actor, body.channel),
        )
        return {"ok": True, "alert_id": alert_id, "workflow_item_id": row[0] if row else None, "state": "FORWARDED"}
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


class AckBody(BaseModel):
    """Request body: ack body."""

    actor: str = "app_user"
    note: str = "Acknowledged"


@router.post("/{alert_id}/ack")
def ack_alert(alert_id: str, body: AckBody):
    """POST /{alert_id}/ack: handle ack alert."""
    try:
        wf = call_proc(f"CALL {ACTION}.SP_PROMOTE_TO_WORKFLOW(%s, %s)", (alert_id, body.actor))
        wf_id = wf[0] if wf else None
        res = call_proc(
            f"CALL {ACTION}.SP_TRANSITION_WORKFLOW(%s, %s, %s, %s)",
            (wf_id, "ACKNOWLEDGED", body.actor, body.note),
        )
        return {"ok": True, "alert_id": alert_id, "workflow_item_id": wf_id, "result": res[0] if res else None}
    except Exception as e:
        return {"_pending": True, "detail": str(e)}
