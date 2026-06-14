"""Tests for Go To Line number parsing and document word counting (M7 cleanup #4).

CMD_DO_GOTO / CMD_DO_WORDCOUNT themselves block on a dialog (INPUT_FIELD / ALERT),
so we drive their leaf routines: PARSE_NUM16 (line-number parse) and
COUNT_WORDS_IN_PARA (the per-paragraph word scanner the count loop calls).
"""
from _harness import program

TEXTHEAP = 0x7000
LINETBL = 0x6000


def set_namebuf(p, s):
    a = p.sym("NAMEBUF")
    p.poke(a, len(s))                       # length prefix
    for i, c in enumerate(s):
        p.poke(a + 1 + i, ord(c))           # 7-bit, as INPUT_FIELD stores them


def count_words(p, raw):
    """raw = bytes already in heap form (high-bit set). Returns WCOUNT."""
    p.write(TEXTHEAP, bytes(raw))
    p.poke16("PTR0", TEXTHEAP)
    p.poke16("COUNTL", len(raw))
    p.poke16("WCOUNTL", 0)
    p.call("COUNT_WORDS_IN_PARA")
    return p.peek16("WCOUNTL")


def hi(s):
    return bytes(ord(c) | 0x80 for c in s)


# --- PARSE_NUM16 -----------------------------------------------------

def test_parse_num16_basic():
    p = program()
    set_namebuf(p, "1234")
    p.call("PARSE_NUM16")
    assert p.peek16("COUNTL") == 1234


def test_parse_num16_exceeds_byte():
    p = program()
    set_namebuf(p, "1024")                  # needs the 16-bit path
    p.call("PARSE_NUM16")
    assert p.peek16("COUNTL") == 1024


def test_parse_num16_empty_is_zero():
    p = program()
    set_namebuf(p, "")
    p.call("PARSE_NUM16")
    assert p.peek16("COUNTL") == 0


def test_parse_num16_stops_at_nondigit():
    p = program()
    set_namebuf(p, "12x9")
    p.call("PARSE_NUM16")
    assert p.peek16("COUNTL") == 12


# --- COUNT_WORDS_IN_PARA ---------------------------------------------

def test_count_simple():
    p = program()
    assert count_words(p, hi("the quick brown fox")) == 4


def test_count_collapses_runs():
    p = program()
    assert count_words(p, hi("the   quick  brown")) == 3


def test_count_leading_trailing_space():
    p = program()
    assert count_words(p, hi("  hi there  ")) == 2


def test_count_empty():
    p = program()
    assert count_words(p, b"") == 0


def test_count_all_spaces():
    p = program()
    assert count_words(p, hi("     ")) == 0


def test_count_tabs_separate_words():
    p = program()
    # 0x89 = Tab in heap form; treated as whitespace by the < space+1 test
    assert count_words(p, hi("a") + bytes([0x89]) + hi("b")) == 2


# --- CMD_DO_WORDCOUNT message construction (regression: NUM2DEC clobbers X) ---

def test_wordcount_message_keeps_separator():
    """The report string must read 'Words: N', not 'WordsN'.

    NUM2DEC reuses X as its power-of-ten index, so the digit-append loop must
    re-load the write position after the call rather than trusting X to still
    hold the prefix length. CMD_DO_WORDCOUNT ends in ALERT's GETKEY spin, so we
    pre-load the keyboard latch to let it return, then read the built message.
    """
    p = program()
    p.call("DOC_NEW")
    text = bytes([0xE1, 0xA0, 0xE2, 0xA0, 0xE3])     # "a b c" in heap form, 3 words
    p.write(TEXTHEAP, text)
    p.poke(LINETBL, TEXTHEAP & 0xFF)
    p.poke(LINETBL + 1, TEXTHEAP >> 8)
    p.poke(LINETBL + 2, len(text))
    p.poke(LINETBL + 3, 0)
    p.poke16("NLINES", 1)
    p.poke16("DOCLINE", 0)
    p.poke("EDITDIRTY", 0)                            # STOREPARA is a no-op; heap line 0 stays
    p.poke(0xC000, 0x8D)                              # pre-loaded key so ALERT's GETKEY returns
    p.call("CMD_DO_WORDCOUNT")
    raw = bytes(p.read(p.sym("WCMSG"), 12))
    msg = bytes(b & 0x7F for b in raw).split(b"\x00")[0].decode("latin1")
    assert msg == "Words: 3", repr(msg)


def test_count_accumulates_across_calls():
    p = program()
    p.write(TEXTHEAP, hi("one two"))
    p.poke16("PTR0", TEXTHEAP)
    p.poke16("COUNTL", 7)
    p.poke16("WCOUNTL", 0)
    p.call("COUNT_WORDS_IN_PARA")
    p.write(TEXTHEAP, hi("three four five"))
    p.poke16("PTR0", TEXTHEAP)
    p.poke16("COUNTL", 15)
    p.call("COUNT_WORDS_IN_PARA")            # adds to the running total
    assert p.peek16("WCOUNTL") == 5
