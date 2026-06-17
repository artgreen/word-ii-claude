#!/usr/bin/env python3
"""Symbol-driven py65 harness for whole-program unit testing.

Loads a real merlin32-built binary, then calls its individual routines by
name (from the -V symbol file), poking program state in and asserting on
memory/registers out. Stub ROM entry points and fake the ProDOS MLI so
logic that calls them runs in the simulator.

It rides on the py65-backed CPU core in the sibling `harness.py` (vendored
beside this file). Requires the `py65` package: `pip install py65`.

    import sim
    h = sim.Program("build/MYPROG", "build/MYPROG_Symbols.txt", org=0x801)
    h.stub_rom("BELL1")              # JSR BELL1 -> count a beep, RTS
    h.fake_mli()                     # MLI at $BF00 logs calls, returns ok
    h.poke16("GAPS", h.sym("TEXTBUF"))
    h.call("INITST")                 # run a routine to its RTS
    assert h.peek(h.sym("MODE")) == 0

Build the binary and its symbol file with:  merlin32 -V <lib> prog.s
"""
import os
import sys
import importlib


def _scripts_dir(path):
    path = os.path.expanduser(path)
    if os.path.basename(path) == "scripts":
        return path
    return os.path.join(path, "scripts")


def _candidate_codegen_dirs():
    # harness.py is vendored beside this file.
    yield os.path.dirname(os.path.realpath(__file__))
    env = os.environ.get("CODEGEN_DIR")
    if env:
        yield _scripts_dir(env)


def _load_harness():
    tried = []
    for cg in dict.fromkeys(_candidate_codegen_dirs()):
        tried.append(cg)
        if not os.path.exists(os.path.join(cg, "harness.py")):
            continue
        if cg not in sys.path:
            sys.path.insert(0, cg)
        try:
            return importlib.import_module("harness")
        except RuntimeError as e:
            raise SystemExit(f"found harness at {cg!r}, but {e}")
        except ImportError:
            continue
    raise SystemExit(
        "cannot import the py65 harness (harness.py). Tried: "
        + ", ".join(repr(p) for p in tried)
        + ". It should sit beside this file in tests/vendor/.")


def load_symbols(path):
    """Parse a merlin32 -V '<DSK>_Symbols.txt' into {name: address}."""
    syms = {}
    with open(path) as f:
        for line in f:
            p = line.rstrip("\n").split(";")
            if len(p) < 6 or p[0] == "Segment Name":
                continue
            addr, name = p[4], p[5]
            if "/" in addr:                    # "00/1C8D"
                syms[name] = int(addr.split("/")[1], 16)
    return syms


class Program:
    """A loaded binary plus its symbol table, runnable in py65."""

    SENTINEL_BEEP = 0xBFF0             # default stub-ROM counter cell
    MLI_LOG = 0xBFD0                   # fake-MLI: count, then call numbers

    def __init__(self, binpath, sympath, org=0x801, cpu="nmos"):
        self.h = _load_harness()
        self.mpu, _ = self.h._make(cpu)
        self.syms = load_symbols(sympath)
        self.org = org
        data = open(binpath, "rb").read()
        for i, b in enumerate(data):
            self.mpu.memory[org + i] = b
        self.size = len(data)

    # ---- symbols ---------------------------------------------------
    def sym(self, name):
        return self.syms[name]

    # ---- memory ----------------------------------------------------
    def peek(self, where):
        return self.mpu.memory[self._addr(where)]

    def poke(self, where, value):
        self.mpu.memory[self._addr(where)] = value & 0xFF

    def peek16(self, where):
        a = self._addr(where)
        return self.mpu.memory[a] | (self.mpu.memory[a + 1] << 8)

    def poke16(self, where, value):
        a = self._addr(where)
        self.mpu.memory[a] = value & 0xFF
        self.mpu.memory[a + 1] = (value >> 8) & 0xFF

    def read(self, where, n):
        a = self._addr(where)
        return bytes(self.mpu.memory[a:a + n])

    def write(self, where, data):
        a = self._addr(where)
        for i, b in enumerate(data):
            self.mpu.memory[a + i] = b

    def _addr(self, where):
        return self.syms[where] if isinstance(where, str) else where

    # ---- execution -------------------------------------------------
    def call(self, name, a=None, x=None, y=None, max_steps=2_000_000):
        """Run routine `name` to its RTS. Pass a/x/y to seed registers;
        omit one to leave it as-is. Returns the machine (regs live)."""
        if a is not None:
            self.mpu.a = a
        if x is not None:
            self.mpu.x = x
        if y is not None:
            self.mpu.y = y
        if not self.h.run(self.mpu, self._addr(name), max_steps):
            raise AssertionError(f"{name} did not RTS within {max_steps} steps")
        return self.mpu

    # ---- fakes -----------------------------------------------------
    def stub_rom(self, name, counter=None):
        """Replace a ROM entry with `INC counter / RTS` so a JSR to it is
        observable and side-effect-free. Defaults to the beep counter."""
        if counter is None:
            counter = self.SENTINEL_BEEP
        a = self._addr(name)
        self.mpu.memory[a:a + 4] = [0xEE, counter & 0xFF, counter >> 8, 0x60]
        self.mpu.memory[counter] = 0

    def beeps(self):
        return self.mpu.memory[self.SENTINEL_BEEP]

    def fake_mli(self, base=0xBF00):
        """Install a logging ProDOS MLI gate: it records each call number
        at MLI_LOG+1.. (count at MLI_LOG), skips the inline DFB/DA, and
        returns success (carry clear, A=0). Uses ZP $F0/$F1."""
        code = [
            0x68, 0x85, 0xF0,        # pla / sta $F0    (return addr lo)
            0x68, 0x85, 0xF1,        # pla / sta $F1    (return addr hi)
            0xA0, 0x01, 0xB1, 0xF0,  # ldy #1 / lda ($F0),y   = call number
            0xEE, self.MLI_LOG & 0xFF, self.MLI_LOG >> 8,        # inc count
            0xAC, self.MLI_LOG & 0xFF, self.MLI_LOG >> 8,        # ldy count
            0x99, self.MLI_LOG & 0xFF, self.MLI_LOG >> 8,  # sta MLI_LOG,y
            0x18, 0xA5, 0xF0, 0x69, 0x03, 0xAA,   # clc/lda $F0/adc #3/tax
            0xA5, 0xF1, 0x69, 0x00, 0x48,         # lda $F1/adc #0/pha
            0x8A, 0x48,              # txa / pha   (push fixed-up return addr)
            0xA9, 0x00, 0x18, 0x60,  # lda #0 / clc / rts  (success)
        ]
        for i, b in enumerate(code):
            self.mpu.memory[base + i] = b
        self.mpu.memory[self.MLI_LOG] = 0

    def mli_calls(self):
        n = self.mpu.memory[self.MLI_LOG]
        return list(self.mpu.memory[self.MLI_LOG + 1:self.MLI_LOG + 1 + n])

    # ---- text screen ----------------------------------------------
    @staticmethod
    def rowbase(r):
        return 0x400 + (r % 8) * 0x80 + (r // 8) * 0x28

    def row(self, r, plain=True):
        """Decode a text-page row. plain=True strips high bits to ASCII."""
        base = self.rowbase(r)
        out = []
        for c in self.mpu.memory[base:base + 40]:
            if c >= 0xA0:
                out.append(chr(c & 0x7F))
            elif plain:
                out.append(chr((c & 0x3F) + 0x40)
                           if (c & 0x3F) < 0x20 else chr(c & 0x7F))
            else:
                out.append(chr((c & 0x3F) + 0x40))
        return "".join(out)


if __name__ == "__main__":
    # Smoke test: assemble a tiny routine, load it, drive it by symbol.
    import tempfile
    h = _load_harness()
    src = ["INCIT    INC   COUNT", "         RTS", "COUNT    DFB   0"]
    code, syms, _ = h.assemble(src, 0x300)
    # write it out as a raw binary + a fake symbol file, then reload
    lo = min(code)
    blob = bytes(code.get(lo + i, 0) for i in range(max(code) - lo + 1))
    with tempfile.TemporaryDirectory() as d:
        bp = os.path.join(d, "T")
        sp = os.path.join(d, "T_Symbols.txt")
        open(bp, "wb").write(blob)
        with open(sp, "w") as f:
            f.write("Segment Name;..;..;..;Address;Name;..\n")
            for nm, ad in syms.items():
                f.write(f"Seg;1;t;1;00/{ad:04X};{nm};Code\n")
        prog = Program(bp, sp, org=lo)
        before = prog.peek("COUNT")
        prog.call("INCIT")
        assert prog.peek("COUNT") == before + 1, "INC did not run"
        print("sim.py smoke test OK: INCIT incremented COUNT")
