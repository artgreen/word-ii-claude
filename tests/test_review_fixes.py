"""Regression tests for the bugs found by the 6502-review pass."""
from _harness import program

EDITBUF = 0x1C00
EDITMAX = 1024
LINETBL = 0x6000
TEXTHEAP = 0x7000


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


# --- finding 1: ED_TAB must not hang on a full paragraph -------------

def test_ed_tab_on_full_paragraph_returns():
    p = program()
    new(p)
    # force a full paragraph (gap empty) with the cursor at a non-tab-aligned col
    p.poke16("GAPSTART", 5)
    p.poke16("GAPEND", 5)
    p.poke("TABW", 8)
    p.call("ED_TAB", max_steps=200000)   # would loop forever before the fix
    assert p.peek16("GAPSTART") == 5     # nothing inserted, no hang


def test_ed_tab_normal_aligns_to_stop():
    p = program()
    new(p)
    typ(p, "ab")                          # col 2
    p.poke("TABW", 4)
    p.call("ED_TAB")
    assert p.peek16("GAPSTART") == 4      # advanced to the next tab stop


# --- finding 4: Select All must respect CLIPMAX ----------------------

def test_select_all_respects_clipmax():
    p = program()
    new(p)
    for i in range(3):                    # three 500-byte paragraphs in the heap
        loc = TEXTHEAP + i * 0x200
        p.write(loc, bytes([0xC1] * 500))
        e = LINETBL + i * 4
        p.poke(e, loc & 0xFF)
        p.poke(e + 1, loc >> 8)
        p.poke(e + 2, 500 & 0xFF)
        p.poke(e + 3, 500 >> 8)
    p.poke16("NLINES", 3)
    p.poke16("DOCLINE", 0)
    p.poke("EDITDIRTY", 0)                # STOREPARA is a no-op
    p.call("SERIALIZE_TO_CLIP")
    cl = p.peek16("CLIPLEN")
    assert cl <= 1024, f"overflowed CLIPMAX: {cl}"
    assert cl == 1002, cl                 # 500 + CR + 500 + CR, then para 3 refused


# --- finding 5: Replace must not honor overwrite mode ----------------

def test_replace_ignores_overwrite_mode():
    p = program()
    new(p)
    typ(p, "aXb")
    p.call("ED_HOME")
    p.poke("EDITFLAGS", 0x02)             # FL_OVERWRITE on
    setpat(p, "SEARCHPAT", "X")
    setpat(p, "REPLACEPAT", "YZ")
    p.poke("FIND_RESUME", 0)
    p.call("FIND_FROM_CURSOR")            # cursor -> the X
    p.call("DO_REPLACE_AT")
    assert cur_para(p) == "aYZb"          # 'b' preserved (not eaten by overwrite)


# --- finding 6: Find resume includes the cursor column ---------------

def test_find_resume_includes_cursor():
    p = program()
    new(p)
    typ(p, "aaaa")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "aa")
    p.poke("FIND_RESUME", 1)
    p.call("FIND_FROM_CURSOR")
    assert p.peek16("GAPSTART") == 0      # match at the cursor column itself


def test_find_default_skips_cursor():
    p = program()
    new(p)
    typ(p, "aaaa")
    p.call("ED_HOME")
    setpat(p, "SEARCHPAT", "aa")
    p.poke("FIND_RESUME", 0)
    p.call("FIND_FROM_CURSOR")
    assert p.peek16("GAPSTART") == 1      # fresh Find skips the current column
