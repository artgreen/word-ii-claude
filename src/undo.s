*-----------------------------------------------------------------------
* undo.s -- one-level undo of in-paragraph edits.
*
* Before a burst of typing/deleting within a paragraph, UNDO_CHECKPOINT
* snapshots the whole current paragraph (EDITBUF gap buffer + cursor + line
* index) into UNDOBUF. Undo restores it. The checkpoint is invalidated by
* navigation and by structural operations (paragraph split/join, cut/paste,
* file load) -- those are not undoable here, so undo never claims to revert
* something it cannot. This is the honest scope of a single-level undo without
* a full-document history.
*-----------------------------------------------------------------------

* UNDO_CHECKPOINT -- snapshot the current paragraph if a burst isn't open yet.
*   Preserves A: the keyboard calls this immediately before ED_INSERT, which
*   needs the character still in A.
UNDO_CHECKPOINT pha
                lda   UNDO_VALID
                bne   :done
                MOV16 DOCLINE;UNDO_LINE
                MOV16 GAPSTART;UNDO_GS
                MOV16 GAPEND;UNDO_GE
                LDI16 EDITBUF;SRCPTR
                LDI16 UNDOBUF;DSTPTR
                LDI16 EDITMAX;COUNTL
                jsr   MEMCPY_FWD
                lda   #1
                sta   UNDO_VALID
:done           pla
                rts

* UNDO_INVAL -- discard the checkpoint (call on navigation / structural edits).
UNDO_INVAL      stz   UNDO_VALID
                rts

* CMD_DO_UNDO -- restore the last checkpoint.
CMD_DO_UNDO     lda   UNDO_VALID
                beq   :none
                MOV16 UNDO_LINE;DOCLINE
                MOV16 UNDO_GS;GAPSTART
                MOV16 UNDO_GE;GAPEND
                LDI16 UNDOBUF;SRCPTR
                LDI16 EDITBUF;DSTPTR
                LDI16 EDITMAX;COUNTL
                jsr   MEMCPY_FWD
                lda   #1
                sta   EDITDIRTY
                stz   UNDO_VALID                 ; one level: consumed
                jmp   DLG_RESTORE
:none           lda   #<MSG_NOUNDO
                ldx   #>MSG_NOUNDO
                jmp   ALERT

UNDO_VALID      dfb   0
UNDO_LINE       ds    2
UNDO_GS         ds    2
UNDO_GE         ds    2

MSG_NOUNDO      asc   "Nothing to undo.",00
