*-----------------------------------------------------------------------
* util.s -- shared low-level helpers.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* MEMCPY_FWD -- copy COUNTL/COUNTH bytes from (SRCPTR) to (DSTPTR), ascending.
*   Safe for non-overlapping or dst<src. Clobbers A,X,Y; advances the
*   pointers past the copied data.
*-----------------------------------------------------------------------
MEMCPY_FWD      ldx   COUNTH
                beq   :tail              ; no whole pages
:full           ldy   #0
:fp             lda   (SRCPTR),y
                sta   (DSTPTR),y
                iny
                bne   :fp
                inc   SRCPTR+1
                inc   DSTPTR+1
                dex
                bne   :full
:tail           ldy   #0
:tl             cpy   COUNTL
                beq   :done
                lda   (SRCPTR),y
                sta   (DSTPTR),y
                iny
                bne   :tl
:done           rts

*-----------------------------------------------------------------------
* MEMCPY_BWD -- copy COUNTL/COUNTH bytes (SRCPTR)->(DSTPTR), DESCENDING.
*   SRCPTR/DSTPTR must point at the LAST (highest) byte of each region.
*   For overlapping moves where dst>src. Clobbers A; trashes the pointers.
*-----------------------------------------------------------------------
MEMCPY_BWD      lda   COUNTL
                ora   COUNTH
                beq   :done
:lp             lda   (SRCPTR)           ; 65C02 zero-page indirect
                sta   (DSTPTR)
                lda   SRCPTR             ; SRCPTR--
                bne   :s
                dec   SRCPTR+1
:s              dec   SRCPTR
                lda   DSTPTR             ; DSTPTR--
                bne   :d
                dec   DSTPTR+1
:d              dec   DSTPTR
                lda   COUNTL             ; COUNT--
                bne   :c
                dec   COUNTH
:c              dec   COUNTL
                lda   COUNTL
                ora   COUNTH
                bne   :lp
:done           rts

*-----------------------------------------------------------------------
* SETSRC / SETDST -- point SRCPTR / DSTPTR at A=lo, X=hi.
*-----------------------------------------------------------------------
SETSRC          sta   SRCPTR
                stx   SRCPTR+1
                rts
SETDST          sta   DSTPTR
                stx   DSTPTR+1
                rts
