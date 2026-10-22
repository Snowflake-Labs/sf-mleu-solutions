"""Cortex Agent REST API Client for CQC (Acme Industrial Customer Quality).

Calls the Snowflake Cortex Agents REST API and streams responses (thinking steps,
status, executed SQL, result data, chart specs, and answer text) back to the
frontend via SSE.

Works in BOTH local dev (token from snowflake-connector session) and SPCS
(OAuth token file). Agent: {DATABASE}.{SCHEMA}.CUSTOMER_QUALITY_AGENT.

API: POST /api/v2/databases/{db}/schemas/{schema}/agents/{name}:run
"""

import json
import logging
import os
from collections.abc import AsyncGenerator
from typing import Any

import httpx
import snowflake.connector

logger = logging.getLogger(__name__)


def _detect_spcs() -> bool:
    if os.path.exists("/snowflake/session/token"):
        return True
    if os.environ.get("SNOWFLAKE_HOST"):
        return True
    return False


IS_SPCS = _detect_spcs()


class CortexAgentClient:
    """Client for the Snowflake Cortex Agents REST API (streaming)."""

    def __init__(self):
        self.database = os.environ.get("SNOWFLAKE_DATABASE", "CUSTOMER_QUALITY_DB")
        self.schema = os.environ.get("CORTEX_AGENT_SCHEMA", "ML")
        self.agent_name = os.environ.get("CORTEX_AGENT_NAME", "CUSTOMER_QUALITY_AGENT")
        self.connection_name = os.environ.get("SNOWFLAKE_CONNECTION_NAME", "my_snowflake")
        self._conn = None
        self._host = None
        self.is_spcs = IS_SPCS
        if self.is_spcs:
            self._host = os.environ.get("SNOWFLAKE_HOST", "")
        logger.info(
            f"CortexAgentClient init: db={self.database}, schema={self.schema}, "
            f"agent={self.agent_name}, spcs={self.is_spcs}"
        )

    def _get_connection(self):
        if self._conn is None:
            if self.is_spcs:
                return None
            self._conn = snowflake.connector.connect(connection_name=self.connection_name)
            raw_host = self._conn.host or self._conn.rest._host
            self._host = raw_host.replace("_", "-")
            logger.info(f"Connected to Snowflake host: {self._host}")
        return self._conn

    def _get_token(self) -> str:
        token_path = "/snowflake/session/token"
        if os.path.exists(token_path):
            with open(token_path) as f:
                return f.read().strip()
        conn = self._get_connection()
        if conn:
            return conn.rest.token
        raise RuntimeError("No Snowflake token available")

    def _get_base_url(self) -> str:
        if not self._host:
            if self.is_spcs:
                self._host = os.environ.get("SNOWFLAKE_HOST", "")
            else:
                self._get_connection()
        return f"https://{self._host}"

    def _get_agent_url(self) -> str:
        base = self._get_base_url()
        return f"{base}/api/v2/databases/{self.database}/schemas/{self.schema}/agents/{self.agent_name}:run"

    def _format_messages_for_api(self, messages: list[dict[str, str]]) -> list[dict[str, Any]]:
        formatted = []
        for msg in messages:
            content = msg.get("content")
            if isinstance(content, list):
                formatted.append({"role": msg["role"], "content": content})
            else:
                formatted.append(
                    {
                        "role": msg["role"],
                        "content": [{"type": "text", "text": content}],
                    }
                )
        return formatted

    async def run_agent_stream(
        self,
        messages: list[dict[str, str]],
        conversation_id: str | None = None,
    ) -> AsyncGenerator[dict[str, Any], None]:
        """Run agent stream."""
        self._text_channel = None
        try:
            token = self._get_token()
            url = self._get_agent_url()

            if self.is_spcs:
                headers = {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream",
                    "X-Snowflake-Authorization-Token-Type": "OAUTH",
                }
            else:
                headers = {
                    "Authorization": f'Snowflake Token="{token}"',
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream",
                }

            body = {
                "messages": self._format_messages_for_api(messages),
                "stream": True,
            }

            logger.info(f"Calling Cortex Agent: {url}")

            async with httpx.AsyncClient(timeout=180.0) as client:
                async with client.stream("POST", url, headers=headers, json=body) as response:
                    if response.status_code != 200:
                        error_text = await response.aread()
                        logger.error(f"Agent API error: {response.status_code} - {error_text}")
                        yield {
                            "type": "error",
                            "content": f"Agent API error: {response.status_code}",
                            "details": error_text.decode() if error_text else "",
                        }
                        return

                    buffer = ""
                    async for chunk in response.aiter_text():
                        buffer += chunk
                        while "\n\n" in buffer:
                            event_str, buffer = buffer.split("\n\n", 1)
                            event = self._parse_sse_event(event_str)
                            if event:
                                yield event
                    if buffer.strip():
                        event = self._parse_sse_event(buffer)
                        if event:
                            yield event

            yield {"type": "done"}

        except Exception as e:
            logger.error(f"Cortex Agent stream error: {e}", exc_info=True)
            yield {"type": "error", "content": str(e)}

    def _accept_text_channel(self, channel: str) -> bool:
        """Return whether text from this delta channel should be emitted.

        Cortex Agents may stream the answer on both `response.text.delta` and
        `response.content.delta`. Lock onto whichever channel emits text first for a
        given stream and ignore the other to avoid duplicated / interleaved output.
        """
        current = getattr(self, "_text_channel", None)
        if current is None:
            self._text_channel = channel
            return True
        return current == channel

    def _parse_sse_event(self, event_str: str) -> dict[str, Any] | None:
        try:
            lines = event_str.strip().split("\n")
            event_type = None
            data = None
            for line in lines:
                if line.startswith("event:"):
                    event_type = line[6:].strip()
                elif line.startswith("data:"):
                    data_str = line[5:].strip()
                    if data_str == "[DONE]":
                        return {"type": "done"}
                    try:
                        data = json.loads(data_str)
                    except json.JSONDecodeError:
                        data = {"raw": data_str}

            if data is None:
                return None
            if not isinstance(data, dict):
                return {"type": "text", "content": str(data)}

            if event_type in ("response.output_text.delta", "response.text.delta"):
                text = data.get("text", "")
                if not text or not self._accept_text_channel("text"):
                    return None
                return {"type": "text", "content": text}

            elif event_type == "response.thinking.delta":
                text = data.get("text", "")
                return {"type": "thinking", "title": "Reasoning", "content": text} if text else None

            elif event_type == "response.status":
                status = data.get("status", "")
                message = data.get("message", "")
                status_titles = {
                    "planning": "Planning analysis approach",
                    "reasoning_agent_start": "Starting analysis",
                    "reasoning_agent_stop": "Analysis complete",
                    "reevaluating_plan": "Refining approach",
                    "streaming_analyst_results": "Running SQL query",
                    "executing_sql": "Executing SQL",
                    "searching": "Searching knowledge base",
                }
                title = status_titles.get(status, message or status)
                return {"type": "status", "title": title, "status": status} if title else None

            elif event_type == "response.tool_result.status":
                status = data.get("status", "")
                message = data.get("message", "")
                return {"type": "tool_status", "title": message or status, "status": status}

            elif event_type == "response.tool_result":
                content = data.get("content", [])
                result = {"type": "tool_result"}
                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict):
                            if "json" in item:
                                jd = item["json"]
                                if "sql" in jd:
                                    result["sql"] = jd["sql"]
                                if "error" in jd:
                                    err = jd["error"]
                                    result["error"] = (
                                        err.get("message", str(err)) if isinstance(err, dict) else str(err)
                                    )
                                if "data" in jd:
                                    result["data"] = jd["data"]
                                if "searchResults" in jd:
                                    result["search_results"] = jd["searchResults"]
                            if "text" in item:
                                result["content"] = item["text"]
                return result if len(result) > 1 else None

            elif event_type == "response.chart":
                chart_spec = data.get("chart_spec", {})
                if isinstance(chart_spec, str):
                    try:
                        chart_spec = json.loads(chart_spec)
                    except json.JSONDecodeError:
                        return None
                if chart_spec and isinstance(chart_spec, dict):
                    return {"type": "chart", "chart_spec": chart_spec}
                return None

            elif event_type == "response.done":
                return {"type": "done"}

            elif event_type == "error":
                # Agent-side failures arrive as an SSE error frame on an HTTP 200 stream.
                logger.error(f"Agent stream error event: {data}")
                return {"type": "error", "content": data.get("message", str(data))}

            elif event_type == "response.content.delta":
                if not self._accept_text_channel("content"):
                    return None
                text = data.get("text", "")
                if text:
                    return {"type": "text", "content": text}
                content = data.get("content", [])
                if isinstance(content, list):
                    texts = [c.get("text", "") for c in content if isinstance(c, dict)]
                    if texts:
                        return {"type": "text", "content": "".join(texts)}
                return None

            return None
        except Exception as e:
            logger.warning(f"Failed to parse SSE event: {e}")
            return None

    async def run_agent(
        self,
        message: str,
        conversation_history: list[dict[str, str]] | None = None,
    ) -> AsyncGenerator[dict[str, Any], None]:
        """Run agent."""
        messages = list(conversation_history or [])
        messages.append({"role": "user", "content": message})
        async for event in self.run_agent_stream(messages):
            yield event


_agent_client: CortexAgentClient | None = None


def get_cortex_agent_client() -> CortexAgentClient:
    """Get cortex agent client."""
    global _agent_client
    if _agent_client is None:
        _agent_client = CortexAgentClient()
    return _agent_client
