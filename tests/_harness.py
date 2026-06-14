"""Shared test harness for Word II unit tests (py65 tier).

Loads the real merlin32-built binary and drives its routines by symbol name,
per the 6502-testing skill. The 6502-codegen skill owns the py65 core; this
just wires sim.py to our build artifacts.

Note: py65 is a flat-64K 6502 model with no Apple II aux-memory banking, so
screen *rendering* (which depends on main/aux banking) is verified in microM8,
not here. This tier covers pure computation: the document model, cursor/edit
logic, search, reflow, and MLI wrappers against a faked MLI.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILL = "/Users/green/Documents/agent-skills/6502-testing/scripts"
if SKILL not in sys.path:
    sys.path.insert(0, SKILL)

import sim  # noqa: E402

BIN = os.path.join(ROOT, "build", "WORDII.SYSTEM")
SYMS = os.path.join(ROOT, "build", "WORDII.SYSTEM_Symbols.txt")


def program():
    """A fresh Program with the current build loaded at $2000, 65C02 core."""
    if not os.path.exists(BIN):
        raise SystemExit("build/WORDII.SYSTEM missing — run scripts/build.sh first")
    return sim.Program(BIN, SYMS, org=0x2000, cpu="65c02")
