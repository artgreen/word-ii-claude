# Word II — Test Suite

Two tiers. Both run against the **real merlin32-built binary**
(`build/WORDII.SYSTEM` + its symbol file), not a re-creation. The py65
simulator harness (`sim.py` + `harness.py`) is vendored in `vendor/`, so the
unit tier needs only the `py65` package.

## Tier 1 — unit tests (py65, instant)

Load the binary into the py65 simulator and drive its routines **by symbol
name**, poking state in and asserting on memory out. py65 is flat 64K with no
Apple II aux-memory banking, so this tier covers pure computation — the document
store, cursor/edit logic, word-wrap break points, search/replace, clipboard,
undo, the directory parser, and the MLI wrappers against a *faked* MLI. Anything
needing real banking or screen hardware is verified in Tier 2.

```
pip install py65
python3 tests/run_tests.py
```

`run_tests.py` discovers every `test_*.py` and runs each `test_*` function.

| File | Covers |
|------|--------|
| `test_screen.py`   | row-base table, PUTRAW address math |
| `test_editor.py`   | document store + every cursor/edit/split/join command |
| `test_heap.py`     | text-heap accounting (FREE), compaction, alloc-on-full |
| `test_wrap.py`     | word-wrap break-point selection (FIND_WRAP) |
| `test_fileio.py`   | save MLI call sequence (faked MLI), TXT parse + translate |
| `test_filer.py`    | ProDOS directory-block parsing, path building |
| `test_search.py`   | find (case-insensitive, wrap), replace |
| `test_clip_undo.py`| copy/cut/paste/select-all, one-level undo |
| `test_picker_scroll.py` | file-picker scrollbar thumb math |
| `test_confirm.py`  | buttoned confirm dialog result handling |
| `test_review_fixes.py` | regressions for the 6 review findings |
| `test_goto_wordcount.py` | Go To Line number parse, document word count + report string |

Current count: **80 tests, all passing.**

## Tier 2 — acceptance tests (microM8, seconds)

Boot the **generated disk image** in the microM8 Apple II emulator over its MCP
control plane, drive the keyboard, and read the 80-column screen back
byte-exactly. These confirm the things only a real machine has: ProDOS boot, the
aux-banked 80-column display, MouseText, real MLI file I/O, and the feel of the
UI.

```
bash tests/acceptance/m1_boot.sh    # boots ProDOS, launches Word II, checks the 80-col MouseText UI
bash tests/acceptance/m2_edit.sh    # types two paragraphs, checks rendering + status
bash tests/acceptance/m3_files.sh   # opens the directory picker, loads WELCOME.TXT, checks contents
```

`tests/acceptance/lib.sh` manages the emulator lifecycle (launch on the disk,
wait for the `]` prompt, drive via the vendored `vendor/m8.py` MCP CLI) and
provides `assert_contains`. Set `MICROM8_DIR` to your microM8 install; the
driver needs the `mcp` package. Each script exits non-zero on failure.

### Notes / gotchas observed
- Read the screen with `m8.py text` (`get_text_screen_full`) — it is the only
  source correct in 80-column mode and decodes inverse/MouseText.
- `type_text` is asynchronous; sleep ≥1 s after typing before reading.
- Apple II keyboards have a one-key buffer; pace multi-key menu sequences (the
  scripts sleep between keystrokes). The emulator maps `\n`→Return, so down-arrow
  can't be sent as `\n`; menu/picker navigation in the scripts uses **type-ahead**
  (press a letter to jump) which is also a real UX feature.
- In-emulator disk writes persist to the host `.dsk` on this microM8 build
  (verified with `cp2 catalog`/`print` after exit); the acceptance scripts and
  manual sessions both rely on the real ProDOS MLI write path.

## Manual verification

The development log includes microM8 screenshots of the UI, menus, dialogs, the
directory picker, and save/open round-trips, plus `cp2`-level byte verification
of saved TXT files. See `docs/SUMMARY.md`.
