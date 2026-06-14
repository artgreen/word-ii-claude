"""Search and replace logic (py65)."""
from _harness import program

EDITBUF = 0x1C00
EDITMAX = 1024
LINETBL = 0x6000


def new(p):
    p.call("DOC_NEW")


def typ(p, s):
    for c in s:
        p.call("ED_INSERT", a=ord(c) | 0x80)


def setpat(p, sym, s):
    a = p.sym(sym)
    p.poke(a, len(s))
    for i, c in enumerate(s):
        p.poke(a + 1 + i, ord(c))


def cur_para(p):
    gs = p.peek16("GAPSTART")
    ge = p.peek16("GAPEND")
    b = bytes(p.read(EDITBUF, gs)) + bytes(p.read(EDITBUF + ge, EDITMAX - ge))
    return bytes(x & 0x7F for x in b).decode("latin1")


def carry(mpu):
    return mpu.p & 1


def test_find_moves_cursor():
    p = program()
    new(p)
    typ(p, "the quick brown fox")
    p.call("ED_ENTER")
    typ(p, "the lazy dog")
    p.call("ED_UP")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "lazy")
    m = p.call("FIND_FROM_CURSOR")
    assert carry(m) == 1, "should report found"
    assert p.peek16("DOCLINE") == 1
    assert p.peek16("GAPSTART") == 4    # "the " then "lazy"


def test_find_is_case_insensitive():
    p = program()
    new(p)
    typ(p, "Hello World")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "WORLD")
    m = p.call("FIND_FROM_CURSOR")
    assert carry(m) == 1
    assert p.peek16("GAPSTART") == 6


def test_find_not_found():
    p = program()
    new(p)
    typ(p, "abcdef")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "xyz")
    m = p.call("FIND_FROM_CURSOR")
    assert carry(m) == 0, "should report not found"


def test_replace_at_cursor():
    p = program()
    new(p)
    typ(p, "the cat sat")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "cat")
    setpat(p, "REPLACEPAT", "dog")
    p.call("FIND_FROM_CURSOR")           # cursor -> "cat"
    p.call("DO_REPLACE_AT")
    assert cur_para(p) == "the dog sat"


def test_replace_longer():
    p = program()
    new(p)
    typ(p, "a b c")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "b")
    setpat(p, "REPLACEPAT", "XYZ")
    p.call("FIND_FROM_CURSOR")
    p.call("DO_REPLACE_AT")
    assert cur_para(p) == "a XYZ c"


def test_find_wraps_to_match_before_cursor():
    p = program()
    new(p)
    typ(p, "alpha beta gamma")   # cursor at end (col 16)
    setpat(p, "SEARCHPAT", "alpha")
    m = p.call("FIND_FROM_CURSOR")
    assert carry(m) == 1, "should wrap and find earlier match"
    assert p.peek16("GAPSTART") == 0
