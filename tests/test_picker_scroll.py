"""Proportional scrollbar-thumb geometry in the file picker (filer2.s THUMB_CALC).

The thumb math (MUL_AY / DIV16_8) only runs when a directory has more entries
than the visible window, which the boot volume doesn't — so verify it here as
pure arithmetic. PICK_VIS is 14; the inner track is PICK_VIS-2 = 12 cells.
"""
from _harness import program

PICK_VIS = 14
INNER = PICK_VIS - 2          # 12


def thumb(namecount, picktop, visrows):
    p = program()
    p.poke("NAMECOUNT", namecount)
    p.poke("PICKTOP", picktop)
    p.poke("VISROWS", visrows)
    p.call("THUMB_CALC")
    return p.peek("THUMB_TOP"), p.peek("THUMB_H")


def test_mul_ay():
    p = program()
    p.call("MUL_AY", a=14, y=12)
    assert p.peek16("M16") == 168


def test_fits_gives_full_thumb():
    # 5 files, all visible -> thumb fills the whole (adaptive) inner track.
    top, h = thumb(5, 0, 5)
    assert (top, h) == (0, 5 - 2)


def test_scroll_top():
    # 30 files, window 14, at the top.  h = floor(14*12/30) = 5, top = 0.
    assert thumb(30, 0, PICK_VIS) == (0, 5)


def test_scroll_bottom():
    # at the last page: maxtop = 30-14 = 16, span = 12-5 = 7, top = 16*7/16 = 7.
    assert thumb(30, 16, PICK_VIS) == (7, 5)


def test_scroll_middle():
    # pickeptop 8: top = floor(8*7/16) = 3.
    assert thumb(30, 8, PICK_VIS) == (3, 5)


def test_thumb_never_smaller_than_one():
    # 200 files: floor(168/200) = 0 -> clamped to a 1-cell thumb.
    top, h = thumb(200, 0, PICK_VIS)
    assert h == 1 and top == 0


def test_thumb_stays_in_track():
    # For every scroll offset the thumb must fit inside the 12-cell inner track.
    for top_off in range(0, 30 - PICK_VIS + 1):
        top, h = thumb(30, top_off, PICK_VIS)
        assert h >= 1
        assert top + h <= INNER, (top_off, top, h)
