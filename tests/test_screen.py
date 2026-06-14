"""Screen-driver math: the 80-column row-base table and PUTC address compute.

The row bank (main vs aux) cannot be modeled in flat py65 — that is checked
in microM8. Here we verify the base-address table is correct and that PUTC
computes base+col/2 and advances the cursor.
"""
from _harness import program


def _expected_base(row):
    return 0x400 + (row % 8) * 0x80 + (row // 8) * 0x28


def test_row_base_table():
    p = program()
    lo = p.sym("BASEL")
    hi = p.sym("BASEH")
    for row in range(24):
        addr = p.peek(lo + row) | (p.peek(hi + row) << 8)
        assert addr == _expected_base(row), (
            f"row {row}: table={addr:#06x} expected={_expected_base(row):#06x}")


def test_putc_address_and_advance():
    # py65 has no banking, so even+odd columns alias to base+col/2; we test the
    # offset math and the CURCOL advance on a single write.
    p = program()
    CURROW = p.sym("CURROW")
    CURCOL = p.sym("CURCOL")
    for row, col in [(0, 0), (0, 1), (5, 40), (23, 79), (8, 16)]:
        p.poke(CURROW, row)
        p.poke(CURCOL, col)
        p.call("PUTRAW", a=0xC1)  # 'A' high-ascii
        base = _expected_base(row)
        assert p.peek(base + col // 2) == 0xC1, f"row{row} col{col} not written"
        assert p.peek(CURCOL) == col + 1, "CURCOL did not advance"
