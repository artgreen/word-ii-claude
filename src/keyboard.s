*-----------------------------------------------------------------------
* keyboard.s -- decode a keypress and dispatch to an editor command.
* Keys arrive high-bit set (as read from $C000). Internal text is high-bit
* ASCII too, so printable keys pass straight to ED_INSERT.
*
* M2 bindings (Open-Apple menu shortcuts arrive with menus in M3/M6):
*   arrows      move cursor (wrapping across paragraphs)
*   Return      split paragraph
*   DELETE      backspace (delete left / join previous)
*   Ctrl-D      forward delete (join next at end)
*   Ctrl-A/E    start / end of paragraph
*   printable   insert (or overwrite in OVR mode)
*-----------------------------------------------------------------------
KEYDISPATCH     bit   BUTTON0            ; Open-Apple held? (bit 7 -> N)
                bpl   :noopen
                jmp   OA_DISPATCH        ; A = key; route as a command
:noopen         cmp   #K_ESC            ; Esc opens the menu bar
                bne   :k0
                jmp   MENU_ENTER
:k0             cmp   #K_RETURN
                bne   :k1
                jsr   ED_ENTER
                jmp   :edited
:k1             cmp   #K_LEFT            ; $88 left arrow
                bne   :k2
                jsr   UNDO_INVAL
                jsr   ED_LEFT
                rts
:k2             cmp   #K_RIGHT           ; $95 right arrow
                bne   :k3
                jsr   UNDO_INVAL
                jsr   ED_RIGHT
                rts
:k3             cmp   #K_UP              ; $8B up arrow
                bne   :k4
                jsr   UNDO_INVAL
                jsr   ED_UP
                rts
:k4             cmp   #K_DOWN            ; $8A down arrow
                bne   :k5
                jsr   UNDO_INVAL
                jsr   ED_DOWN
                rts
:k5             cmp   #K_DELETE          ; $FF DELETE = backspace
                bne   :k6
                jsr   UNDO_CHECKPOINT
                jsr   ED_BACKSPACE
                jmp   :editinc
:k6             cmp   #$84               ; Ctrl-D forward delete
                bne   :k7
                jsr   UNDO_CHECKPOINT
                jsr   ED_DELETE
                jmp   :editinc
:k7             cmp   #$81               ; Ctrl-A home
                bne   :k8
                jsr   UNDO_INVAL
                jsr   ED_HOME
                rts
:k8             cmp   #$85               ; Ctrl-E end
                bne   :k8b
                jsr   UNDO_INVAL
                jsr   ED_END
                rts
:k8b            cmp   #$8f               ; Ctrl-O toggle insert/overwrite
                bne   :k8c
                lda   EDITFLAGS
                eor   #FL_OVERWRITE
                sta   EDITFLAGS
                rts
:k8c            cmp   #K_TAB             ; $89 Tab -> soft tab (spaces to tab stop)
                bne   :k9
                jsr   UNDO_CHECKPOINT
                jsr   ED_TAB
                jmp   :editinc
:k9             cmp   #$a0               ; printable $A0..$FE ?
                bcc   :other
                cmp   #$ff
                bcs   :other
                jsr   UNDO_CHECKPOINT
                jsr   ED_INSERT
                jmp   :editinc
:other          rts                       ; unhandled key
:editinc        lda   #1                  ; in-paragraph edit -> incremental repaint
                sta   RENDER_INCR
:edited         lda   EDITFLAGS
                ora   #FL_DIRTY
                sta   EDITFLAGS
                rts
