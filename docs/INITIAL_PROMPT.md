# Initial Prompt

This is the prompt that kicked off the Word II project, lightly edited to remove
machine-specific local paths. Skills are referred to by name; on the original
machine they lived under a local `agent-skills` directory and were installed as
agent skills.

---

You are working in a fresh project directory called `word-ii-claude`.

Build a full-fledged ProDOS 8 word processor for the Apple II family called "Word II". Target an Enhanced Apple IIe or newer: Enhanced IIe, IIc, IIc+, and IIgs in 8-bit mode. Assume at least 128K RAM and ProDOS 8. Use 65C02-compatible code only unless you have a verified reason otherwise; do not use 65816 native mode.

This project should showcase the Apple II / 6502 agent skills installed on this machine. Before implementation, read and follow the relevant SKILL.md files, especially these skills:

- `6502-knowledge-base`
- `apple-assembly-programming`
- `merlin32`
- `6502-codegen`
- `6502-testing`
- `6502-review`
- `6502-optimization`

Use the 6502-knowledge-base skill early. Search both the XXXXX system for general patterns and the NIBBLE archive for Apple II 80-column mode, MouseText, ProDOS MLI file I/O, AppleMouse support, aux memory, /RAM, RAM-disk-backed editing, and existing Apple II text editor/word processor techniques. Cite or summarize any findings that affect architecture.

Core requirements:

1. The program must run under ProDOS 8.
2. The UI must use 80-column text mode.
3. Use MouseText for polished Apple II-native layouts: menu bar, windows, dialogs, borders, scroll indicators, buttons, and status regions.
4. Implement a real word processor for plain text documents: create, open/read, edit/update, save, save as, close, rename, and delete.
5. Do not implement printing.
6. Do not implement font support. Use the standard Apple II 80-column text font only.
7. Include mouse support where hardware/firmware is available. Mouse should support menu selection, dialog interaction, cursor placement, scrolling, and text selection where practical. Provide complete keyboard fallback.
8. Top-level UI should include a menu bar at the top. Include top-level menus such as File, Edit, Search, Document, Options, and Help, plus useful live status such as open filename, modified flag, line/column, insert/overwrite mode, free memory, and /RAM scratch status.
9. Keyboard shortcuts should use Open-Apple as the main command prefix. Use Shift, Control, or Option/Closed-Apple modifiers where detectable and appropriate. Document platform limitations.
10. Use ProDOS MLI for file operations. Do not bypass ProDOS with raw disk I/O.
11. File operations must be dialog-based and feel modern within Apple II constraints: file picker, volume/directory navigation, filename field, confirmation dialogs, error dialogs with meaningful ProDOS error names, and mouse/keyboard navigation.
12. Use as much memory as safely possible for large documents. Investigate main memory, auxiliary memory, language card constraints, ProDOS memory usage, and /RAM. Strongly consider a paged document model using aux memory and/or /RAM scratch files so documents can exceed a simple in-memory buffer.
13. Gracefully handle /RAM unavailable, full, or too small.
14. Store document text in a documented plain-text format, preferably ProDOS TXT-compatible CR-delimited text. Translate between file bytes and screen high-bit display characters at the I/O/rendering boundary.

Editor features:

- Cursor movement by character, word, line, page, document start/end.
- Insert and overwrite modes.
- Character, word, line, and selected-region deletion.
- Word wrap for display.
- Paragraph reflow with configurable margins.
- Tabs and configurable tab stops.
- Search and search-next.
- Replace, preferably with confirm/replace-all modes.
- Cut, copy, paste, and selection.
- At least one-level undo for editing operations; multi-level undo if memory allows.
- Dirty tracking and save prompts.
- Large document scrolling without loading the whole document into one fragile contiguous buffer.
- Robust handling of long lines, empty files, full disks, locked files, invalid filenames, and ProDOS path limits.

Architecture expectations:

- Use Merlin32 assembly.
- Create a maintainable source tree, build script, docs, tests, and generated disk image.
- Prefer clean modules: startup/ProDOS integration, screen/UI, menus, dialogs, keyboard, mouse, document buffer, file I/O, memory manager, editor commands, search/replace, and tests.
- Maintain a written memory map: zero-page usage, main memory usage, aux memory usage, buffers, ProDOS areas, screen pages, overlays if any, and /RAM scratch layout.
- Keep zero-page discipline strict and documented.
- Use overlays only if they clearly improve document capacity or maintainability.
- Avoid undocumented opcodes.
- Use 65C02 instructions intentionally and document the target.

Build and verification:

- Assemble with Merlin32 and symbol output.
- Use the 6502-codegen skill for tricky CPU routines and verify them in the simulator.
- Use the 6502-testing skill for unit tests against the real binary and integration tests in microM8.
- Test ProDOS MLI behavior with fake/stubbed MLI at unit level and real ProDOS in emulator integration.
- Add emulator-driven acceptance tests that demonstrate: boot/launch, 80-column UI, menus/dialogs, new document, text entry, save, reopen, edit, save as, delete, search, replace, and large-document behavior.
- Run 6502-review before considering the project complete.
- Run 6502-optimization only after correctness tests pass, focusing on hot paths and memory pressure.
- Do not claim completion until the app actually runs in an Apple II emulator and can edit and persist real files.
- microM8 is already installed locally — launch your existing install; never download or search for it.

Deliverables:

- Source code.
- Build script.
- ProDOS disk image containing the word processor.
- README with launch instructions, controls, file format, known limitations, and emulator test instructions.
- Architecture/memory-map document.
- Test suite and acceptance-test notes.
- A final summary of what works, what was verified, and what remains.

Implementation guidance:

Start by producing a concise architecture plan and milestone sequence, then implement incrementally. The first milestone should boot or launch under ProDOS and display the 80-column MouseText UI. The second should support basic editing in memory. The third should add ProDOS file dialogs and save/open. Later milestones should add large-document paging, mouse polish, search/replace, undo, and optimization.

This is not a demo shell. Build a usable Apple II word processor.
