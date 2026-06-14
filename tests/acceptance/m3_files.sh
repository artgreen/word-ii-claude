#!/usr/bin/env bash
# M3 acceptance: drive the file UI. Open the directory picker, type-ahead to
# WELCOME.TXT, load it, and confirm its contents render. Exercises menus,
# the ProDOS directory read, the picker, and FILE_LOAD end to end.
source "$(dirname "$0")/lib.sh"

m8_boot
m8_launch

# Esc -> File menu, 'O' (Open), Return -> picker, 'W' -> WELCOME.TXT, Return.
drive type '{e}' sleep 1 type 'O' sleep 1 type '{r}' sleep 1 >/dev/null
picker="$(drive text)"
assert_contains "$picker" "Open File"     "directory picker opens"
assert_contains "$picker" "WELCOME.TXT"   "picker lists a real ProDOS file"
assert_contains "$picker" "WORDII.SYSTEM" "picker lists the program itself"

drive type 'W' sleep 1 type '{r}' sleep 2 >/dev/null
loaded="$(drive text)"
echo "$loaded" | sed -n '4,7p'
assert_contains "$loaded" "Welcome to Word II"             "WELCOME.TXT loaded (line 1)"
assert_contains "$loaded" "ProDOS 8 word processor"        "WELCOME.TXT loaded (line 2)"
assert_contains "$loaded" "Open-Apple"                     "WELCOME.TXT loaded (last line)"

m8_stop
finish
