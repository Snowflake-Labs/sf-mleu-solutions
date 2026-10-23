"""Unit tests for the voice-formatter (Task 1)."""

from voice.conversation import formatter


def test_strip_markdown_removes_syntax():
    """Test strip markdown removes syntax."""
    src = "**Bold** and _italic_ and `code` and # Heading\n- item one\n- item two"
    out = formatter.strip_markdown(src)
    assert "*" not in out
    assert "_" not in out
    assert "`" not in out
    assert "#" not in out
    assert "Bold" in out and "italic" in out and "code" in out
    assert "item one" in out


def test_strip_markdown_links():
    """Test strip markdown links."""
    out = formatter.strip_markdown("See [the datasheet](http://x/y) now")
    assert out == "See the datasheet now"


def test_currency_magnitude_normalized():
    """Test currency magnitude normalized."""
    assert "four" not in formatter.normalize_for_speech("$4.6M")  # keeps digits
    assert formatter.normalize_for_speech("$4.6M") == "4.6 million dollars"
    assert formatter.normalize_for_speech("$33.1K") == "33.1 thousand dollars"
    assert formatter.normalize_for_speech("$2B") == "2 billion dollars"


def test_plain_currency_normalized():
    """Test plain currency normalized."""
    assert formatter.normalize_for_speech("$42") == "42 dollars"
    assert formatter.normalize_for_speech("$1,200") == "1200 dollars"


def test_bare_magnitude_and_symbols():
    """Test bare magnitude and symbols."""
    assert formatter.normalize_for_speech("120K units") == "120 thousand units"
    assert formatter.normalize_for_speech("95%") == "95 percent"
    assert formatter.normalize_for_speech("sales & service") == "sales and service"


def test_table_summarized_to_sentence():
    """Test table summarized to sentence."""
    table = (
        "| Account | Pipeline |\n"
        "|---|---|\n"
        "| Cascade Partners | $4.6M |\n"
        "| Evergreen Industries | $3.7M |\n"
        "| Cardinal Chemicals | $2.3M |\n"
    )
    out = formatter.summarize_table(table, top_n=3)
    assert "3 results" in out
    assert "Cascade Partners with 4.6 million dollars" in out
    assert "Evergreen Industries" in out


def test_to_speakable_caps_sentences():
    """Test to speakable caps sentences."""
    long = " ".join(f"Sentence number {i}." for i in range(10))
    out = formatter.to_speakable(long, max_sentences=3)
    assert out.count(".") <= 5  # 3 sentences + offer
    assert "more detail" in out.lower()


def test_to_speakable_embeds_table_summary():
    """Test to speakable embeds table summary."""
    answer = (
        "Here are the top accounts:\n\n"
        "| Account | Pipeline |\n"
        "|---|---|\n"
        "| Cascade Partners | $4.6M |\n"
        "| Evergreen Industries | $3.7M |\n\n"
        "Let me know if you want more."
    )
    out = formatter.to_speakable(answer, max_sentences=6)
    assert "|" not in out
    assert "million dollars" in out
    assert "Cascade Partners" in out


def test_to_speakable_handles_empty():
    """Test to speakable handles empty."""
    out = formatter.to_speakable("")
    assert "rephrase" in out.lower()
