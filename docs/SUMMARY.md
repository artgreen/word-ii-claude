# Word II — Completion Summary

Status as of the M0–M4 + finalization pass.

## What works (and was verified)

Every item below is exercised by automated tests — py65 unit tests that drive
the **real assembled binary** by symbol name, and/or microM8 acceptance scripts
that boot the **generated disk** and drive it like a real Apple II. 60 unit
tests + 3 acceptance scripts, all green.

### Platform / boot (M0–M1)
- ProDOS 8 SYS program, ORG `$2000`, 65C02 only. Boots from the generated
  ProDOS disk and launches via `-WORDII.SYSTEM`. *(acceptance: m1_boot)*
- 80-column text driven directly to main+aux screen RAM (no firmware COUT for
  the UI). MouseText menu bar, full-height text viewport (rows 1–21), bottom
  border, status line, and a live scroll bar — all confirmed as real
  MouseText/inverse via the emulator's attribute grid. *(acceptance: m1_boot)*
- Ctrl-Reset re-enters cleanly (RESET vector installed).

### Editing core (M2)
- Document model: paragraph **line table** + **text heap** + current-paragraph
  **gap buffer** (O(1) insert/delete; not a single fragile buffer).
- Cursor by char/line/home/end and across paragraphs (up/down/left/right wrap);
  insert and overwrite modes; char delete; paragraph split (Return) and join
  (Backspace/Delete at boundaries). *(16 unit tests)*
- **Word wrap** at a configurable margin, greedy break at spaces, hard-break for
  over-long words. *(6 unit tests + emulator)*
- Viewport scrolling with ensure-visible; dirty tracking; live status
  (line:col, INS/OVR, modified `*`, free bytes).
- **Flicker-free compositing renderer** (build each row in RAM, blit once) with
  an **incremental** fast path that repaints only the cursor paragraph and below
  during typing. *(verified correct through navigation + mid-document edits)*

### ProDOS files (M3)
- MLI wrappers (OPEN/READ/WRITE/CLOSE/CREATE/DESTROY/RENAME/GET_FILE_INFO via
  GET/SET_EOF, ONLINE, GET/SET_PREFIX); never RWTS/raw blocks. *(unit-tested
  against a faked MLI for the call sequence)*
- TXT format: 7-bit ASCII, CR-delimited; high-bit translation only at the I/O
  boundary; load tolerates classic high-bit text. *(unit-tested parser +
  on-disk byte verification)*
- **Save / Open round-trip on a real ProDOS volume**: typed "HELLO WORLD"
  saved, reloaded, and the host disk image confirmed to hold the exact bytes.
- **Pull-down menus** (Esc, arrows, type-ahead) and **Open-Apple shortcuts**.
- **Modal dialogs**: alert, yes/no confirm, ProDOS-error alert with readable
  names, and a single-line filename field.
- **Scrolling directory picker** that reads a real ProDOS directory, lists the
  files, scrolls/type-aheads, and opens the selection. *(acceptance: m3_files —
  opens WELCOME.TXT via the picker and confirms its contents)*
- New, Open, Save, Save As, Close, Rename, Delete, Quit — all wired and working
  through the menu; prefix derived from the boot volume so bare names resolve.

### Editor features (M4)
- **Search / Find Next** (case-insensitive, wraps once). **Replace** with
  per-hit Yes/No/All/Esc. *(6 unit tests)*
- **Clipboard**: Copy/Cut the current line, Paste (splits on CR), Select All
  (serialize the document). *(unit-tested)*
- **Undo**: one level of in-paragraph edits, invalidated by navigation /
  structural ops. *(unit-tested)*
- **Reflow** (join hard-wrapped lines), **configurable margin**, and **soft
  tabs** to a configurable tab stop. *(wired + unit-tested helpers)*

## Bugs found and fixed during development

Systematic py65 + microM8 debugging caught several real defects (all fixed and
now regression-tested):
- Screen `PUTC`/`PRINTZ` pointer aliasing (garbled banner).
- Menu-title table indexed `*2` instead of `*1` (garbage menu).
- **Scratch-register aliasing** (a recurring class): `FILLSPAN` clobbering
  `DRAWBOX`'s width/height → runaway fill → crash; the menu command byte held in
  `TMPA` clobbered by `NUM2DEC` → every menu item ran "New"; `UNDO_CHECKPOINT`
  clobbering the character in A → every typed key inserted `$01`.
- Empty ProDOS prefix when launched as a SYS program → relative saves failed
  (now derived from the boot volume via ONLINE).
- Find not wrapping to a match before the cursor.

## 6502-review pass

A multi-agent static review (8 reviewers + adversarial verifiers over the whole
source tree) found **6 confirmed correctness bugs**, all since fixed and covered
by `tests/test_review_fixes.py`:

1. **Delete/Rename with an empty name** acted on a stale `PATHBUF` → could delete
   the currently-open file. (Now aborts on empty input.)
2. **Select All** had no `CLIPMAX` bound → overflowed `CLIPBUF` into live buffers
   on any document over 1 KB. (Now truncates at the clipboard limit.)
3. **Save** ignored a `STOREPARA` (heap-full) failure → reported success while
   dropping the current paragraph's edits. (Now aborts the save, file untouched.)
4. **Tab** in a full (1024-byte) paragraph at a non-aligned column hung forever.
   (Now stops when the paragraph can't grow.)
5. **Replace** inserted via `ED_INSERT`, which honored overwrite mode → ate the
   following text. (Now inserts via the pure-insert primitive.)
6. **Replace/skip** resumed at cursor+1 → missed adjacent overlapping matches.
   (Now resumes at the cursor and steps past the whole match.)

## What remains (honestly)

- **Large-document paging to aux / `/RAM` (M5).** The line-table/heap interface
  was designed for it (location-tagged entries; `FETCHPARA`/`STOREPARA` are the
  only heap-touching routines), but the heap currently lives in main RAM
  (~20 KB) and the aux/`/RAM` backing is **not yet wired** — oversized files are
  refused rather than paged.
- **Mouse support (M6).** Not wired. The editor is fully keyboard-operable (the
  required fallback); mouse is additive.
- **6502-optimization pass.** The review pass is done (6 bugs found and fixed,
  above); the incremental renderer is the main optimization so far, and further
  hot-path tuning (e.g. a faster `RB_PUT`) is future work.
- Still future work: multi-level undo; per-character cross-paragraph selection
  highlighting.

## How it was verified

- `tests/run_tests.py` — 60 py65 unit tests over the shipped binary.
- `tests/acceptance/*.sh` — microM8 boot-the-disk acceptance scripts.
- Manual microM8 sessions (screenshots in this repo and `/tmp`) for the UI,
  menus, dialogs, picker, and save/open round-trips, with byte-level
  verification of saved files via `cp2`.
