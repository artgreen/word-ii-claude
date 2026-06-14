"""CONFIRM dialog result logic after the two-button (DRAWBUTTON) rewrite.

CONFIRM draws ( Yes ) ( No ) buttons and loops on GETKEY; we pre-load the
keyboard latch ($C000) so GETKEY returns immediately, then read CONFRES
(1 = Yes, 0 = No). The button *rendering* is verified visually in microM8;
here we lock the keyboard-result contract that callers (delete, discard) rely on.
"""
from _harness import program

KBD = 0xC000


def confirm_with_key(key):
    p = program()
    p.call("DOC_NEW")                       # valid doc state for DLG_RESTORE's RENDER
    prompt = p.sym("MSG_PRESSKEY")          # any zero-terminated string works
    p.poke(KBD, key)                        # pre-load the key GETKEY will read
    p.call("CONFIRM", a=prompt & 0xFF, x=prompt >> 8)
    return p.peek("CONFRES")


def test_confirm_y_is_yes():
    assert confirm_with_key(0xD9) == 1      # 'Y'


def test_confirm_lower_y_is_yes():
    assert confirm_with_key(0xF9) == 1      # 'y'


def test_confirm_n_is_no():
    assert confirm_with_key(0xCE) == 0      # 'N'


def test_confirm_lower_n_is_no():
    assert confirm_with_key(0xEE) == 0      # 'n'


def test_confirm_esc_is_no():
    assert confirm_with_key(0x9B) == 0      # Esc


def test_confirm_return_takes_default_yes():
    # Default focus is Yes, so Return (no arrow pressed) confirms.
    assert confirm_with_key(0x8D) == 1      # Return
