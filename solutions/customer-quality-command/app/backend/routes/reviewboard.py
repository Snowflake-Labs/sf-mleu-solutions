"""Quality Review Board — 3-agent adversarial debate (see boardroom.py).

A debate takes ~2 minutes on the larger models, longer than the SPCS ingress will
reliably hold one streaming response open. So each debate runs in its own thread
and event loop, independent of any HTTP request, and the client polls for events:

  POST /debate/start               -> {run_id}
  GET  /debate/{run_id}/events     -> {events, next, done}   (incremental)
  GET  /debate/{run_id}/result     -> {brief, finals, done}

/debate/stream is kept for local/SSE use and reads from the same run registry.
"""

import asyncio
import json
import logging
import threading
import time
import uuid
from collections import OrderedDict

import config
from boardroom import DebateRequest, ReviewBoardOrchestrator
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/reviewboard", tags=["reviewboard"])

# In-memory run registry (single-container service). Oldest runs are evicted.
MAX_RUNS = 25
RUNS: "OrderedDict[str, dict]" = OrderedDict()
_LOCK = threading.Lock()


def _start_run(req: DebateRequest) -> str:
    run_id = uuid.uuid4().hex
    run = {
        "started": time.time(),
        "done": False,
        "brief": None,
        "finals": {},
        "error": None,
        "events": [{"type": "run", "run_id": run_id}],
    }
    with _LOCK:
        RUNS[run_id] = run
        while len(RUNS) > MAX_RUNS:
            RUNS.popitem(last=False)

    async def consume():
        """Consume."""
        orch = ReviewBoardOrchestrator(req.question, req.issue_id)
        async for event in orch.run_debate():
            t = event.get("type")
            if t == "brief":
                run["brief"] = event.get("text")
            elif t == "final":
                run["finals"][event.get("agent")] = event.get("data")
            run["events"].append(event)

    def worker():
        """Worker."""
        try:
            asyncio.run(consume())
        except Exception as e:
            logger.exception("reviewboard debate failed")
            run["error"] = str(e)
            run["events"].append({"type": "error", "message": str(e)})
        finally:
            run["done"] = True

    threading.Thread(target=worker, name=f"reviewboard-{run_id[:8]}", daemon=True).start()
    return run_id


def _get_run(run_id: str) -> dict:
    run = RUNS.get(run_id)
    if run is None:
        raise HTTPException(status_code=404, detail="unknown or expired run")
    return run


@router.post("/debate/start")
async def debate_start(req: DebateRequest):
    """POST /debate/start: handle debate start."""
    return {"run_id": _start_run(req)}


@router.get("/debate/{run_id}/events")
async def debate_events(run_id: str, after: int = 0):
    """GET /debate/{run_id}/events: return debate events."""
    run = _get_run(run_id)
    done = run["done"]  # read before slicing so no trailing events are missed
    events = run["events"][after:]
    return {"run_id": run_id, "events": events, "next": after + len(events), "done": done}


@router.get("/debate/{run_id}/result")
async def debate_result(run_id: str):
    """GET /debate/{run_id}/result: return debate result."""
    run = _get_run(run_id)
    return {
        "run_id": run_id,
        "done": run["done"],
        "brief": run["brief"],
        "finals": run["finals"],
        "error": run["error"],
        "elapsed_s": round(time.time() - run["started"], 1),
    }


@router.post("/debate/stream")
async def debate_stream(req: DebateRequest, raw_request: Request):
    """POST /debate/stream: handle debate stream."""
    if config.IS_SPCS:
        # The SPCS ingress drops long streams before the brief arrives. Only a stale,
        # cached frontend still calls this route there — tell it to reload.
        stale = {
            "type": "error",
            "message": "This page is out of date. Reload the page (Cmd+Shift+R) and convene the board again.",
        }
        return StreamingResponse(iter([f"data: {json.dumps(stale)}\n\n"]), media_type="text/event-stream")
    run_id = _start_run(req)
    run = RUNS[run_id]

    async def event_generator():
        """Event generator."""
        sent, last_beat = 0, time.time()
        while True:
            done = run["done"]
            events = run["events"][sent:]
            for ev in events:
                yield f"data: {json.dumps(ev, default=str)}\n\n"
            sent += len(events)
            if done and sent >= len(run["events"]):
                break
            if await raw_request.is_disconnected():
                break  # the run continues; the client can recover via /result
            if time.time() - last_beat > 15:
                yield ": keepalive\n\n"
                last_beat = time.time()
            await asyncio.sleep(0.5)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
