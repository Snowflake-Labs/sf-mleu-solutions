"""Shared DB query helpers for CQC routes."""

import datetime
import decimal

from config import DATABASE, WAREHOUSE, get_connection
from snowflake.connector import DictCursor


def _serialize(v):
    if isinstance(v, datetime.date | datetime.datetime):
        return v.isoformat()
    if isinstance(v, decimal.Decimal):
        return float(v)
    return v


def run_query(sql: str, params=None) -> list:
    """Execute a SELECT and return a list of JSON-serializable dict rows."""
    conn = get_connection()
    try:
        cur = conn.cursor(DictCursor)
        cur.execute(f"USE DATABASE {DATABASE}")
        cur.execute(f"USE WAREHOUSE {WAREHOUSE}")
        cur.execute(sql, params) if params else cur.execute(sql)
        rows = cur.fetchall()
        cur.close()
        return [{k: _serialize(v) for k, v in row.items()} for row in rows]
    finally:
        conn.close()


def call_proc(sql: str, params=None):
    """Execute a stored-procedure CALL / DML statement and return the first row."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(f"USE DATABASE {DATABASE}")
        cur.execute(f"USE WAREHOUSE {WAREHOUSE}")
        cur.execute(sql, params) if params else cur.execute(sql)
        result = cur.fetchone()
        cur.close()
        return result
    finally:
        conn.close()
