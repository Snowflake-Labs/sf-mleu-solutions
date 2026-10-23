"""Live multi-turn integration check for the voice conversation engine.

Hits the REAL FIELDIQ_AGENT (not mocked) to validate the end-to-end logic loop:
transcript(text) -> session -> agent_bridge -> Cortex Agent -> formatter -> speakable.

Run:
    SNOWFLAKE_CONNECTION_NAME=my_snowflake PYTHONPATH=. \
        python3.11 voice/client/live_smoke.py

This is a manual smoke test (network + Snowflake), not part of unit tests.
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # app/

os.environ.setdefault("SNOWFLAKE_CONNECTION_NAME", "my_snowflake")

from voice.conversation.session import VoiceSession  # noqa: E402

TURNS = [
    "What is the total open pipeline for Cascade Partners?",
    "What products are they evaluating?",
    "Draft a short follow-up email to their main contact about that.",
]


async def main() -> None:
    """Main."""
    s = VoiceSession(session_id="smoke")
    for i, turn in enumerate(TURNS, 1):
        print(f"\n=== TURN {i} ===")
        print(f"REP:       {turn}")
        answer = await s.handle_utterance(turn, max_sentences=3)
        print(f"FIELDIQ: {answer}")
    print(f"\nHistory messages: {len(s.history)} (expect {len(TURNS) * 2})")


if __name__ == "__main__":
    asyncio.run(main())
