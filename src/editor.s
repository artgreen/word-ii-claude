*-----------------------------------------------------------------------
* editor.s -- editing commands over the document store. The current paragraph
* lives in EDITBUF as a gap buffer (see docstore.s); these routines move the
* gap (cursor), edit, and split/join paragraphs, flushing across boundaries.
*
* Characters are stored internally as high-bit ASCII ($A0-$FF printable);
* the keyboard layer hands us that form.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* Gap-buffer primitives (operate within the current paragraph only).
*-----------------------------------------------------------------------

* GAP_INSCHAR -- insert A at the cursor (before the gap). ERR_PARAFULL if full.
GAP_INSCHAR     sta   TMPA
                CMP16 GAPSTART;GAPEND      ; gap empty -> paragraph buffer full
                bne   :room
                lda   #ERR_PARAFULL
                sta   RETCODE
                rts
:room           clc
                lda   #<EDITBUF
                adc   GAPSTART
                sta   PTR3
                lda   #>EDITBUF
                adc   GAPSTART+1
                sta   PTR3+1
                lda   TMPA
                sta   (PTR3)
                INC16 GAPSTART
                lda   #1
                sta   EDITDIRTY
                rts

* GAP_RIGHT -- move cursor one char right within the paragraph (if room).
GAP_RIGHT       lda   GAPEND+1
                cmp   #>EDITMAX
                bcc   :go
                bne   :no
                lda   GAPEND
                cmp   #<EDITMAX
                bcs   :no
:go             clc                        ; TMPA = EDITBUF[GAPEND]
                lda   #<EDITBUF
                adc   GAPEND
                sta   PTR3
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   PTR3+1
                lda   (PTR3)
                sta   TMPA
                clc                        ; EDITBUF[GAPSTART] = TMPA
                lda   #<EDITBUF
                adc   GAPSTART
                sta   PTR3
                lda   #>EDITBUF
                adc   GAPSTART+1
                sta   PTR3+1
                lda   TMPA
                sta   (PTR3)
                INC16 GAPSTART
                INC16 GAPEND
:no             rts

* GAP_LEFT -- move cursor one char left within the paragraph (if room).
GAP_LEFT        lda   GAPSTART
                ora   GAPSTART+1
                bne   :go
                rts
:go             DEC16 GAPSTART
                DEC16 GAPEND
                clc                        ; TMPA = EDITBUF[GAPSTART]
                lda   #<EDITBUF
                adc   GAPSTART
                sta   PTR3
                lda   #>EDITBUF
                adc   GAPSTART+1
                sta   PTR3+1
                lda   (PTR3)
                sta   TMPA
                clc                        ; EDITBUF[GAPEND] = TMPA
                lda   #<EDITBUF
                adc   GAPEND
                sta   PTR3
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   PTR3+1
                lda   TMPA
                sta   (PTR3)
                rts

* GAP_DELFWD -- delete the character at the cursor within the paragraph (no
*   paragraph join). Used by replace.
GAP_DELFWD      lda   GAPEND+1
                cmp   #>EDITMAX
                bne   :go
                lda   GAPEND
                cmp   #<EDITMAX
                beq   :no
:go             INC16 GAPEND
                lda   #1
                sta   EDITDIRTY
:no             rts

* GAP_HOME_MOVE / GAP_END_MOVE -- cursor to column 0 / end of paragraph.
GAP_HOME_MOVE   lda   GAPSTART
                ora   GAPSTART+1
                beq   :done
                jsr   GAP_LEFT
                bra   GAP_HOME_MOVE
:done           rts

GAP_END_MOVE    lda   GAPEND+1
                cmp   #>EDITMAX
                bcc   :go
                bne   :done
                lda   GAPEND
                cmp   #<EDITMAX
                bcs   :done
:go             jsr   GAP_RIGHT
                bra   GAP_END_MOVE
:done           rts

* CURSOR_SET_COL -- move cursor toward column PTR2 (clamped at paragraph end).
CURSOR_SET_COL  CMP16 GAPSTART;PTR2
                bcs   :left              ; GAPSTART >= target
                lda   GAPEND+1           ; want right; stop if at end
                cmp   #>EDITMAX
                bcc   :r
                bne   :left
                lda   GAPEND
                cmp   #<EDITMAX
                bcs   :left
:r              jsr   GAP_RIGHT
                bra   CURSOR_SET_COL
:left           CMP16 GAPSTART;PTR2
                beq   :done
                bcc   :done              ; couldn't reach (short line)
                jsr   GAP_LEFT
                bra   :left
:done           rts

*-----------------------------------------------------------------------
* ED_INSERT -- type character A. Honors INS/OVR via EDITFLAGS.
*-----------------------------------------------------------------------
ED_INSERT       pha
                lda   EDITFLAGS
                and   #FL_OVERWRITE
                beq   :ins
                lda   GAPEND+1            ; overwrite: drop char at cursor unless at end
                cmp   #>EDITMAX
                bne   :ovr
                lda   GAPEND
                cmp   #<EDITMAX
                beq   :ins
:ovr            INC16 GAPEND
:ins            pla
                jmp   GAP_INSCHAR

*-----------------------------------------------------------------------
* ED_BACKSPACE -- delete left; join with previous paragraph at column 0.
*-----------------------------------------------------------------------
ED_BACKSPACE    lda   GAPSTART
                ora   GAPSTART+1
                bne   :within
                jmp   ED_JOIN_PREV
:within         DEC16 GAPSTART
                lda   #1
                sta   EDITDIRTY
                rts

*-----------------------------------------------------------------------
* ED_DELETE -- delete right; join with next paragraph at end of paragraph.
*-----------------------------------------------------------------------
ED_DELETE       lda   GAPEND+1
                cmp   #>EDITMAX
                bne   :within
                lda   GAPEND
                cmp   #<EDITMAX
                bne   :within
                jmp   ED_JOIN_NEXT
:within         INC16 GAPEND
                lda   #1
                sta   EDITDIRTY
                rts

*-----------------------------------------------------------------------
* Cursor movement across paragraphs.
*-----------------------------------------------------------------------
ED_LEFT         lda   GAPSTART
                ora   GAPSTART+1
                bne   :within
                lda   DOCLINE            ; at col 0: end of previous paragraph
                ora   DOCLINE+1
                bne   :prev
                rts
:prev           jsr   STOREPARA
                bcs   :abort                ; flush failed (heap full): stay put, keep edits
                DEC16 DOCLINE
                jsr   FETCHPARA
                jmp   GAP_END_MOVE
:within         jmp   GAP_LEFT
:abort          rts

ED_RIGHT        lda   GAPEND+1
                cmp   #>EDITMAX
                bne   :within
                lda   GAPEND
                cmp   #<EDITMAX
                bne   :within
                MOV16 NLINES;SCRATCH16    ; at end: start of next paragraph
                DEC16 SCRATCH16
                CMP16 DOCLINE;SCRATCH16
                bcc   :next
                rts
:next           jsr   STOREPARA
                bcs   :abort
                INC16 DOCLINE
                jmp   FETCHPARA
:within         jmp   GAP_RIGHT
:abort          rts

ED_UP           lda   DOCLINE
                ora   DOCLINE+1
                bne   :go
                rts
:go             MOV16 GAPSTART;PTR2
                jsr   STOREPARA
                bcs   :abort
                DEC16 DOCLINE
                jsr   FETCHPARA
                jmp   CURSOR_SET_COL
:abort          rts

ED_DOWN         MOV16 NLINES;SCRATCH16
                DEC16 SCRATCH16
                CMP16 DOCLINE;SCRATCH16
                bcc   :go
                rts
:go             MOV16 GAPSTART;PTR2
                jsr   STOREPARA
                bcs   :abort
                INC16 DOCLINE
                jsr   FETCHPARA
                jmp   CURSOR_SET_COL
:abort          rts

ED_HOME         jmp   GAP_HOME_MOVE      ; start of current paragraph
ED_END          jmp   GAP_END_MOVE       ; end of current paragraph

*-----------------------------------------------------------------------
* ED_ENTER -- split the current paragraph at the cursor.
*   before-part stays as DOCLINE; after-part becomes a new paragraph DOCLINE+1;
*   cursor moves to the start of the new paragraph.
*-----------------------------------------------------------------------
* EDTMP0/EDTMP1 hold the after-part length and source across STOREPARA and
* LINE_INSERT (both of which clobber the shared TMPPTR/PTR1/PTR2/SCRATCH16).
ED_ENTER        jsr   UNDO_INVAL
                sec                        ; EDTMP0 = afterlen = EDITMAX - GAPEND
                lda   #<EDITMAX
                sbc   GAPEND
                sta   EDTMP0
                lda   #>EDITMAX
                sbc   GAPEND+1
                sta   EDTMP0+1
                clc                        ; EDTMP1 = EDITBUF + GAPEND (after-part src)
                lda   #<EDITBUF
                adc   GAPEND
                sta   EDTMP1
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   EDTMP1+1
                MOV16 DOCLINE;SCRATCH16    ; insert a new entry at DOCLINE+1
                INC16 SCRATCH16
                jsr   LINE_INSERT
                bcs   :fail
                jsr   LT_PTR               ; new entry: len 0 so a compaction skips it
                stz   COUNTL
                stz   COUNTH
                jsr   LT_SETLEN
                MOV16 EDTMP0;COUNTL        ; allocate afterlen bytes for it
                jsr   HEAP_ALLOC_CMP
                bcs   :full
                MOV16 DOCLINE;SCRATCH16    ; re-derive index (compaction moved scratch)
                INC16 SCRATCH16
                jsr   LT_PTR               ; entry SCRATCH16 (= DOCLINE+1)
                jsr   LT_SETLOC
                MOV16 EDTMP0;COUNTL
                jsr   LT_SETLEN
                MOV16 EDTMP1;SRCPTR        ; copy the after-part into the new paragraph
                MOV16 PTR0;DSTPTR
                MOV16 EDTMP0;COUNTL
                jsr   MEMCPY_FWD
                LDI16 EDITMAX;GAPEND        ; truncate current paragraph to before-part
                lda   #1
                sta   EDITDIRTY
                jsr   STOREPARA            ; before-part -> DOCLINE
                INC16 DOCLINE             ; move to the new paragraph, column 0
                jsr   FETCHPARA
                stz   RETCODE
                rts
:full           lda   #ERR_DOCFULL
                sta   RETCODE
                rts
:fail           rts

*-----------------------------------------------------------------------
* ED_JOIN_PREV -- merge the current paragraph onto the end of the previous one.
*-----------------------------------------------------------------------
ED_JOIN_PREV    jsr   UNDO_INVAL
                lda   DOCLINE
                ora   DOCLINE+1
                bne   :ok
                rts
:ok             jsr   STOREPARA            ; current -> heap
                jsr   LT_PTR_CUR
                jsr   LT_GETLEN            ; currlen -> PTR1
                MOV16 COUNTL;PTR1
                jsr   LT_GETLOC            ; curloc -> PTR2
                MOV16 PTR0;PTR2
                MOV16 DOCLINE;SCRATCH16    ; prevlen = entry[DOCLINE-1].len
                DEC16 SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLEN
                clc                        ; total = prevlen + currlen
                lda   COUNTL
                adc   PTR1
                sta   SCRATCH16
                lda   COUNTH
                adc   PTR1+1
                sta   SCRATCH16+1
                lda   SCRATCH16+1
                cmp   #>EDIT_LIMIT
                bcc   :feasible
                bne   :toolong
                lda   SCRATCH16
                cmp   #<EDIT_LIMIT
                bcs   :toolong
:feasible       DEC16 DOCLINE
                jsr   FETCHPARA            ; previous paragraph into EDITBUF
                jsr   GAP_END_MOVE         ; cursor at end of previous (= junction)
                sec                        ; GAPEND = EDITMAX - currlen
                lda   #<EDITMAX
                sbc   PTR1
                sta   GAPEND
                lda   #>EDITMAX
                sbc   PTR1+1
                sta   GAPEND+1
                MOV16 PTR2;SRCPTR          ; copy current bytes after cursor
                clc
                lda   #<EDITBUF
                adc   GAPEND
                sta   DSTPTR
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   DSTPTR+1
                MOV16 PTR1;COUNTL
                jsr   MEMCPY_FWD
                lda   #1
                sta   EDITDIRTY
                MOV16 DOCLINE;SCRATCH16    ; delete old current entry (DOCLINE+1)
                INC16 SCRATCH16
                jsr   LINE_DELETE
                stz   RETCODE
                rts
:toolong        lda   #ERR_PARAFULL
                sta   RETCODE
                rts

*-----------------------------------------------------------------------
* ED_JOIN_NEXT -- merge the next paragraph onto the end of the current one.
*   Cursor is assumed at end of the current paragraph (caller's contract).
*-----------------------------------------------------------------------
ED_JOIN_NEXT    jsr   UNDO_INVAL
                MOV16 NLINES;SCRATCH16
                DEC16 SCRATCH16
                CMP16 DOCLINE;SCRATCH16
                bcc   :ok
                rts
:ok             MOV16 DOCLINE;SCRATCH16    ; next entry = DOCLINE+1
                INC16 SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLEN            ; nextlen -> PTR1
                MOV16 COUNTL;PTR1
                jsr   LT_GETLOC            ; nextloc -> PTR2
                MOV16 PTR0;PTR2
                clc                        ; total = currlen(GAPSTART) + nextlen
                lda   GAPSTART
                adc   PTR1
                sta   SCRATCH16
                lda   GAPSTART+1
                adc   PTR1+1
                sta   SCRATCH16+1
                lda   SCRATCH16+1
                cmp   #>EDIT_LIMIT
                bcc   :feasible
                bne   :toolong
                lda   SCRATCH16
                cmp   #<EDIT_LIMIT
                bcs   :toolong
:feasible       sec                        ; GAPEND = EDITMAX - nextlen
                lda   #<EDITMAX
                sbc   PTR1
                sta   GAPEND
                lda   #>EDITMAX
                sbc   PTR1+1
                sta   GAPEND+1
                MOV16 PTR2;SRCPTR          ; copy next bytes after cursor
                clc
                lda   #<EDITBUF
                adc   GAPEND
                sta   DSTPTR
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   DSTPTR+1
                MOV16 PTR1;COUNTL
                jsr   MEMCPY_FWD
                lda   #1
                sta   EDITDIRTY
                MOV16 DOCLINE;SCRATCH16    ; delete the next entry (DOCLINE+1)
                INC16 SCRATCH16
                jsr   LINE_DELETE
                stz   RETCODE
                rts
:toolong        lda   #ERR_PARAFULL
                sta   RETCODE
                rts
