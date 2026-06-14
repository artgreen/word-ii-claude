*-----------------------------------------------------------------------
* reflow.s -- configurable margin, paragraph reflow, and tabs.
*
* The display already word-wraps at MARGIN, so "margin" just re-wraps. Reflow
* joins the current paragraph with the following non-blank paragraphs (turning
* hard-wrapped imported text into one soft-wrapped paragraph). Tabs are soft:
* the Tab key inserts spaces to the next TABW-aligned column.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* CMD_DO_MARGINS / CMD_DO_TABS -- prompt for a number and update the setting.
*-----------------------------------------------------------------------
CMD_DO_MARGINS  lda   #<P_MARGIN
                ldx   #>P_MARGIN
                jsr   INPUT_FIELD
                bcc   :cancel
                jsr   PARSE_NUM
                cmp   #20                       ; clamp 20..78
                bcs   :lo
                lda   #20
:lo             cmp   #79
                bcc   :ok
                lda   #78
:ok             sta   MARGIN
                jmp   DLG_RESTORE
:cancel         rts

CMD_DO_TABS     lda   #<P_TAB
                ldx   #>P_TAB
                jsr   INPUT_FIELD
                bcc   :cancel
                jsr   PARSE_NUM
                cmp   #1
                bcs   :lo
                lda   #1
:lo             cmp   #17
                bcc   :ok
                lda   #16
:ok             sta   TABW
                jmp   DLG_RESTORE
:cancel         rts

*-----------------------------------------------------------------------
* CMD_DO_REFLOW -- join the current paragraph with following non-blank ones.
*-----------------------------------------------------------------------
CMD_DO_REFLOW   jsr   UNDO_INVAL
:loop           MOV16 NLINES;SCRATCH16          ; is there a next paragraph?
                DEC16 SCRATCH16
                CMP16 DOCLINE;SCRATCH16
                bcs   :done                      ; current is the last paragraph
                MOV16 DOCLINE;SCRATCH16          ; next paragraph empty -> stop
                INC16 SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLEN
                lda   COUNTL
                ora   COUNTH
                beq   :done
                jsr   GAP_END_MOVE              ; to end of current paragraph
                lda   #SPC                       ; separate the joined lines
                jsr   ED_INSERT
                jsr   ED_JOIN_NEXT
                bra   :loop
:done           lda   EDITFLAGS
                ora   #FL_DIRTY
                sta   EDITFLAGS
                jmp   DLG_RESTORE

*-----------------------------------------------------------------------
* ED_TAB -- insert spaces to the next TABW-aligned column (soft tab).
*-----------------------------------------------------------------------
ED_TAB          CMP16 GAPSTART;GAPEND           ; paragraph already full -> do nothing
                beq   :done
                lda   #SPC
                jsr   ED_INSERT                 ; at least one
:lp             jsr   GAP_MOD_TABW
                beq   :done
                CMP16 GAPSTART;GAPEND           ; full now? stop (insert can't advance -> would hang)
                beq   :done
                lda   #SPC
                jsr   ED_INSERT
                bra   :lp
:done           rts

* GAP_MOD_TABW -- A := GAPSTART mod TABW (TABW is 1..16).
GAP_MOD_TABW    MOV16 GAPSTART;SCRATCH16
:s              lda   SCRATCH16+1
                bne   :sub                       ; high byte set -> still >= TABW
                lda   SCRATCH16
                cmp   TABW
                bcc   :done
:sub            sec
                lda   SCRATCH16
                sbc   TABW
                sta   SCRATCH16
                lda   SCRATCH16+1
                sbc   #0
                sta   SCRATCH16+1
                bra   :s
:done           lda   SCRATCH16
                rts

*-----------------------------------------------------------------------
* PARSE_NUM -- NAMEBUF (length-prefixed ASCII digits) -> A (0..255, wraps).
*-----------------------------------------------------------------------
PARSE_NUM       stz   TMPA
                ldy   #1
:lp             cpy   NAMEBUF
                beq   :dig
                bcs   :done
:dig            lda   NAMEBUF,y
                sec
                sbc   #'0'
                cmp   #10
                bcs   :done                      ; non-digit ends parsing
                sta   TMPB
                lda   TMPA                        ; result = result*10 + digit
                asl
                sta   TMPC                        ; result*2
                asl
                asl                               ; result*8
                clc
                adc   TMPC                         ; result*10
                clc
                adc   TMPB
                sta   TMPA
                iny
                bra   :lp
:done           lda   TMPA
                rts

*-----------------------------------------------------------------------
* CMD_DO_GOTO -- jump the cursor to a 1-based line (paragraph) number.
*-----------------------------------------------------------------------
CMD_DO_GOTO     lda   #<P_GOTO
                ldx   #>P_GOTO
                jsr   INPUT_FIELD
                bcc   :cancel
                jsr   PARSE_NUM16             ; COUNT = line number (1-based)
                lda   COUNTL
                ora   COUNTH
                bne   :nz
                lda   #1
                sta   COUNTL
:nz             DEC16 COUNTL                  ; 0-based target
                MOV16 NLINES;SCRATCH16        ; clamp to NLINES-1
                DEC16 SCRATCH16
                CMP16 COUNTL;SCRATCH16
                bcc   :ok
                MOV16 SCRATCH16;COUNTL
:ok             jsr   UNDO_INVAL
                MOV16 COUNTL;PTR2             ; preserve target across STOREPARA
                jsr   STOREPARA
                bcs   :cancel
                MOV16 PTR2;DOCLINE
                jsr   FETCHPARA
                jmp   DLG_RESTORE
:cancel         rts

*-----------------------------------------------------------------------
* CMD_DO_WORDCOUNT -- count words across the whole document and report it.
*-----------------------------------------------------------------------
CMD_DO_WORDCOUNT
                jsr   STOREPARA                ; flush so every paragraph is in the heap
                stz   WCOUNTL
                stz   WCOUNTH
                stz   WCPARA
                stz   WCPARA+1
:ploop          CMP16 WCPARA;NLINES
                bcs   :report
                MOV16 WCPARA;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLOC                ; PTR0 = loc
                jsr   LT_GETLEN                ; COUNT = len
                jsr   COUNT_WORDS_IN_PARA
                INC16 WCPARA
                bra   :ploop
:report         ldx   #0                        ; build "Words: NNN"
:c1             lda   WCPREFIX,x
                beq   :c2
                sta   WCMSG,x
                inx
                bra   :c1
:c2             stx   TMPC                       ; NUM2DEC reuses X, so park the index
                MOV16 WCOUNTL;COUNTL
                jsr   NUM2DEC                  ; DECBUF = decimal
                ldx   TMPC                       ; resume appending after the prefix
                ldy   #0
:c3             lda   DECBUF,y
                sta   WCMSG,x
                beq   :c4
                inx
                iny
                bra   :c3
:c4             lda   #<WCMSG
                ldx   #>WCMSG
                jmp   ALERT

* COUNT_WORDS_IN_PARA -- add word starts in heap paragraph (PTR0=loc, COUNT=len).
COUNT_WORDS_IN_PARA
                MOV16 PTR0;PTR3
                stz   TMPA                       ; not in a word
:loop           lda   COUNTL
                ora   COUNTH
                beq   :done
                lda   (PTR3)
                and   #$7f
                cmp   #' '+1                      ; <= space -> whitespace
                bcc   :ws
                lda   TMPA                        ; non-space
                bne   :adv                        ; already in a word
                INC16 WCOUNTL                     ; word start
                lda   #1
                sta   TMPA
                bra   :adv
:ws             stz   TMPA
:adv            INC16 PTR3
                DEC16 COUNTL
                bra   :loop
:done           rts

*-----------------------------------------------------------------------
* PARSE_NUM16 -- NAMEBUF (length-prefixed ASCII digits) -> COUNT (16-bit).
*-----------------------------------------------------------------------
PARSE_NUM16     stz   COUNTL
                stz   COUNTH
                ldy   #1
:lp             cpy   NAMEBUF
                beq   :dig
                bcs   :done
:dig            lda   NAMEBUF,y
                sec
                sbc   #'0'
                cmp   #10
                bcs   :done
                sta   TMPB
                MOV16 COUNTL;SCRATCH16           ; COUNT = COUNT*10 + digit
                asl   SCRATCH16
                rol   SCRATCH16+1                 ; SCRATCH16 = COUNT*2
                MOV16 SCRATCH16;COUNTL
                asl   COUNTL
                rol   COUNTH
                asl   COUNTL
                rol   COUNTH                      ; COUNT = (COUNT*2)*4 = COUNT*8
                ADD16 SCRATCH16;COUNTL            ; + COUNT*2  -> COUNT*10
                clc
                lda   COUNTL
                adc   TMPB
                sta   COUNTL
                lda   COUNTH
                adc   #0
                sta   COUNTH
                iny
                bra   :lp
:done           rts

WCOUNTL         dfb   0
WCOUNTH         dfb   0
WCPARA          ds    2
WCMSG           ds    32

P_MARGIN        asc   "Right margin (20-78):",00
P_TAB           asc   "Tab width (1-16):",00
P_GOTO          asc   "Go to line:",00
WCPREFIX        asc   "Words: ",00
