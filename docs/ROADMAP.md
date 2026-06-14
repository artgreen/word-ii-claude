# Word II — Roadmap & milestones

Incremental build. Each milestone ends with green unit tests (py65) and a
microM8 integration check before the next begins.

- **M0 — Research, architecture, scaffold.** Skills read, knowledge base
  searched, toolchain verified, ARCHITECTURE + MEMORY-MAP written, build script,
  source tree, smoke build that boots a ProDOS disk and shows a banner. ✅ when
  the disk boots in microM8 and the screen reads back.
- **M1 — 80-col MouseText UI shell.** Screen driver, menu bar, window border,
  status line. No editing yet. ✅ when the chrome renders correctly in microM8
  and screen-encoding unit tests pass.
- **M2 — In-memory editing.** docstore (paragraph heap + line table + edit
  buffer), cursor motion, insert/overwrite, deletes, word wrap, scrolling,
  dirty flag, keyboard with Open-Apple shortcuts. ✅ type/edit verified.
- **M3 — ProDOS files.** MLI wrappers, dialog framework, file picker, New/Open/
  Save/SaveAs/Close/Rename/Delete, TXT translation, error alerts. ✅ save +
  reopen round-trips real bytes on a real ProDOS volume in microM8.
- **M4 — Editor features.** Search/search-next, replace (confirm/all), selection
  + cut/copy/paste, undo, reflow + margins, tab stops. ✅ each feature tested.
- **M5 — Large documents.** Aux-heap compaction + `/RAM` paging, graceful `/RAM`
  degradation, large-doc scroll/edit acceptance. ✅ a doc bigger than the aux
  heap edits and saves.
- **M6 — Mouse + polish.** Firmware probe, passive poll, menu/dialog/cursor/
  scroll/selection by mouse, keyboard fallback intact.
- **M7 — Review, optimize, document.** 6502-review pass, 6502-optimization on hot
  paths, full acceptance suite, README + docs finalized, completion summary.

Status is tracked live in the session task list (M0–M7 = tasks #1–#8).
