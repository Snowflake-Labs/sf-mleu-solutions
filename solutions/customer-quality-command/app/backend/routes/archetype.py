"""Customer Archetype (customer-back) endpoints — reads INSIGHTS/ACTION/ATOMIC.

Exposes the four customer archetypes, per-issue archetype exposure mix with
relative pain, the customer-back priority lens, and archetype-driven routing.
"""

from config import ACTION, ATOMIC, INSIGHTS
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/archetype", tags=["archetype"])


def _safe(sql, params=None):
    try:
        return run_query(sql, params)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/reference")
def reference():
    """The four governed archetypes as defined by the manufacturer."""
    return _safe(
        f"SELECT archetype, archetype_rank, account_model, operations_label, size_hint, "
        f"quality_definition, quality_definition_cd, pain_channel, pain_channel_cd, "
        f"response_mode, equip_rev_midpoint, pop_pct "
        f"FROM {ATOMIC}.REF_ACCOUNT_ARCHETYPE ORDER BY archetype_rank"
    )


@router.get("/distribution")
def distribution():
    """Global customer-population split by archetype."""
    return _safe(
        f"SELECT c.account_archetype AS archetype, r.archetype_rank, r.operations_label, "
        f"COUNT(*) AS customers, "
        f"ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct "
        f"FROM {ATOMIC}.DIM_CUSTOMER c "
        f"JOIN {ATOMIC}.REF_ACCOUNT_ARCHETYPE r ON r.archetype = c.account_archetype "
        f"GROUP BY 1,2,3 ORDER BY r.archetype_rank"
    )


@router.get("/mix/{issue_id}")
def issue_mix(issue_id: str):
    """Per-issue archetype exposure mix with relative pain + pain share."""
    return _safe(
        f"SELECT archetype, archetype_rank, units, customers, basis, per_unit_usd, "
        f"relative_pain_per_unit, relative_pain, pain_share_pct, is_dominant_pain, "
        f"quality_definition, quality_definition_cd, pain_channel, pain_channel_cd, response_mode "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE_ARCHETYPE "
        f"WHERE issue_id = %s ORDER BY archetype_rank",
        (issue_id,),
    )


@router.get("/routing/{issue_id}")
def issue_routing(issue_id: str):
    """Archetype-driven closed-loop routing for an issue (owner + response mode)."""
    return _safe(
        f"SELECT archetype, archetype_rank, units, pain_share_pct, pain_channel, "
        f"owner_id, owner_name, org_unit, response_mode, response_play, is_dominant_pain "
        f"FROM {ACTION}.V_ARCHETYPE_ROUTING "
        f"WHERE issue_id = %s ORDER BY archetype_rank",
        (issue_id,),
    )


@router.get("/customer-back/{issue_id}")
def issue_customer_back(issue_id: str):
    """Customer-back priority rollup for an issue (rank vs standard, dominant pain)."""
    return _safe(
        f"SELECT issue_id, quality_dimension, orig_priority_rank, customer_back_rank, "
        f"rank_in_tier, rank_delta, pain_intensity, dominant_archetype, dominant_channel, "
        f"dominant_pain_share_pct, dominant_units "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE_CUSTOMER_BACK WHERE issue_id = %s",
        (issue_id,),
    )


@router.get("/customer-back-board")
def customer_back_board(pillar: str | None = None, limit: int = 15):
    """Leaderboard re-ranked by customer-back pain (safety stays absolute)."""
    where = "AND cb.quality_dimension = %s" if pillar else ""
    return _safe(
        f"SELECT cb.customer_back_rank, cb.orig_priority_rank, cb.rank_delta, "
        f"cb.quality_dimension, cb.pain_intensity, cb.dominant_archetype, cb.dominant_channel, "
        f"cb.dominant_pain_share_pct, ii.title, ii.model, ii.system_group, ii.failure_mode, cb.issue_id "
        f"FROM {INSIGHTS}.INSIGHT_ISSUE_CUSTOMER_BACK cb "
        f"JOIN {INSIGHTS}.INSIGHT_ISSUE ii ON ii.issue_id = cb.issue_id "
        f"WHERE 1=1 {where} ORDER BY cb.customer_back_rank LIMIT {int(limit)}",
        (pillar,) if pillar else None,
    )
