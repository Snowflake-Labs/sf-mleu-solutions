"""Quality Command dashboard endpoints (reads INSIGHTS). See docs 5 & 7."""

from config import INSIGHTS
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/command", tags=["command"])


def _safe(sql: str, params=None):
    try:
        return run_query(sql, params)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/trend")
def trend():
    """Monthly event counts by S/P/E dimension (last 24 months) for ribbon sparklines."""
    return _safe(
        f"SELECT metric_name AS dimension, TO_VARCHAR(period, 'YYYY-MM') AS month, SUM(value) AS value "
        f"FROM {INSIGHTS}.INSIGHT_METRIC_TREND "
        f"WHERE grain = 'dimension' AND period >= DATEADD('month', -24, DATE_TRUNC('month', CURRENT_DATE())) "
        f"GROUP BY 1, 2 ORDER BY 2"
    )


@router.get("/ribbon")
def metric_ribbon():
    """S/P/E + Enterprise Impact ribbon, computed from INSIGHT_ISSUE."""
    return _safe(
        f"""
        SELECT 'SAFETY' AS pillar,
               MAX(IFF(quality_dimension='SAFETY',1,0)) AS present,
               (SELECT COUNT(*) FROM {INSIGHTS}.INSIGHT_ISSUE WHERE quality_dimension='SAFETY') AS issue_count,
               (SELECT ROUND(MAX(pro_sif_risk),1) FROM {INSIGHTS}.INSIGHT_ISSUE
                 WHERE quality_dimension='SAFETY') AS headline
        FROM {INSIGHTS}.INSIGHT_ISSUE
        UNION ALL
        SELECT 'PRODUCTIVITY', 1,
               (SELECT COUNT(*) FROM {INSIGHTS}.INSIGHT_ISSUE WHERE quality_dimension='PRODUCTIVITY'),
               (SELECT ROUND(MAX(vtc_usd)) FROM {INSIGHTS}.INSIGHT_ISSUE WHERE quality_dimension='PRODUCTIVITY')
        UNION ALL
        SELECT 'EXPERIENCE', 1,
               (SELECT COUNT(*) FROM {INSIGHTS}.INSIGHT_ISSUE WHERE quality_dimension='EXPERIENCE'),
               (SELECT ROUND(MAX(cei_score),1) FROM {INSIGHTS}.INSIGHT_ISSUE WHERE quality_dimension='EXPERIENCE')
        UNION ALL
        SELECT 'ENTERPRISE', 1,
               (SELECT COUNT(*) FROM {INSIGHTS}.INSIGHT_ISSUE),
               (SELECT ROUND(SUM(warranty_exposure_p90)) FROM {INSIGHTS}.INSIGHT_ISSUE)
        """
    )


@router.get("/curated-issues")
def curated_issues(limit: int = 10):
    """GET /curated-issues: return curated issues."""
    return _safe(
        f"SELECT issue_id, title, quality_dimension, model, system_group, priority_rank, "
        f"warranty_exposure_p90, exposed_fleet_count, impacted_customer_count, status, "
        f"root_cause_type, data_confidence_band "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE ORDER BY priority_rank LIMIT {int(limit)}"
    )


@router.get("/impacted/{dimension}")
def impacted(dimension: str, issue_id: str | None = None):
    """Dimension in {customers, dealers, facilities, areas}."""
    dim = dimension.lower()
    table = {
        "customers": "INSIGHT_IMPACTED_CUSTOMERS",
        "dealers": "INSIGHT_IMPACTED_DEALERS",
        "facilities": "INSIGHT_IMPACTED_FACILITIES",
        "areas": "INSIGHT_IMPACTED_AREAS",
    }.get(dim)
    if not table:
        return {"error": f"unknown dimension {dimension}"}
    where = "WHERE issue_id = %s" if issue_id else ""
    return _safe(
        f"SELECT entity_name, exposure_count, impact_value, geo FROM {INSIGHTS}.{table} {where} "
        f"ORDER BY exposure_count DESC LIMIT 15",
        (issue_id,) if issue_id else None,
    )
