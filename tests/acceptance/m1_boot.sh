#!/usr/bin/env bash
# M1 acceptance: boot the ProDOS disk, launch Word II, confirm the 80-column
# MouseText UI shell renders (menu titles + 80-col mode + MouseText cells).
source "$(dirname "$0")/lib.sh"

m8_boot
boot_screen="$(drive text)"
assert_contains "$boot_screen" "PRODOS BASIC" "disk boots ProDOS to BASIC"

m8_launch
ui="$(drive text)"
echo "$ui" | head -2

assert_contains "$ui" "80 columns x 24 rows" "UI is 80-column"
assert_contains "$ui" "alt charset: on"      "MouseText charset enabled"
for t in File Edit Search Document Options Help; do
  assert_contains "$ui" "$t" "menu title: $t"
done

attrs="$(drive text attrs)"
# row 0 should be an inverse menu bar; row 1/right edge proper MouseText
assert_contains "$attrs" "mmmmmmmmmmmm" "window border is real MouseText (m)"

m8_stop
finish
