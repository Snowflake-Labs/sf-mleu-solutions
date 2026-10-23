"""Task 4 - Voice Activity Detection (Silero VAD, MIT).

Streaming turn-taking over 16 kHz mono PCM (int16):
- Feed inbound audio; emit an end-of-turn signal after ~`silence_ms` of trailing
  silence *following* detected speech.
- Expose per-frame speech detection for barge-in (speech while assistant talks).

Silero expects fixed-size windows: 512 samples at 16 kHz (256 at 8 kHz). `push`
accepts arbitrary-length PCM and internally slices it into those windows.

torch/silero are imported lazily so the module (and the rest of the voice package)
can be imported on machines without the GPU/model deps installed.
"""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

_WINDOW = {16000: 512, 8000: 256}
_BYTES_PER_SAMPLE = 2  # int16


class VADetector:
    """Vadetector."""

    def __init__(
        self,
        *,
        sample_rate: int = 16000,
        silence_ms: int = 700,
        threshold: float = 0.5,
        min_speech_ms: int = 200,
    ) -> None:
        if sample_rate not in _WINDOW:
            raise ValueError(f"sample_rate must be one of {list(_WINDOW)}")
        self.sample_rate = sample_rate
        self.silence_ms = silence_ms
        self.threshold = threshold
        self.min_speech_ms = min_speech_ms

        self._window = _WINDOW[sample_rate]
        self._window_ms = 1000.0 * self._window / sample_rate

        self._model = None
        self._torch = None
        self._np = None

        # Streaming state
        self._buf = bytearray()  # leftover PCM not yet a full window
        self._turn_audio = bytearray()  # audio accumulated for the current turn
        self._speech_ms = 0.0  # total speech seen this turn
        self._trailing_silence_ms = 0.0  # silence since last speech
        self._speech_started = False

    def _load(self) -> None:
        if self._model is not None:
            return
        import numpy as np
        import torch
        from silero_vad import load_silero_vad

        self._np = np
        self._torch = torch
        self._model = load_silero_vad()
        logger.info("Silero VAD loaded (sr=%d, window=%d)", self.sample_rate, self._window)

    def _prob(self, window_bytes: bytes) -> float:
        """Speech probability for one fixed-size window of int16 PCM."""
        self._load()
        np, torch = self._np, self._torch
        pcm = np.frombuffer(window_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        with torch.no_grad():
            return float(self._model(torch.from_numpy(pcm), self.sample_rate).item())

    def is_speech(self, frame: bytes) -> bool:
        """True if any full window in `frame` is speech (used for barge-in)."""
        wb = self._window * _BYTES_PER_SAMPLE
        for off in range(0, len(frame) - wb + 1, wb):
            if self._prob(frame[off : off + wb]) >= self.threshold:
                return True
        return False

    def push(self, frame: bytes) -> bool:
        """Feed PCM; return True once end-of-turn is detected.

        Accumulates the turn's audio in `self._turn_audio`; call `take_turn_audio()`
        after a True to retrieve it and reset for the next turn.
        """
        self._buf.extend(frame)
        wb = self._window * _BYTES_PER_SAMPLE

        end_of_turn = False
        while len(self._buf) >= wb:
            window = bytes(self._buf[:wb])
            del self._buf[:wb]
            self._turn_audio.extend(window)

            if self._prob(window) >= self.threshold:
                self._speech_started = True
                self._speech_ms += self._window_ms
                self._trailing_silence_ms = 0.0
            elif self._speech_started:
                self._trailing_silence_ms += self._window_ms

            if (
                self._speech_started
                and self._speech_ms >= self.min_speech_ms
                and self._trailing_silence_ms >= self.silence_ms
            ):
                end_of_turn = True
                break

        return end_of_turn

    def take_turn_audio(self) -> bytes:
        """Return the accumulated turn audio and reset streaming state."""
        audio = bytes(self._turn_audio)
        self.reset()
        return audio

    def flush(self) -> bytes:
        """Force end-of-turn and return the turn audio.

        Folds any leftover partial-window PCM into the turn audio and resets state. Used for push-to-talk release, where
        no trailing silence is streamed to trigger `push`.
        """
        if self._buf:
            self._turn_audio.extend(self._buf)
        return self.take_turn_audio()

    def reset(self) -> None:
        """Reset."""
        self._buf.clear()
        self._turn_audio.clear()
        self._speech_ms = 0.0
        self._trailing_silence_ms = 0.0
        self._speech_started = False
