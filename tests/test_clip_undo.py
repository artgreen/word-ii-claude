"""Clipboard (copy/cut/paste/select-all) and one-level undo (py65)."""
from _harness import program

EDITBUF = 0x1C00
EDITMAX = 1024
CLIPBUF = 0x1000


def new(p):
    p.call("DOC_NEW")


def typ(p, s):
    for c in s:
        p.call("ED_INSERT", a=ord(c) | 0x80)


def cur_para(p):
    gs = p.peek16("GAPSTART")
    ge = p.peek16("GAPEND")
    b = bytes(p.read(EDITBUF, gs)) + bytes(p.read(EDITBUF + ge, EDITMAX - ge))
    return bytes(x & 0x7F for x in b).decode("latin1")


def clip_text(p):
    n = p.peek16("CLIPLEN")
    return bytes(x & 0x7F for x in p.read(CLIPBUF, n)).decode("latin1")


def test_copy_then_paste():
    p = program()
    new(p)
    typ(p, "HELLO")
    p.call("COPY_LINE")
    assert clip_text(p) == "HELLO"
    p.call("ED_ENTER")          # new empty paragraph
    p.call("PASTE_CLIP")
    assert cur_para(p) == "HELLO"


def test_cut_line_removes_paragraph():
    p = program()
    new(p)
    typ(p, "AB")
    p.call("ED_ENTER")
    typ(p, "CD")
    p.call("ED_UP")             # to paragraph 0
    p.call("ED_HOME")
    p.call("COPY_LINE")
    p.call("DELETE_LINE")
    assert p.peek16("NLINES") == 1
    assert cur_para(p) == "CD"
    assert clip_text(p) == "AB"


def test_select_all_serializes():
    p = program()
    new(p)
    typ(p, "AB")
    p.call("ED_ENTER")
    typ(p, "CD")
    p.call("SERIALIZE_TO_CLIP")
    assert p.peek16("CLIPLEN") == 5     # "AB" + CR + "CD"
    assert clip_text(p) == "AB\rCD"


def test_undo_reverts_typing():
    p = program()
    new(p)
    p.call("UNDO_CHECKPOINT")    # snapshot the empty paragraph
    typ(p, "MISTAKE")
    assert cur_para(p) == "MISTAKE"
    p.call("CMD_DO_UNDO")
    assert cur_para(p) == ""


def test_undo_invalidated_has_nothing():
    p = program()
    new(p)
    p.call("UNDO_CHECKPOINT")
    typ(p, "X")
    p.call("UNDO_INVAL")         # e.g. navigation cleared it
    p.poke(0xC000, 0xD9)         # stage a key so the "Nothing to undo" alert returns
    p.call("CMD_DO_UNDO")        # should do nothing (no checkpoint)
    assert cur_para(p) == "X"
