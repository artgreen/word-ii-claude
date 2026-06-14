#!/usr/bin/env bash
# mkdisk.sh -- build a bootable ProDOS disk image with Word II on it.
# Starts from a known-bootable ProDOS template (PRODOS + BASIC.SYSTEM), then
# adds WORDII.SYSTEM (and a sample document). The disk boots to the ProDOS
# BASIC prompt; launch Word II with  -WORDII.SYSTEM .
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
TEMPLATE="/Users/green/projects/microm8-cln/prodos402.dsk"
DISK="$BUILD/WORDII.po"
STAGE="$BUILD/stage"

[[ -f "$BUILD/WORDII.SYSTEM" ]] || { echo "build first: scripts/build.sh" >&2; exit 1; }

cp -f "$TEMPLATE" "$DISK"
mkdir -p "$STAGE"

# Trim template clutter to free space (ignore if absent).
for f in BLACKJACK ADVENTURE EDIT VI READ.ME TEST1 TEST2 SMOKE FOOBAR SETTINGS; do
  cp2 rm "$DISK" "$f" 2>/dev/null || true
done

# Stage with NAPS suffixes so cp2 sets ProDOS type/aux.
cp -f "$BUILD/WORDII.SYSTEM" "$STAGE/WORDII.SYSTEM#ff2000"
printf 'Welcome to Word II.\rA ProDOS 8 word processor for the Apple IIe family.\r\rType to edit. Open-Apple-? for help.\r' > "$STAGE/WELCOME.TXT#040000"

( cd "$STAGE" && cp2 add --overwrite "$DISK" "WORDII.SYSTEM#ff2000" "WELCOME.TXT#040000" )

echo ">> disk: $DISK"
cp2 catalog "$DISK" | grep -iE "WORDII|WELCOME|free"
