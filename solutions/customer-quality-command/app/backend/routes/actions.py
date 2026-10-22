"""Action / recommendation endpoints (reads INSIGHTS.INSIGHT_ACTION + agent procs)."""

from config import INSIGHTS
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api", tags=["actions"])


def _safe(sql, params=None):
    try:
        return run_query(sql, params)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/actions/recommended/{issue_id}")
def recommended_actions(issue_id: str):
    """GET /actions/recommended/{issue_id}: return recommended actions."""
    return _safe(
        f"SELECT action_id, owner_persona, time_window, action_text, action_rationale, "
        f"expected_risk_reduction, source, status FROM {INSIGHTS}.INSIGHT_ACTION "
        f"WHERE issue_id = %s ORDER BY time_window",
        (issue_id,),
    )


@router.get("/actions/tracker")
def resolution_tracker():
    """Open work items across issues (Resolution Tracker tile)."""
    return _safe(
        f"SELECT i.issue_id, i.title, i.quality_dimension, i.status, i.priority_rank, "
        f"COUNT(a.action_id) AS open_actions "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE i "
        f"LEFT JOIN {INSIGHTS}.INSIGHT_ACTION a ON a.issue_id = i.issue_id AND a.status='RECOMMENDED' "
        f"WHERE i.status='IN_PROGRESS' GROUP BY 1,2,3,4,5 ORDER BY i.priority_rank LIMIT 25"
    )
