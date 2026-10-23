"""GPU audio I/O layer (runs on SPCS GPU_NV_S / A10G).

- vad.py   Silero VAD: end-of-turn detection + barge-in  (Task 4)
- stt.py   faster-whisper streaming transcription        (Task 5)
- tts.py   Piper (fast) + MOSS-TTSD (quality) dual-mode   (Task 6)

All three operate on raw PCM audio frames streamed over the WebSocket. Models are
warm-loaded once at service start (see server/ws_service.py).
"""
