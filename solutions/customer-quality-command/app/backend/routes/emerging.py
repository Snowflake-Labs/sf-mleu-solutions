"""Emerging-issue detections (reads ML.EMERGING_ISSUE_SIGNALS). See doc 4 module 2."""

from config import ML
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/emerging", tags=["emerging"])


def _safe(sql, params=None):
    try:
        return run_query(sql, params) if params else run_query(sql)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/summary")
def summary():
    """GET /summary: return summary."""
    return _safe(
        f"SELECT COUNT_IF(alarm=1) AS alarms, "
        f"COUNT_IF(is_changepoint) AS changepoints, "
        f"COUNT_IF(anomaly_flag=1) AS anomalies, "
        f"COUNT(DISTINCT model || '|' || system_group_cd) AS watched_series, "
        f"MAX(event_month) AS latest_month "
        f"FROM {ML}.EMERGING_ISSUE_SIGNALS"
    )


@router.get("/signals")
def signals():
    """GET /signals: return signals."""
    return _safe(
        f"SELECT model, system_group_cd, event_month, n, active_fleet, rate_per_1k, "
        f"baseline_rate, z, ewma, cusum, alarm, is_changepoint, anomaly_flag "
        f"FROM {ML}.EMERGING_ISSUE_SIGNALS "
        f"WHERE alarm=1 OR is_changepoint OR anomaly_flag=1 "
        f"ORDER BY event_month DESC, z DESC NULLS LAST LIMIT 60"
    )


@router.get("/series")
def series(model: str, system_group: str):
    """GET /series: return series."""
    return _safe(
        f"SELECT event_month, rate_per_1k, baseline_rate, ewma, z, alarm, is_changepoint "
        f"FROM {ML}.EMERGING_ISSUE_SIGNALS "
        f"WHERE model = %s AND system_group_cd = %s "
        f"ORDER BY event_month",
        (model, system_group),
    )
