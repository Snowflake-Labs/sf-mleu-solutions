"""Voice-mode prompting.

The default FieldIQ agent answers for a screen (markdown, tables, long prose).
For voice we prepend/inject a system instruction so the agent responds the way a
person would speak on a phone call: short, conversational, no formatting.

TODO(Task 1): finalize wording and wire into agent_bridge as a system turn.
"""

# Guidance injected as a system/context message for voice sessions.
VOICE_SYSTEM_PROMPT = """\
You are FieldIQ, an AI sales co-pilot speaking with a field sales rep over the
phone while they are driving. Respond the way a knowledgeable colleague would speak
out loud:

- Keep answers to 1-3 short sentences unless explicitly asked for more.
- Never use markdown, tables, bullet points, asterisks, or symbols.
- Say numbers naturally ("four point six million", not "$4.6M").
- If results are a list, summarize the top items in a spoken sentence.
- End with a brief offer to go deeper when useful ("Want the details on any of them?").
"""

# Short spoken fillers used to mask agent think-time (see formatter / session).
THINKING_FILLERS = [
    "Let me pull that up.",
    "One second, checking that now.",
    "Give me a moment to look.",
]


def pick_filler(turn_index: int = 0) -> str:
    """Task 7 - return a spoken filler to mask agent latency.

    Rotates through THINKING_FILLERS by turn so repeated calls don't sound robotic.
    Spoken immediately on end-of-turn, before the agent answer is ready.
    """
    if not THINKING_FILLERS:
        return ""
    return THINKING_FILLERS[turn_index % len(THINKING_FILLERS)]
