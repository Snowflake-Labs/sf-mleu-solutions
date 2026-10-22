"""Ask CQC — Cortex Agent SSE endpoint. See doc 6."""

import json
import logging

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from services.cortex_agent_client import get_cortex_agent_client

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/agent", tags=["agent"])


class ChatMessage(BaseModel):
    """Request body: chat message."""

    role: str
    content: str


class ChatRequest(BaseModel):
    """Request body: chat request."""

    message: str
    history: list[ChatMessage] | None = None
    persona: str | None = None


@router.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    """POST /chat/stream: handle chat stream."""
    client = get_cortex_agent_client()
    history = [{"role": m.role, "content": m.content} for m in (req.history or [])]
    message = req.message
    if req.persona:
        message = f"[persona={req.persona}] {message}"

    async def event_gen():
        """Event gen."""
        try:
            async for event in client.run_agent(message, history):
                yield f"data: {json.dumps(event)}\n\n"
        except Exception as e:
            logger.error(f"Ask CQC stream error: {e}", exc_info=True)
            yield f"data: {json.dumps({'type': 'error', 'content': str(e)})}\n\n"

    return StreamingResponse(
        event_gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
