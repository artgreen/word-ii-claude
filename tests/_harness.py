"""Shared test harness for Word II unit tests (py65 tier).

Loads the real merlin32-built binary and drives its routines by symbol name.
The py65-backed simulator core is vendored in tests/vendor/ (sim.py +
harness.py); the only external dependency is the `py65` package
(`pip install py65`).

Note: py65 is a flat-64K 6502 model with no Apple II aux-memory banking, so
screen *rendering* (which depends on main/aux banking) is verified in microM8,
not here. This tier covers pure computation: the document model, cursor/edit
logic, search, reflow, and MLI wrappers against a faked MLI.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")
if VENDOR not in sys.path:
    sys.path.insert(0, VENDOR)

import sim  # noqa: E402

BIN = os.path.join(ROOT, "build", "WORDII.SYSTEM")
SYMS = os.path.join(ROOT, "build", "WORDII.SYSTEM_Symbols.txt")


def program():
    """A fresh Program with the current build loaded at $2000, 65C02 core."""
    if not os.path.exists(BIN):
        raise SystemExit("build/WORDII.SYSTEM missing — run scripts/build.sh first")
    return sim.Program(BIN, SYMS, org=0x2000, cpu="65c02")
