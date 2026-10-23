"""Task 2 - Conversation / session engine.

Turns stateless agent calls into a stateful, multi-turn spoken conversation.

- One VoiceSession per connection/call, keyed by a connection id.
- Maintains `history[]` in the shape the Cortex Agent expects (role/content), so
  context ("they", "that account") carries across turns.
- Tracks turn state: LISTENING -> THINKING -> SPEAKING (-> LISTENING).
- Barge-in: incoming speech during SPEAKING cancels playback, back to LISTENING.
- Rolls long histories down to a bounded window to protect the token budget.

No audio here - consumes final transcripts (str), produces speakable text (str).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from . import agent_bridge, formatter
from .prompts import VOICE_SYSTEM_PROMPT

# Keep at most this many prior turns (user+assistant messages) in the live window.
MAX_HISTORY_MESSAGES = 12


class TurnState(str, Enum):  # noqa: UP042
    """Turn state."""

    LISTENING = "listening"
    THINKING = "thinking"
    SPEAKING = "speaking"


@dataclass
class VoiceSession:
    """Per-connection conversation state."""

    session_id: str
    history: list[dict] = field(default_factory=list)
    state: TurnState = TurnState.LISTENING
    _cancelled: bool = False

    def add_user_turn(self, text: str) -> None:
        """Add user turn."""
        self.history.append({"role": "user", "content": text})
        self._trim()

    def add_assistant_turn(self, text: str) -> None:
        """Add assistant turn."""
        self.history.append({"role": "assistant", "content": text})
        self._trim()

    def _trim(self) -> None:
        if len(self.history) > MAX_HISTORY_MESSAGES:
            # Drop oldest, but keep pairs aligned by trimming from the front.
            self.history = self.history[-MAX_HISTORY_MESSAGES:]

    async def handle_utterance(self, text: str, *, max_sentences: int = 3) -> str:
        """Full turn: user text -> agent (with history) -> speakable answer.

        The user turn is added to history first so context carries. The agent is
        called with the prior history (excluding the just-added turn, which is
        passed as the current message). The assistant answer stored in history is
        the SPEAKABLE version so follow-ups stay consistent with what was said.
        """
        text = (text or "").strip()
        if not text:
            return "Sorry, I didn't catch that. Could you say it again?"

        self._cancelled = False
        self.state = TurnState.THINKING

        prior = list(self.history)  # history BEFORE this turn
        self.add_user_turn(text)

        raw = await agent_bridge.ask_agent(text, prior, system_prompt=VOICE_SYSTEM_PROMPT)

        if self._cancelled:
            # Rep barged in while we were thinking; abandon this answer.
            self.state = TurnState.LISTENING
            return ""

        speakable = formatter.to_speakable(raw, max_sentences=max_sentences)
        self.add_assistant_turn(speakable)
        self.state = TurnState.SPEAKING
        return speakable

    def on_barge_in(self) -> None:
        """Rep started speaking; cancel current turn and return to LISTENING."""
        self._cancelled = True
        self.state = TurnState.LISTENING

    def on_speech_finished(self) -> None:
        """TTS playback finished normally; ready for the next turn."""
        if self.state == TurnState.SPEAKING:
            self.state = TurnState.LISTENING


class SessionManager:
    """Creates/destroys VoiceSessions keyed by connection id."""

    def __init__(self) -> None:
        self._sessions: dict[str, VoiceSession] = {}

    def get_or_create(self, session_id: str) -> VoiceSession:
        """Get or create."""
        sess = self._sessions.get(session_id)
        if sess is None:
            sess = VoiceSession(session_id=session_id)
            self._sessions[session_id] = sess
        return sess

    def end(self, session_id: str) -> None:
        """End."""
        self._sessions.pop(session_id, None)

    def active_count(self) -> int:
        """Active count."""
        return len(self._sessions)
