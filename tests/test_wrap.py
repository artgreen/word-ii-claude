"""Word-wrap break point (FIND_WRAP) -- pure computation, py65."""
from _harness import program

SCRATCH = 0x7000  # free RAM in the test; stand-in for a paragraph's bytes


def _setup(text, margin, off=0):
    p = program()
    data = bytes((ord(c) | 0x80) for c in text)  # high-bit ASCII
    p.write(SCRATCH, data)
    p.poke16("RENDSRC", SCRATCH)
    p.poke16("RENDLEN", len(data))
    p.poke16("RENDOFF", off)
    p.poke("MARGIN", margin)
    return p


def _wrap(text, margin, off=0):
    p = _setup(text, margin, off)
    p.call("FIND_WRAP")
    return p.peek("ROWCOUNT"), p.peek16("RENDOFF")


def test_short_line_fits():
    count, nextoff = _wrap("HELLO", 10)
    assert count == 5 and nextoff == 5


def test_breaks_at_space():
    # "HELLO WORLD FOO", margin 10 -> first row "HELLO" (break at space@5)
    count, nextoff = _wrap("HELLO WORLD FOO", 10)
    assert count == 5, count
    assert nextoff == 6, nextoff   # skip the space


def test_long_word_hard_break():
    count, nextoff = _wrap("ABCDEFGHIJKLMNOP", 10)
    assert count == 10 and nextoff == 10


def test_second_row_offset():
    # continue "HELLO WORLD FOO" from offset 6 -> "WORLD FOO" is 9 <= 10, fits whole
    count, nextoff = _wrap("HELLO WORLD FOO", 10, off=6)
    assert count == 9, count
    assert nextoff == 15, nextoff


def test_second_row_offset_wraps():
    # longer tail forces a real second break: "WORLD FOOBAR" from offset 6, margin 10
    count, nextoff = _wrap("HELLO WORLD FOOBAR", 10, off=6)
    assert count == 5, count       # "WORLD"
    assert nextoff == 12, nextoff  # skip space before "FOOBAR"


def test_exact_margin_with_trailing_space():
    # "ABCDEFGHIJ KLM" margin 10: index10 is a space -> 10 chars fit, break at space
    count, nextoff = _wrap("ABCDEFGHIJ KLM", 10)
    assert count == 10, count
    assert nextoff == 11, nextoff
