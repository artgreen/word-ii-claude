#!/usr/bin/env bash
# build.sh -- assemble Word II with Merlin32 and stage outputs in build/.
# Outputs: build/WORDII.SYSTEM (binary), build/WORDII.SYSTEM_Symbols.txt,
#          build/WORDII.SYSTEM_S01_Segment1_Output.txt (listing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="/Users/green/merlin32/Library"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

# Run from src/ so PUT (which resolves relative to the main source file) finds
# the sibling modules, and Merlin32 writes its outputs next to main.s.
cd "$ROOT/src"

# Clean stale outputs so a failed assemble can't leave a misleading binary.
rm -f WORDII.SYSTEM WORDII.SYSTEM_* _FileInformation.txt

echo ">> merlin32 assembling src/main.s"
merlin32 -V "$LIB" main.s | tee "$BUILD/assemble.log"

if grep -qiE '\berror\b' "$BUILD/assemble.log"; then
  echo "!! assembly reported errors" >&2
  exit 1
fi

if [[ ! -f WORDII.SYSTEM ]]; then
  echo "!! WORDII.SYSTEM not produced" >&2
  exit 1
fi

mv -f WORDII.SYSTEM "$BUILD/"
mv -f WORDII.SYSTEM_* "$BUILD/" 2>/dev/null || true
mv -f _FileInformation.txt "$BUILD/" 2>/dev/null || true

echo ">> built $(du -h "$BUILD/WORDII.SYSTEM" | cut -f1) -> build/WORDII.SYSTEM"
ls -1 "$BUILD" | sed 's/^/   /'
