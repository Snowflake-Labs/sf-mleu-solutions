"""Thin bridge to the existing FIELDIQ_AGENT Cortex Agent.

Reuses app/backend/services/cortex_agent_client.py rather than duplicating the
REST/SSE logic. Collapses the streamed agent response into a single text string
for the voice formatter.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

# Make the existing backend package importable when running the voice service
# standalone (app/ on sys.path so `backend...` resolves).
_APP_ROOT = Path(__file__).resolve().parents[2]  # .../app
if str(_APP_ROOT) not in sys.path:
    sys.path.insert(0, str(_APP_ROOT))


def _get_client():
    """Lazy import so unit tests can run without backend deps installed."""
    from backend.services.cortex_agent_client import get_cortex_agent_client

    return get_cortex_agent_client()


async def ask_agent(
    message: str,
    history: list[dict] | None = None,
    *,
    system_prompt: str | None = None,
) -> str:
    """Send a turn to the Cortex Agent and return the full text answer.

    Args:
        message: the user's (transcribed) utterance for this turn.
        history: prior turns as [{"role","content"}] (clean, un-augmented).
        system_prompt: optional voice-mode guidance prepended for this call only.

    Returns:
        Concatenated agent output text (raw markdown; caller runs the formatter).
    """
    messages: list[dict] = []
    if system_prompt:
        # Cortex Agent messages accept user/assistant roles; deliver guidance as a
        # user-role preamble so we never rely on unsupported "system" role.
        messages.append({"role": "user", "content": system_prompt})
        messages.append({"role": "assistant", "content": "Understood. I'll keep answers brief and conversational."})
    if history:
        messages.extend(history)
    messages.append({"role": "user", "content": message})

    client = _get_client()

    chunks: list[str] = []
    error: str | None = None
    async for event in client.run_agent_stream(messages):
        etype = event.get("type")
        if etype == "text":
            chunks.append(event.get("content", ""))
        elif etype == "error":
            error = event.get("content", "agent error")
        elif etype == "done":
            break

    text = "".join(chunks).strip()
    if not text and error:
        logger.warning("agent_bridge error: %s", error)
        return ""
    return text
