"""Issue detail + evidence endpoints (reads INSIGHTS). See doc 5."""

from config import INSIGHTS
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/issues", tags=["issues"])


def _safe(sql, params=None):
    try:
        return run_query(sql, params)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("")
def list_issues(pillar: str | None = None, limit: int = 50):
    """GET : return list issues."""
    where = "WHERE quality_dimension = %s" if pillar else ""
    return _safe(
        f"SELECT issue_id, title, quality_dimension, model, system_group, failure_mode, status, "
        f"warranty_exposure_p90, exposed_fleet_count, priority_rank, root_cause_type, data_confidence_band "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE {where} ORDER BY priority_rank LIMIT {int(limit)}",
        (pillar,) if pillar else None,
    )


@router.get("/{issue_id}")
def issue_detail(issue_id: str):
    """GET /{issue_id}: return issue detail."""
    return _safe(
        f"SELECT * EXCLUDE (evidence, provenance) FROM {INSIGHTS}.INSIGHT_ISSUE WHERE issue_id = %s",
        (issue_id,),
    )


@router.get("/{issue_id}/evidence")
def issue_evidence(issue_id: str):
    """GET /{issue_id}/evidence: return issue evidence."""
    return _safe(
        f"SELECT issue_id, title, model, system_group, failure_mode, quality_dimension, "
        f"evidence, rationale_text, provenance, root_cause_type, data_confidence, data_confidence_band "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE WHERE issue_id = %s",
        (issue_id,),
    )


@router.get("/{issue_id}/risk")
def issue_risk(issue_id: str):
    """GET /{issue_id}/risk: return issue risk."""
    return _safe(f"SELECT * FROM {INSIGHTS}.INSIGHT_RISK_ASSESSMENT WHERE issue_id = %s", (issue_id,))


@router.get("/{issue_id}/actions")
def issue_actions(issue_id: str):
    """GET /{issue_id}/actions: return issue actions."""
    return _safe(
        f"SELECT action_id, owner_persona, time_window, action_text, action_rationale, "
        f"expected_risk_reduction, source, status FROM {INSIGHTS}.INSIGHT_ACTION "
        f"WHERE issue_id = %s ORDER BY time_window",
        (issue_id,),
    )
