"""Directory picker logic: ProDOS directory-block parsing and path building."""
from _harness import program

DIRDATA = 0x1800
NAMELIST = 0x0C00          # IOBUF_B (moved off CLIPBUF so the clipboard can use $1000)


def _slot(p, i):
    s = NAMELIST + i * 16
    ln = p.peek(s)
    return bytes(p.read(s + 1, ln)).decode("latin1")


def _setstr(p, sym, s):
    a = p.sym(sym)
    p.poke(a, len(s))
    for i, c in enumerate(s):
        p.poke(a + 1 + i, ord(c))


def test_parse_dir_block_collects_files_skips_headers():
    p = program()
    blk = bytearray(512)
    blk[4] = 0xF8                       # volume header (storage $F) -> skip
    blk[43] = 0x24                      # file storage 2, len 4
    blk[44:48] = b"FILE"
    blk[82] = 0x13                      # file storage 1, len 3
    blk[83:86] = b"DOC"
    blk[121] = 0xD3                     # subdirectory (storage $D) -> skip
    p.write(DIRDATA, bytes(blk))
    p.poke("NAMECOUNT", 0)
    p.call("PARSE_DIRBLOCK")
    assert p.peek("NAMECOUNT") == 2
    assert _slot(p, 0) == "FILE"
    assert _slot(p, 1) == "DOC"


def test_parse_dir_skips_deleted_entries():
    p = program()
    blk = bytearray(512)
    blk[4] = 0x00                       # deleted/inactive -> skip
    blk[43] = 0x21                      # file, len 1 "A"
    blk[44] = ord("A")
    p.write(DIRDATA, bytes(blk))
    p.poke("NAMECOUNT", 0)
    p.call("PARSE_DIRBLOCK")
    assert p.peek("NAMECOUNT") == 1
    assert _slot(p, 0) == "A"


def test_build_dirpath_strips_trailing_slash():
    p = program()
    _setstr(p, "PREFIXBUF", "/PRODOS402/")
    p.call("BUILD_DIRPATH")
    a = p.sym("DIRPATH")
    ln = p.peek(a)
    assert bytes(p.read(a + 1, ln)).decode("latin1") == "/PRODOS402"
