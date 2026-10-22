"""Foundation: data readiness + explainability (reads STAGING DQ + INSIGHTS). See doc 7."""

from config import INSIGHTS, STAGING
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/readiness", tags=["readiness"])


def _safe(sql):
    try:
        return run_query(sql)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/dq-checks")
def dq_checks():
    """GET /dq-checks: return dq checks."""
    return _safe(
        f"SELECT check_name, target_object, check_type, numerator, denominator, rate, status, checked_ts "
        f"FROM {STAGING}.STG_DQ_CHECKS ORDER BY status DESC, checked_ts DESC LIMIT 200"
    )


@router.get("/confidence")
def confidence():
    """GET /confidence: return confidence."""
    return _safe(
        f"SELECT issue_id, title, quality_dimension, data_confidence, data_confidence_band "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE "
        f"ORDER BY data_confidence ASC LIMIT 50"
    )
