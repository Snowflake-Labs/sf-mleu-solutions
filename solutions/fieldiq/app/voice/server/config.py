"""Runtime configuration for the voice service.

Values come from environment variables so the same image runs locally and on SPCS.
TODO: finalize as pydantic BaseSettings once implementation starts.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class VoiceConfig:
    # Transport
    """Voice config."""

    host: str = os.getenv("VOICE_HOST", "0.0.0.0")
    port: int = int(os.getenv("VOICE_PORT", "8080"))
    sample_rate: int = int(os.getenv("VOICE_SAMPLE_RATE", "16000"))

    # Models
    whisper_model: str = os.getenv("WHISPER_MODEL", "large-v3")
    tts_mode: str = os.getenv("TTS_MODE", "fast")  # fast=Piper, quality=MOSS-TTSD
    piper_model: str = os.getenv("PIPER_MODEL", "/app/models/piper/en_US-lessac-medium.onnx")
    piper_config: str = os.getenv("PIPER_CONFIG", "/app/models/piper/en_US-lessac-medium.onnx.json")
    vad_silence_ms: int = int(os.getenv("VAD_SILENCE_MS", "700"))
    device: str = os.getenv("VOICE_DEVICE", "cuda")

    # Cortex Agent (reuse existing app config)
    agent_database: str = os.getenv("AGENT_DATABASE", "SF_SOLUTIONS")
    agent_schema: str = os.getenv("AGENT_SCHEMA", "CORTEX")
    agent_name: str = os.getenv("AGENT_NAME", "FIELDIQ_AGENT")
    # On SPCS the OAuth token is auto-injected here:
    sf_token_path: str = os.getenv("SF_TOKEN_PATH", "/snowflake/session/token")


config = VoiceConfig()
