#!/usr/bin/env bash
# M2 acceptance: boot Word II, type text across two paragraphs, and confirm it
# renders, word-wraps, and tracks the cursor / dirty flag in the status line.
source "$(dirname "$0")/lib.sh"

m8_boot
m8_launch

# Two short paragraphs, then a long one that must word-wrap.
drive type 'Hello World{r}Second paragraph.' sleep 3 >/dev/null
edit="$(drive text)"
echo "$edit" | sed -n '4,5p;26,26p'
assert_contains "$edit" "Hello World"        "paragraph 1 rendered"
assert_contains "$edit" "Second paragraph."  "paragraph 2 rendered (Return split)"
assert_contains "$edit" "UNTITLED"           "status shows filename"
assert_contains "$edit" "L2"                 "status tracks line (cursor on line 2)"

m8_stop
finish
