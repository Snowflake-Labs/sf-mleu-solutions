"""FieldIQ Snowflake service.

Works in both modes:
- LOCAL  (dev): uses snowflake.connector with connection_name = $SNOWFLAKE_CONNECTION_NAME (default: my_snowflake)
- SPCS    (prod): uses OAuth token at /snowflake/session/token

Exposes:
- execute_query(sql, params)
- get_rest_token()  -> bearer/oauth token
- get_rest_host()   -> https host (with hyphens, valid TLS cert)
"""

from __future__ import annotations

import logging
import os
import re
from typing import Any

logger = logging.getLogger(__name__)

SPCS_TOKEN_PATH = "/snowflake/session/token"


def _is_spcs() -> bool:
    return os.path.exists(SPCS_TOKEN_PATH)


class FieldIQService:
    """Field iqservice."""

    def __init__(self):
        self.database = os.environ.get("SNOWFLAKE_DATABASE", "SF_SOLUTIONS")
        self.warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "SF_SOLUTIONS_WH")
        self.connection_name = os.environ.get("SNOWFLAKE_CONNECTION_NAME", "my_snowflake")
        self._conn = None
        self._is_spcs = _is_spcs()
        self._spcs_token: str | None = None
        self._init()

    # ------------------------------------------------------------------
    def _init(self):
        import snowflake.connector

        if self._is_spcs:
            with open(SPCS_TOKEN_PATH) as f:
                self._spcs_token = f.read().strip()
            self._conn = snowflake.connector.connect(
                host=os.environ.get("SNOWFLAKE_HOST", ""),
                account=os.environ.get("SNOWFLAKE_ACCOUNT", ""),
                authenticator="oauth",
                token=self._spcs_token,
                database=self.database,
                warehouse=self.warehouse,
            )
            logger.info(f"FieldIQService SPCS-mode init  db={self.database} wh={self.warehouse}")
        else:
            self._conn = snowflake.connector.connect(connection_name=self.connection_name)
            cs = self._conn.cursor()
            cs.execute(f"USE DATABASE {self.database}")
            cs.execute(f"USE WAREHOUSE {self.warehouse}")
            cs.close()
            logger.info(f"FieldIQService LOCAL-mode init connection={self.connection_name}")

    # ------------------------------------------------------------------
    def execute_query(self, sql: str, params: list[Any] | None = None) -> list[dict[str, Any]]:
        """Execute query."""
        cs = self._conn.cursor()
        try:
            cs.execute(sql, params or [])
            cols = [d[0] for d in cs.description] if cs.description else []
            results = []
            for row in cs.fetchall():
                d = {}
                for i, c in enumerate(cols):
                    v = row[i]
                    if hasattr(v, "isoformat"):
                        v = v.isoformat()
                    d[c] = v
                results.append(d)
            return results
        except Exception as e:
            msg = str(e)
            if "390114" in msg or ("token" in msg.lower() and "expired" in msg.lower()):
                logger.warning("Token expired, reconnecting…")
                self._init()
                return self.execute_query(sql, params)
            logger.error(f"SQL error: {msg[:200]}\n  query: {sql[:200]}")
            raise
        finally:
            try:
                cs.close()
            except Exception:
                pass

    # ------------------------------------------------------------------
    def get_rest_token(self) -> str:
        """Token for calling Snowflake REST APIs from the backend."""
        if self._is_spcs:
            with open(SPCS_TOKEN_PATH) as f:
                return f.read().strip()
        # local: use connector's session token (good for ~1h)
        return self._conn.rest.token  # type: ignore

    def get_rest_host(self) -> str:
        """Hostname (with hyphens, TLS-valid) for REST API."""
        if self._is_spcs:
            return os.environ["SNOWFLAKE_HOST"]
        # Local: derive from CURRENT_ACCOUNT() and pick org-account-host w/ hyphens
        env_host = os.environ.get("SNOWFLAKE_HOST")
        if env_host:
            return env_host
        # Convert connector's host (which may have underscores) to dashed form
        host = self._conn.host or ""  # e.g. <account>.snowflakecomputing.com
        host = re.sub(r"_", "-", host)
        return host

    def close(self):
        """Close the Snowflake connection if one is open."""
        try:
            if self._conn:
                self._conn.close()
        except Exception:
            pass


# ----- Singleton ------------------------------------------------------
_SVC: FieldIQService | None = None


def get_fieldiq_service() -> FieldIQService:
    """Get fieldiq service."""
    global _SVC
    if _SVC is None:
        _SVC = FieldIQService()
    return _SVC
