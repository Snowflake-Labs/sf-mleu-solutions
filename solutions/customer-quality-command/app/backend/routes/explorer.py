"""Data Explorer — bounded, read-only catalog browsing. See doc 7."""

import re

from config import (
    DATABASE,
    SCHEMA_ACTION,
    SCHEMA_ANALYTICS,
    SCHEMA_ATOMIC,
    SCHEMA_DOCS,
    SCHEMA_FEATURE_STORE,
    SCHEMA_INSIGHTS,
    SCHEMA_ML,
    SCHEMA_RAW,
    SCHEMA_STAGING,
)
from db import run_query
from fastapi import APIRouter

router = APIRouter(prefix="/api/explorer", tags=["explorer"])

_SCHEMA_MAP = {
    "RAW": SCHEMA_RAW,
    "STAGING": SCHEMA_STAGING,
    "ATOMIC": SCHEMA_ATOMIC,
    "FEATURE_STORE": SCHEMA_FEATURE_STORE,
    "ML": SCHEMA_ML,
    "ANALYTICS": SCHEMA_ANALYTICS,
    "INSIGHTS": SCHEMA_INSIGHTS,
    "ACTION": SCHEMA_ACTION,
    "DOCS": SCHEMA_DOCS,
}
ALLOWED_SCHEMAS = set(_SCHEMA_MAP.values())
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")


def _resolve_schema(short_name: str) -> str | None:
    return _SCHEMA_MAP.get(short_name.upper())


def _safe(sql, params=None):
    try:
        return run_query(sql, params) if params else run_query(sql)
    except Exception as e:
        return {"_pending": True, "detail": str(e)}


@router.get("/tables")
def tables(schema: str | None = None):
    """GET /tables: return tables."""
    where = ""
    params = None
    if schema:
        actual = _resolve_schema(schema)
        if actual:
            where = "AND table_schema = %s"
            params = (actual,)
    schema_list = ",".join(f"'{s}'" for s in ALLOWED_SCHEMAS)
    sql = (
        f"SELECT table_schema, table_name, row_count, bytes, table_type "
        f"FROM {DATABASE}.INFORMATION_SCHEMA.TABLES "
        f"WHERE table_schema IN ({schema_list}) "
        f"{where} ORDER BY table_schema, row_count DESC NULLS LAST"
    )
    return _safe(sql, params)


@router.get("/preview")
def preview(schema: str, table: str, limit: int = 50):
    """GET /preview: return preview."""
    actual = _resolve_schema(schema)
    if not actual:
        return {"error": f"schema {schema} not allowed"}
    if not (_IDENT.match(schema) and _IDENT.match(table)):
        return {"error": "invalid identifier"}
    limit = max(1, min(int(limit), 200))
    return _safe(f"SELECT * FROM {DATABASE}.{actual}.{table.upper()} LIMIT {limit}")
