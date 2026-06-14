*-----------------------------------------------------------------------
* screen.s -- 80-column text driver. Writes screen RAM directly: even columns
* live in aux ($0400-$07FF aux), odd in main, byte offset within a row = col/2.
* PAGE2 (TXTPAGE1/2) selects the bank while 80STORE is on. No ROM/firmware use.
*
* Char model: PUTRAW writes a RAW screen code. With ALTCHARSET on:
*   $00-$1F inverse caps, $20-$3F inverse symbols, $40-$5F MouseText,
*   $60-$7F inverse lowercase, $80-$FF normal video.
* TONORM/TOINV translate plain ASCII ($20-$7F) to normal/inverse codes.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* SCRINIT -- 80-column text, MouseText character set, full screen, page 1.
*-----------------------------------------------------------------------
SCRINIT         sta   TXTSET            ; text mode
                sta   MIXCLR            ; full screen
                lda   LORES             ; keep graphics latch out of hi-res
                sta   SET80COL          ; 80-column display
                sta   SET80STORE        ; PAGE2 banks the $0400 window
                sta   SETALTCHAR        ; MouseText / alternate set
                sta   TXTPAGE1          ; default to the main half
                rts

*-----------------------------------------------------------------------
* SCRCLR -- clear the whole 80-column screen to normal-video spaces.
*-----------------------------------------------------------------------
SCRCLR          sta   TXTPAGE2          ; aux half (even columns)
                jsr   :fill
                sta   TXTPAGE1          ; main half (odd columns)
                jsr   :fill
                rts
:fill           lda   #<$0400
                sta   SCRPTR
                lda   #>$0400
                sta   SCRPTR+1
                ldx   #4                 ; 4 pages = $0400..$07FF
                ldy   #0
                lda   #SPC
:f1             sta   (SCRPTR),y
                iny
                bne   :f1
                inc   SCRPTR+1
                dex
                bne   :f1
                rts

*-----------------------------------------------------------------------
* PUTRAW -- write raw screen code A at CURROW,CURCOL; advance CURCOL.
*   Preserves A, X, Y (a clean one-char primitive).
*-----------------------------------------------------------------------
PUTRAW          phx
                phy
                pha                      ; save the character (top of stack)
                ldx   CURROW
                lda   BASEL,x
                sta   SCRPTR
                lda   BASEH,x
                sta   SCRPTR+1
                lda   CURCOL
                lsr                      ; A=col/2, C=col&1
                tay
                bcs   :odd               ; odd -> main
                sta   TXTPAGE2           ; even -> aux
                bra   :put
:odd            sta   TXTPAGE1
:put            pla                      ; character back into A
                sta   (SCRPTR),y
                sta   TXTPAGE1           ; leave main bank selected
                inc   CURCOL
                ply
                plx
                rts

*-----------------------------------------------------------------------
* GOTORC -- set the cursor: A = row, Y = col.
*-----------------------------------------------------------------------
GOTORC          sta   CURROW
                sty   CURCOL
                rts

*-----------------------------------------------------------------------
* TONORM / TOINV -- map plain ASCII in A ($20-$7F) to a screen code.
*   TONORM -> normal video ( | $80 ). TOINV -> inverse band.
*-----------------------------------------------------------------------
TONORM          ora   #$80
                rts
TOINV           and   #$7f               ; fold normal (high-bit) text to 7-bit first,
                cmp   #$60               ;   so inverting works on `asc` strings too
                bcs   :keep              ; $60-$7F inverse lowercase stays
                cmp   #$40
                bcc   :keep              ; $20-$3F inverse symbols stay
                and   #$1f               ; $40-$5F -> $00-$1F inverse caps
:keep           rts

*-----------------------------------------------------------------------
* PRNORMZ / PRINVZ -- print the zero-terminated ASCII string at STRPTR,
*   starting at CURROW,CURCOL, as normal / inverse video.
*-----------------------------------------------------------------------
PRNORMZ         ldy   #0
:pl             lda   (STRPTR),y
                beq   :done
                jsr   TONORM
                jsr   PUTRAW             ; preserves Y
                iny
                bne   :pl
:done           rts

PRINVZ          ldy   #0
:pl             lda   (STRPTR),y
                beq   :done
                jsr   TOINV
                jsr   PUTRAW             ; preserves Y
                iny
                bne   :pl
:done           rts

*-----------------------------------------------------------------------
* SETSTR -- point STRPTR at A=lo / X=hi (a string address).
*-----------------------------------------------------------------------
SETSTR          sta   STRPTR
                stx   STRPTR+1
                rts

*-----------------------------------------------------------------------
* FILLSPAN -- write screen code A, X times (X must be >= 1), from CURROW,CURCOL.
*   Advances CURCOL by X; leaves A = code. Uses NO zero-page scratch: PUTRAW
*   preserves A/X/Y, so the count stays in X and the code in A across the loop.
*   (Earlier this aliased TMPC/TMPD with DRAWBOX's width/height -- never reuse
*   shared scratch across a subroutine that also uses it.)
*-----------------------------------------------------------------------
FILLSPAN        jsr   PUTRAW
                dex
                bne   FILLSPAN
                rts

*-----------------------------------------------------------------------
* Text row base table -- 80-col shares 40-col bases; the bank switch picks
* main vs aux. base(row) = $0400 + (row%8)*$80 + (row/8)*$28.
*-----------------------------------------------------------------------
BASEL           dfb   <$0400,<$0480,<$0500,<$0580,<$0600,<$0680,<$0700,<$0780
                dfb   <$0428,<$04a8,<$0528,<$05a8,<$0628,<$06a8,<$0728,<$07a8
                dfb   <$0450,<$04d0,<$0550,<$05d0,<$0650,<$06d0,<$0750,<$07d0
BASEH           dfb   >$0400,>$0480,>$0500,>$0580,>$0600,>$0680,>$0700,>$0780
                dfb   >$0428,>$04a8,>$0528,>$05a8,>$0628,>$06a8,>$0728,>$07a8
                dfb   >$0450,>$04d0,>$0550,>$05d0,>$0650,>$06d0,>$0750,>$07d0
