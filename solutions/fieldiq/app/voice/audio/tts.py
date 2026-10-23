"""Task 6 - Text-to-speech, dual-mode.

- FAST (Piper, MIT): low time-to-first-byte, CPU-capable. Default for live turns.
- QUALITY (MOSS-TTSD, OpenMOSS): richer conversational speech on GPU, used where
  the latency budget allows. (Verify streaming support + license before enabling.)

`stream(text)` yields raw int16 PCM chunks at `self.sample_rate` so the transport
can start playback before synthesis finishes.

Model libs are imported lazily so the package imports without TTS deps installed.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from enum import Enum

logger = logging.getLogger(__name__)


class TTSMode(str, Enum):  # noqa: UP042
    """Text-to-speech engine: fast (Piper) or quality."""

    FAST = "fast"  # Piper
    QUALITY = "quality"  # MOSS-TTSD


class Synthesizer:
    """Synthesizer."""

    def __init__(
        self,
        *,
        mode: TTSMode = TTSMode.FAST,
        piper_model_path: str | None = None,
        piper_config_path: str | None = None,
        moss_model_path: str | None = None,
    ) -> None:
        self.mode = TTSMode(mode)
        self.piper_model_path = piper_model_path
        self.piper_config_path = piper_config_path
        self.moss_model_path = moss_model_path

        self._piper = None
        self._moss = None
        self.sample_rate = 22050  # updated on load based on the active voice

    # ---- loading -------------------------------------------------------------
    def load(self) -> None:
        """Warm-load the active mode's model (call once at startup)."""
        if self.mode == TTSMode.FAST:
            self._load_piper()
        else:
            self._load_moss()

    def _load_piper(self) -> None:
        if self._piper is not None:
            return
        if not self.piper_model_path:
            raise RuntimeError("piper_model_path is required for FAST/Piper mode")
        from piper.voice import PiperVoice

        self._piper = PiperVoice.load(self.piper_model_path, config_path=self.piper_config_path)
        try:
            self.sample_rate = int(self._piper.config.sample_rate)
        except Exception:
            self.sample_rate = 22050
        logger.info("Piper voice loaded (sr=%d)", self.sample_rate)

    def _load_moss(self) -> None:
        if self._moss is not None:
            return
        # TODO(Task 6/quality): load MOSS-TTSD weights + processor. Confirm the
        # package exposes chunked/streaming synthesis; otherwise QUALITY mode is
        # batch-only and should be gated behind the latency budget.
        raise NotImplementedError(
            "MOSS-TTSD quality mode not yet wired. Verify streaming API + license, "
            "then implement _load_moss and _stream_moss. FAST/Piper is the default."
        )

    # ---- synthesis -----------------------------------------------------------
    async def stream(self, text: str) -> AsyncIterator[bytes]:
        """Yield int16 PCM audio chunks for `text` at `self.sample_rate`."""
        text = (text or "").strip()
        if not text:
            return
        if self.mode == TTSMode.FAST:
            for chunk in self._stream_piper(text):
                yield chunk
        else:
            async for chunk in self._stream_moss(text):
                yield chunk

    def _stream_piper(self, text: str):
        self._load_piper()
        # piper-tts >=1.3: synthesize() yields AudioChunk objects. Each carries
        # raw int16 PCM (audio_int16_bytes) at chunk.sample_rate.
        for chunk in self._piper.synthesize(text):
            self.sample_rate = int(chunk.sample_rate)
            yield chunk.audio_int16_bytes

    async def _stream_moss(self, text: str) -> AsyncIterator[bytes]:
        self._load_moss()  # raises NotImplementedError until wired
        yield b""  # pragma: no cover
