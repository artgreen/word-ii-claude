*-----------------------------------------------------------------------
* filer.s -- filename entry, path building, and the rename/delete commands.
* The scrolling directory picker is added in filer2.s (FILE_PICKER) and used by
* ASK_OPEN_NAME; here ASK_OPEN_NAME falls back to a typed name.
*-----------------------------------------------------------------------

* --- filer state (absolute) ---
PREFIXBUF       ds    65                       ; current directory prefix (len-prefixed)
NAMEBUF         ds    65                       ; typed name (len byte + chars)
NAMELEN         dfb   0
PROMPTPTR       ds    2
OLDPATH         ds    65                       ; second path for RENAME

*-----------------------------------------------------------------------
* INIT_PREFIX -- establish a usable prefix. Try GET_PREFIX; if it is empty
* (a SYS program is often launched with no prefix set), derive "/VOLUME/" from
* the boot device via ONLINE and SET_PREFIX to it.
*-----------------------------------------------------------------------
INIT_PREFIX     DOMLI MLI_GETPREFIX;PFXPARM
                bcs   :derive
                lda   PREFIXBUF                ; non-empty prefix -> use it
                bne   :done
:derive         lda   DEVNUM                   ; ONLINE the boot device
                sta   ONL_UNIT
                DOMLI MLI_ONLINE;ONLINEPARM
                bcs   :empty
                lda   ONL_BUF
                and   #$0f                      ; low nibble = volume-name length
                beq   :empty
                sta   TMPA
                lda   #'/'                      ; build "/VOLUME/"
                sta   PREFIXBUF+1
                ldx   #0
:cp             lda   ONL_BUF+1,x
                and   #$7f
                sta   PREFIXBUF+2,x
                inx
                cpx   TMPA
                bcc   :cp
                lda   #'/'
                sta   PREFIXBUF+2,x
                lda   TMPA
                clc
                adc   #2
                sta   PREFIXBUF                 ; length = namelen + 2
                DOMLI MLI_SETPREFIX;PFXPARM
                rts
:empty          stz   PREFIXBUF                ; no prefix; absolute paths only
:done           rts

ONLINEPARM      dfb   2
ONL_UNIT        dfb   0                         ; unit number (set from DEVNUM)
                da    ONL_BUF                    ; 16-byte result buffer
ONL_BUF         ds    16

*-----------------------------------------------------------------------
* INIT_RAM -- detect a ProDOS /RAM disk (slot 3, drive 2 = unit $B0) and set
* HASRAM for the status line. (Used by the M5 paging design.)
*-----------------------------------------------------------------------
INIT_RAM        stz   HASRAM
                lda   #$b0                        ; slot 3, drive 2
                sta   ONL_UNIT
                DOMLI MLI_ONLINE;ONLINEPARM
                bcs   :done
                lda   ONL_BUF                     ; volume name must be "RAM"
                and   #$0f
                cmp   #3
                bne   :done
                lda   ONL_BUF+1
                cmp   #'R'
                bne   :done
                lda   ONL_BUF+2
                cmp   #'A'
                bne   :done
                lda   ONL_BUF+3
                cmp   #'M'
                bne   :done
                lda   #1
                sta   HASRAM
:done           rts

HASRAM          dfb   0

*-----------------------------------------------------------------------
* INPUT_FIELD -- modal text-entry dialog. A=lo,X=hi prompt. The typed text ends
*   up length-prefixed in NAMEBUF. Carry set = accepted, clear = cancelled.
*-----------------------------------------------------------------------
INPUT_FIELD     sta   PROMPTPTR
                stx   PROMPTPTR+1
                lda   #18                      ; box: cols 18..61, titled
                sta   TMPB
                sta   BOXC
                lda   #44
                sta   TMPC
                sta   BOXW
                lda   #DLG_TOP
                sta   TMPA
                lda   #DLG_HEIGHT
                sta   TMPD
                jsr   DRAWBOX
                LDI16 T_WORDII;DLGTITLE         ; hatched title bar + separator
                lda   #DLG_TITLEROW
                jsr   DRAW_TITLEBAR
                lda   PROMPTPTR
                sta   STRPTR
                lda   PROMPTPTR+1
                sta   STRPTR+1
                lda   #DLG_MSGROW
                jsr   PRCENTER
                stz   NAMELEN
:redraw         jsr   DRAW_FIELD
:k              jsr   GETKEY
                cmp   #K_RETURN
                beq   :accept
                cmp   #K_ESC
                beq   :cancel
                cmp   #K_DELETE
                beq   :back
                cmp   #$88                      ; left arrow = backspace here
                beq   :back
                cmp   #$a0
                bcc   :k
                cmp   #$ff
                bcs   :k
                ldx   NAMELEN                   ; append if room
                cpx   #38
                bcs   :k
                and   #$7f                       ; pathnames are 7-bit
                sta   NAMEBUF+1,x
                inc   NAMELEN
                bra   :redraw
:back           ldx   NAMELEN
                beq   :k
                dec   NAMELEN
                bra   :redraw
:accept         lda   NAMELEN
                sta   NAMEBUF                    ; length prefix
                jsr   DLG_RESTORE
                sec
                rts
:cancel         jsr   DLG_RESTORE
                clc
                rts

* DRAW_FIELD -- inverse entry field (cols 20..57) with text + cursor.
DRAW_FIELD      lda   #DLG_MSGROW+1
                sta   CURROW
                lda   #20
                sta   CURCOL
                lda   #$20                      ; inverse background
                ldx   #38
                jsr   FILLSPAN
                lda   #DLG_MSGROW+1
                sta   CURROW
                lda   #20
                sta   CURCOL
                ldx   #0
:pl             cpx   NAMELEN
                bcs   :curs
                lda   NAMEBUF+1,x
                jsr   TOINV
                jsr   PUTRAW                    ; preserves X
                inx
                bra   :pl
:curs           lda   #SPC                       ; normal space over inverse = cursor cell
                jmp   PUTRAW

*-----------------------------------------------------------------------
* BUILD_PATH -- PATHBUF := absolute path from NAMEBUF (prefix-relative unless it
*   already starts with '/').
*-----------------------------------------------------------------------
BUILD_PATH      lda   NAMEBUF
                beq   :empty
                lda   NAMEBUF+1
                cmp   #'/'
                beq   :absolute
                ldx   #1                         ; relative: PATHBUF = PREFIX + NAME
                ldy   #1                         ; copy PREFIXBUF[1..plen]
:p1             cpy   PREFIXBUF
                bcc   :p1do
                bne   :p2
:p1do           lda   PREFIXBUF,y
                sta   PATHBUF,x
                iny
                inx
                bra   :p1
:p2             ldy   #1                         ; copy NAMEBUF[1..nlen]
:n1             cpy   NAMEBUF
                bcc   :n1do
                bne   :n2
:n1do           lda   NAMEBUF,y
                sta   PATHBUF,x
                iny
                inx
                bra   :n1
:n2             dex                              ; total length = X-1
                txa
                sta   PATHBUF
                sec
                rts
:absolute       ldx   NAMEBUF                    ; copy NAMEBUF (incl length) -> PATHBUF
:ca             lda   NAMEBUF,x
                sta   PATHBUF,x
                dex
                bpl   :ca
                sec
                rts
:empty          clc
                rts

*-----------------------------------------------------------------------
* ASK_SAVE_NAME / ASK_OPEN_NAME -- prompt for a name; build PATHBUF. Carry set
*   = a path is ready, clear = cancelled. ASK_OPEN_NAME prefers the picker.
*-----------------------------------------------------------------------
ASK_SAVE_NAME   lda   #<P_SAVEAS
                ldx   #>P_SAVEAS
                jsr   INPUT_FIELD
                bcc   :no
                jmp   BUILD_PATH
:no             clc
                rts

ASK_OPEN_NAME   jmp   FILE_PICKER               ; filer2.s; returns carry + PATHBUF

*-----------------------------------------------------------------------
* FILER_RENAME -- rename an existing file.
*-----------------------------------------------------------------------
FILER_RENAME    lda   #<P_RENFROM
                ldx   #>P_RENFROM
                jsr   INPUT_FIELD
                bcc   :cancel
                jsr   BUILD_PATH
                bcc   :cancel                    ; empty name -> abort
                ldx   PATHBUF                    ; stash old path
:so             lda   PATHBUF,x
                sta   OLDPATH,x
                dex
                bpl   :so
                lda   #<P_RENTO
                ldx   #>P_RENTO
                jsr   INPUT_FIELD
                bcc   :cancel
                jsr   BUILD_PATH                 ; new path in PATHBUF
                bcc   :cancel                    ; empty new name -> abort
                DOMLI MLI_RENAME;RENAMEPARM
                bcc   :ok
                sta   RETCODE
                jmp   ERR_ALERT
:ok             lda   #<MSG_RENAMED
                ldx   #>MSG_RENAMED
                jmp   ALERT
:cancel         rts

*-----------------------------------------------------------------------
* FILER_DELETE -- delete a file (with confirmation).
*-----------------------------------------------------------------------
FILER_DELETE    lda   #<P_DELETE
                ldx   #>P_DELETE
                jsr   INPUT_FIELD
                bcc   :cancel
                jsr   BUILD_PATH
                bcc   :cancel                    ; empty name -> don't act on a stale PATHBUF
                lda   #<MSG_DELCONF
                ldx   #>MSG_DELCONF
                jsr   CONFIRM
                bcc   :cancel
                DOMLI MLI_DESTROY;DESTROYPARM
                bcc   :ok
                sta   RETCODE
                jmp   ERR_ALERT
:ok             lda   #<MSG_DELETED
                ldx   #>MSG_DELETED
                jmp   ALERT
:cancel         rts

*-----------------------------------------------------------------------
* MLI parameter blocks for filer operations
*-----------------------------------------------------------------------
PFXPARM         dfb   1
                da    PREFIXBUF
DESTROYPARM     dfb   1
                da    PATHBUF
RENAMEPARM      dfb   2
                da    OLDPATH
                da    PATHBUF

P_SAVEAS        asc   "Save as (name or /VOL/path):",00
P_RENFROM       asc   "Rename which file?",00
P_RENTO         asc   "New name:",00
P_DELETE        asc   "Delete which file?",00
MSG_DELCONF     asc   "Delete this file?",00
MSG_DELETED     asc   "File deleted.",00
MSG_RENAMED     asc   "File renamed.",00
