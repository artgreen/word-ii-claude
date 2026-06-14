*-----------------------------------------------------------------------
* dialog.s -- modal dialog primitives: a MouseText-bordered box, an alert, a
* yes/no confirm, the ProDOS-error alert, and the help/about boxes. The
* filename-entry field and the file picker live in filer.s.
*
* Every dialog repaints the screen (RENDER + chrome + status) on exit so the
* editor is left clean underneath.
*-----------------------------------------------------------------------

* --- dialog scratch (absolute) ---
BOXMLEN         dfb   0
BOXW            dfb   0
BOXC            dfb   0
CONFRES         dfb   0
BTNFOCUS        dfb   0                         ; DRAWBUTTON: 0 = normal, !=0 = inverse (focused)
BTNSEL          dfb   0                         ; CONFIRM: which button has focus (0 = Yes, 1 = No)
BTNX            dfb   0                         ; CONFIRM: left column of the button pair
DLGTITLE        ds    2                         ; -> current dialog title string (incl. pad spaces)
MSGPTR          ds    2                         ; OPENBOX: message pointer saved across the title draw

DLG_TOP         equ   7                         ; titled-dialog geometry (screen rows)
DLG_TITLEROW    equ   8                         ; hatched title bar (separator on the next row)
DLG_MSGROW      equ   11                        ; message / prompt row
DLG_FOOTROW     equ   13                        ; "Press a key" / button row
DLG_HEIGHT      equ   8                         ; total box height

*-----------------------------------------------------------------------
* STRLEN -- STRPTR -> Y = length of the zero-terminated string.
*-----------------------------------------------------------------------
STRLEN          ldy   #0
:l              lda   (STRPTR),y
                beq   :d
                iny
                bne   :l
:d              rts

*-----------------------------------------------------------------------
* DRAWBOX -- MouseText box, interior cleared to normal spaces.
*   TMPA = top row, TMPB = left col, TMPC = width, TMPD = height.
*-----------------------------------------------------------------------
DRAWBOX         lda   TMPA                    ; top border row (Glen Bredon's trick)
                sta   CURROW
                lda   TMPB
                sta   CURCOL
                lda   #SPC                    ; blank corner
                jsr   PUTRAW
                lda   #$DF                    ; underscore = a rule at the BOTTOM of the cell,
                ldx   TMPC                     ;   so the top edge sits flush above the side walls
                dex
                dex
                jsr   FILLSPAN
                lda   #SPC                    ; blank corner
                jsr   PUTRAW
                lda   TMPA                    ; first interior row
                clc
                adc   #1
                sta   CURROW
                lda   TMPD
                sec
                sbc   #2
                beq   :bottom
                sta   LOOPI
:ir             lda   TMPB                    ; left border (left-aligned so it hugs the edge)
                sta   CURCOL
                lda   #MT_VLINEL
                jsr   PUTRAW
                lda   TMPB                    ; interior spaces
                clc
                adc   #1
                sta   CURCOL
                lda   #SPC
                ldx   TMPC
                dex
                dex
                jsr   FILLSPAN
                lda   TMPB                    ; right border
                clc
                adc   TMPC
                sec
                sbc   #1
                sta   CURCOL
                lda   #MT_VLINE
                jsr   PUTRAW
                inc   CURROW
                dec   LOOPI
                bne   :ir
:bottom         lda   TMPA                    ; bottom border row
                clc
                adc   TMPD
                sec
                sbc   #1
                sta   CURROW
                lda   TMPB
                sta   CURCOL
                lda   #SPC                    ; blank corner
                jsr   PUTRAW
                lda   #MT_HLINE               ; $4C = a rule at the TOP of the cell, flush below the walls
                ldx   TMPC
                dex
                dex
                jsr   FILLSPAN
                lda   #SPC                    ; blank corner
                jsr   PUTRAW
                rts

*-----------------------------------------------------------------------
* PRCENTER -- print STRPTR (normal) centered within the box, on row A.
*-----------------------------------------------------------------------
PRCENTER        sta   CURROW
                jsr   STRLEN
                sty   TMPB
                lda   BOXW
                sec
                sbc   TMPB
                lsr
                clc
                adc   BOXC
                sta   CURCOL
                jmp   PRNORMZ

*-----------------------------------------------------------------------
* OPENBOX -- size and draw a centered titled dialog for the message at STRPTR
*   and the title at DLGTITLE; leaves the message printed on the body row.
*   BOXW/BOXC set. Layout: top rule / hatched title / separator / body / foot /
*   bottom rule.
*-----------------------------------------------------------------------
OPENBOX         MOV16 STRPTR;MSGPTR             ; remember the message pointer
                jsr   STRLEN
                sty   BOXMLEN                    ; message length
                MOV16 DLGTITLE;STRPTR
                jsr   STRLEN                     ; title length -> Y
                sty   TMPA
                lda   BOXMLEN                    ; width = max(msg, title) + 6, min 26
                cmp   TMPA
                bcs   :wide
                lda   TMPA
:wide           clc
                adc   #6
                cmp   #26
                bcs   :w
                lda   #26
:w              sta   BOXW
                lda   #80                        ; center horizontally
                sec
                sbc   BOXW
                lsr
                sta   BOXC
                lda   #DLG_TOP
                sta   TMPA
                lda   BOXC
                sta   TMPB
                lda   BOXW
                sta   TMPC
                lda   #DLG_HEIGHT
                sta   TMPD
                jsr   DRAWBOX
                lda   #DLG_TITLEROW             ; hatched title bar + separator
                jsr   DRAW_TITLEBAR
                MOV16 MSGPTR;STRPTR              ; restore the message
                lda   #DLG_MSGROW
                jmp   PRCENTER

*-----------------------------------------------------------------------
* DRAW_TITLEBAR -- A = title-bar row. Fill the box interior on that row with the
*   $56/$57 checkerboard hatch (Glen Bredon's title-bar texture), overprint the
*   centered DLGTITLE (its pad spaces open a clean gap), and rule a separator on
*   the next row. Uses BOXC/BOXW.
*-----------------------------------------------------------------------
DRAW_TITLEBAR   sta   CURROW
                lda   BOXC
                clc
                adc   #1
                sta   CURCOL
                ldx   BOXW                        ; checkerboard hatch across the interior
                dex
                dex
                jsr   CHECKER_FILL
                MOV16 DLGTITLE;STRPTR
                jsr   STRLEN
                sty   TMPB
                lda   BOXW                        ; center the title
                sec
                sbc   TMPB
                lsr
                clc
                adc   BOXC
                sta   CURCOL
                jsr   PRNORMZ
                inc   CURROW                      ; separator rule on the next row
                lda   BOXC
                clc
                adc   #1
                sta   CURCOL
                lda   #MT_HLINE
                ldx   BOXW
                dex
                dex
                jmp   FILLSPAN

* CHECKER_FILL -- write X cells of alternating $56/$57 (the checkerboard hatch
*   Glen uses for title-bar caps) from CURROW,CURCOL. PUTRAW preserves X.
CHECKER_FILL    txa
                and   #1
                bne   :odd
                lda   #$56
                bra   :put
:odd            lda   #$57
:put            jsr   PUTRAW
                dex
                bne   CHECKER_FILL
                rts

*-----------------------------------------------------------------------
* ALERT -- message box (A=lo, X=hi) with "Press a key"; waits, then restores.
*-----------------------------------------------------------------------
ALERT           sta   STRPTR
                stx   STRPTR+1
                LDI16 T_WORDII;DLGTITLE          ; default title
ALERT_T         jsr   OPENBOX                    ; enter here with STRPTR + DLGTITLE preset
                LDI16 MSG_PRESSKEY;STRPTR
                lda   #DLG_FOOTROW
                jsr   PRCENTER
                jsr   GETKEY
                jmp   DLG_RESTORE

*-----------------------------------------------------------------------
* CONFIRM -- yes/no box (A=lo, X=hi). Returns carry set = Yes, clear = No.
*   Shows two MouseText "buttons" ( Yes ) ( No ); Left/Right move focus, Return
*   activates the focused one, Y/N are direct shortcuts, Esc = No. Default focus
*   is Yes (preserves the old Return = Yes behavior).
*-----------------------------------------------------------------------
CONFIRM         sta   STRPTR
                stx   STRPTR+1
                LDI16 T_WORDII;DLGTITLE          ; default title
                jsr   OPENBOX                 ; titled box + prompt on DLG_MSGROW
                stz   BTNSEL                  ; default focus = Yes
                lda   BOXW                    ; centre the 16-cell button pair
                sec
                sbc   #16
                lsr
                clc
                adc   BOXC
                sta   BTNX
:redraw         jsr   DRAW_YESNO
:k              jsr   GETKEY
                cmp   #K_LEFT
                beq   :focusyes
                cmp   #K_RIGHT
                beq   :focusno
                cmp   #$d9                    ; Y
                beq   :yes
                cmp   #$f9                    ; y
                beq   :yes
                cmp   #$ce                    ; N
                beq   :no
                cmp   #$ee                    ; n
                beq   :no
                cmp   #K_ESC
                beq   :no
                cmp   #K_RETURN
                beq   :enter
                bra   :k
:focusyes       stz   BTNSEL
                bra   :redraw
:focusno        lda   #1
                sta   BTNSEL
                bra   :redraw
:enter          lda   BTNSEL                  ; Return activates the focused button
                beq   :yes
                bra   :no
:yes            lda   #1
                sta   CONFRES
                bra   :fin
:no             stz   CONFRES
:fin            jsr   DLG_RESTORE
                lda   CONFRES
                lsr                            ; CONFRES bit0 -> carry
                rts

* DRAW_YESNO -- paint ( Yes ) and ( No ) on row 12, focusing button BTNSEL.
DRAW_YESNO      lda   #DLG_FOOTROW            ; "Yes" button at BTNX (7 cells wide)
                ldy   BTNX
                jsr   GOTORC
                LDI16 BTN_YES;STRPTR
                lda   BTNSEL
                eor   #1                       ; focus when BTNSEL == 0
                jsr   DRAWBUTTON
                lda   BTNX                     ; "No" button at BTNX+10
                clc
                adc   #10
                tay
                lda   #DLG_FOOTROW
                jsr   GOTORC
                LDI16 BTN_NO;STRPTR
                lda   BTNSEL                   ; focus when BTNSEL == 1
                jsr   DRAWBUTTON
                rts

*-----------------------------------------------------------------------
* DRAWBUTTON -- draw a MouseText "button" at CURROW,CURCOL: a "(" cap, a
*   one-cell-padded label band, and a ")" cap. A = focus (0 = normal video,
*   non-zero = inverse, i.e. the focused/default look). STRPTR = zero-terminated
*   label. The caps are always normal video; only the band follows the flag.
*   This is the stock-MouseText button idiom (ShrinkIt / ProTERM / Install
*   Modem): no rounded-corner glyph exists, so the raised look comes from the
*   inverse band plus the parenthesis end-caps.
*-----------------------------------------------------------------------
DRAWBUTTON      sta   BTNFOCUS
                lda   #'('
                ora   #$80                     ; left cap (always normal)
                jsr   PUTRAW
                lda   #' '                     ; leading pad, in band video
                jsr   :band
                ldy   #0                        ; the label, in band video
:lp             lda   (STRPTR),y
                beq   :pad
                jsr   :band
                iny
                bne   :lp
:pad            lda   #' '                     ; trailing pad
                jsr   :band
                lda   #')'
                ora   #$80                     ; right cap
                jmp   PUTRAW
* :band -- emit ASCII char A as inverse if focused, else normal; advance CURCOL.
:band           ldx   BTNFOCUS
                beq   :norm
                jsr   TOINV
                jmp   PUTRAW
:norm           ora   #$80
                jmp   PUTRAW

BTN_YES         asc   "Yes",00
BTN_NO          asc   "No",00

*-----------------------------------------------------------------------
* ERR_ALERT -- alert for a ProDOS error code in A. Looks up a readable name.
*-----------------------------------------------------------------------
ERR_ALERT       ldx   #0
:sl             lda   ERRTAB,x
                beq   :unknown                ; 0 terminates the table
                cmp   RETCODE                  ; (caller put the code in RETCODE)
                beq   :hit
                inx
                inx
                inx
                bra   :sl
:hit            lda   ERRTAB+1,x              ; name pointer
                ldy   ERRTAB+2,x
                bra   :show
:unknown        lda   #<EN_UNKNOWN
                ldy   #>EN_UNKNOWN
:show           sta   STRPTR
                sty   STRPTR+1
                LDI16 T_DISKERR;DLGTITLE
                jsr   OPENBOX
                LDI16 MSG_PRESSKEY;STRPTR
                lda   #DLG_FOOTROW
                jsr   PRCENTER
                jsr   GETKEY
                jmp   DLG_RESTORE

*-----------------------------------------------------------------------
* SHOW_HELP / DLG_RESTORE
*-----------------------------------------------------------------------
SHOW_HELP       lda   #<MSG_HELP
                sta   STRPTR
                lda   #>MSG_HELP
                sta   STRPTR+1
                LDI16 T_KEYS;DLGTITLE
                jmp   ALERT_T

DLG_RESTORE     jsr   RENDER
                jsr   DRAWMENUBAR
                jmp   STATUS_REFRESH

*-----------------------------------------------------------------------
* Strings
*-----------------------------------------------------------------------
MSG_PRESSKEY    asc   "Press a key",00
MSG_NOTYET      asc   "Not implemented yet.",00

* Dialog titles (the surrounding spaces open a clean gap in the hatch).
T_WORDII        asc   " Word II ",00
T_ABOUT         asc   " About ",00
T_KEYS          asc   " Keys ",00
T_DISKERR       asc   " Disk Error ",00
T_REPLACE       asc   " Replace ",00
T_OPENFILE      asc   " Open File ",00
MSG_ABOUT       asc   "Word II - a ProDOS word processor",00
MSG_HELP        asc   "Esc=menus  OA-S save  OA-O open  arrows move",00

* ProDOS error-code -> name table: code, nameptr(lo,hi). 0 terminates.
ERRTAB          dfb   $27
                da    EN_IO
                dfb   $28
                da    EN_NODEV
                dfb   $2b
                da    EN_WPROT
                dfb   $40
                da    EN_BADPATH
                dfb   $44
                da    EN_PNF
                dfb   $45
                da    EN_VNF
                dfb   $46
                da    EN_FNF
                dfb   $47
                da    EN_DUP
                dfb   $48
                da    EN_VFULL
                dfb   $49
                da    EN_DFULL
                dfb   $4e
                da    EN_ACCESS
                dfb   $80
                da    EN_DOCFULL
                dfb   0

EN_IO           asc   "Disk I/O error",00
EN_NODEV        asc   "No device connected",00
EN_WPROT        asc   "Disk is write protected",00
EN_BADPATH      asc   "Invalid pathname",00
EN_PNF          asc   "Path not found",00
EN_VNF          asc   "Volume not found",00
EN_FNF          asc   "File not found",00
EN_DUP          asc   "Duplicate file name",00
EN_VFULL        asc   "Disk is full",00
EN_DFULL        asc   "Directory is full",00
EN_ACCESS       asc   "File is locked",00
EN_DOCFULL      asc   "Document too large for memory",00
EN_UNKNOWN      asc   "ProDOS error",00
