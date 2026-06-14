*-----------------------------------------------------------------------
* render.s -- flicker-free compositing renderer with word wrap.
*
* Every redrawn row (text rows and the status line) is composed into a pair of
* 40-byte RAM buffers -- AUXROW (even columns) and MAINROW (odd columns) -- then
* blitted to screen RAM in ONE pass per bank. Each cell goes straight from its
* old code to its new code with no intervening clear, so there is no visible
* blank frame, and the per-row bank switch (2 instead of 80) makes redraw cheap.
*
* Paragraphs are greedily word-wrapped at MARGIN columns (breaking at spaces;
* a word longer than MARGIN is hard-broken). The current paragraph is
* materialized from its gap buffer into RENDBUF once per frame; others render
* straight from the heap. Tab display is deferred to the M4 tabs feature.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* Row-buffer primitives
*-----------------------------------------------------------------------

* RB_CLEAR -- fill both row buffers with code A.
RB_CLEAR        ldx   #39
:c              sta   AUXROW,x
                sta   MAINROW,x
                dex
                bpl   :c
                rts

* RB_PUT -- place code A at column Y (even->aux, odd->main). Preserves Y.
RB_PUT          pha
                tya
                lsr
                tax
                pla
                bcs   :main
                sta   AUXROW,x
                rts
:main           sta   MAINROW,x
                rts

* RB_PUTSTR_INV -- place zero-terminated ASCII at STRPTR, inverse, from column
*   TMPC. Leaves TMPC = next free column.
RB_PUTSTR_INV   lda   TMPC
                sta   LOOPJ
                ldy   #0
:lp             lda   (STRPTR),y
                beq   :done
                jsr   TOINV
                phy
                ldy   LOOPJ
                jsr   RB_PUT
                ply
                inc   LOOPJ
                iny
                bne   :lp
:done           lda   LOOPJ
                sta   TMPC
                rts

* RB_PUTDEC_INV -- place COUNT as decimal, inverse, from column TMPC.
RB_PUTDEC_INV   jsr   NUM2DEC
                lda   #<DECBUF
                sta   STRPTR
                lda   #>DECBUF
                sta   STRPTR+1
                jmp   RB_PUTSTR_INV

* RB_BLIT -- write both row buffers to screen row CURROW (aux then main).
RB_BLIT         ldx   CURROW
                lda   BASEL,x
                sta   SCRPTR
                lda   BASEH,x
                sta   SCRPTR+1
                sta   TXTPAGE2
                ldy   #39
:a              lda   AUXROW,y
                sta   (SCRPTR),y
                dey
                bpl   :a
                sta   TXTPAGE1
                ldy   #39
:m              lda   MAINROW,y
                sta   (SCRPTR),y
                dey
                bpl   :m
                rts

*-----------------------------------------------------------------------
* RENDER -- repaint the text viewport (rows 2..21), word-wrapped, flicker-free.
*-----------------------------------------------------------------------
* RENDER repaints the viewport. As an optimization, an in-paragraph edit sets
* RENDER_INCR so only the cursor's paragraph and the rows below it are rebuilt
* (rows above can't have changed); any scroll or non-typing action falls back
* to a full repaint. The full path is always correct, so incremental only ever
* skips rows that provably did not change.
RENDER          jsr   ENSURE_VISIBLE
                lda   RENDER_INCR             ; decide full vs incremental
                beq   :full
                CMP16 VPTOP;OLDVPTOP
                bne   :full                    ; scrolled -> must repaint all
                stz   DRAWALL
                bra   :saved
:full           lda   #1
                sta   DRAWALL
:saved          MOV16 VPTOP;OLDVPTOP
                stz   RENDER_INCR
                jsr   MATERIALIZE_CURRENT
                stz   LOOPI                  ; viewport row 0..NTXTROWS-1
                MOV16 VPTOP;ROWPARA
:nextpara       lda   LOOPI
                cmp   #NTXTROWS
                bcs   :done
                CMP16 ROWPARA;NLINES
                bcs   :blanks
                jsr   SETUP_ROWPARA
                stz   RENDOFF
                stz   RENDOFF+1
:nextrow        MOV16 RENDOFF;ROWSTART
                jsr   FIND_WRAP              ; ROWCOUNT, RENDOFF->next row start
                jsr   ROW_DRAWP              ; skip rows above the cursor paragraph
                bcc   :skiprow
                jsr   BUILD_WRAPPED_ROW
                jsr   BUILD_SCROLLBAR
                clc
                lda   #ROW_TXT0
                adc   LOOPI
                sta   CURROW
                jsr   RB_BLIT
:skiprow        inc   LOOPI
                lda   LOOPI
                cmp   #NTXTROWS
                bcs   :done
                CMP16 RENDOFF;RENDLEN
                bcc   :nextrow               ; more wrapped rows in this paragraph
                INC16 ROWPARA
                bra   :nextpara
:blanks         lda   #SPC
                jsr   RB_CLEAR
                jsr   BUILD_SCROLLBAR
                clc
                lda   #ROW_TXT0
                adc   LOOPI
                sta   CURROW
                jsr   RB_BLIT
                inc   LOOPI
                lda   LOOPI
                cmp   #NTXTROWS
                bcc   :blanks
:done           rts

*-----------------------------------------------------------------------
* FIND_WRAP -- choose this row's break. In: RENDOFF (= ROWSTART), RENDSRC,
*   RENDLEN, MARGIN. Out: ROWCOUNT chars to place; RENDOFF advanced to the next
*   row's start (skipping the break space).
*-----------------------------------------------------------------------
FIND_WRAP       sec                            ; remaining = RENDLEN - RENDOFF
                lda   RENDLEN
                sbc   RENDOFF
                sta   SCRATCH16
                lda   RENDLEN+1
                sbc   RENDOFF+1
                sta   SCRATCH16+1
                lda   SCRATCH16+1
                bne   :wrap                     ; remaining >= 256 -> must wrap
                lda   MARGIN
                cmp   SCRATCH16
                bcc   :wrap                     ; MARGIN < remaining -> must wrap
                lda   SCRATCH16                  ; whole rest fits on one row
                sta   ROWCOUNT
                MOV16 RENDLEN;RENDOFF
                rts
:wrap           clc                            ; PTR3 = RENDSRC + RENDOFF
                lda   RENDSRC
                adc   RENDOFF
                sta   PTR3
                lda   RENDSRC+1
                adc   RENDOFF+1
                sta   PTR3+1
                ldy   MARGIN                     ; scan back from the margin for a space
:scan           lda   (PTR3),y
                cmp   #SPC
                beq   :space
                dey
                bne   :scan
                lda   MARGIN                     ; no space: hard-break at the margin
                sta   ROWCOUNT
                clc
                lda   RENDOFF
                adc   MARGIN
                sta   RENDOFF
                lda   RENDOFF+1
                adc   #0
                sta   RENDOFF+1
                rts
:space          sty   ROWCOUNT                   ; break before the space at index Y
                clc
                lda   RENDOFF
                adc   ROWCOUNT
                sta   RENDOFF
                lda   RENDOFF+1
                adc   #0
                sta   RENDOFF+1
                INC16 RENDOFF                    ; skip the space
                rts

*-----------------------------------------------------------------------
* BUILD_WRAPPED_ROW -- place ROWCOUNT chars from RENDSRC[ROWSTART] into the row
*   buffers, then the block cursor if this is the cursor paragraph.
*-----------------------------------------------------------------------
BUILD_WRAPPED_ROW
                lda   #SPC
                jsr   RB_CLEAR
                clc                            ; PTR3 = RENDSRC + ROWSTART
                lda   RENDSRC
                adc   ROWSTART
                sta   PTR3
                lda   RENDSRC+1
                adc   ROWSTART+1
                sta   PTR3+1
                ldy   #0
:pl             cpy   ROWCOUNT
                bcs   :cursor
                lda   (PTR3),y
                jsr   RB_PUT                    ; A=char, Y=column (preserved)
                iny
                bne   :pl
:cursor         lda   ROWPARA
                cmp   DOCLINE
                bne   :done
                lda   ROWPARA+1
                cmp   DOCLINE+1
                bne   :done
                jsr   WRAP_CURSOR
:done           rts

*-----------------------------------------------------------------------
* WRAP_CURSOR -- draw the block cursor if GAPSTART falls on this wrapped row.
*   This row covers paragraph bytes [ROWSTART, RENDOFF).
*-----------------------------------------------------------------------
WRAP_CURSOR     CMP16 GAPSTART;ROWSTART
                bcc   :no                       ; cursor before this row
                CMP16 GAPSTART;RENDOFF
                bcc   :here                      ; within this row
                CMP16 RENDOFF;RENDLEN            ; else only if this is the last row
                bcc   :no                        ; not last row -> a later row owns it
:here           sec                              ; cursorcol = GAPSTART - ROWSTART
                lda   GAPSTART
                sbc   ROWSTART
                sta   TMPC
                lda   TMPC
                cmp   #TXTWIDTH
                bcc   :ok
                lda   #TXTWIDTH-1
                sta   TMPC
:ok             clc
                lda   #ROW_TXT0
                adc   LOOPI
                sta   VPROW
                lda   TMPC
                sta   VPCOL
                CMP16 GAPSTART;RENDLEN            ; char under cursor (space past end)
                bcs   :space
                clc
                lda   RENDSRC
                adc   GAPSTART
                sta   PTR3
                lda   RENDSRC+1
                adc   GAPSTART+1
                sta   PTR3+1
                lda   (PTR3)
                bra   :inv
:space          lda   #SPC
:inv            and   #$7f
                jsr   TOINV
                ldy   TMPC
                jmp   RB_PUT
:no             rts

*-----------------------------------------------------------------------
* BUILD_SCROLLBAR -- column-79 marker for the current viewport row (LOOPI).
*-----------------------------------------------------------------------
BUILD_SCROLLBAR lda   LOOPI
                bne   :notop
                lda   #MT_UP
                bra   :place
:notop          cmp   #NTXTROWS-1
                bne   :mid
                lda   #MT_DOWN
                bra   :place
:mid            jsr   THUMBROW
                cmp   LOOPI
                bne   :track
                lda   #MT_BLOCK
                bra   :place
:track          lda   #MT_VLINE
:place          ldy   #COL_SB
                jmp   RB_PUT

* THUMBROW -- A := viewport row of the scroll thumb (1..NTXTROWS-2), a simple
*   position indicator that tracks VPTOP down the bar.
THUMBROW        lda   VPTOP+1
                bne   :bot
                lda   VPTOP
                cmp   #NTXTROWS-2
                bcs   :bot
                clc
                adc   #1
                rts
:bot            lda   #NTXTROWS-2
                rts

* ROW_DRAWP -- carry set if the current row should be (re)drawn. Full repaint
*   draws everything; an incremental repaint draws only ROWPARA >= DOCLINE.
ROW_DRAWP       lda   DRAWALL
                bne   :yes
                CMP16 ROWPARA;DOCLINE
                bcs   :yes
                clc
                rts
:yes            sec
                rts

*-----------------------------------------------------------------------
* ENSURE_VISIBLE -- scroll VPTOP (paragraph granularity) to keep the cursor's
*   paragraph on screen. Tall-paragraph sub-scrolling is refined in M5.
*-----------------------------------------------------------------------
ENSURE_VISIBLE  CMP16 DOCLINE;VPTOP
                bcs   :below
                MOV16 DOCLINE;VPTOP
                rts
:below          clc
                lda   VPTOP
                adc   #NTXTROWS
                sta   SCRATCH16
                lda   VPTOP+1
                adc   #0
                sta   SCRATCH16+1
                CMP16 DOCLINE;SCRATCH16
                bcc   :done
                sec
                lda   DOCLINE
                sbc   #NTXTROWS-1
                sta   VPTOP
                lda   DOCLINE+1
                sbc   #0
                sta   VPTOP+1
:done           rts

*-----------------------------------------------------------------------
* MATERIALIZE_CURRENT -- copy the current paragraph (gap buffer) into RENDBUF.
*-----------------------------------------------------------------------
MATERIALIZE_CURRENT
                LDI16 EDITBUF;SRCPTR
                LDI16 RENDBUF;DSTPTR
                MOV16 GAPSTART;COUNTL
                jsr   MEMCPY_FWD
                clc
                lda   #<EDITBUF
                adc   GAPEND
                sta   SRCPTR
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   SRCPTR+1
                clc
                lda   #<RENDBUF
                adc   GAPSTART
                sta   DSTPTR
                lda   #>RENDBUF
                adc   GAPSTART+1
                sta   DSTPTR+1
                sec
                lda   #<EDITMAX
                sbc   GAPEND
                sta   COUNTL
                lda   #>EDITMAX
                sbc   GAPEND+1
                sta   COUNTH
                jsr   MEMCPY_FWD
                rts

*-----------------------------------------------------------------------
* SETUP_ROWPARA -- set RENDSRC/RENDLEN for paragraph ROWPARA.
*-----------------------------------------------------------------------
SETUP_ROWPARA   CMP16 ROWPARA;DOCLINE
                bne   :heap
                LDI16 RENDBUF;RENDSRC
                jsr   PARALEN
                MOV16 COUNTL;RENDLEN
                rts
:heap           MOV16 ROWPARA;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLOC
                MOV16 PTR0;RENDSRC
                jsr   LT_GETLEN
                MOV16 COUNTL;RENDLEN
                rts

*-----------------------------------------------------------------------
* STATUS_REFRESH -- compose and blit the status line (row 23), flicker-free.
*-----------------------------------------------------------------------
STATUS_REFRESH  lda   #$20
                jsr   RB_CLEAR
                lda   DOCNAME                    ; real document name, or UNTITLED
                beq   :untitled
                LDI16 DOCNAME;STRPTR
                bra   :name
:untitled       LDI16 STDOCNAME;STRPTR
:name           lda   #1
                sta   TMPC
                jsr   RB_PUTSTR_INV             ; leaves TMPC at the next column
                lda   EDITFLAGS
                and   #FL_DIRTY
                beq   :lc
                inc   TMPC                       ; one space, then the dirty mark
                ldy   TMPC
                lda   #$2a                       ; inverse '*'
                jsr   RB_PUT
:lc             lda   #'L'
                jsr   TOINV
                ldy   #38
                jsr   RB_PUT
                lda   #39
                sta   TMPC
                MOV16 DOCLINE;COUNTL
                INC16 COUNTL
                jsr   RB_PUTDEC_INV
                lda   #' '
                jsr   TOINV
                ldy   TMPC
                jsr   RB_PUT
                inc   TMPC
                lda   #'C'
                jsr   TOINV
                ldy   TMPC
                jsr   RB_PUT
                inc   TMPC
                MOV16 GAPSTART;COUNTL
                INC16 COUNTL
                jsr   RB_PUTDEC_INV
                lda   EDITFLAGS
                and   #FL_OVERWRITE
                beq   :ins
                LDI16 STOVR;STRPTR
                bra   :pmode
:ins            LDI16 STINS;STRPTR
:pmode          lda   #54
                sta   TMPC
                jsr   RB_PUTSTR_INV
                LDI16 STFREE;STRPTR
                lda   #60
                sta   TMPC
                jsr   RB_PUTSTR_INV
                jsr   HEAP_USED                  ; COUNT = live document bytes
                sec                              ; FREE = capacity - used (tracks deletes)
                lda   #<HEAPCAP
                sbc   COUNTL
                sta   COUNTL
                lda   #>HEAPCAP
                sbc   COUNTH
                sta   COUNTH
                jsr   RB_PUTDEC_INV
                lda   #71                        ; /RAM status
                sta   TMPC
                lda   HASRAM
                beq   :noram
                LDI16 STRAM;STRPTR
                bra   :ramdone
:noram          LDI16 STNORAM;STRPTR
:ramdone        jsr   RB_PUTSTR_INV
                lda   #ROW_STAT
                sta   CURROW
                jmp   RB_BLIT

*-----------------------------------------------------------------------
* NUM2DEC -- COUNT (consumed) -> zero-terminated decimal ASCII in DECBUF.
*-----------------------------------------------------------------------
NUM2DEC         ldx   #0
                ldy   #0
                stz   TMPA
:pw             lda   #$ff
                sta   TMPB
:sub            inc   TMPB
                sec
                lda   COUNTL
                sbc   POW10L,x
                sta   SCRATCH16
                lda   COUNTH
                sbc   POW10H,x
                sta   SCRATCH16+1
                bcc   :under
                MOV16 SCRATCH16;COUNTL
                bra   :sub
:under          lda   TMPB
                bne   :emit
                lda   TMPA
                bne   :emit
                cpx   #4
                beq   :emit
                bra   :next
:emit           lda   #1
                sta   TMPA
                lda   TMPB
                ora   #$30
                sta   DECBUF,y
                iny
:next           inx
                cpx   #5
                bcc   :pw
                lda   #0
                sta   DECBUF,y
                rts

POW10L          dfb   <10000,<1000,<100,<10,<1
POW10H          dfb   >10000,>1000,>100,>10,>1
DECBUF          ds    8
AUXROW          ds    40
MAINROW         ds    40
ROWSTART        ds    2
RENDER_INCR     dfb   0                         ; set by in-paragraph edits
DRAWALL         dfb   1                         ; this frame: 1=full, 0=incremental
OLDVPTOP        ds    2                         ; VPTOP at the previous frame

STDOCNAME       asc   "UNTITLED",00
STINS           asc   "INS",00
STOVR           asc   "OVR",00
STFREE          asc   "FREE ",00
STRAM           asc   "/RAM",00
STNORAM         asc   "no /RAM",00
