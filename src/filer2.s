*-----------------------------------------------------------------------
* filer2.s -- the scrolling ProDOS directory picker (FILE_PICKER), used by
* Open. Reads the current prefix directory via the MLI, lists its files in a
* MouseText box, and lets the user scroll (arrows) and select (Return). Esc or
* an unreadable directory falls back to typing a name.
*
* Directory format (ProDOS): each 512-byte block is a 4-byte link header then
* 13 entries of 39 bytes. Entry byte 0 = (storage_type<<4 | name_length);
* storage types 1-3 are files, $D subdir, $E/$F headers, 0 deleted.
*-----------------------------------------------------------------------
NAMELIST        equ   IOBUF_B                  ; 60 slots x 16 bytes (len + 15 name); IOBUF_B
                                               ; is free while picking (dir OPEN uses IOBUF_A)
DIRDATA         equ   RENDBUF                  ; one 512-byte directory block
DIRENT0         equ   DIRDATA+4
MAXNAMES        equ   60
ENTPTR          equ   AUXPTR                    ; zero-page ptr for (ENTPTR),y entry walk
PICK_VIS        equ   14                        ; visible rows in the list
PICK_TOP        equ   3                         ; box top row
PICK_LCOL       equ   18                        ; box left column
PICK_W          equ   44

*-----------------------------------------------------------------------
* FILE_PICKER -- pick a file from the current directory; build PATHBUF.
*   Carry set = PATHBUF ready, clear = cancelled.
*-----------------------------------------------------------------------
FILE_PICKER     jsr   READ_DIR
                bcs   :typed
                lda   NAMECOUNT
                beq   :typed
                stz   PICKSEL
                stz   PICKTOP
                lda   NAMECOUNT                 ; visible rows = min(count, PICK_VIS)
                cmp   #PICK_VIS+1
                bcc   :visok
                lda   #PICK_VIS
:visok          sta   VISROWS
                sec
                sbc   #1
                sta   VISLAST
:redraw         jsr   DRAW_PICKER
:pk             jsr   GETKEY
                cmp   #K_ESC
                beq   :cancel
                cmp   #K_RETURN
                beq   :select
                cmp   #K_UP
                beq   :up
                cmp   #K_DOWN
                beq   :down
                jsr   PICK_TYPEAHEAD            ; a letter jumps to the next match
                jsr   PICK_SCROLL
                bra   :redraw
:up             lda   PICKSEL
                beq   :pk
                dec   PICKSEL
                jsr   PICK_SCROLL
                bra   :redraw
:down           lda   PICKSEL
                clc
                adc   #1
                cmp   NAMECOUNT
                bcs   :pk
                inc   PICKSEL
                jsr   PICK_SCROLL
                bra   :redraw
:select         jsr   COPY_SELNAME             ; -> NAMEBUF
                jsr   DLG_RESTORE
                jmp   BUILD_PATH
:cancel         jsr   DLG_RESTORE
                clc
                rts
:typed          lda   #<P_OPEN                 ; no listing -> type a name
                ldx   #>P_OPEN
                jsr   INPUT_FIELD
                bcc   :no
                jmp   BUILD_PATH
:no             clc
                rts

* PICK_TYPEAHEAD -- A = letter; advance PICKSEL to the next file whose name
*   begins with it (cyclic). Leaves PICKSEL unchanged if no match.
PICK_TYPEAHEAD  jsr   UPCASE
                sta   TMPB
                lda   NAMECOUNT
                sta   TMPD
                lda   PICKSEL
                sta   TMPC
:loop           inc   TMPC
                lda   TMPC
                cmp   NAMECOUNT
                bcc   :nw
                stz   TMPC
:nw             lda   TMPC
                sta   LOOPJ
                jsr   SLOT_PTR
                ldy   #1
                lda   (PTR2),y
                jsr   UPCASE
                cmp   TMPB
                beq   :found
                dec   TMPD
                bne   :loop
                rts
:found          lda   TMPC
                sta   PICKSEL
                rts

* PICK_SCROLL -- keep PICKSEL within the visible window [PICKTOP, +PICK_VIS).
PICK_SCROLL     lda   PICKSEL
                cmp   PICKTOP
                bcs   :below
                sta   PICKTOP
                rts
:below          sec
                sbc   #PICK_VIS-1
                bcc   :ok                       ; PICKSEL < PICK_VIS-1
                cmp   PICKTOP
                bcc   :ok
                sta   PICKTOP                   ; scroll down
:ok             rts

*-----------------------------------------------------------------------
* DRAW_PICKER -- draw the picker box and the visible slice of the list.
*-----------------------------------------------------------------------
DRAW_PICKER     lda   #PICK_TOP
                sta   TMPA
                lda   #PICK_LCOL
                sta   TMPB
                sta   BOXC
                lda   #PICK_W
                sta   TMPC
                sta   BOXW
                lda   VISROWS                    ; box height tracks the file count
                clc
                adc   #5
                sta   TMPD
                jsr   DRAWBOX
                jsr   DRAW_PICK_TITLE            ; inverse title bar
                jsr   THUMB_CALC                 ; scrollbar thumb geometry
                lda   #0                          ; list rows
                sta   LOOPI
:row            clc                              ; screen row = PICK_TOP+3+LOOPI
                lda   #PICK_TOP+3
                adc   LOOPI
                sta   CURROW
                clc                              ; idx = PICKTOP + LOOPI
                lda   PICKTOP
                adc   LOOPI
                sta   LOOPJ
                cmp   NAMECOUNT
                bcs   :blank
                jsr   DRAW_PICK_ROW
                bra   :sb
:blank          lda   #PICK_LCOL+1               ; clear marker + name area
                sta   CURCOL
                lda   #SPC
                ldx   #PICK_W-3
                jsr   FILLSPAN
:sb             jsr   DRAW_SB_CELL               ; scrollbar cell for this row
                inc   LOOPI
                lda   LOOPI
                cmp   VISROWS
                bcc   :row
                jmp   DRAW_PICK_LEGEND

* DRAW_PICK_TITLE -- hatched title bar + separator (same style as the dialogs).
DRAW_PICK_TITLE LDI16 T_OPENFILE;DLGTITLE       ; BOXC/BOXW already = PICK_LCOL/PICK_W
                lda   #PICK_TOP+1
                jmp   DRAW_TITLEBAR              ; hatch title on +1, separator on +2

* DRAW_PICK_ROW -- draw NAMELIST[LOOPJ] on row CURROW (inverse + pointer if sel).
DRAW_PICK_ROW   lda   #PICK_LCOL+1               ; marker column
                sta   CURCOL
                lda   LOOPJ
                cmp   PICKSEL
                bne   :normal
                lda   #MT_RIGHT                  ; selection pointer
                jsr   PUTRAW
                lda   #PICK_LCOL+2
                sta   CURCOL
                lda   #$20                       ; inverse name bar
                ldx   #PICK_W-5                  ; leave a gap column before the scrollbar
                jsr   FILLSPAN
                lda   #PICK_LCOL+2
                sta   CURCOL
                jsr   SLOT_PTR
                jmp   PRINT_NAME_INV
:normal         lda   #SPC                       ; no pointer
                jsr   PUTRAW
                lda   #PICK_LCOL+2
                sta   CURCOL
                lda   #SPC
                ldx   #PICK_W-5                  ; leave a gap column before the scrollbar
                jsr   FILLSPAN
                lda   #PICK_LCOL+2
                sta   CURCOL
                jsr   SLOT_PTR
                jmp   PRINT_NAME_NORM

* DRAW_SB_CELL -- draw one scrollbar cell at col PICK_LCOL+PICK_W-2, row CURROW.
*   LOOPI = visible row (0 = up cap, PICK_VIS-1 = down cap, else track/thumb).
DRAW_SB_CELL    lda   #PICK_LCOL+PICK_W-2
                sta   CURCOL
                lda   LOOPI
                bne   :nottop
                lda   #MT_UP
                jmp   PUTRAW
:nottop         cmp   VISLAST
                bne   :mid
                lda   #MT_DOWN
                jmp   PUTRAW
:mid            lda   LOOPI                      ; inner index = LOOPI-1
                sec
                sbc   #1
                cmp   THUMB_TOP                  ; in [THUMB_TOP, THUMB_TOP+THUMB_H)?
                bcc   :track
                sec
                sbc   THUMB_TOP
                cmp   THUMB_H
                bcc   :thumb
:track          lda   #MT_VLINE
                jmp   PUTRAW
:thumb          lda   #MT_BLOCK
                jmp   PUTRAW

* THUMB_CALC -- size/position the thumb in the inner track (PICK_VIS-2 cells).
*   THUMB_H = visible/total fraction; THUMB_TOP = offset/maxoffset fraction.
*   Whole list visible -> a full-height thumb.
THUMB_CALC      lda   NAMECOUNT
                cmp   #PICK_VIS+1
                bcc   :fits                       ; NAMECOUNT <= PICK_VIS
                lda   #PICK_VIS                   ; THUMB_H = PICK_VIS*inner/total
                ldy   #PICK_VIS-2
                jsr   MUL_AY
                lda   NAMECOUNT
                sta   DIVB
                jsr   DIV16_8
                bne   :hok
                lda   #1                          ; never smaller than one cell
:hok            sta   THUMB_H
                lda   #PICK_VIS-2                 ; span = inner - THUMB_H
                sec
                sbc   THUMB_H
                sta   TMPB
                lda   PICKTOP                     ; THUMB_TOP = PICKTOP*span/maxtop
                ldy   TMPB
                jsr   MUL_AY
                lda   NAMECOUNT
                sec
                sbc   #PICK_VIS
                sta   DIVB
                jsr   DIV16_8
                sta   THUMB_TOP
                rts
:fits           stz   THUMB_TOP
                lda   VISROWS
                sec
                sbc   #2
                sta   THUMB_H
                rts

* MUL_AY -- M16 (16-bit) := A * Y (8x8).
MUL_AY          sta   MULA
                sty   MULB
                stz   M16
                stz   M16+1
                ldx   #8
:lp             asl   M16
                rol   M16+1
                asl   MULA
                bcc   :skip
                clc
                lda   M16
                adc   MULB
                sta   M16
                lda   M16+1
                adc   #0
                sta   M16+1
:skip           dex
                bne   :lp
                rts

* DIV16_8 -- A := M16 / DIVB (16/8 by repeated subtraction; caps at 255).
DIV16_8         ldx   #0
:l              lda   M16+1
                bne   :sub                        ; high byte set -> M16 >= DIVB
                lda   M16
                cmp   DIVB
                bcc   :done
:sub            sec
                lda   M16
                sbc   DIVB
                sta   M16
                lda   M16+1
                sbc   #0
                sta   M16+1
                inx
                bne   :l
:done           txa
                rts

* DRAW_PICK_LEGEND -- key hints with real MouseText glyphs on the last row.
DRAW_PICK_LEGEND
                lda   VISROWS                    ; last interior row = PICK_TOP+3+VISROWS
                clc
                adc   #PICK_TOP+3
                ldy   #PICK_LCOL+8
                jsr   GOTORC
                lda   #MT_RETURN
                jsr   PUTRAW
                LDI16 L_PICKOPEN;STRPTR
                jsr   PRNORMZ
                lda   #MT_UP
                jsr   PUTRAW
                lda   #MT_DOWN
                jsr   PUTRAW
                LDI16 L_PICKMOVE;STRPTR
                jmp   PRNORMZ

* SLOT_PTR -- PTR2 := NAMELIST + LOOPJ*16
SLOT_PTR        lda   LOOPJ
                sta   PTR2
                stz   PTR2+1
                ldx   #4
:sh             asl   PTR2
                rol   PTR2+1
                dex
                bne   :sh
                clc
                lda   PTR2
                adc   #<NAMELIST
                sta   PTR2
                lda   PTR2+1
                adc   #>NAMELIST
                sta   PTR2+1
                rts

* PRINT_NAME_NORM / PRINT_NAME_INV -- print the length-prefixed name at PTR2.
PRINT_NAME_NORM ldy   #0
                lda   (PTR2),y
                sta   TMPA                       ; length
                ldy   #1
:l              cpy   TMPA
                beq   :last
                bcs   :done
:last           lda   (PTR2),y
                ora   #$80
                jsr   PUTRAW
                iny
                bne   :l
:done           rts

PRINT_NAME_INV  ldy   #0
                lda   (PTR2),y
                sta   TMPA
                ldy   #1
:l              cpy   TMPA
                beq   :last
                bcs   :done
:last           lda   (PTR2),y
                jsr   TOINV
                jsr   PUTRAW
                iny
                bne   :l
:done           rts

* COPY_SELNAME -- NAMEBUF := NAMELIST[PICKSEL] (length-prefixed).
COPY_SELNAME    lda   PICKSEL
                sta   LOOPJ
                jsr   SLOT_PTR                   ; PTR2 = slot
                ldy   #0
                lda   (PTR2),y
                sta   TMPA                       ; length
                tay
:cp             lda   (PTR2),y
                sta   NAMEBUF,y
                dey
                bpl   :cp
                rts

*-----------------------------------------------------------------------
* READ_DIR -- read the current prefix directory into NAMELIST. Carry set on
*   failure (no prefix / open error).
*-----------------------------------------------------------------------
READ_DIR        jsr   BUILD_DIRPATH
                lda   DIRPATH                    ; empty path -> fail
                beq   :err
                stz   NAMECOUNT
                DOMLI MLI_OPEN;DIROPENPARM
                bcs   :err
                lda   DIROPEN_REF
                sta   DIRREAD_REF
                sta   DIRCLOSE_REF
:rdblk          DOMLI MLI_READ;DIRREADPARM
                bcs   :closeit                   ; EOF or error -> stop
                lda   DIRREAD_XFER
                ora   DIRREAD_XFER+1
                beq   :closeit
                jsr   PARSE_DIRBLOCK
                lda   DIRREAD_XFER+1             ; full 512-byte block?
                cmp   #2
                bcs   :rdblk
:closeit        DOMLI MLI_CLOSE;DIRCLOSEPARM
                clc
                rts
:err            sec
                rts

* PARSE_DIRBLOCK -- collect file names from the 13 entries in DIRDATA.
PARSE_DIRBLOCK  LDI16 DIRENT0;ENTPTR
                lda   #13
                sta   ENTLEFT
:eloop          ldy   #0
                lda   (ENTPTR),y
                sta   ENTBYTE0
                lsr
                lsr
                lsr
                lsr                              ; storage type
                cmp   #1
                bcc   :adv                       ; 0 = deleted
                cmp   #4
                bcs   :adv                       ; >=4: subdir/header -> skip
                jsr   ADD_NAME
:adv            clc
                lda   ENTPTR
                adc   #39
                sta   ENTPTR
                lda   ENTPTR+1
                adc   #0
                sta   ENTPTR+1
                dec   ENTLEFT
                bne   :eloop
                rts

* ADD_NAME -- append entry at ENTPTR (name length in ENTBYTE0) to NAMELIST.
ADD_NAME        lda   NAMECOUNT
                cmp   #MAXNAMES
                bcs   :full
                sta   LOOPJ
                jsr   SLOT_PTR                   ; PTR2 = slot (DSTPTR via PTR2)
                lda   ENTBYTE0
                and   #$0f
                sta   TMPB                       ; name length
                ldy   #0
                sta   (PTR2),y                   ; slot[0] = length
:cp             iny
                lda   (ENTPTR),y                 ; name chars start at entry+1
                sta   (PTR2),y
                cpy   TMPB
                bcc   :cp
                inc   NAMECOUNT
:full           rts

* BUILD_DIRPATH -- DIRPATH := PREFIXBUF with any trailing '/' removed.
BUILD_DIRPATH   ldx   PREFIXBUF
                beq   :empty
                lda   PREFIXBUF,x                ; trailing '/' ?
                cmp   #'/'
                bne   :copy
                dex
                beq   :empty
:copy           stx   DIRPATH                    ; new length
:cl             lda   PREFIXBUF,x
                sta   DIRPATH,x
                dex
                bne   :cl
                rts
:empty          stz   DIRPATH
                rts

*-----------------------------------------------------------------------
* State and MLI parameter blocks
*-----------------------------------------------------------------------
NAMECOUNT       dfb   0
PICKSEL         dfb   0
PICKTOP         dfb   0
ENTLEFT         dfb   0
ENTBYTE0        dfb   0
VISROWS         dfb   0                         ; visible list rows = min(NAMECOUNT, PICK_VIS)
VISLAST         dfb   0                         ; VISROWS-1 (down-arrow row)
THUMB_TOP       dfb   0                         ; scrollbar thumb: top inner cell
THUMB_H         dfb   0                         ; scrollbar thumb: height (cells)
DIVB            dfb   0                         ; MUL_AY/DIV16_8 scratch
MULA            dfb   0
MULB            dfb   0
M16             ds    2
DIRPATH         ds    65

DIROPENPARM     dfb   3
                da    DIRPATH
                da    IOBUF_A
DIROPEN_REF     dfb   0
DIRREADPARM     dfb   4
DIRREAD_REF     dfb   0
                da    DIRDATA
                da    512
DIRREAD_XFER    da    0
DIRCLOSEPARM    dfb   1
DIRCLOSE_REF    dfb   0

P_OPEN          asc   "Open file (name or /VOL/path):",00
L_PICKOPEN      asc   " Open   ",00
L_PICKMOVE      asc   " Move   Esc Cancel",00
