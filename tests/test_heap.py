"""Text-heap accounting + compaction (py65).

The heap is a bump allocator: growing a paragraph past its slot abandons the old
slot, so dead space accrues. HEAP_USED reports the *live* document size (so the
status line reflects deletes), and HEAP_COMPACT packs the live paragraphs back
down and resets HEAPTOP, reclaiming the dead space. HEAP_ALLOC_CMP compacts and
retries when a raw allocation would fail.
"""
from _harness import program
from test_editor import setup, typ, paras

TEXTHEAP = 0x7000
HEAP_LIMIT = 0xBF00


def used(p):
    p.call("HEAP_USED")
    return p.peek16("COUNTL")


def heaptop(p):
    return p.peek16("HEAPTOP")


# ---- HEAP_USED tracks live document size ----------------------------

def test_used_counts_live_paragraph_before_store():
    p = setup()
    typ(p, "HELLO")                 # 5 bytes, never stored (still in EDITBUF)
    assert used(p) == 5            # counted live via PARALEN, not the stale table


def test_used_shrinks_on_delete():
    p = setup()
    typ(p, "HELLO")
    assert used(p) == 5
    p.call("ED_BACKSPACE")
    assert used(p) == 4            # the reported number drops immediately
    p.call("ED_BACKSPACE")
    assert used(p) == 3


def test_used_sums_all_paragraphs():
    p = setup()
    typ(p, "AAA")
    p.call("ED_ENTER")
    typ(p, "BBBBB")                # paras "AAA" (stored) + "BBBBB" (live)
    assert used(p) == 8


# ---- a grow-realloc leaks dead space that compaction reclaims --------

def _make_dead_space(p):
    """Leave the heap holding "AAAAXXXXXX" and "BB" with a dead 4-byte slot:
    para0 is grown after being stored, abandoning its first slot."""
    typ(p, "AAAA")
    p.call("ED_ENTER")             # store para0 (len 4 at TEXTHEAP)
    typ(p, "BB")                   # para1
    p.call("ED_UP")                # store para1 (len 2), fetch para0
    p.call("ED_END")               # to end of "AAAA" (FETCHPARA homes the cursor)
    typ(p, "XXXXXX")               # para0 now 10 bytes -- won't fit its slot
    p.call("ED_DOWN")              # store para0 -> new 10-byte slot; old slot dead
    return p


def test_grow_abandons_old_slot():
    p = _make_dead_space(setup())
    # live document is 12 bytes, but HEAPTOP has advanced past 16 (4 dead).
    assert used(p) == 12
    assert heaptop(p) - TEXTHEAP == 16


def test_compact_reclaims_and_preserves():
    p = _make_dead_space(setup())
    p.call("HEAP_COMPACT")
    assert heaptop(p) - TEXTHEAP == 12          # dead 4 bytes reclaimed
    assert paras(p) == ["AAAAXXXXXX", "BB"]    # content intact after relocation


def test_compact_is_idempotent():
    p = _make_dead_space(setup())
    p.call("HEAP_COMPACT")
    top1 = heaptop(p)
    p.call("HEAP_COMPACT")                      # already packed -- no change
    assert heaptop(p) == top1
    assert paras(p) == ["AAAAXXXXXX", "BB"]


# ---- allocation near the ceiling compacts instead of failing --------

def test_alloc_compacts_when_nearly_full():
    p = _make_dead_space(setup())               # DOCLINE=1 ("BB" live), 4 dead bytes
    p.poke("RETCODE", 0)
    p.poke16("HEAPTOP", HEAP_LIMIT - 3)         # only 3 bytes above the tip
    p.call("ED_END")                            # to end of "BB"
    typ(p, "YYYY")                              # grow "BB" -> "BBYYYY" (needs 6)
    p.call("ED_UP")                            # store "BBYYYY": raw alloc fails -> compact
    assert p.peek("RETCODE") != 0x80           # not ERR_DOCFULL: compaction rescued it
    assert paras(p) == ["AAAAXXXXXX", "BBYYYY"]
    assert heaptop(p) - TEXTHEAP == 16         # 10 + 6, packed with no dead space
