"""Task 5 - Speech-to-text (faster-whisper, MIT).

Transcribes a turn's 16 kHz mono int16 PCM to text on GPU. `transcribe_turn` is the
primary call (invoked when VAD signals end-of-turn). `transcribe_partial` supports
optional early/partial transcripts for responsiveness.

faster-whisper is imported lazily so the package imports without CUDA/model deps.
"""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


class Transcriber:
    """Transcriber."""

    def __init__(
        self,
        *,
        model_size: str = "large-v3",
        device: str = "cuda",
        compute_type: str = "float16",
        language: str = "en",
        beam_size: int = 1,
        sample_rate: int = 16000,
    ) -> None:
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self.language = language
        self.beam_size = beam_size
        self.sample_rate = sample_rate

        self._model = None
        self._np = None

    def load(self) -> None:
        """Warm-load the model (call once at service startup)."""
        if self._model is not None:
            return
        import numpy as np
        from faster_whisper import WhisperModel

        self._np = np
        self._model = WhisperModel(self.model_size, device=self.device, compute_type=self.compute_type)
        logger.info(
            "faster-whisper loaded (model=%s, device=%s, compute=%s)",
            self.model_size,
            self.device,
            self.compute_type,
        )

    def _pcm_to_float(self, pcm_audio: bytes):
        np = self._np
        return np.frombuffer(pcm_audio, dtype=np.int16).astype(np.float32) / 32768.0

    def _decode(self, pcm_audio: bytes) -> str:
        self.load()
        if not pcm_audio:
            return ""
        audio = self._pcm_to_float(pcm_audio)
        segments, _info = self._model.transcribe(
            audio,
            language=self.language,
            beam_size=self.beam_size,
            vad_filter=False,  # our VAD already gates turns
        )
        return " ".join(seg.text.strip() for seg in segments).strip()

    def transcribe_turn(self, pcm_audio: bytes) -> str:
        """Transcribe a complete turn's audio to final text."""
        return self._decode(pcm_audio)

    def transcribe_partial(self, pcm_audio: bytes) -> str:
        """Best-effort partial transcript for the audio so far."""
        return self._decode(pcm_audio)
