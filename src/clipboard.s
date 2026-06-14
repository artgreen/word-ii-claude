*-----------------------------------------------------------------------
* clipboard.s -- cut / copy / paste / select-all.
*
* Copy and Cut work on the current paragraph (line); Select All serializes the
* whole document (CR-separated) into the clipboard. Paste inserts the clipboard
* at the cursor, splitting on any embedded CRs. Clipboard text is stored in the
* editor's internal high-bit form in CLIPBUF, length in CLIPLEN.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* CMD_DO_COPY / CMD_DO_CUT / CMD_DO_PASTE / CMD_DO_SELALL
*-----------------------------------------------------------------------
CMD_DO_COPY     jsr   COPY_LINE
                lda   #<MSG_COPIED
                ldx   #>MSG_COPIED
                jmp   ALERT

CMD_DO_CUT      jsr   UNDO_INVAL
                jsr   COPY_LINE
                jsr   DELETE_LINE
                jsr   SET_DIRTY
                jmp   DLG_RESTORE

CMD_DO_PASTE    jsr   UNDO_INVAL
                lda   CLIPLEN
                ora   CLIPLEN+1
                beq   :empty
                jsr   PASTE_CLIP
                jsr   SET_DIRTY
                jmp   DLG_RESTORE
:empty          rts

CMD_DO_SELALL   jsr   SERIALIZE_TO_CLIP
                lda   #<MSG_ALLCOPIED
                ldx   #>MSG_ALLCOPIED
                jmp   ALERT

* SET_DIRTY -- mark the document modified.
SET_DIRTY       lda   EDITFLAGS
                ora   #FL_DIRTY
                sta   EDITFLAGS
                rts

*-----------------------------------------------------------------------
* COPY_LINE -- copy the current paragraph into CLIPBUF / CLIPLEN.
*-----------------------------------------------------------------------
COPY_LINE       jsr   PARALEN
                MOV16 COUNTL;CLIPLEN
                LDI16 EDITBUF;SRCPTR             ; before-part: GAPSTART bytes
                LDI16 CLIPBUF;DSTPTR
                MOV16 GAPSTART;COUNTL
                jsr   MEMCPY_FWD
                clc                              ; after-part src = EDITBUF + GAPEND
                lda   #<EDITBUF
                adc   GAPEND
                sta   SRCPTR
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   SRCPTR+1
                clc                              ; dst = CLIPBUF + GAPSTART
                lda   #<CLIPBUF
                adc   GAPSTART
                sta   DSTPTR
                lda   #>CLIPBUF
                adc   GAPSTART+1
                sta   DSTPTR+1
                sec                              ; count = EDITMAX - GAPEND
                lda   #<EDITMAX
                sbc   GAPEND
                sta   COUNTL
                lda   #>EDITMAX
                sbc   GAPEND+1
                sta   COUNTH
                jmp   MEMCPY_FWD

*-----------------------------------------------------------------------
* DELETE_LINE -- remove the current paragraph (Cut). Empties it if it is the
*   only paragraph; otherwise deletes its entry and reloads the neighbour.
*-----------------------------------------------------------------------
DELETE_LINE     lda   NLINES+1
                bne   :multi
                lda   NLINES
                cmp   #2
                bcs   :multi
                stz   GAPSTART                   ; sole paragraph -> empty it
                stz   GAPSTART+1
                LDI16 EDITMAX;GAPEND
                lda   #1
                sta   EDITDIRTY
                rts
:multi          MOV16 DOCLINE;SCRATCH16
                jsr   LINE_DELETE                ; drop the entry (don't flush EDITBUF)
                CMP16 DOCLINE;NLINES
                bcc   :ok
                DEC16 DOCLINE                    ; was the last paragraph
:ok             jmp   FETCHPARA

*-----------------------------------------------------------------------
* PASTE_CLIP -- insert CLIPBUF[0..CLIPLEN) at the cursor; CR -> paragraph split.
*-----------------------------------------------------------------------
PASTE_CLIP      stz   PASTEI
                stz   PASTEI+1
:loop           CMP16 PASTEI;CLIPLEN
                bcc   :body
                rts
:body           clc
                lda   #<CLIPBUF
                adc   PASTEI
                sta   PTR3
                lda   #>CLIPBUF
                adc   PASTEI+1
                sta   PTR3+1
                lda   (PTR3)
                pha
                and   #$7f
                cmp   #CR
                beq   :cr
                pla
                jsr   ED_INSERT
                bra   :next
:cr             pla
                jsr   ED_ENTER
:next           INC16 PASTEI
                bra   :loop

*-----------------------------------------------------------------------
* SERIALIZE_TO_CLIP -- copy the whole document (CR-separated) into CLIPBUF.
*-----------------------------------------------------------------------
SERIALIZE_TO_CLIP
                jsr   STOREPARA
                stz   CLIPLEN
                stz   CLIPLEN+1
                stz   SERI
                stz   SERI+1
:ploop          CMP16 SERI;NLINES
                bcc   :body
                rts
:body           MOV16 SERI;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLOC                  ; PTR0 = loc
                jsr   LT_GETLEN                  ; COUNT = len
                clc                              ; bounds: stop if CLIPLEN+len >= CLIPMAX
                lda   CLIPLEN
                adc   COUNTL
                sta   SCRATCH16
                lda   CLIPLEN+1
                adc   COUNTH
                sta   SCRATCH16+1
                lda   SCRATCH16+1
                cmp   #>CLIPMAX
                bcc   :room
                bne   :full
                lda   SCRATCH16
                cmp   #<CLIPMAX
                bcc   :room
:full           rts                              ; clipboard full -> truncate the copy
:room           MOV16 PTR0;SRCPTR
                clc                              ; dst = CLIPBUF + CLIPLEN
                lda   #<CLIPBUF
                adc   CLIPLEN
                sta   DSTPTR
                lda   #>CLIPBUF
                adc   CLIPLEN+1
                sta   DSTPTR+1
                jsr   MEMCPY_FWD
                ADD16 COUNTL;CLIPLEN
                MOV16 NLINES;SCRATCH16           ; append CR unless last paragraph
                DEC16 SCRATCH16
                CMP16 SERI;SCRATCH16
                bcs   :nocr
                clc
                lda   #<CLIPBUF
                adc   CLIPLEN
                sta   PTR3
                lda   #>CLIPBUF
                adc   CLIPLEN+1
                sta   PTR3+1
                lda   #$8d                        ; internal high-bit CR
                sta   (PTR3)
                INC16 CLIPLEN
:nocr           INC16 SERI
                jmp   :ploop

*-----------------------------------------------------------------------
* State
*-----------------------------------------------------------------------
CLIPLEN         ds    2
PASTEI          ds    2
SERI            ds    2

MSG_COPIED      asc   "Line copied.",00
MSG_ALLCOPIED   asc   "Document copied.",00
