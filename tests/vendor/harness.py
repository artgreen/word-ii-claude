"""
6502 / 65C02 assemble-and-run harness (vendored).

Purpose: let a caller VERIFY a generated routine instead of trusting it.
Assembles a Merlin-style *subset* (see "Assembler scope" below), runs it in a
real 6502/65C02 simulator (py65), and checks memory / registers / flags against
expected values.

Dependency: py65. Install in an isolated environment:
    python3 -m venv .venv && . .venv/bin/activate && pip install py65
  or user-site (no venv):
    python3 -m pip install --user py65

CPU cores that actually EXECUTE here:
    cpu="nmos"  (alias "6502")            -> NMOS 6502
    cpu="65c02" (alias "c02"/"rockwell")  -> WDC/Rockwell 65C02 (incl. RMB/SMB)
  py65 has no 65816 core. For 816 *8-bit* code that stays inside the 65C02
  instruction set, use cpu="65c02". Native-mode 816 ops (REP/SEP/16-bit/long/
  MVN/MVP/...) and the CMOS ops BBR/BBS/STP cannot be assembled here. WAI
  assembles but parks the CPU waiting for an interrupt the harness cannot
  inject, so it never reaches RTS. All of these must be paper-verified.

Assembler scope (what the parser/assembler accepts):
  - instructions for the selected CPU, operands resolved through symbols;
  - labels: column-1 global (FOO or FOO:), Merlin local (:LOOP), or a label
    sharing a line with an instruction (":DPOS  TAX");
  - directives: EQU / = , DFB / DB , DA / DW , DDB , DS , HEX;
  - literals: $hex, %binary, 0xhex, decimal;
  - expression operators: + - , unary < (low byte) and > (high byte),
    and parentheses, e.g.  DFB <(HAND0-1),>(HAND0-1).
  NOT supported (paper-territory): macros, conditional assembly, ORG/PUT/SAV,
  string/ASCII directives. Labels are a single flat namespace; reusing a local
  name (two :LOOP) raises.
"""
import re

try:
    from py65.devices.mpu6502 import MPU as _MPU_NMOS
    from py65.devices.mpu65c02 import MPU as _MPU_65C02
    from py65.assembler import Assembler as _Assembler
except ImportError as _e:  # pragma: no cover - environment guard
    raise RuntimeError(
        "py65 is required but not installed. Install it in an isolated env:\n"
        "    python3 -m venv .venv && . .venv/bin/activate && pip install py65\n"
        "  or user-site (no venv):\n"
        "    python3 -m pip install --user py65"
    ) from _e

# Backward-compatible default core (NMOS). harness.MPU() still works.
MPU = _MPU_NMOS

_CORES = {
    "nmos": _MPU_NMOS, "6502": _MPU_NMOS, "nmos6502": _MPU_NMOS,
    "65c02": _MPU_65C02, "c02": _MPU_65C02, "65c02s": _MPU_65C02,
    "rockwell": _MPU_65C02, "wdc": _MPU_65C02, "wdc65c02": _MPU_65C02,
}
_NO_CORE_816 = {"816", "65816", "65c816", "w65c816"}


def _make(cpu):
    """Return (mpu, assembler) for a CPU name."""
    key = (cpu or "nmos").strip().lower()
    if key in _NO_CORE_816:
        raise ValueError(
            "no 65816 core in py65. For 816 8-bit code within the 65C02 "
            "instruction set use cpu='65c02'; paper-verify native-816 ops.")
    if key not in _CORES:
        raise ValueError("unknown cpu %r; use one of %s"
                         % (cpu, sorted(set(_CORES))))
    mpu = _CORES[key]()
    return mpu, _Assembler(mpu)


# Generic workspace symbols (mirror references/6502_reference.md, Section 3).
SYM = {
    'ZP_PTR': 0x00, 'ZP_PTR2': 0x02, 'ZP_TMP': 0x04, 'ZP_TMP2': 0x05,
    'ZP_COUNT': 0x06, 'ZP_STATE': 0x07, 'ZP_SAVEA': 0x08, 'ZP_SAVEX': 0x09,
    'ZP_SAVEY': 0x0A,
    'WORKBUF': 0x2000, 'WORKBUF2': 0x2100, 'CODEBUF': 0x3000, 'TABLE': 0x4000,
    'SQLO': 0x4000, 'SQHI': 0x4200,   # quarter-square tables (T34)
}

_MNEMONICS = set("""
ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRA BRK BVC BVS CLC CLD CLI CLV CMP
CPX CPY DEC DEA DEX DEY EOR INC INA INX INY JMP JSR LDA LDX LDY LSR NOP ORA
PHA PHP PHX PHY PLA PLP PLX PLY ROL ROR RTI RTS SBC SEC SED SEI STA STP STX
STY STZ TAX TAY TRB TSB TSX TXA TXS TYA WAI
""".split())
for _i in range(8):
    for _m in ("RMB", "SMB", "BBR", "BBS"):
        _MNEMONICS.add("%s%d" % (_m, _i))

_DIRECTIVES = {'EQU', '=', 'DFB', 'DB', 'DA', 'DW', 'DDB', 'DS', 'HEX'}


# ---------------------------------------------------------------- expressions
def _eval(expr, syms):
    """Evaluate a Merlin-subset expression to an int.

    Supports: symbols, $hex, %bin, 0xhex, decimal, + - , parentheses, and the
    unary prefix < (low byte) / > (high byte).
    """
    s = str(expr).strip()
    if s == '':
        raise ValueError("empty expression")
    if s[0] == '<':
        return _eval(s[1:], syms) & 0xFF
    if s[0] == '>':
        return (_eval(s[1:], syms) >> 8) & 0xFF
    tokens, buf, depth = [], '', 0
    for ch in s:
        if ch == '(':
            depth += 1; buf += ch
        elif ch == ')':
            depth -= 1; buf += ch
        elif ch in '+-' and depth == 0 and buf.strip() != '':
            tokens.append(buf); tokens.append(ch); buf = ''
        else:
            buf += ch
    tokens.append(buf)
    val = _term(tokens[0], syms)
    i = 1
    while i < len(tokens):
        op = tokens[i].strip()
        rhs = _term(tokens[i + 1], syms)
        val = val + rhs if op == '+' else val - rhs
        i += 2
    return val


def _term(t, syms):
    t = str(t).strip()
    if t == '':
        raise ValueError("empty term in expression")
    if t[0] == '<':
        return _eval(t[1:], syms) & 0xFF
    if t[0] == '>':
        return (_eval(t[1:], syms) >> 8) & 0xFF
    if t[0] == '-':
        return -_term(t[1:], syms)
    if t[0] == '(' and t[-1] == ')':
        return _eval(t[1:-1], syms)
    if re.match(r'^:?[A-Za-z_][\w]*$', t):
        return syms[t]
    if t[0] == '$':
        return int(t[1:], 16)
    if t[0] == '%':
        return int(t[1:], 2)
    if t[:2].lower() == '0x':
        return int(t, 16)
    return int(t, 10)


_val = _eval  # backwards-compatible alias


def _resolve(op, syms):
    """Turn a Merlin operand into a py65-acceptable operand string."""
    op = op.strip()
    if op == '' or op.upper() == 'A':
        return op
    if op.startswith('#'):
        return '#$%02X' % (_eval(op[1:], syms) & 0xFF)
    m = re.match(r'^\((.+)\),Y$', op, re.I)
    if m:
        return '($%02X),Y' % (_eval(m.group(1), syms) & 0xFF)
    m = re.match(r'^\((.+),X\)$', op, re.I)
    if m:
        return '($%02X,X)' % (_eval(m.group(1), syms) & 0xFF)
    m = re.match(r'^\((.+)\)$', op)
    if m:
        v = _eval(m.group(1), syms)
        return ('($%04X)' % v) if v >= 256 else ('($%02X)' % v)
    m = re.match(r'^(.+),([XYxy])$', op)
    if m:
        v = _eval(m.group(1), syms)
        idx = m.group(2).upper()
        return ('$%04X,%s' % (v, idx)) if v >= 256 else ('$%02X,%s' % (v, idx))
    v = _eval(op, syms)
    return ('$%04X' % v) if v >= 256 else ('$%02X' % v)


# --------------------------------------------------------------------- parsing
def _parse_line(raw):
    """Return (label_or_None, instruction_or_None)."""
    s = raw.split(';')[0].rstrip()
    if not s.strip():
        return (None, None)
    if s[0].isspace():
        return (None, s.strip())
    parts = s.split(None, 1)
    first = parts[0]
    rest = parts[1].strip() if len(parts) > 1 else ''
    if first.endswith(':'):
        return (first[:-1], rest or None)
    if first.startswith(':'):
        return (first, rest or None)
    if first.upper() in _MNEMONICS or first.upper() in _DIRECTIVES:
        return (None, s.strip())
    return (first, rest or None)


def _split_instr(instr):
    parts = instr.split(None, 1)
    mn = parts[0]
    op = parts[1] if len(parts) > 1 else ''
    return mn, op


def _items(op):
    return [x for x in op.split(',') if x.strip() != '']


def _hex_bytes(op):
    """Parse a Merlin HEX operand into bytes; reject an odd nibble count so
    sizing (pass 1) and emission (pass 2) can never disagree."""
    h = re.sub(r'[^0-9A-Fa-f]', '', op)
    if len(h) % 2:
        raise ValueError("HEX needs an even number of hex digits: %r" % op)
    return [int(h[i:i + 2], 16) for i in range(0, len(h), 2)]


def _dir_size(U, op, syms):
    if U in ('EQU', '='):
        return 0
    if U in ('DFB', 'DB'):
        return len(_items(op))
    if U in ('DA', 'DW', 'DDB'):
        return 2 * len(_items(op))
    if U == 'DS':
        return _eval(_items(op)[0], syms)
    if U == 'HEX':
        return len(_hex_bytes(op))
    raise ValueError("unknown directive %s" % U)


def _emit_dir(U, op, syms):
    out = []
    if U in ('DFB', 'DB'):
        for it in _items(op):
            out.append(_eval(it, syms) & 0xFF)
    elif U in ('DA', 'DW'):
        for it in _items(op):
            w = _eval(it, syms) & 0xFFFF
            out.append(w & 0xFF); out.append((w >> 8) & 0xFF)
    elif U == 'DDB':
        for it in _items(op):
            w = _eval(it, syms) & 0xFFFF
            out.append((w >> 8) & 0xFF); out.append(w & 0xFF)
    elif U == 'DS':
        parts = op.split(',')
        n = _eval(parts[0], syms)
        fill = _eval(parts[1], syms) & 0xFF if len(parts) > 1 and parts[1].strip() else 0
        out.extend([fill] * n)
    elif U == 'HEX':
        out.extend(_hex_bytes(op))
    return out


_BRANCHES = {'BCC', 'BCS', 'BEQ', 'BMI', 'BNE', 'BPL', 'BVC', 'BVS', 'BRA'}


def _parse_records(program):
    """Parse each source line once into a record used by both passes."""
    recs = []
    for raw in program:
        label, instr = _parse_line(raw)
        rec = {'label': label, 'instr': instr, 'raw': raw,
               'mn': None, 'op': None, 'U': None,
               'is_equ': False, 'is_dir': False, 'is_instr': False}
        if instr is not None:
            mn, op = _split_instr(instr)
            U = mn.upper()
            rec['mn'], rec['op'], rec['U'] = mn, op, U
            if U in ('EQU', '='):
                rec['is_equ'] = True
            elif U in _DIRECTIVES:
                rec['is_dir'] = True
            else:
                rec['is_instr'] = True
        recs.append(rec)
    return recs


def assemble(program, origin, cpu="nmos"):
    """Assemble source lines for `cpu`. Returns ({addr: byte}, syms, end_addr).

    Sizing and emission share ONE symbol table that is iterated to a fixed
    point, so each instruction is sized with the same operand value it is later
    emitted with. This prevents phase errors from forward / zero-page EQUs:
    e.g. `LDA FOO` with `FOO EQU $10` declared later would otherwise be sized
    absolute (3 bytes) but emitted zero-page (2 bytes), shifting every label and
    branch target after it. Relative branches are always sized as 2 bytes so an
    unresolved forward target never trips the assembler during sizing.
    """
    mpu, asm = _make(cpu)
    recs = _parse_records(program)

    class _D(dict):
        def __missing__(self, k):
            return 0x0300

    # collect + validate labels and EQU definitions (source order preserved)
    defined = set()
    equ = []
    for rec in recs:
        lab = rec['label']
        if rec['is_equ']:
            if lab is None:
                raise ValueError("EQU/= needs a label: %r" % rec['raw'])
            if lab in defined:
                raise ValueError("duplicate label: %r" % lab)
            defined.add(lab)
            equ.append((lab, rec['op']))
        elif lab is not None:
            if lab in defined:
                raise ValueError("duplicate label: %r" % lab)
            defined.add(lab)

    syms = dict(SYM)

    def _resolve_equ():
        for _ in range(len(equ) + 1):
            changed = False
            for lab, expr in equ:
                try:
                    v = _eval(expr, syms)
                except KeyError:
                    continue
                if syms.get(lab) != v:
                    syms[lab] = v
                    changed = True
            if not changed:
                break

    def _size_pass():
        pc = origin
        for rec in recs:
            if rec['is_equ']:
                continue
            if rec['label'] is not None:
                syms[rec['label']] = pc
            if rec['is_dir']:
                pc += _dir_size(rec['U'], rec['op'], _D(syms))
            elif rec['is_instr']:
                if rec['U'] in _BRANCHES:
                    pc += 2
                else:
                    rop = _resolve(rec['op'], _D(syms))
                    pc += len(asm.assemble((rec['mn'] + ' ' + rop).strip(), pc))
        return pc

    # iterate EQU resolution + sizing until the symbol table stops moving
    prev = None
    for _ in range(16):
        _resolve_equ()
        _size_pass()
        _resolve_equ()
        snap = dict(syms)
        if snap == prev:
            break
        prev = snap
    else:
        raise ValueError("assembly did not converge (phase error / unresolved "
                         "forward reference?)")
    for lab, expr in equ:
        if lab not in syms:
            raise ValueError("cannot resolve EQU %s = %r" % (lab, expr))

    # emission pass with the converged symbol table
    out = {}
    pc = origin
    for rec in recs:
        if rec['is_equ'] or rec['instr'] is None:
            continue
        if rec['is_dir']:
            for b in _emit_dir(rec['U'], rec['op'], syms):
                out[pc] = b
                pc += 1
        else:
            rop = _resolve(rec['op'], syms)
            b = list(asm.assemble((rec['mn'] + ' ' + rop).strip(), pc))
            for i, by in enumerate(b):
                out[pc + i] = by
            pc += len(b)
    return out, syms, pc


def load(mpu, code):
    for a, b in code.items():
        mpu.memory[a] = b


def make_tables(mpu, base_lo=0x4000, base_hi=0x4200):
    """Fill the quarter-square tables floor(n^2/4) for T34 (MUL_QS)."""
    for n in range(512):
        q = (n * n) // 4
        mpu.memory[base_lo + n] = q & 0xFF
        mpu.memory[base_hi + n] = (q >> 8) & 0xFF


_SENTINEL = 0x8000


def run(mpu, start, max_steps=1000):
    """Run from `start`; return True if it RTS'd back to the sentinel in budget.

    Note: the runner controls PC and SP (it seeds a sentinel return address), so
    setting PC/SP as a case input has no effect; set A/X/Y/P and flags instead.
    """
    mpu.pc = start
    mpu.sp = 0xFF
    ret = _SENTINEL - 1
    mpu.memory[0x0100 + mpu.sp] = (ret >> 8) & 0xFF
    mpu.sp = (mpu.sp - 1) & 0xFF
    mpu.memory[0x0100 + mpu.sp] = ret & 0xFF
    mpu.sp = (mpu.sp - 1) & 0xFF
    for _ in range(max_steps):
        if mpu.pc == _SENTINEL:
            return True
        mpu.step()
        if getattr(mpu, 'waiting', False):
            return False  # hit WAI; run_cases reports this distinctly
    return False


def s8(b):
    return b - 256 if b >= 128 else b


def s16(w):
    return w - 65536 if w >= 32768 else w


# ------------------------------------------------------- set/expect key kinds
_FLAG_BITS = {
    'C': 0x01, 'Z': 0x02, 'I': 0x04, 'D': 0x08, 'B': 0x10, 'V': 0x40, 'N': 0x80,
    'CARRY': 0x01, 'ZERO': 0x02, 'INTERRUPT': 0x04, 'DECIMAL': 0x08,
    'BREAK': 0x10, 'OVERFLOW': 0x40, 'NEGATIVE': 0x80,
}
_REGS = {'A', 'X', 'Y', 'SP', 'S', 'PC', 'P'}


def _word(v):
    if isinstance(v, bool):
        return int(v)
    if isinstance(v, int):
        return v
    v = str(v).strip()
    if v.startswith('$'):
        return int(v[1:], 16)
    if v.lower().startswith('0x'):
        return int(v, 0)
    if v.startswith('%'):
        return int(v[1:], 2)
    return int(v, 0)


def _byteval(v):
    return _word(v) & 0xFF


def _addr(k):
    """Accept int, '0x..', '$..', decimal string, or a SYM/expr name."""
    if isinstance(k, int):
        return k
    k = str(k).strip()
    if k.startswith('$'):
        return int(k[1:], 16)
    if k.lower().startswith('0x'):
        return int(k, 0)
    if re.match(r'^:?[A-Za-z_]', k):
        return _eval(k, SYM)
    return int(k, 0)


def _flagval(v):
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, int):
        return 1 if v else 0
    s = str(v).strip().lower()
    if s in ('1', 'true', 'set', 'yes', 'on'):
        return 1
    if s in ('0', 'false', 'clear', 'no', 'off'):
        return 0
    return 1 if int(s, 0) else 0


def _key_kind(k):
    """Classify a set/expect key -> ('reg',NAME) | ('flag',MASK) | ('mem',ADDR)."""
    if isinstance(k, int):
        return ('mem', k)
    ks = str(k).strip()
    ku = ks.upper()
    if ku in _REGS:
        return ('reg', 'SP' if ku == 'S' else ku)
    if ku in _FLAG_BITS:
        return ('flag', _FLAG_BITS[ku])
    return ('mem', _addr(ks))


def _apply_set(mpu, k, v):
    kind, info = _key_kind(k)
    if kind == 'reg':
        val = _word(v)
        if info == 'A':
            mpu.a = val & 0xFF
        elif info == 'X':
            mpu.x = val & 0xFF
        elif info == 'Y':
            mpu.y = val & 0xFF
        elif info == 'SP':
            mpu.sp = val & 0xFF
        elif info == 'P':
            mpu.p = val & 0xFF
        elif info == 'PC':
            mpu.pc = val & 0xFFFF
    elif kind == 'flag':
        if _flagval(v):
            mpu.p |= info
        else:
            mpu.p &= (~info) & 0xFF
    else:
        mpu.memory[info] = _byteval(v)


def _check_expect(mpu, k, v):
    """Return a failure string, or None if the expectation holds."""
    kind, info = _key_kind(k)
    if kind == 'reg':
        want = _word(v)
        got = {'A': mpu.a, 'X': mpu.x, 'Y': mpu.y,
               'SP': mpu.sp, 'P': mpu.p, 'PC': mpu.pc}[info]
        if got != want:
            return "%s = $%02X, expected $%02X" % (info, got, want)
    elif kind == 'flag':
        want = _flagval(v)
        got = 1 if (mpu.p & info) else 0
        if got != want:
            return "flag %s = %d, expected %d" % (k, got, want)
    else:
        got = mpu.memory[info]
        want = _byteval(v)
        if got != want:
            return "mem[%s] = $%02X, expected $%02X" % (k, got, want)
    return None


def run_cases(program, origin, cases, cpu="nmos"):
    """
    cases: list of dicts, each:
      { "set":   {key: value, ...},   # initial conditions before running
        "tables": True|False,         # preload quarter-square tables (T34)
        "steps":  int,                # step budget (default 1000)
        "expect": {key: value, ...} } # required state after running
    A key is a memory address (int / "0x.." / "$.." / decimal / symbol like
    "ZP_PTR+1"), a register (A/X/Y/SP/P), or a flag (C/Z/I/D/V/N or
    carry/zero/decimal/...). PC/SP set is ignored (the runner owns them).
    Returns (all_passed, results) where results is a list of
      {"index", "passed", "failures":[...]} .
    """
    code, _, _ = assemble(program, origin, cpu)
    results = []
    all_ok = True
    for i, case in enumerate(cases):
        mpu, _ = _make(cpu)
        load(mpu, code)
        if case.get("tables"):
            make_tables(mpu)
        for k, v in case.get("set", {}).items():
            _apply_set(mpu, k, v)
        ret = run(mpu, origin, case.get("steps", 1000))
        fails = []
        if not ret:
            if getattr(mpu, 'waiting', False):
                fails.append("hit WAI: waiting for an interrupt this harness "
                             "cannot inject -- can't run to RTS (paper-verify "
                             "the WAI path against the reference)")
            else:
                fails.append("routine did not return within %d steps "
                             "(runaway/jam?)" % case.get("steps", 1000))
        for k, v in case.get("expect", {}).items():
            f = _check_expect(mpu, k, v)
            if f:
                fails.append(f)
        ok = not fails
        all_ok = all_ok and ok
        results.append({"index": i, "passed": ok, "failures": fails})
    return all_ok, results
