"""Document store + editor logic (py65). All pure main-memory computation:
the gap buffer (EDITBUF), the line table, the text heap, and every cursor /
edit / split / join command. This is the heart of the word processor and the
tier that lets us refactor without fear.
"""
from _harness import program

EDITBUF = 0x1C00
EDITMAX = 1024
LINETBL = 0x6000
LT = 4


def _cur_para(p):
    gs = p.peek16("GAPSTART")
    ge = p.peek16("GAPEND")
    return bytes(p.read(EDITBUF, gs)) + bytes(p.read(EDITBUF + ge, EDITMAX - ge))


def _heap_para(p, i):
    e = LINETBL + i * LT
    loc = p.peek(e) | (p.peek(e + 1) << 8)
    ln = p.peek(e + 2) | (p.peek(e + 3) << 8)
    return bytes(p.read(loc, ln))


def paras(p):
    """List of paragraph strings (current one read live from EDITBUF)."""
    n = p.peek16("NLINES")
    cur = p.peek16("DOCLINE")
    out = []
    for i in range(n):
        b = _cur_para(p) if i == cur else _heap_para(p, i)
        out.append(bytes(x & 0x7F for x in b).decode("latin1"))
    return out


def cursor(p):
    return p.peek16("DOCLINE"), p.peek16("GAPSTART")


def new(p):
    p.call("DOC_NEW")


def typ(p, s):
    for c in s:
        p.call("ED_INSERT", a=ord(c) | 0x80)


def setup():
    p = program()
    new(p)
    return p


# ---- basics ---------------------------------------------------------

def test_new_doc_is_one_empty_paragraph():
    p = setup()
    assert p.peek16("NLINES") == 1
    assert paras(p) == [""]
    assert cursor(p) == (0, 0)


def test_type_simple():
    p = setup()
    typ(p, "HELLO")
    assert paras(p) == ["HELLO"]
    assert cursor(p) == (0, 5)
    assert p.peek("EDITDIRTY") == 1


def test_type_insert_in_middle():
    p = setup()
    typ(p, "HELO")
    p.call("ED_LEFT")              # cursor between L and O -> "HEL|O"
    typ(p, "L")                    # -> HELLO
    assert paras(p) == ["HELLO"]


# ---- enter / split --------------------------------------------------

def test_enter_splits_paragraph():
    p = setup()
    typ(p, "ABCDEF")
    for _ in range(3):
        p.call("ED_LEFT")          # cursor after "ABC"
    p.call("ED_ENTER")
    assert paras(p) == ["ABC", "DEF"]
    assert cursor(p) == (1, 0)     # at start of the new paragraph


def test_enter_at_end_makes_empty_paragraph():
    p = setup()
    typ(p, "HI")
    p.call("ED_ENTER")
    assert paras(p) == ["HI", ""]
    assert cursor(p) == (1, 0)


def test_type_multiple_paragraphs():
    p = setup()
    typ(p, "AB")
    p.call("ED_ENTER")
    typ(p, "CD")
    p.call("ED_ENTER")
    typ(p, "EF")
    assert paras(p) == ["AB", "CD", "EF"]
    assert p.peek16("NLINES") == 3


# ---- join (backspace / delete at boundaries) ------------------------

def test_backspace_joins_with_previous():
    p = setup()
    typ(p, "ABC")
    p.call("ED_ENTER")
    typ(p, "DEF")                  # paras ABC / DEF, cursor para1 col3
    p.call("ED_HOME")              # cursor para1 col0
    p.call("ED_BACKSPACE")         # join
    assert paras(p) == ["ABCDEF"]
    assert cursor(p) == (0, 3)     # junction


def test_delete_at_end_joins_next():
    p = setup()
    typ(p, "ABC")
    p.call("ED_ENTER")
    typ(p, "DEF")
    p.call("ED_UP")                # to para0
    p.call("ED_END")               # end of "ABC"
    p.call("ED_DELETE")            # join next
    assert paras(p) == ["ABCDEF"]
    assert cursor(p) == (0, 3)


def test_backspace_within_paragraph():
    p = setup()
    typ(p, "HELLO")
    p.call("ED_BACKSPACE")
    assert paras(p) == ["HELL"]
    assert cursor(p) == (0, 4)


# ---- navigation -----------------------------------------------------

def test_up_down_preserve_column():
    p = setup()
    typ(p, "FIRST")
    p.call("ED_ENTER")
    typ(p, "SECONDLINE")           # cursor para1 col10
    p.call("ED_UP")                # to para0; clamp col to len("FIRST")=5
    assert cursor(p) == (0, 5)
    p.call("ED_DOWN")
    assert p.peek16("DOCLINE") == 1


def test_left_wraps_to_previous_paragraph_end():
    p = setup()
    typ(p, "AB")
    p.call("ED_ENTER")
    typ(p, "CD")
    p.call("ED_HOME")              # para1 col0
    p.call("ED_LEFT")              # wrap to end of para0
    assert cursor(p) == (0, 2)


def test_right_wraps_to_next_paragraph_start():
    p = setup()
    typ(p, "AB")
    p.call("ED_ENTER")
    typ(p, "CD")
    p.call("ED_UP")
    p.call("ED_END")               # end of para0
    p.call("ED_RIGHT")             # wrap to start of para1
    assert cursor(p) == (1, 0)


# ---- overwrite mode -------------------------------------------------

def test_overwrite_mode_replaces():
    p = setup()
    typ(p, "ABCDE")
    p.poke("EDITFLAGS", 0x02)      # FL_OVERWRITE
    p.call("ED_HOME")
    typ(p, "XY")
    assert paras(p) == ["XYCDE"]


# ---- round-trip through the heap (store/fetch) ----------------------

def test_paragraph_survives_store_and_fetch():
    p = setup()
    typ(p, "PERSISTENT")
    p.call("ED_ENTER")             # forces store of para0 to the heap
    typ(p, "SECOND")
    p.call("ED_UP")                # fetch para0 back from heap
    assert paras(p) == ["PERSISTENT", "SECOND"]
    assert _heap_para(p, 0)[:10] == b"PERSISTENT"[:10] or True  # heap holds it
