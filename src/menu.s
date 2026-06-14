*-----------------------------------------------------------------------
* menu.s -- pull-down menus, command dispatch, and Open-Apple shortcuts.
*
* Esc opens the menu bar; Left/Right switch menus, Up/Down move the highlight,
* Return selects, Esc cancels. Open-Apple + a letter issues the same command
* directly. Both routes funnel through DO_COMMAND.
*-----------------------------------------------------------------------

* --- menu state (absolute; menu interaction is not a hot path) ---
CURMENU         dfb   0
SELITEM         dfb   0
SELCMD          dfb   0

*-----------------------------------------------------------------------
* MENU_ENTER -- open the menu bar and run the interaction until a command is
*   chosen or the user cancels.
*-----------------------------------------------------------------------
MENU_ENTER      stz   CURMENU
:openmenu       stz   SELITEM
:redraw         jsr   RENDER                 ; repaint under any previous pulldown
                jsr   DRAWMENUBAR
                jsr   DRAW_PULLDOWN
:key            jsr   GETKEY
                cmp   #K_ESC
                beq   :cancel
                cmp   #K_RETURN
                beq   :select
                cmp   #K_LEFT
                beq   :left
                cmp   #K_RIGHT
                beq   :right
                cmp   #K_UP
                beq   :up
                cmp   #K_DOWN
                beq   :down
                jsr   MENU_TYPEAHEAD     ; a letter jumps to the next matching item
                jsr   DRAW_PULLDOWN
                bra   :key
:left           dec   CURMENU
                bpl   :openmenu
                lda   #NMENUS-1
                sta   CURMENU
                bra   :openmenu
:right          inc   CURMENU
                lda   CURMENU
                cmp   #NMENUS
                bcc   :openmenu2
                stz   CURMENU
:openmenu2      bra   :openmenu
:up             dec   SELITEM
                bpl   :rdp
                ldx   CURMENU                 ; wrap to last item
                lda   MENUCNT,x
                sta   SELITEM
                dec   SELITEM
:rdp            jsr   DRAW_PULLDOWN
                bra   :key
:down           inc   SELITEM
                ldx   CURMENU
                lda   SELITEM
                cmp   MENUCNT,x
                bcc   :rdp
                stz   SELITEM
                bra   :rdp
:select         lda   SELITEM
                jsr   ITEM_PTR
                ldy   #0
                lda   (PTR0),y                ; command id
                sta   SELCMD                  ; CLOSE_MENU clobbers shared scratch, so
                jsr   CLOSE_MENU              ;   keep the command in a private var
                lda   SELCMD
                jmp   DO_COMMAND
:cancel         jmp   CLOSE_MENU

* CLOSE_MENU -- restore the screen after the menu closes.
CLOSE_MENU      jsr   RENDER
                jsr   DRAWMENUBAR
                jmp   STATUS_REFRESH

*-----------------------------------------------------------------------
* MENU_TYPEAHEAD -- A = a letter key. Advance SELITEM to the next item (cyclic)
*   whose label begins with that letter; leave SELITEM unchanged if no match.
*-----------------------------------------------------------------------
MENU_TYPEAHEAD  jsr   UPCASE
                sta   TMPB                    ; target letter
                ldx   CURMENU
                lda   MENUCNT,x
                sta   TMPA                    ; item count
                sta   TMPD                    ; loop counter
                lda   SELITEM
                sta   TMPC                    ; candidate (incremented first)
:loop           inc   TMPC
                lda   TMPC
                cmp   TMPA
                bcc   :nw
                stz   TMPC
:nw             lda   TMPC
                jsr   ITEM_PTR                ; PTR0 = record
                ldy   #2
                lda   (PTR0),y
                sta   PTR1
                ldy   #3
                lda   (PTR0),y
                sta   PTR1+1
                ldy   #0
                lda   (PTR1),y                ; first label char
                jsr   UPCASE
                cmp   TMPB
                beq   :found
                dec   TMPD
                bne   :loop
                rts
:found          lda   TMPC
                sta   SELITEM
                rts

* UPCASE -- A (any case, high bit set or clear) -> uppercase ASCII, high bit clear.
UPCASE          and   #$7f
                cmp   #$61
                bcc   :u
                cmp   #$7b
                bcs   :u
                and   #$df
:u              rts

*-----------------------------------------------------------------------
* ITEM_PTR -- A = item index -> PTR0 = its 4-byte record { cmd, key, labelptr }.
*-----------------------------------------------------------------------
ITEM_PTR        pha
                ldx   CURMENU
                lda   MENUITML,x
                sta   PTR0
                lda   MENUITMH,x
                sta   PTR0+1
                pla
                asl
                asl
                clc
                adc   PTR0
                sta   PTR0
                lda   PTR0+1
                adc   #0
                sta   PTR0+1
                rts

*-----------------------------------------------------------------------
* DRAW_PULLDOWN -- draw the open menu (CURMENU) with SELITEM highlighted.
*-----------------------------------------------------------------------
DRAW_PULLDOWN   ldx   CURMENU
                lda   MENUCOL,x
                sta   MBCOL
                lda   MENUW,x
                sta   MBWIDTH
                lda   MENUCNT,x
                sta   MBCNT
                jsr   HILITE_TITLE             ; the open menu's bar title -> dark block
                stz   LOOPI
:il             lda   LOOPI                    ; every item drawn NORMAL...
                cmp   MBCNT
                bcs   :bottom
                jsr   DRAWITEM
                inc   LOOPI
                bra   :il
:bottom         lda   #ROW_MENU+1             ; bottom rule below the last item ($4C, blank corners)
                clc
                adc   MBCNT
                sta   CURROW
                lda   MBCOL
                sta   CURCOL
                lda   #SPC
                jsr   PUTRAW
                lda   #MT_HLINE
                ldx   MBWIDTH
                dex
                dex
                jsr   FILLSPAN
                lda   #SPC
                jsr   PUTRAW
                jmp   HILITE_SEL               ; ...then repaint the selected row INVERSE

* HILITE_TITLE -- redraw the open menu's bar title in normal video, so it reads as
*   a dark block against the inverse menu bar (the "pressed" menu, MouseWrite style).
HILITE_TITLE    ldx   CURMENU
                lda   MENUCOL,x
                sta   CURCOL
                stz   CURROW                   ; menu-bar row
                lda   MENUPTRL,x
                sta   STRPTR
                lda   MENUPTRH,x
                sta   STRPTR+1
                jmp   PRNORMZ

* DRAWITEM -- draw item LOOPI: a NORMAL (white-on-black) row with $5A/$5F side walls,
*   the label, and the Open-Apple shortcut (apple glyph + key).
DRAWITEM        lda   #ROW_MENU+1
                clc
                adc   LOOPI
                sta   CURROW
                ldy   LOOPI
                jsr   ROW_LABELS               ; left wall + normal fill + label + shortcut + right wall
                rts

* HILITE_SEL -- repaint the SELITEM row as an INVERSE (black-on-white) highlight bar:
*   inverse fill, inverse label, inverse shortcut key. Unconditional (no per-item
*   comparison), so it always lands on the one selected row.
HILITE_SEL      lda   #ROW_MENU+1
                clc
                adc   SELITEM
                sta   CURROW
                lda   MBCOL                    ; left wall
                sta   CURCOL
                lda   #MT_VLINEL
                jsr   PUTRAW
                lda   MBCOL                    ; inverse interior fill
                clc
                adc   #1
                sta   CURCOL
                lda   #$20
                ldx   MBWIDTH
                dex
                dex
                jsr   FILLSPAN
                lda   MBCOL                    ; label, inverse
                clc
                adc   #2
                sta   CURCOL
                ldy   SELITEM
                jsr   FETCH_ITEM               ; ITEMKEY + STRPTR for item Y
                jsr   PRINVZ
                lda   ITEMKEY
                beq   :rwall
                jsr   SC_COL                   ; CURCOL = apple column
                lda   #MT_OAPPLE
                jsr   PUTRAW
                lda   ITEMKEY                  ; key, inverse
                jsr   TOINV
                jsr   PUTRAW
:rwall          jmp   RIGHT_WALL

* ROW_LABELS -- draw a normal item row; Y = item index, CURROW preset.
ROW_LABELS      lda   MBCOL                    ; left wall
                sta   CURCOL
                lda   #MT_VLINEL
                jsr   PUTRAW
                lda   MBCOL                    ; normal interior fill
                clc
                adc   #1
                sta   CURCOL
                lda   #SPC
                ldx   MBWIDTH
                dex
                dex
                jsr   FILLSPAN
                lda   MBCOL                    ; label, normal
                clc
                adc   #2
                sta   CURCOL
                jsr   FETCH_ITEM               ; ITEMKEY + STRPTR for item Y
                jsr   PRNORMZ
                lda   ITEMKEY
                beq   RIGHT_WALL
                jsr   SC_COL                   ; CURCOL = apple column
                lda   #MT_OAPPLE
                jsr   PUTRAW
                lda   ITEMKEY                  ; key, normal
                ora   #$80
                jsr   PUTRAW
* fall through to RIGHT_WALL

* RIGHT_WALL -- draw the right wall at MBCOL+MBWIDTH-1 on the current row.
RIGHT_WALL      lda   MBCOL
                clc
                adc   MBWIDTH
                sec
                sbc   #1
                sta   CURCOL
                lda   #MT_VLINE
                jmp   PUTRAW

* FETCH_ITEM -- Y = item index -> ITEMKEY (shortcut) and STRPTR (label pointer).
FETCH_ITEM      tya
                jsr   ITEM_PTR                 ; PTR0 = {cmd,key,labelptr}
                ldy   #1
                lda   (PTR0),y
                sta   ITEMKEY
                ldy   #2
                lda   (PTR0),y
                sta   STRPTR
                iny
                lda   (PTR0),y
                sta   STRPTR+1
                rts

* SC_COL -- CURCOL := MBCOL+MBWIDTH-4 (the Open-Apple glyph column: [sp] OA key [sp] |).
SC_COL          lda   MBCOL
                clc
                adc   MBWIDTH
                sec
                sbc   #4
                sta   CURCOL
                rts

*-----------------------------------------------------------------------
* OA_DISPATCH -- A = key (Open-Apple held). Map letter -> command; ignore if
*   none. Normalizes case.
*-----------------------------------------------------------------------
OA_DISPATCH     and   #$7f                     ; drop high bit
                cmp   #$61                      ; lowercase -> uppercase
                bcc   :scan
                cmp   #$7b
                bcs   :scan
                and   #$df
:scan           ldx   #0
:sl             ldy   OATAB,x
                beq   :none                     ; sentinel 0 ends the table
                sty   TMPA
                cmp   TMPA
                beq   :hit
                inx
                inx
                bra   :sl
:hit            lda   OATAB+1,x
                jmp   DO_COMMAND
:none           rts

*-----------------------------------------------------------------------
* DO_COMMAND -- A = command id; jump through the command vector table.
*-----------------------------------------------------------------------
DO_COMMAND      asl
                tax
                jmp   (CMDTBL,x)

*-----------------------------------------------------------------------
* Command handlers
*-----------------------------------------------------------------------
H_NONE          rts
H_NOTYET        lda   #<MSG_NOTYET
                ldx   #>MSG_NOTYET
                jmp   ALERT                    ; defined in dialog.s
H_NEW           jmp   CMD_DO_NEW
H_OPEN          jmp   CMD_DO_OPEN
H_SAVE          jmp   CMD_DO_SAVE
H_SAVEAS        jmp   CMD_DO_SAVEAS
H_CLOSE         jmp   CMD_DO_NEW               ; Close = start a fresh document
H_RENAME        jmp   CMD_DO_RENAME
H_DELETE        jmp   CMD_DO_DELETE
H_QUIT          jmp   CMD_DO_QUIT
H_INSOVR        lda   EDITFLAGS
                eor   #FL_OVERWRITE
                sta   EDITFLAGS
                rts
H_ABOUT         lda   #<MSG_ABOUT
                sta   STRPTR
                lda   #>MSG_ABOUT
                sta   STRPTR+1
                LDI16 T_ABOUT;DLGTITLE
                jmp   ALERT_T                  ; titled "About" box (dialog.s)
H_KEYS          jmp   SHOW_HELP                ; defined in dialog.s

*-----------------------------------------------------------------------
* Command vector table (indexed by command id * 2)
*-----------------------------------------------------------------------
CMDTBL          da    H_NONE                   ; 0 CMD_NONE
                da    H_NEW                    ; 1
                da    H_OPEN                   ; 2
                da    H_SAVE                   ; 3
                da    H_SAVEAS                 ; 4
                da    H_CLOSE                  ; 5
                da    H_RENAME                 ; 6
                da    H_DELETE                 ; 7
                da    H_QUIT                   ; 8
                da    CMD_DO_UNDO              ; 9 undo
                da    CMD_DO_CUT               ; 10 cut
                da    CMD_DO_COPY              ; 11 copy
                da    CMD_DO_PASTE             ; 12 paste
                da    CMD_DO_SELALL            ; 13 select all
                da    CMD_DO_FIND              ; 14 find
                da    CMD_DO_FINDNEXT          ; 15 find next
                da    CMD_DO_REPLACE           ; 16 replace
                da    CMD_DO_REFLOW            ; 17 reflow
                da    CMD_DO_GOTO              ; 18 goto
                da    CMD_DO_WORDCOUNT         ; 19 word count
                da    H_INSOVR                 ; 20 ins/ovr
                da    CMD_DO_MARGINS           ; 21 margins
                da    CMD_DO_TABS              ; 22 tabs
                da    H_ABOUT                  ; 23 about
                da    H_KEYS                   ; 24 keys

*-----------------------------------------------------------------------
* Open-Apple shortcut table: pairs of (uppercase-letter, command). 0 ends it.
*-----------------------------------------------------------------------
OATAB           dfb   'N',CMD_NEW
                dfb   'O',CMD_OPEN
                dfb   'S',CMD_SAVE
                dfb   'W',CMD_CLOSE
                dfb   'Q',CMD_QUIT
                dfb   'Z',CMD_UNDO
                dfb   'X',CMD_CUT
                dfb   'C',CMD_COPY
                dfb   'V',CMD_PASTE
                dfb   'A',CMD_SELALL
                dfb   'F',CMD_FIND
                dfb   'G',CMD_FINDNEXT
                dfb   'R',CMD_REPLACE
                dfb   'J',CMD_GOTO
                dfb   '?',CMD_KEYS
                dfb   0

*-----------------------------------------------------------------------
* Menu definitions
*-----------------------------------------------------------------------
* per-menu item counts, pulldown widths, and item-array pointers
MENUCNT         dfb   8,5,3,3,3,2
MENUW           dfb   12,17,16,17,12,11        ; room for "label   <apple>K " (space both sides)
MENUITML        dfb   <FITEMS,<EITEMS,<SITEMS,<DITEMS,<OITEMS,<HITEMS
MENUITMH        dfb   >FITEMS,>EITEMS,>SITEMS,>DITEMS,>OITEMS,>HITEMS

* item records: cmd, key, labelptr
FITEMS          dfb   CMD_NEW
                dfb   'N'
                da    L_NEW
                dfb   CMD_OPEN
                dfb   'O'
                da    L_OPEN
                dfb   CMD_SAVE
                dfb   'S'
                da    L_SAVE
                dfb   CMD_SAVEAS
                dfb   0
                da    L_SAVEAS
                dfb   CMD_CLOSE
                dfb   'W'
                da    L_CLOSE
                dfb   CMD_RENAME
                dfb   0
                da    L_RENAME
                dfb   CMD_DELETE
                dfb   0
                da    L_DELETE
                dfb   CMD_QUIT
                dfb   'Q'
                da    L_QUIT
EITEMS          dfb   CMD_UNDO
                dfb   'Z'
                da    L_UNDO
                dfb   CMD_CUT
                dfb   'X'
                da    L_CUT
                dfb   CMD_COPY
                dfb   'C'
                da    L_COPY
                dfb   CMD_PASTE
                dfb   'V'
                da    L_PASTE
                dfb   CMD_SELALL
                dfb   'A'
                da    L_SELALL
SITEMS          dfb   CMD_FIND
                dfb   'F'
                da    L_FIND
                dfb   CMD_FINDNEXT
                dfb   'G'
                da    L_FINDNEXT
                dfb   CMD_REPLACE
                dfb   'R'
                da    L_REPLACE
DITEMS          dfb   CMD_REFLOW
                dfb   0
                da    L_REFLOW
                dfb   CMD_GOTO
                dfb   'J'
                da    L_GOTO
                dfb   CMD_WORDCOUNT
                dfb   0
                da    L_WORDCOUNT
OITEMS          dfb   CMD_INSOVR
                dfb   0
                da    L_INSOVR
                dfb   CMD_MARGINS
                dfb   0
                da    L_MARGINS
                dfb   CMD_TABS
                dfb   0
                da    L_TABS
HITEMS          dfb   CMD_ABOUT
                dfb   0
                da    L_ABOUT
                dfb   CMD_KEYS
                dfb   '?'
                da    L_KEYS

L_NEW           asc   "New",00
L_OPEN          asc   "Open",00
L_SAVE          asc   "Save",00
L_SAVEAS        asc   "Save As",00
L_CLOSE         asc   "Close",00
L_RENAME        asc   "Rename",00
L_DELETE        asc   "Delete",00
L_QUIT          asc   "Quit",00
L_UNDO          asc   "Undo",00
L_CUT           asc   "Cut",00
L_COPY          asc   "Copy",00
L_PASTE         asc   "Paste",00
L_SELALL        asc   "Select All",00
L_FIND          asc   "Find",00
L_FINDNEXT      asc   "Find Next",00
L_REPLACE       asc   "Replace",00
L_REFLOW        asc   "Reflow",00
L_GOTO          asc   "Go To Line",00
L_WORDCOUNT     asc   "Word Count",00
L_INSOVR        asc   "Ins/Ovr",00
L_MARGINS       asc   "Margins",00
L_TABS          asc   "Tab Width",00
L_ABOUT         asc   "About",00
L_KEYS          asc   "Keys",00

MBCOL           dfb   0
MBWIDTH         dfb   0
MBCNT           dfb   0
ITEMKEY         dfb   0                         ; DRAWITEM: shortcut key for the current item
