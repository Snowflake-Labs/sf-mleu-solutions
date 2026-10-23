"""Conversation logic layer (no GPU required).

Holds everything that turns single-shot agent Q&A into a natural, multi-turn
*spoken* conversation:

- prompts.py      voice-mode system prompt
- formatter.py    agent output -> speakable text  (Task 1)
- session.py      session state, turn machine, context carry  (Task 2)
- agent_bridge.py thin client to the existing Cortex Agent endpoint
"""
