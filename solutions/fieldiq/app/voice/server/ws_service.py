"""Task 3 - FastAPI WebSocket voice service.

Wires the full Phase 1 loop over a WebSocket carrying 16 kHz mono int16 PCM:

    client (mic PCM) --WS binary--> service
        VAD.push(frame) -> end-of-turn?
            take turn audio -> STT.transcribe_turn -> text
            emit filler audio immediately (latency mask, Task 7)
            VoiceSession.handle_utterance(text) -> speakable answer
            TTS.stream(answer) -> PCM chunks --WS binary--> client (speaker)
        (barge-in) inbound speech during SPEAKING -> cancel + new turn

Control messages (JSON text frames) are also sent to the client for UX:
    {"type":"state","state":"listening|thinking|speaking"}
    {"type":"transcript","text": "..."}         # what we heard
    {"type":"answer","text": "..."}              # what we're speaking
    {"type":"audio_end"}                          # end of a TTS utterance

Models (VAD/STT/TTS) are warm-loaded once at startup. On SPCS this runs on a
GPU_NV_S compute pool; the Cortex Agent OAuth token is read from config.sf_token_path.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse

from ..audio.stt import Transcriber
from ..audio.tts import Synthesizer, TTSMode
from ..audio.vad import VADetector
from ..conversation.prompts import pick_filler
from ..conversation.session import SessionManager, TurnState
from .config import config

logger = logging.getLogger(__name__)

app = FastAPI(title="FieldIQ Voice Service")

_CLIENT_HTML = Path(__file__).resolve().parent.parent / "client" / "ws_test_client.html"

# Shared singletons (models loaded once; sessions are per-connection).
_stt = Transcriber(model_size=config.whisper_model, device=config.device, sample_rate=config.sample_rate)
_tts = Synthesizer(
    mode=TTSMode(config.tts_mode), piper_model_path=config.piper_model, piper_config_path=config.piper_config
)
_sessions = SessionManager()
_ready = {"stt": False, "tts": False}


@app.on_event("startup")
async def _warm_load() -> None:
    """Warm-load models so the first call isn't slow. Non-fatal if unavailable."""
    try:
        _stt.load()
        _ready["stt"] = True
    except Exception as e:  # pragma: no cover - depends on GPU env
        logger.warning("STT warm-load deferred: %s", e)
    try:
        _tts.load()
        _ready["tts"] = True
    except Exception as e:  # pragma: no cover
        logger.warning("TTS warm-load deferred: %s", e)


@app.get("/", response_class=HTMLResponse)
async def client_page() -> HTMLResponse:
    """Serve the browser mic client from the service itself.

    Loading the page from the (OAuth-protected) SPCS ingress means the browser
    holds the Snowflake session cookie, so the same-origin WebSocket upgrade to
    /voice/{id} is authenticated automatically — no token juggling required.
    """
    try:
        return HTMLResponse(_CLIENT_HTML.read_text(encoding="utf-8"))
    except FileNotFoundError:  # pragma: no cover
        return HTMLResponse("<h1>voice client not bundled</h1>", status_code=404)


@app.get("/health")
async def health() -> dict:
    """GET /health: return health."""
    return {
        "status": "ok",
        "models": _ready,
        "active_sessions": _sessions.active_count(),
        "tts_mode": _tts.mode.value,
        "whisper_model": _stt.model_size,
    }


async def _send_json(ws: WebSocket, payload: dict) -> None:
    await ws.send_text(json.dumps(payload))


async def _speak(ws: WebSocket, text: str) -> None:
    """Stream synthesized audio for `text` to the client as binary frames."""
    if not text:
        return
    # Announce format so the client can play the raw int16 PCM correctly.
    await _send_json(ws, {"type": "audio_start", "sample_rate": _tts.sample_rate})
    async for chunk in _tts.stream(text):
        if chunk:
            await ws.send_bytes(chunk)
    await _send_json(ws, {"type": "audio_end"})


async def _run_turn(ws: WebSocket, session, turn_audio: bytes, tctx: dict) -> None:
    """STT -> (filler while agent runs) -> agent answer -> TTS, for one turn."""
    await _send_json(ws, {"type": "state", "state": TurnState.THINKING.value})

    text = _stt.transcribe_turn(turn_audio)
    await _send_json(ws, {"type": "transcript", "text": text})
    if not text.strip():
        await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})
        return

    # Latency mask: speak a filler immediately, agent answer in parallel.
    filler = pick_filler(tctx["i"])
    tctx["i"] += 1
    answer_task = asyncio.create_task(session.handle_utterance(text))
    await _speak(ws, filler)

    answer = await answer_task
    if not answer:  # barged-in / cancelled
        await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})
        return

    await _send_json(ws, {"type": "answer", "text": answer})
    await _send_json(ws, {"type": "state", "state": TurnState.SPEAKING.value})
    await _speak(ws, answer)

    session.on_speech_finished()
    await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})


@app.websocket("/voice/{session_id}")
async def voice(ws: WebSocket, session_id: str) -> None:
    """Voice."""
    await ws.accept()
    session = _sessions.get_or_create(session_id)
    vad = VADetector(sample_rate=config.sample_rate, silence_ms=config.vad_silence_ms)
    tctx = {"i": 0}  # turn counter for filler selection
    logger.info("voice session connected: %s", session_id)

    await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})

    try:
        while True:
            msg = await ws.receive()

            # Client can close or send control text; we mainly expect binary PCM.
            if msg.get("type") == "websocket.disconnect":
                break

            data = msg.get("bytes")
            if data is None:
                # Optional JSON control from client (e.g. explicit end/reset).
                txt = msg.get("text")
                if txt:
                    await _handle_control(ws, session, vad, txt, tctx)
                continue

            # Barge-in: if we're speaking and the rep starts talking, cancel.
            if session.state == TurnState.SPEAKING and vad.is_speech(data):
                session.on_barge_in()
                await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})

            if not vad.push(data):
                continue

            # --- End of turn detected (VAD silence) ---
            await _run_turn(ws, session, vad.take_turn_audio(), tctx)

    except WebSocketDisconnect:
        pass
    finally:
        _sessions.end(session_id)
        logger.info("voice session closed: %s", session_id)


async def _handle_control(ws: WebSocket, session, vad: VADetector, txt: str, tctx: dict) -> None:
    """Handle optional JSON control frames from the client."""
    try:
        ctrl = json.loads(txt)
    except json.JSONDecodeError:
        return
    kind = ctrl.get("type")
    if kind == "reset":
        vad.reset()
        await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})
    elif kind == "end_turn":
        # Push-to-talk release: no trailing silence is streamed, so flush the
        # buffered mic audio and process it as a turn.
        audio = vad.flush()
        if audio:
            await _run_turn(ws, session, audio, tctx)
        else:
            await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})
    elif kind == "text_turn":
        # Text-only turn (useful for the browser test client without a mic).
        text = (ctrl.get("text") or "").strip()
        if text:
            await _send_json(ws, {"type": "transcript", "text": text})
            answer = await session.handle_utterance(text)
            await _send_json(ws, {"type": "answer", "text": answer})
            await _speak(ws, answer)
            session.on_speech_finished()
            await _send_json(ws, {"type": "state", "state": TurnState.LISTENING.value})
