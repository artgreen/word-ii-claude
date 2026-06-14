# Word II — Memory Map

The single authoritative record of who owns what. `src/zp.s` and `src/const.s`
must match this file; if they diverge, this file is the intent and the code is
the bug. Addresses are hex.

## Target environment facts

- ProDOS 8 SYS program: loads at `$2000`, entered by `JMP $2000`.
- ProDOS lives in the language card (`$D000-$FFFF` banked) + global page
  `$BF00-$BFFF`; MLI gate at `$BF00`. Main RAM `$0800-$BEFF` is ours.
- 64K aux RAM mirrors `$0000-$BFFF`. We use the aux **`$0800-$BEFF`** window for
  the document heap. Aux `$0400-$07FF` is the 80-col display's even columns and
  is off-limits to the heap.

## Zero page

Only `$06-$09` are free on every Apple II setup. Because Word II writes the
screen with its **own** driver and never calls the monitor's COUT/GETLN/text
routines, the monitor's ZP (`$20-$4F` text window/cursor, `$36-$39` CSW/KSW) is
free for us — **except** `$40-$4F`, which **ProDOS MLI uses as scratch and may
clobber across any MLI call**. We therefore treat `$40-$4F` as volatile and keep
no persistent state there. `$45` is additionally trashed by the ROM IRQ path.

| Range | Owner | Notes |
|-------|-------|-------|
| `$00-$05` | reserved/system | left alone (various ROM/ProDOS uses) |
| `$06-$0F` | Word II pointers | `PTR0..PTR4` general 16-bit pointers (5×2) |
| `$10-$1F` | Word II pointers | `SCRPTR` (screen base), `SRCPTR`, `DSTPTR`, `AUXPTR`, `TMPPTR` (16-bit each) |
| `$20-$2F` | Word II state | cursor row/col, viewport top line, scratch bytes |
| `$30-$3F` | Word II state | doc line index (cur line 16-bit), col-in-line 16-bit, counters, flags |
| `$40-$4F` | **ProDOS MLI** | volatile — never persist anything here |
| `$50-$5F` | Word II scratch | safe again below MLI block; loop temporaries |
| `$60-$FF` | reserved | avoid; some setups/firmware use the upper ZP. Not claimed. |

`zp.s` is the contract. Every label there has a one-line comment and falls in a
range above.

## Page 1 / 2 / 3

| Range | Use |
|-------|-----|
| `$0100-$01FF` | 6502 stack (reset to `$FF` at entry) |
| `$0200-$02FF` | Word II line-input scratch (we don't use ROM GETLN) |
| `$0300-$03EF` | Word II small scratch / mouse jump table |
| `$03F0-$03FF` | system vectors: BRK `($03F0)`, RESET `($03F2/$3)` + `$3F4` powerup byte, IRQ `($03FE)` |

We set `$03F2/$03F3` (RESET) to `RESET_ENTRY` and update the `$3F4` checksum so
Ctrl-Reset repaints the UI instead of dropping to BASIC/monitor.

## Main RAM `$0400-$BEFF`

As implemented (constants in `src/const.s`):

| Range | Size | Use |
|-------|------|-----|
| `$0400-$07FF` | 1K | **80-col text screen, main half** (odd columns 1,3,5,…79) |
| `$0800-$0BFF` | 1K | ProDOS I/O buffer **A** (`IOBUF_A`: open document or directory file) |
| `$0C00-$0FFF` | 1K | ProDOS I/O buffer **B** (`IOBUF_B`); reused as the picker's name list while a directory is open |
| `$1000-$13FF` | 1K | **Clipboard** (`CLIPBUF`, `CLIPMAX`=1024) |
| `$1400-$17FF` | 1K | **Undo** snapshot of the current paragraph (`UNDOBUF`, one level) |
| `$1800-$1BFF` | 1K | **Render scratch** (`RENDBUF`: materialized current paragraph; also the 512-byte directory block during the picker) |
| `$1C00-$1FFF` | 1K | **Edit buffer** (`EDITBUF`, `EDITMAX`=1024) — the current-paragraph gap buffer |
| `$2000-(code end)` | ~10K | **Program code** (all modules), grows up; ends ~`$4Fxx` |
| `$6000-$6FFF` | 4K | **Line table** (`LINETBL`): 1024 paragraph records of `{loc(2),len(2)}` |
| `$7000-$BEFF` | ~20K | **Text heap** (`TEXTHEAP`): paragraph bytes, bump-allocated (`HEAPTOP` = tip) |

Free-memory display (status line) = `HEAP_LIMIT - HEAPTOP` (remaining text-heap
bytes). Note the text heap is in **main** RAM in M0–M4; the M5 design moves it
to the aux window below for far larger documents (the line-table `loc` field is
already a location tag for that).

## Aux RAM

Accessed via `AUXMOVE` (`$C311`) block copies (A1=`$3C/$3D` src,
A2=`$3E/$3F` end, A4=`$42/$43` dst; C set = main→aux, clear = aux→main).
`80STORE` is turned **off** around `AUXMOVE` so the display windows don't
override the move (Apple IIe TN #3). We never run code with `RAMRD` on.

| Range (aux) | Use |
|-------------|-----|
| `$0000-$01FF` | aux ZP/stack — untouched (we keep `ALTZP` off) |
| `$0200-$03FF` | free aux scratch (small) |
| `$0400-$07FF` | **80-col display even columns** (cols 0,2,4,…78) — off-limits |
| `$0800-$BEFF` | **Document paragraph heap** (~46 KB). `HEAPTOP` = bump tip. |

## /RAM scratch (M5)

`/RAM` appears at slot 3, drive 2 when present. Word II probes it with MLI
`ONLINE`/`GET_FILE_INFO`. Layout when used:

- `/RAM/WORDII.PAGE` — overflow paragraph store (spilled when aux heap is full).
- Absent → capacity capped at aux+main, status shows `/RAM:none`.
- Full/too-small → spill fails gracefully; the offending edit is refused with an
  alert, document integrity preserved; status shows `/RAM:full`.

## Why not a whole-document aux gap buffer?

A single contiguous gap buffer spanning aux would need byte shifts performed
*in aux*. But `RAMRD`/`RAMWRT` bank all of `$0200-$BFFF`, including the page our
code executes from — turning `RAMRD` on makes the CPU fetch instructions from
aux and crash. Block moves must therefore go through the ROM `AUXMOVE` mover (or
run shift code from the language card). The paragraph-heap + main-edit-buffer
model confines all aux traffic to `AUXMOVE` block copies and keeps every byte
shift in main RAM, which is both safe and simpler to test.
