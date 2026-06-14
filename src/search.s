*-----------------------------------------------------------------------
* search.s -- find, find-next, and replace.
*
* Search is case-insensitive. The current paragraph is flushed to the heap so
* every paragraph can be scanned uniformly; on a hit the cursor moves there.
* The scan starts after the cursor and wraps once through the document.
*-----------------------------------------------------------------------
MPTR            equ   PTR3                      ; zero-page ptr for (MPTR),y compares

*-----------------------------------------------------------------------
* CMD_DO_FIND -- prompt for a pattern, then search from the cursor.
*-----------------------------------------------------------------------
CMD_DO_FIND     lda   #<P_FIND
                ldx   #>P_FIND
                jsr   INPUT_FIELD
                bcc   :cancel
                lda   #<SEARCHPAT
                ldx   #>SEARCHPAT
                jsr   COPY_NAMEBUF             ; NAMEBUF -> SEARCHPAT
                stz   FIND_RESUME
                jsr   FIND_FROM_CURSOR
                bcc   :nf
                jmp   DLG_RESTORE
:nf             lda   #<MSG_NOTFOUND
                ldx   #>MSG_NOTFOUND
                jmp   ALERT
:cancel         rts

*-----------------------------------------------------------------------
* CMD_DO_FINDNEXT -- repeat the last search.
*-----------------------------------------------------------------------
CMD_DO_FINDNEXT lda   SEARCHPAT
                bne   :go
                lda   #<MSG_NOSRCH
                ldx   #>MSG_NOSRCH
                jmp   ALERT
:go             stz   FIND_RESUME
                jsr   FIND_FROM_CURSOR
                bcc   :nf
                jmp   DLG_RESTORE
:nf             lda   #<MSG_NOTFOUND
                ldx   #>MSG_NOTFOUND
                jmp   ALERT

*-----------------------------------------------------------------------
* CMD_DO_REPLACE -- find/replace with per-hit Y/N/All/Esc confirmation.
*-----------------------------------------------------------------------
CMD_DO_REPLACE  lda   #<P_FIND
                ldx   #>P_FIND
                jsr   INPUT_FIELD
                bcc   :cancel
                lda   #<SEARCHPAT
                ldx   #>SEARCHPAT
                jsr   COPY_NAMEBUF
                lda   #<P_REPL
                ldx   #>P_REPL
                jsr   INPUT_FIELD
                bcc   :cancel
                lda   #<REPLACEPAT
                ldx   #>REPLACEPAT
                jsr   COPY_NAMEBUF
                stz   REPLALL
                lda   #1                         ; replace resumes at the cursor column
                sta   FIND_RESUME
:loop           jsr   FIND_FROM_CURSOR
                bcc   :done
                jsr   DLG_RESTORE             ; show the hit
                lda   REPLALL
                bne   :doit                    ; already in replace-all mode
                lda   #<MSG_REPLQ
                ldx   #>MSG_REPLQ
                jsr   REPLACE_PROMPT           ; A: 0=no 1=yes 2=all 3=esc
                cmp   #3
                beq   :done
                cmp   #0
                beq   :skip
                cmp   #2
                bne   :doit
                lda   #1
                sta   REPLALL
:doit           jsr   DO_REPLACE_AT
                bra   :loop
:skip           lda   SEARCHPAT                ; step past the whole hit, keep searching
                sta   TMPA
:sk             jsr   GAP_RIGHT
                dec   TMPA
                bne   :sk
                bra   :loop
:done           jmp   DLG_RESTORE
:cancel         rts

* DO_REPLACE_AT -- the cursor is at a match; delete PATLEN chars, insert the
*   replacement text in their place.
DO_REPLACE_AT   lda   SEARCHPAT
                sta   TMPA                       ; chars to delete
:del            lda   TMPA
                beq   :ins
                jsr   GAP_DELFWD
                dec   TMPA
                bra   :del
:ins            ldx   #0
:il             cpx   REPLACEPAT
                bcs   :done
                lda   REPLACEPAT+1,x
                ora   #$80                       ; store internal high-bit
                phx
                jsr   GAP_INSCHAR                ; pure insert (NOT ED_INSERT, which honors OVR)
                plx
                inx
                bra   :il
:done           rts

*-----------------------------------------------------------------------
* FIND_FROM_CURSOR -- search forward (wrapping once) for SEARCHPAT. On a hit,
*   move the cursor there and return carry set; carry clear if not found.
*-----------------------------------------------------------------------
FIND_FROM_CURSOR
                jsr   UNDO_INVAL              ; cursor will move paragraphs
                lda   SEARCHPAT
                bne   :go
                clc
                rts
:go             jsr   STOREPARA
                MOV16 DOCLINE;FINDLINE
                MOV16 GAPSTART;FINDCOL
                lda   FIND_RESUME              ; resume (replace/skip) scans from the cursor
                bne   :noinc                    ;   column itself; a fresh Find skips it
                INC16 FINDCOL
:noinc          MOV16 NLINES;FINDLEFT           ; +1 so the start paragraph is re-scanned
                INC16 FINDLEFT                  ;   from column 0 on wrap-around
:ploop          CMP16 FINDLINE;NLINES
                bcc   :inrange
                stz   FINDLINE                   ; wrap to top
                stz   FINDLINE+1
                stz   FINDCOL
                stz   FINDCOL+1
:inrange        MOV16 FINDLINE;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLOC                  ; PTR0 = loc
                jsr   LT_GETLEN                  ; COUNT = len
                jsr   SCAN_PARA
                bcs   :found
                INC16 FINDLINE
                stz   FINDCOL
                stz   FINDCOL+1
                DEC16 FINDLEFT
                lda   FINDLEFT
                ora   FINDLEFT+1
                bne   :ploop
                clc
                rts
:found          MOV16 FINDLINE;DOCLINE
                jsr   FETCHPARA
                MOV16 FINDRESULT;PTR2
                jsr   CURSOR_SET_COL
                sec
                rts

* SCAN_PARA -- search heap paragraph (PTR0=loc, COUNT=len) from FINDCOL for
*   SEARCHPAT. Carry set + position in FINDRESULT if found.
SCAN_PARA       lda   SEARCHPAT
                sta   PATLEN
                sec                              ; maxstart = len - patlen
                lda   COUNTL
                sbc   PATLEN
                sta   MAXSTART
                lda   COUNTH
                sbc   #0
                sta   MAXSTART+1
                bcc   :no                        ; len < patlen
                MOV16 FINDCOL;POS
:posloop        CMP16 POS;MAXSTART
                beq   :check
                bcs   :no                        ; POS > maxstart
:check          jsr   MATCH_AT_POS
                bcs   :hit
                INC16 POS
                bra   :posloop
:hit            MOV16 POS;FINDRESULT
                sec
                rts
:no             clc
                rts

* MATCH_AT_POS -- compare SEARCHPAT against heap[loc+POS], case-insensitive.
MATCH_AT_POS    clc
                lda   PTR0
                adc   POS
                sta   MPTR
                lda   PTR0+1
                adc   POS+1
                sta   MPTR+1
                ldy   #0
:cmp            lda   (MPTR),y
                jsr   UPCASE
                sta   TMPA
                lda   SEARCHPAT+1,y
                jsr   UPCASE
                cmp   TMPA
                bne   :no
                iny
                cpy   PATLEN
                bcc   :cmp
                sec
                rts
:no             clc
                rts

*-----------------------------------------------------------------------
* COPY_NAMEBUF -- copy NAMEBUF (len-prefixed) to the buffer at A=lo/X=hi.
*-----------------------------------------------------------------------
COPY_NAMEBUF    sta   DSTPTR
                stx   DSTPTR+1
                ldy   #0
                lda   NAMEBUF
                tay
:cp             lda   NAMEBUF,y
                sta   (DSTPTR),y
                dey
                bpl   :cp
                rts

*-----------------------------------------------------------------------
* REPLACE_PROMPT -- box with A=lo/X=hi message; returns A: 0=No 1=Yes 2=All 3=Esc
*-----------------------------------------------------------------------
REPLACE_PROMPT  sta   STRPTR
                stx   STRPTR+1
                LDI16 T_REPLACE;DLGTITLE
                jsr   OPENBOX
                LDI16 MSG_YNAE;STRPTR
                lda   #DLG_FOOTROW
                jsr   PRCENTER
:k              jsr   GETKEY
                cmp   #$d9                       ; Y
                beq   :yes
                cmp   #$f9
                beq   :yes
                cmp   #$c1                       ; A
                beq   :all
                cmp   #$e1
                beq   :all
                cmp   #$ce                       ; N
                beq   :no
                cmp   #$ee
                beq   :no
                cmp   #K_ESC
                beq   :esc
                bra   :k
:yes            lda   #1
                bra   :ret
:all            lda   #2
                bra   :ret
:no             lda   #0
                bra   :ret
:esc            lda   #3
:ret            sta   RPRES
                jsr   DLG_RESTORE
                lda   RPRES
                rts

*-----------------------------------------------------------------------
* State
*-----------------------------------------------------------------------
SEARCHPAT       ds    64
REPLACEPAT      ds    64
PATLEN          dfb   0
REPLALL         dfb   0
RPRES           dfb   0
FIND_RESUME     dfb   0                         ; 1 = scan from the cursor column (replace/skip)
POS             ds    2
MAXSTART        ds    2
FINDLINE        ds    2
FINDCOL         ds    2
FINDLEFT        ds    2
FINDRESULT      ds    2

P_FIND          asc   "Find:",00
P_REPL          asc   "Replace with:",00
MSG_NOTFOUND    asc   "Not found.",00
MSG_NOSRCH      asc   "No previous search.",00
MSG_REPLQ       asc   "Replace this one?",00
MSG_YNAE        asc   "Y=Yes  N=No  A=All  Esc=Stop",00
