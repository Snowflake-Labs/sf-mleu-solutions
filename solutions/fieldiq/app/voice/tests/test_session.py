"""Unit tests for the conversation/session engine (Task 2).

Uses a monkeypatched agent_bridge.ask_agent so the engine logic is tested without
calling the live Cortex Agent.
"""

import asyncio

from voice.conversation import session as session_mod
from voice.conversation.session import SessionManager, TurnState, VoiceSession


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _patch_agent(monkeypatch_answer):
    async def fake_ask(message, history=None, *, system_prompt=None):
        """Fake ask."""
        return monkeypatch_answer(message, history or [])

    session_mod.agent_bridge.ask_agent = fake_ask


def test_history_accumulates_across_turns():
    """Test history accumulates across turns."""
    _patch_agent(lambda msg, hist: f"Answer to: {msg}")
    s = VoiceSession(session_id="t1")

    _run(s.handle_utterance("What is the pipeline for Cascade Partners?"))
    _run(s.handle_utterance("What products are they evaluating?"))

    roles = [m["role"] for m in s.history]
    assert roles == ["user", "assistant", "user", "assistant"]
    assert s.history[0]["content"].startswith("What is the pipeline")
    assert s.history[3]["content"].startswith("Answer to")


def test_agent_receives_prior_history():
    """Test agent receives prior history."""
    seen = {}

    def answer(msg, hist):
        """Answer."""
        seen["history_len"] = len(hist)
        return "ok"

    _patch_agent(answer)
    s = VoiceSession(session_id="t2")
    _run(s.handle_utterance("first"))
    assert seen["history_len"] == 0  # no prior history on first turn
    _run(s.handle_utterance("second"))
    assert seen["history_len"] == 2  # user+assistant from turn 1


def test_assistant_turn_stores_speakable():
    """Test assistant turn stores speakable."""
    _patch_agent(lambda msg, hist: "The pipeline is **$4.6M** across 3 opps.")
    s = VoiceSession(session_id="t3")
    _run(s.handle_utterance("pipeline?"))
    stored = s.history[-1]["content"]
    assert "*" not in stored
    assert "million dollars" in stored


def test_barge_in_resets_to_listening():
    """Test barge in resets to listening."""
    s = VoiceSession(session_id="t4")
    s.state = TurnState.SPEAKING
    s.on_barge_in()
    assert s.state == TurnState.LISTENING


def test_empty_utterance_is_handled():
    """Test empty utterance is handled."""
    _patch_agent(lambda msg, hist: "should not be called")
    s = VoiceSession(session_id="t5")
    out = _run(s.handle_utterance("   "))
    assert "say it again" in out.lower()
    assert s.history == []


def test_history_trimmed_to_window():
    """Test history trimmed to window."""
    _patch_agent(lambda msg, hist: "a")
    s = VoiceSession(session_id="t6")
    for i in range(20):
        _run(s.handle_utterance(f"turn {i}"))
    assert len(s.history) <= session_mod.MAX_HISTORY_MESSAGES


def test_session_manager_lifecycle():
    """Test session manager lifecycle."""
    mgr = SessionManager()
    a = mgr.get_or_create("x")
    b = mgr.get_or_create("x")
    assert a is b
    assert mgr.active_count() == 1
    mgr.end("x")
    assert mgr.active_count() == 0
