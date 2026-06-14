# Word II — Architecture

A ProDOS 8 word processor for the Enhanced Apple IIe / IIc / IIc+ / IIgs (8-bit).

## Target & constraints

- **CPU:** 65C02. The whole tree assembles with `XC` (65C02 opcodes:
  `STZ`, `BRA`, `PHX/PLX/PHY/PLY`, `INC A`, `(zp)`). No 65816 native mode, no
  undocumented opcodes. Runs on the IIgs only in 8-bit emulation mode.
- **OS:** ProDOS 8. The program is a ProDOS **SYS** file (`TYP $FF`), ORG `$2000`,
  launched by ProDOS like any system program. All disk access goes through the
  ProDOS **MLI** (`$BF00`) — never RWTS or raw block I/O for documents.
- **RAM:** ≥128K assumed (main + 64K aux). Degrades but still runs on 64K (no
  aux document heap → smaller capacity); always degrades gracefully if `/RAM`
  is missing/full/small.
- **Display:** 80-column text only, written **directly to screen RAM**
  (main `$0400-$07FF` odd columns, aux `$0400-$07FF` even columns). The
  standard 80-column character ROM + MouseText alternate set is the only font.
  No graphics modes, no printing.

## Process model

ProDOS loads `WORDII.SYSTEM` at `$2000` and `JMP $2000`. `START` (src/main.s):

1. Save the ProDOS unit we booted from (`$BF30` DEVNUM) for the default prefix.
2. Set up our zero page, clear decimal, reset the 6502 stack.
3. Bring up the 80-column screen driver and MouseText, paint the UI shell.
4. Detect aux memory, `/RAM`, and a mouse card; record capabilities.
5. Enter the main event loop: poll keyboard (+ mouse), dispatch commands.
6. Quit returns to ProDOS via MLI `QUIT` (`$65`).

The RESET vector is pointed at a clean re-entry so Ctrl-Reset repaints rather
than crashing.

## Module map (`src/`)

| File | Responsibility |
|------|----------------|
| `main.s`     | SYS entry, init order, main event loop, QUIT, RESET handler; `PUT`s every module |
| `zp.s`       | Zero-page variable map (a `DUM` section — the single source of truth for ZP) |
| `const.s`    | Hardware soft switches, ROM/MLI addresses, command IDs, UI geometry, key codes |
| `macros.s`   | 16-bit helper macros (`INC16/DEC16/MOV16/LDI16/CMP16/ADD16`) and `DOMLI` |
| `util.s`     | `MEMCPY_FWD` / `MEMCPY_BWD` block moves |
| `screen.s`   | 80-col text driver: row-base table, `PUTRAW` to main+aux, fills, normal/inverse, MouseText |
| `ui.s`       | Persistent chrome: inverse menu bar + bottom window border |
| `render.s`   | Compositing word-wrap renderer (row buffers + blit, incremental fast path), status refresh, decimal |
| `docstore.s` | Document model: line table + text heap + gap-buffer fetch/store; heap allocator |
| `editor.s`   | Gap-buffer edit primitives, cursor motion, insert/overwrite, split/join |
| `keyboard.s` | Key decode, Open-Apple detection, Esc→menu, editor/undo dispatch |
| `menu.s`     | Pull-down menus (data + interaction + type-ahead), command vector table, OA shortcuts |
| `dialog.s`   | Modal box/alert/confirm framework + ProDOS-error names |
| `fileio.s`   | MLI wrappers, FILE_SAVE/LOAD, TXT (CR) translation, the file command handlers |
| `filer.s`    | Prefix handling, filename-entry field, path building, rename/delete |
| `filer2.s`   | Scrolling ProDOS directory picker (read directory, list, type-ahead, select) |
| `search.s`   | Find, find-next, replace (Y/N/All) |
| `clipboard.s`| Copy/cut/paste/select-all |
| `undo.s`     | One-level paragraph-snapshot undo |
| `reflow.s`   | Paragraph reflow, configurable margin, soft tabs, Go To Line, Word Count |

`main.s` is the master Merlin32 source: it sets `ORG/TYP/DSK`, then `PUT`s each
module in dependency order, then `END`. Everything assembles to one flat binary.

Not yet built: `mouse.s` (M6) and the aux/`/RAM` paging backend of the text heap
(M5) — the heap currently lives in main RAM.

## Document model (the core design decision)

Requirement 12/14 forbid "one fragile contiguous buffer" and ask for a paged
model using aux/`/RAM`. We store the document as **CR-delimited paragraphs**
(matching the on-disk TXT format), not as a single byte gap buffer:

```
  line table (main RAM, grows down from $BEFF)
  ┌───────────────────────────────┐        paragraph heap (AUX $0800-$BEFF)
  │ line 0:  loc, len, flags      │──────▶ "The quick brown fox..."
  │ line 1:  loc, len, flags      │──────▶ "second paragraph bytes"
  │ ...                           │        ...
  └───────────────────────────────┘
            current line ──────────────▶ edit buffer (main RAM, 1 paragraph)
```

- **Line table** (main): one fixed record per paragraph — `loc` (2), `len` (2),
  `flags` (1). `loc`'s tag bit selects *where* the bytes live (aux heap offset,
  or `/RAM` scratch block). Inserting/deleting a paragraph shifts table entries
  (O(lines), cheap). Indexing line N is O(1).
- **Paragraph heap** (aux `$0800-$BEFF`, ~46 KB): paragraph bytes packed by a
  bump allocator; a full heap triggers compaction (walk the table in order,
  `AUXMOVE` each paragraph down). Editing reallocs at the bump tip; stale copies
  become garbage reclaimed at the next compaction.
- **Edit buffer** (main, one paragraph): the cursor's current paragraph is
  `AUXMOVE`d into main RAM and edited there with a small in-line gap buffer
  (fast, simple, no in-aux byte shifting). It is flushed back to the heap on a
  structural change or when the cursor leaves the paragraph.
- **Paging (M5):** when the aux heap can't grow, the least-recently-touched
  paragraphs spill to a `/RAM` (or disk) scratch file; the line-table `loc` tag
  records the spill location. Absent/full/small `/RAM` just caps capacity with a
  status note — never a crash.

This never shifts bytes across the main/aux boundary, only `AUXMOVE` block
copies plus single-paragraph editing in main. Word wrap and reflow are pure
display/transform passes over paragraphs; the stored bytes stay CR-delimited.

Rationale and the alternative (whole-document aux gap buffer, rejected because
running code while `RAMRD` banks `$0200-$BFFF` to aux is unsafe — instructions
would fetch from aux) are in [MEMORY-MAP.md](MEMORY-MAP.md).

## File format

Plain **ProDOS TXT** (`TYP $04`): paragraphs separated by `$8D` (high-bit CR),
which is ProDOS's convention for text files. Translation happens only at the
I/O boundary (`fileio.s`):

- **Load:** file byte → set high bit for the editor's internal high-ASCII form;
  `$0D`/`$8D` ends a paragraph; tabs (`$09/$89`) preserved as a tab byte.
- **Save:** internal byte → file byte; paragraph boundary → single `$0D`.

Internally text is stored as high-bit ASCII (`$A0-$FF` printable) so screen
writes are a straight copy. The editor's on-disk form is documented in the
README so files interchange with other ProDOS text tools.

## UI model

- **Menu bar** row 0: `File  Edit  Search  Document  Options  Help`, MouseText
  Apple glyph at left. Pull-downs are modal overlays saved/restored from a
  stash buffer.
- **Document window**: the text viewport fills rows 1–21 directly under the
  menu bar, with MouseText scroll indicators down the right edge and a horizontal
  border rule on the row above the status line.
- **Status line** (bottom): filename, modified flag (`*`), line:col,
  INS/OVR, free bytes, `/RAM` state.
- **Dialogs**: centered MouseText boxes with buttons, a filename field, and the
  volume/directory list for the file picker; full keyboard + mouse operation.

## Testing strategy

Two tiers, per the 6502-testing skill:

- **Unit (py65, `tests/`)**: load the real merlin32 binary, drive routines by
  symbol, assert on memory. Covers docstore invariants, screen encoding,
  cursor/edit logic, search, reflow, the MLI wrappers against a *faked* MLI.
- **Integration/acceptance (microM8)**: boot the generated disk, drive the
  keyboard/mouse, read the 80-col screen back byte-exactly. Covers boot, UI,
  new/type/save/reopen/edit/save-as/delete, search, replace, large-doc scroll.

See [../tests/README.md](../tests/README.md) and [ROADMAP.md](ROADMAP.md).
