"""File I/O: the MLI call sequence (against a faked MLI) and the byte-level
parse/translate logic (pure computation). Real disk I/O is verified in microM8.
"""
from _harness import program

TEXTHEAP = 0x7000
LINETBL = 0x6000

# ProDOS MLI call numbers we expect to see logged.
CREATE, OPEN, SETEOF, WRITE, CLOSE, GETEOF, READ = (
    0xC0, 0xC8, 0xD0, 0xCB, 0xCC, 0xD1, 0xCA)


def test_save_issues_expected_mli_sequence():
    p = program()
    p.fake_mli()
    p.call("DOC_NEW")
    for c in "HELLO":
        p.call("ED_INSERT", a=ord(c) | 0x80)
    p.call("FILE_SAVE")
    calls = p.mli_calls()
    # one paragraph -> create, open, set_eof(truncate), write, close
    assert calls == [CREATE, OPEN, SETEOF, WRITE, CLOSE], calls


def test_save_two_paragraphs_writes_separator():
    p = program()
    p.fake_mli()
    p.call("DOC_NEW")
    for c in "AB":
        p.call("ED_INSERT", a=ord(c) | 0x80)
    p.call("ED_ENTER")
    for c in "CD":
        p.call("ED_INSERT", a=ord(c) | 0x80)
    p.call("FILE_SAVE")
    calls = p.mli_calls()
    # two paragraphs -> WRITE(para0), WRITE(CR), WRITE(para1)
    assert calls == [CREATE, OPEN, SETEOF, WRITE, WRITE, WRITE, CLOSE], calls


def _para(p, i):
    e = LINETBL + i * 4
    loc = p.peek(e) | (p.peek(e + 1) << 8)
    ln = p.peek(e + 2) | (p.peek(e + 3) << 8)
    return bytes(b & 0x7F for b in p.read(loc, ln)).decode("latin1")


def _parse(p, raw):
    p.write(TEXTHEAP, raw)
    p.poke16("COUNTL", len(raw))
    p.call("PARSE_DOC")


def test_parse_three_paragraphs():
    p = program()
    p.call("DOC_NEW")
    _parse(p, b"ABC\rDEF\rGHI")
    assert p.peek16("NLINES") == 3
    assert [_para(p, i) for i in range(3)] == ["ABC", "DEF", "GHI"]


def test_parse_empty_file_is_one_empty_paragraph():
    p = program()
    p.call("DOC_NEW")
    _parse(p, b"")
    assert p.peek16("NLINES") == 1
    assert _para(p, 0) == ""


def test_parse_accepts_high_bit_cr():
    # classic Apple II text: high-bit chars + $8D line breaks
    p = program()
    p.call("DOC_NEW")
    _parse(p, bytes([0xC1, 0xC2, 0x8D, 0xC3, 0xC4]))  # "AB"\r"CD"
    assert p.peek16("NLINES") == 2
    assert [_para(p, i) for i in range(2)] == ["AB", "CD"]


def test_xlat_low_strips_high_bit():
    p = program()
    src, dst = 0x7000, 0x7100
    p.write(src, bytes([0xC8, 0xC9, 0xA0, 0xFE]))  # H I space ~
    p.poke16("SRCPTR", src)
    p.poke16("DSTPTR", dst)
    p.poke16("COUNTL", 4)
    p.call("XLAT_LOW")
    assert bytes(p.read(dst, 4)) == bytes([0x48, 0x49, 0x20, 0x7E])
