"""Task 8 - CLI harness to verify the voice service over WebSocket.

Two modes (no microphone required):

  text  : send {"type":"text_turn"} turns, save each returned TTS utterance to WAV,
          and print transcripts/answers. Exercises session -> agent -> formatter ->
          TTS end-to-end and verifies multi-turn context carry.

  wav   : stream a 16 kHz mono WAV as PCM frames so the server VAD/STT path runs,
          then save the spoken answer.

Usage:
    python -m voice.client.cli_client --url ws://localhost:8080/voice/cli \
        --text "What is the pipeline for Cascade Partners?" \
        --text "What products are they evaluating?"

    python -m voice.client.cli_client --url ws://localhost:8080/voice/cli \
        --wav turn1.wav --wav turn2.wav

Requires: websockets (in voice/requirements.txt). Audio in/out is raw int16 PCM;
outputs are written as WAV using the sample_rate announced by the server.
"""

from __future__ import annotations

import argparse
import asyncio
import audioop
import json
import wave

import websockets

FRAME_BYTES = 4096  # PCM bytes per send (streaming granularity)
SR_IN = 16000


def _read_wav_as_pcm16_mono_16k(path: str) -> bytes:
    with wave.open(path, "rb") as w:
        n, width, ch, rate = w.getnframes(), w.getsampwidth(), w.getnchannels(), w.getframerate()
        pcm = w.readframes(n)
    if width != 2:
        pcm = audioop.lin2lin(pcm, width, 2)
        width = 2
    if ch == 2:
        pcm = audioop.tomono(pcm, width, 0.5, 0.5)
    if rate != SR_IN:
        pcm, _ = audioop.ratecv(pcm, width, 1, rate, SR_IN, None)
    return pcm


def _write_wav(path: str, pcm: bytes, sample_rate: int) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(pcm)


async def _collect_reply(ws) -> tuple[bytes, int]:
    """Read messages until an utterance completes; return (pcm, sample_rate).

    Handles: transcript/answer (printed), audio_start (rate), binary audio chunks,
    audio_end (utterance boundary), state (back to listening ends the turn).
    """
    audio = bytearray()
    sr = 22050
    got_answer = False
    while True:
        msg = await ws.recv()
        if isinstance(msg, bytes | bytearray):
            audio.extend(msg)
            continue
        evt = json.loads(msg)
        t = evt.get("type")
        if t == "transcript":
            print(f"  heard:  {evt.get('text', '')!r}")
        elif t == "answer":
            print(f"  answer: {evt.get('text', '')}")
            got_answer = True
        elif t == "audio_start":
            sr = evt.get("sample_rate", sr)
        elif t == "audio_end":
            # An utterance finished. A filler may precede the real answer, so only
            # return once we've seen the answer text (or on a lone utterance).
            if got_answer:
                return bytes(audio), sr
        elif t == "state" and evt.get("state") == "listening" and got_answer:
            return bytes(audio), sr


async def run(url: str, text_turns: list[str], wav_turns: list[str]) -> None:
    """Run."""
    async with websockets.connect(url, max_size=None) as ws:
        print(f"connected: {url}")
        idx = 0

        for turn in text_turns:
            print(f"\n=== text turn {idx + 1} ===\n  send:   {turn!r}")
            await ws.send(json.dumps({"type": "text_turn", "text": turn}))
            pcm, sr = await _collect_reply(ws)
            out = f"reply_{idx + 1}.wav"
            _write_wav(out, pcm, sr)
            print(f"  audio:  {len(pcm)} bytes @ {sr}Hz -> {out}")
            idx += 1

        for path in wav_turns:
            print(f"\n=== wav turn {idx + 1} ({path}) ===")
            pcm_in = _read_wav_as_pcm16_mono_16k(path)
            for off in range(0, len(pcm_in), FRAME_BYTES):
                await ws.send(pcm_in[off : off + FRAME_BYTES])
                await asyncio.sleep(0.01)  # pace like real-time-ish streaming
            pcm, sr = await _collect_reply(ws)
            out = f"reply_{idx + 1}.wav"
            _write_wav(out, pcm, sr)
            print(f"  audio:  {len(pcm)} bytes @ {sr}Hz -> {out}")
            idx += 1

        print("\ndone.")


def main() -> None:
    """Main."""
    ap = argparse.ArgumentParser(description="FieldIQ Voice WebSocket test client")
    ap.add_argument("--url", default="ws://localhost:8080/voice/cli")
    ap.add_argument("--text", action="append", default=[], help="text turn (repeatable)")
    ap.add_argument("--wav", action="append", default=[], help="16k mono WAV turn (repeatable)")
    args = ap.parse_args()
    if not args.text and not args.wav:
        args.text = [
            "What is the total open pipeline for Cascade Partners?",
            "What products are they evaluating?",
        ]
    asyncio.run(run(args.url, args.text, args.wav))


if __name__ == "__main__":
    main()
