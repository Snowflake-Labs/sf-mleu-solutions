"""Task 1 - Voice-formatter.

Converts Cortex Agent output (markdown, tables, bold, long prose) into clean,
speakable text suitable for TTS. This is the single most important adaptation for
voice quality.

Pure functions, no I/O - fully unit-testable (see tests/test_formatter.py).
"""

from __future__ import annotations

import re

# Ordered magnitude suffixes for currency/number normalization.
_MAGNITUDES = {
    "k": "thousand",
    "m": "million",
    "b": "billion",
    "t": "trillion",
}


def strip_markdown(text: str) -> str:
    """Remove markdown syntax, leaving plain prose."""
    if not text:
        return ""

    out = text

    # Fenced code blocks -> keep inner text.
    out = re.sub(r"```[a-zA-Z0-9]*\n?", "", out)
    # Inline code `x` -> x
    out = re.sub(r"`([^`]*)`", r"\1", out)
    # Images ![alt](url) -> alt
    out = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", out)
    # Links [text](url) -> text
    out = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", out)
    # Bold/italic markers ** __ * _
    out = re.sub(r"(\*\*|__|\*|_)", "", out)
    # Headings / blockquotes at line start
    out = re.sub(r"(?m)^\s{0,3}#{1,6}\s*", "", out)
    out = re.sub(r"(?m)^\s{0,3}>\s?", "", out)
    # Unordered list markers at line start -> nothing
    out = re.sub(r"(?m)^\s*[-*+]\s+", "", out)
    # Ordered list markers "1. " at line start -> nothing
    out = re.sub(r"(?m)^\s*\d+\.\s+", "", out)
    # Horizontal rules
    out = re.sub(r"(?m)^\s*([-*_])\1{2,}\s*$", "", out)
    # Any leftover stray markdown symbols not caught above
    out = out.replace("#", "")
    # Collapse extra whitespace
    out = re.sub(r"[ \t]{2,}", " ", out)
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip()


def _parse_table(md: str) -> tuple[list[str], list[list[str]]] | None:
    """Parse a markdown pipe-table block into (headers, rows). None if not a table."""
    lines = [ln.strip() for ln in md.strip().splitlines() if ln.strip()]
    pipe_lines = [ln for ln in lines if ln.count("|") >= 1 and "|" in ln]
    if len(pipe_lines) < 2:
        return None

    def cells(line: str) -> list[str]:
        """Cells."""
        line = line.strip()
        if line.startswith("|"):
            line = line[1:]
        if line.endswith("|"):
            line = line[:-1]
        return [c.strip() for c in line.split("|")]

    headers = cells(pipe_lines[0])
    # Second line should be the separator (---|---). Confirm it looks like one.
    sep = pipe_lines[1]
    if not re.match(r"^\|?[\s:\-|]+\|?$", sep):
        return None
    data_rows = [cells(ln) for ln in pipe_lines[2:]]
    return headers, data_rows


def summarize_table(markdown_table: str, *, top_n: int = 3) -> str:
    """Turn a markdown/pipe table into a spoken one-liner summary."""
    parsed = _parse_table(markdown_table)
    if not parsed:
        return strip_markdown(markdown_table)

    headers, rows = parsed
    if not rows:
        return "No results were found."

    total = len(rows)
    shown = rows[:top_n]

    def describe(row: list[str]) -> str:
        # Lead with the first column (usually the entity name).
        """Describe."""
        label = normalize_for_speech(row[0]) if row else ""
        # If a second column exists, add it as "with <value>".
        if len(row) > 1 and row[1]:
            return f"{label} with {normalize_for_speech(row[1])}"
        return label

    items = [describe(r) for r in shown if any(c for c in r)]
    if not items:
        return "No results were found."

    if total == 1:
        return f"{items[0]}."

    listed = "; ".join(items)
    if total > len(items):
        return f"There are {total} results. The top {len(items)} are: {listed}."
    return f"There are {total} results: {listed}."


def normalize_for_speech(text: str) -> str:
    """Expand currency, units, and symbols for natural TTS."""
    if not text:
        return ""

    out = text

    # Currency with magnitude, e.g. $4.6M, $33.1K, $2B
    def _money_mag(m: re.Match) -> str:
        num = m.group(1)
        suffix = m.group(2).lower()
        word = _MAGNITUDES.get(suffix, "")
        return f"{num} {word} dollars".replace("  ", " ")

    out = re.sub(r"\$\s?(\d+(?:\.\d+)?)\s?([KkMmBbTt])\b", _money_mag, out)

    # Plain currency, e.g. $42, $1,200.50
    def _money(m: re.Match) -> str:
        num = m.group(1).replace(",", "")
        return f"{num} dollars"

    out = re.sub(r"\$\s?(\d[\d,]*(?:\.\d+)?)", _money, out)

    # Bare number with magnitude, e.g. 4.6M, 120K (not preceded by a letter)
    def _num_mag(m: re.Match) -> str:
        num = m.group(1)
        word = _MAGNITUDES.get(m.group(2).lower(), "")
        return f"{num} {word}".strip()

    out = re.sub(r"(?<![A-Za-z])(\d+(?:\.\d+)?)\s?([KkMmBbTt])\b", _num_mag, out)

    # Percent and symbols
    out = re.sub(r"(\d)\s?%", r"\1 percent", out)
    out = out.replace("%", " percent")
    out = re.sub(r"\s?&\s?", " and ", out)

    out = re.sub(r"[ \t]{2,}", " ", out)
    return out.strip()


def _split_sentences(text: str) -> list[str]:
    """Naive sentence splitter on ., !, ? keeping it simple for spoken text."""
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p.strip() for p in parts if p.strip()]


def to_speakable(agent_text: str, *, max_sentences: int = 3) -> str:
    """Convert raw agent output into a speakable string.

    Steps: summarize any tables -> strip markdown -> normalize numbers/symbols
    -> cap to `max_sentences` (append a brief offer of detail if truncated).
    """
    if not agent_text or not agent_text.strip():
        return "I didn't get a result for that. Could you rephrase?"

    text = agent_text

    # Replace each markdown table block with a spoken summary.
    table_pattern = re.compile(
        r"(?:^|\n)((?:\s*\|.*\|\s*\n)(?:\s*\|?[\s:\-|]+\|?\s*\n)(?:\s*\|.*\|\s*\n?)*)",
    )

    def _table_sub(m: re.Match) -> str:
        return " " + summarize_table(m.group(1)) + " "

    text = table_pattern.sub(_table_sub, text)

    # Strip remaining markdown, then normalize for speech.
    text = strip_markdown(text)
    text = normalize_for_speech(text)

    # Flatten newlines into spaces for continuous speech.
    text = re.sub(r"\s*\n+\s*", " ", text).strip()
    text = re.sub(r"[ \t]{2,}", " ", text)

    sentences = _split_sentences(text)
    if len(sentences) <= max_sentences:
        return text

    capped = " ".join(sentences[:max_sentences])
    return f"{capped} Want me to go into more detail?"
