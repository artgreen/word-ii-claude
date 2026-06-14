*-----------------------------------------------------------------------
* WORD II -- a ProDOS 8 word processor for the Enhanced Apple IIe family.
*
* main.s -- master source: ORG/TYP/DSK live here, modules are PUT in
* dependency order, START is the SYS entry at $2000.
* Target: 65C02 (Enhanced IIe / IIc / IIc+ / IIgs 8-bit). 65C02 opcodes used
* intentionally (BRA, STZ, PHX/PLX). No 65816 native mode, no undocumented ops.
*
* M1: boots under ProDOS, brings up the 80-column MouseText UI shell (menu
* bar, window borders + title, status line, scrollbar) and runs an event
* loop. Editing arrives in M2.
*-----------------------------------------------------------------------
                xc                       ; enable 65C02 opcodes
                org   $2000
                typ   $ff                ; ProDOS SYS file
                dsk   WORDII.SYSTEM

                put   const
                put   zp
                put   macros

*-----------------------------------------------------------------------
* START -- ProDOS has loaded us at $2000 and JMP'd here.
*-----------------------------------------------------------------------
START           cld
                ldx   #$ff
                txs                      ; own the stack
                jsr   SETRESET           ; Ctrl-Reset repaints instead of crashing
                jsr   SCRINIT
                jsr   SCRCLR
                jsr   DRAWCHROME
                jsr   DOC_NEW            ; start with an empty document
                jsr   INIT_PREFIX        ; learn the ProDOS prefix for file dialogs
                jsr   INIT_RAM           ; detect /RAM for the status line
                jsr   RENDER
                jsr   STATUS_REFRESH

EVLOOP          jsr   GETKEY             ; blocking; A = key ($80+)
                jsr   KEYDISPATCH
                jsr   RENDER
                jsr   STATUS_REFRESH
                bra   EVLOOP

*-----------------------------------------------------------------------
* GETKEY -- block until a key, return it in A (high bit set), strobe cleared.
*-----------------------------------------------------------------------
GETKEY          lda   KBD
                bpl   GETKEY
                sta   KBDSTRB
                rts

*-----------------------------------------------------------------------
* SETRESET -- install RESET_ENTRY at the ProDOS soft-reset vector.
*-----------------------------------------------------------------------
SETRESET        lda   #<RESET_ENTRY
                sta   $03f2
                lda   #>RESET_ENTRY
                sta   $03f3
                lda   $03f3
                eor   #$a5
                sta   $03f4              ; power-up byte so the vector is honored
                rts

RESET_ENTRY     cld
                ldx   #$ff
                txs
                jsr   SCRINIT
                jsr   SCRCLR
                jsr   DRAWCHROME
                jmp   EVLOOP

*-----------------------------------------------------------------------
* QUIT -- return to ProDOS.
*-----------------------------------------------------------------------
QUIT            jsr   MLI
                dfb   MLI_QUIT
                da    QPARM
                bcs   :hang
:hang           jmp   :hang
QPARM           dfb   4
                dfb   0
                da    0
                dfb   0
                da    0

*-----------------------------------------------------------------------
* Modules
*-----------------------------------------------------------------------
                put   screen
                put   ui
                put   util
                put   docstore
                put   editor
                put   render
                put   keyboard
                put   fileio
                put   dialog
                put   menu
                put   filer
                put   filer2
                put   search
                put   clipboard
                put   undo
                put   reflow

                end
