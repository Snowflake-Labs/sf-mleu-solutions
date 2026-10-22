"""Central configuration for the CQC backend.

Single source of truth for Snowflake object names and dual local/SPCS auth.
Works unchanged in local dev (snowflake-connector named connection) and in SPCS
(OAuth token file). Presence of SNOWFLAKE_HOST flips the app into SPCS mode.

Defaults match a fresh reference install (CUSTOMER_QUALITY_DB, short schema names).
Deployments into an existing database with its own naming conventions override
via env vars in the SPCS service spec, e.g.:
  SNOWFLAKE_DATABASE=MY_CUSTOMER_DB
  SNOWFLAKE_WAREHOUSE=MY_WAREHOUSE
  SCHEMA_PREFIX=CQ_          -> CQ_RAW, CQ_INSIGHTS, ...
  SCHEMA_SUFFIX=_SCHEMA      -> RAW_SCHEMA, INSIGHTS_SCHEMA, ...

Brand settings (rebrand in one place; mirror app/frontend/src/config/brand.ts):
  PRODUCT_NAME, PRODUCT_SHORT, COMPANY_NAME, BUSINESS_UNIT, ANCHOR_MODEL
"""

import os

import snowflake.connector

DATABASE = os.getenv("SNOWFLAKE_DATABASE", "CUSTOMER_QUALITY_DB")
WAREHOUSE = os.getenv("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH")

_SCHEMA_PREFIX = os.getenv("SCHEMA_PREFIX", "")
_SCHEMA_SUFFIX = os.getenv("SCHEMA_SUFFIX", "")

SCHEMA_RAW = f"{_SCHEMA_PREFIX}RAW{_SCHEMA_SUFFIX}"
SCHEMA_STAGING = f"{_SCHEMA_PREFIX}STAGING{_SCHEMA_SUFFIX}"
SCHEMA_ATOMIC = f"{_SCHEMA_PREFIX}ATOMIC{_SCHEMA_SUFFIX}"
SCHEMA_FEATURE_STORE = f"{_SCHEMA_PREFIX}FEATURE_STORE{_SCHEMA_SUFFIX}"
SCHEMA_ML = f"{_SCHEMA_PREFIX}ML{_SCHEMA_SUFFIX}"
SCHEMA_ANALYTICS = f"{_SCHEMA_PREFIX}ANALYTICS{_SCHEMA_SUFFIX}"
SCHEMA_INSIGHTS = f"{_SCHEMA_PREFIX}INSIGHTS{_SCHEMA_SUFFIX}"
SCHEMA_ACTION = f"{_SCHEMA_PREFIX}ACTION{_SCHEMA_SUFFIX}"
SCHEMA_DOCS = f"{_SCHEMA_PREFIX}DOCS{_SCHEMA_SUFFIX}"

RAW = f"{DATABASE}.{SCHEMA_RAW}"
STAGING = f"{DATABASE}.{SCHEMA_STAGING}"
ATOMIC = f"{DATABASE}.{SCHEMA_ATOMIC}"
FEATURE_STORE = f"{DATABASE}.{SCHEMA_FEATURE_STORE}"
ML = f"{DATABASE}.{SCHEMA_ML}"
ANALYTICS = f"{DATABASE}.{SCHEMA_ANALYTICS}"
INSIGHTS = f"{DATABASE}.{SCHEMA_INSIGHTS}"
ACTION = f"{DATABASE}.{SCHEMA_ACTION}"
DOCS = f"{DATABASE}.{SCHEMA_DOCS}"

AGENT_NAME = os.getenv("CORTEX_AGENT_NAME", "CUSTOMER_QUALITY_AGENT")
AGENT_SCHEMA = os.getenv("CORTEX_AGENT_SCHEMA", SCHEMA_ML)
AGENT_FQN = f"{DATABASE}.{AGENT_SCHEMA}.{AGENT_NAME}"

PRODUCT_NAME = os.getenv("PRODUCT_NAME", "Customer Quality Command")
PRODUCT_SHORT = os.getenv("PRODUCT_SHORT", "CQC")
COMPANY_NAME = os.getenv("COMPANY_NAME", "Acme Industrial")
BUSINESS_UNIT = os.getenv("BUSINESS_UNIT", "Construction Equipment Division")
ANCHOR_MODEL = os.getenv("ANCHOR_MODEL", "LX-950")
ANCHOR_MACHINE = f"{ANCHOR_MODEL} Large Excavator"

IS_SPCS = os.getenv("SNOWFLAKE_HOST") is not None


def get_connection():
    """Return a Snowflake connection (SPCS OAuth token file or local named conn)."""
    snowflake_host = os.getenv("SNOWFLAKE_HOST")
    if snowflake_host:
        return snowflake.connector.connect(
            host=snowflake_host,
            account=os.getenv("SNOWFLAKE_ACCOUNT"),
            authenticator="oauth",
            token=open("/snowflake/session/token").read(),
            database=DATABASE,
            schema=SCHEMA_ML,
            warehouse=WAREHOUSE,
        )
    return snowflake.connector.connect(connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME", "my_snowflake"))
