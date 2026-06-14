*-----------------------------------------------------------------------
* ui.s -- the persistent chrome: the menu bar and the bottom window rule.
* Painted once by DRAWCHROME. Column 79 (scroll bar) and the status line
* (row 23) are owned by RENDER / STATUS_REFRESH; the text area now runs
* directly under the menu bar (ROW_TXT0 = 1).
*
* Inverse bars use code $20 (inverse space = solid block); inverse text via
* TOINV. The bottom rule uses MouseText $4C (hline). Verified in microM8.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* DRAWCHROME -- paint the persistent frame (menu bar + bottom rule).
*-----------------------------------------------------------------------
DRAWCHROME      jsr   DRAWMENUBAR
                jsr   DRAWBOTBORDER
                rts

*-----------------------------------------------------------------------
* DRAWMENUBAR -- inverse bar on row 0 with the apple glyph and the six titles.
*-----------------------------------------------------------------------
DRAWMENUBAR     lda   #ROW_MENU
                sta   CURROW
                lda   #0
                sta   CURCOL
                lda   #$20               ; inverse space (solid block)
                ldx   #SCRNW
                jsr   FILLSPAN
                ldx   #0                  ; titles (MENUPTRL/H indexed by menu number)
:loop           lda   MENUCOL,x
                cmp   #$ff
                beq   :done
                sta   CURCOL
                stz   CURROW
                lda   MENUPTRL,x
                sta   STRPTR
                lda   MENUPTRH,x
                sta   STRPTR+1
                jsr   PRINVZ             ; preserves X
                inx
                bne   :loop
:done           rts

*-----------------------------------------------------------------------
* DRAWBOTBORDER -- MouseText hline across row 22 (between text and status).
*-----------------------------------------------------------------------
DRAWBOTBORDER   lda   #ROW_BOT
                sta   CURROW
                lda   #0
                sta   CURCOL
                lda   #MT_HLINE
                ldx   #SCRNW
                jsr   FILLSPAN
                rts

*-----------------------------------------------------------------------
* Menu titles and lookup tables (plain ASCII, printed inverse)
*-----------------------------------------------------------------------
M_FILE          asc   "File",00
M_EDIT          asc   "Edit",00
M_SEARCH        asc   "Search",00
M_DOC           asc   "Document",00
M_OPTS          asc   "Options",00
M_HELP          asc   "Help",00

MENUCOL         dfb   2,9,16,25,36,46,$ff
MENUPTRL        dfb   <M_FILE,<M_EDIT,<M_SEARCH,<M_DOC,<M_OPTS,<M_HELP
MENUPTRH        dfb   >M_FILE,>M_EDIT,>M_SEARCH,>M_DOC,>M_OPTS,>M_HELP
