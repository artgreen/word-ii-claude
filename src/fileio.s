*-----------------------------------------------------------------------
* fileio.s -- ProDOS MLI file operations. All disk access goes through the MLI
* ($BF00); never RWTS/raw blocks.
*
* On-disk format: ProDOS TXT (type $04), plain 7-bit ASCII, paragraphs
* separated by a single CR ($0D). Internal text is high-bit ASCII, so we
* translate at this boundary only: SAVE writes (char & $7F); LOAD sets the high
* bit and accepts $0D or $8D as a paragraph break (so it reads both 7-bit and
* classic high-bit Apple II text files).
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* FILE_SAVE -- write the whole document to the file named in PATHBUF.
*   Returns carry clear on success; carry set with RETCODE = ProDOS error.
*-----------------------------------------------------------------------
FILE_SAVE       jsr   STOREPARA              ; flush the current paragraph
                bcc   :flushed
                rts                            ; flush failed (heap full): RETCODE set,
                                               ;   leave the on-disk file untouched
:flushed        DOMLI MLI_CREATE;CREATEPARM   ; create (a duplicate name is fine)
                DOMLI MLI_OPEN;OPENPARM
                bcc   :opened
                jmp   :err
:opened         lda   OPN_REF
                sta   WRT_REF
                sta   CLS_REF
                sta   EOF_REF
                stz   EOF_VAL                 ; truncate any existing file to 0
                stz   EOF_VAL+1
                stz   EOF_VAL+2
                DOMLI MLI_SETEOF;EOFPARM
                stz   PTR1                    ; paragraph index i
                stz   PTR1+1
:ploop          CMP16 PTR1;NLINES
                bcc   :body
                jmp   :closeok
:body           MOV16 PTR1;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLOC               ; PTR0 = loc
                jsr   LT_GETLEN               ; COUNT = len
                MOV16 PTR0;SRCPTR             ; translate paragraph -> RENDBUF (7-bit)
                LDI16 RENDBUF;DSTPTR
                jsr   XLAT_LOW
                LDI16 RENDBUF;WRT_DATA        ; write the paragraph bytes
                lda   COUNTL
                sta   WRT_CNT
                lda   COUNTH
                sta   WRT_CNT+1
                DOMLI MLI_WRITE;WRITEPARM
                bcc   :wrok
                jmp   :errclose
:wrok           MOV16 NLINES;SCRATCH16        ; last paragraph? then no separator CR
                DEC16 SCRATCH16
                CMP16 PTR1;SCRATCH16
                bcs   :nocr
                LDI16 CRBUF;WRT_DATA          ; write one CR separator
                lda   #1
                sta   WRT_CNT
                stz   WRT_CNT+1
                DOMLI MLI_WRITE;WRITEPARM
                bcc   :nocr
                jmp   :errclose
:nocr           INC16 PTR1
                jmp   :ploop
:closeok        DOMLI MLI_CLOSE;CLOSEPARM
                stz   RETCODE
                clc
                rts
:errclose       pha                            ; preserve the error across CLOSE
                DOMLI MLI_CLOSE;CLOSEPARM
                pla
:err            sta   RETCODE
                sec
                rts

*-----------------------------------------------------------------------
* FILE_LOAD -- read the file named in PATHBUF and rebuild the document.
*-----------------------------------------------------------------------
FILE_LOAD       DOMLI MLI_OPEN;OPENPARM
                bcc   :opened
                jmp   :err
:opened         lda   OPN_REF
                sta   RD_REF
                sta   CLS_REF
                sta   EOF_REF
                DOMLI MLI_GETEOF;EOFPARM       ; EOF_VAL (3 bytes) = file size
                bcc   :goteof
                jmp   :errclose
:goteof         lda   EOF_VAL+2                ; > 64K -> too big for the M3 heap
                bne   :toobig
                lda   EOF_VAL+1                ; >= heap capacity?
                cmp   #>HEAPCAP
                bcc   :ok
                bne   :toobig
                lda   EOF_VAL
                cmp   #<HEAPCAP
                bcs   :toobig
:ok             LDI16 TEXTHEAP;RD_DATA         ; read the file straight into the heap
                lda   EOF_VAL
                sta   RD_CNT
                lda   EOF_VAL+1
                sta   RD_CNT+1
                DOMLI MLI_READ;READPARM
                bcc   :readok
                jmp   :errclose
:readok         DOMLI MLI_CLOSE;CLOSEPARM
                lda   RD_XFER                  ; COUNT = bytes actually read
                sta   COUNTL
                lda   RD_XFER+1
                sta   COUNTH
                jsr   PARSE_DOC
                stz   RETCODE
                clc
                rts
:toobig         lda   #ERR_DOCFULL
                bra   :errclose2
:errclose       sta   RETCODE
:errclose2      pha
                DOMLI MLI_CLOSE;CLOSEPARM
                pla
:err            sta   RETCODE
                sec
                rts

*-----------------------------------------------------------------------
* PARSE_DOC -- build the line table from COUNT bytes already at TEXTHEAP.
*   Splits on CR; translates other bytes to high-bit in place. Always yields
*   at least one (possibly empty) paragraph.
*-----------------------------------------------------------------------
PARSE_DOC       stz   NLINES
                stz   NLINES+1
                LDI16 TEXTHEAP;AUXPTR          ; running byte pointer
                LDI16 TEXTHEAP;SRCPTR          ; current paragraph start
                LDI16 LINETBL;LTPTR            ; next line-table entry
:loop           lda   COUNTL
                ora   COUNTH
                beq   :final
                lda   (AUXPTR)
                and   #$7f
                cmp   #$0d                     ; CR -> end of paragraph
                beq   :eol
                ora   #$80                     ; store high-bit internally
                sta   (AUXPTR)
                INC16 AUXPTR
                DEC16 COUNTL
                bra   :loop
:eol            jsr   ADD_PARA
                INC16 AUXPTR                   ; skip the CR; next paragraph starts here
                MOV16 AUXPTR;SRCPTR
                DEC16 COUNTL
                bra   :loop
:final          jsr   ADD_PARA                 ; the trailing paragraph
                MOV16 AUXPTR;HEAPTOP
                stz   DOCLINE
                stz   DOCLINE+1
                stz   VPTOP
                stz   VPTOP+1
                jsr   FETCHPARA
                stz   EDITDIRTY
                rts

* ADD_PARA -- append a line-table entry { loc=SRCPTR, len=AUXPTR-SRCPTR }.
*   Drops paragraphs past MAXLINES (truncates rather than overrunning LINETBL).
ADD_PARA        lda   NLINES+1
                cmp   #>MAXLINES
                bcc   :ok
                lda   NLINES
                cmp   #<MAXLINES
                bcc   :ok
                rts                            ; table full -> ignore extra paragraphs
:ok             sec
                lda   AUXPTR
                sbc   SRCPTR
                sta   TMPPTR
                lda   AUXPTR+1
                sbc   SRCPTR+1
                sta   TMPPTR+1
                ldy   #0
                lda   SRCPTR
                sta   (LTPTR),y
                iny
                lda   SRCPTR+1
                sta   (LTPTR),y
                iny
                lda   TMPPTR
                sta   (LTPTR),y
                iny
                lda   TMPPTR+1
                sta   (LTPTR),y
                clc
                lda   LTPTR
                adc   #LT_ENTSZ
                sta   LTPTR
                lda   LTPTR+1
                adc   #0
                sta   LTPTR+1
                INC16 NLINES
                rts

*-----------------------------------------------------------------------
* XLAT_LOW -- copy COUNT bytes (SRCPTR)->(DSTPTR), masking each to 7 bits.
*   COUNT is preserved (used afterwards as the write length).
*-----------------------------------------------------------------------
XLAT_LOW        ldx   COUNTH
                beq   :tail
:full           ldy   #0
:fp             lda   (SRCPTR),y
                and   #$7f
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
                and   #$7f
                sta   (DSTPTR),y
                iny
                bne   :tl
:done           rts

*-----------------------------------------------------------------------
* PATH_COPY -- copy the length-prefixed path at A=lo/X=hi into PATHBUF.
*-----------------------------------------------------------------------
PATH_COPY       sta   SRCPTR
                stx   SRCPTR+1
                ldy   #0
                lda   (SRCPTR),y               ; length byte
                tax
:cp             lda   (SRCPTR),y
                sta   PATHBUF,y
                iny
                dex
                bpl   :cp
                rts

*-----------------------------------------------------------------------
* Parameter blocks (fields we patch are labelled). PATHBUF is the live path.
*-----------------------------------------------------------------------
PATHBUF         ds    65                       ; length byte + up to 64 chars
CRBUF           dfb   $0d                      ; the one-byte CR separator

CREATEPARM      dfb   7
                da    PATHBUF
                dfb   $c3                       ; access: destroy/rename/write/read
                dfb   $04                       ; file type TXT
                da    $0000                     ; aux type
                dfb   $01                       ; storage type: standard file
                da    $0000                     ; create date
                da    $0000                     ; create time

OPENPARM        dfb   3
                da    PATHBUF
                da    IOBUF_A
OPN_REF         dfb   0                         ; <- returned ref number

WRITEPARM       dfb   4
WRT_REF         dfb   0
WRT_DATA        da    0
WRT_CNT         da    0
                da    0                         ; transfer count (out)

READPARM        dfb   4
RD_REF          dfb   0
RD_DATA         da    0
RD_CNT          da    0
RD_XFER         da    0

CLOSEPARM       dfb   1
CLS_REF         dfb   0

EOFPARM         dfb   2
EOF_REF         dfb   0
EOF_VAL         dfb   0,0,0                     ; 3-byte EOF / size

*-----------------------------------------------------------------------
* File command handlers (invoked by the File menu and Open-Apple shortcuts).
* SAVE_DOC / LOAD_DOC save or load the path currently in PATHBUF and return
* carry set on error (RETCODE holds the ProDOS code).
*-----------------------------------------------------------------------
SAVE_DOC        jsr   FILE_SAVE
                bcs   :err
                lda   EDITFLAGS
                and   #$fe                      ; clear FL_DIRTY on a clean save
                sta   EDITFLAGS
                lda   #1
                sta   HASNAME
                jsr   SET_DOCNAME               ; status line shows the real name
                clc
                rts
:err            sec
                rts

LOAD_DOC        jsr   FILE_LOAD
                bcs   :err
                lda   EDITFLAGS
                and   #$fe
                sta   EDITFLAGS
                lda   #1
                sta   HASNAME
                jsr   SET_DOCNAME
                clc
                rts
:err            sec
                rts

* SET_DOCNAME -- DOCNAME := the last path component of PATHBUF (zero-terminated).
SET_DOCNAME     ldx   PATHBUF                    ; X = length
                beq   :empty
:scan           lda   PATHBUF,x                  ; find the last '/'
                cmp   #'/'
                beq   :after
                dex
                bne   :scan
                ldx   #1                          ; no slash -> whole name
                bra   :copy
:after          inx                               ; name starts after the '/'
:copy           ldy   #0
:cl             cpx   PATHBUF
                bcc   :do
                beq   :do
                bra   :term
:do             lda   PATHBUF,x
                sta   DOCNAME,y
                inx
                iny
                bra   :cl
:term           lda   #0
                sta   DOCNAME,y
                rts
:empty          stz   DOCNAME
                rts

DOCNAME         ds    40                         ; current document name (zero-terminated)

* CMD_DO_NEW -- start a fresh document (confirm if there are unsaved changes).
CMD_DO_NEW      jsr   ASK_DISCARD
                bcc   :cancel
                jsr   DOC_NEW
                stz   HASNAME
                jsr   CLEAR_PATHNAME
:cancel         rts

* CMD_DO_SAVE -- save to the current name, or Save As if untitled.
CMD_DO_SAVE     lda   HASNAME
                beq   CMD_DO_SAVEAS
                jsr   SAVE_DOC
                bcc   :ok
                jmp   ERR_ALERT
:ok             rts

* CMD_DO_SAVEAS -- prompt for a name (filer.s), then save.
CMD_DO_SAVEAS   jsr   ASK_SAVE_NAME            ; carry clear = cancelled
                bcc   :cancel
                jsr   SAVE_DOC
                bcc   :cancel
                jmp   ERR_ALERT
:cancel         rts

* CMD_DO_OPEN -- confirm discard, pick a file (filer.s), then load.
CMD_DO_OPEN     jsr   ASK_DISCARD
                bcc   :cancel
                jsr   ASK_OPEN_NAME
                bcc   :cancel
                jsr   LOAD_DOC
                bcc   :cancel
                jmp   ERR_ALERT
:cancel         rts

* CMD_DO_RENAME -- rename the on-disk file to a new name.
CMD_DO_RENAME   jmp   FILER_RENAME

* CMD_DO_DELETE -- delete an on-disk file (with confirmation).
CMD_DO_DELETE   jmp   FILER_DELETE

* CMD_DO_QUIT -- confirm if dirty, then exit to ProDOS.
CMD_DO_QUIT     jsr   ASK_DISCARD
                bcc   :cancel
                jmp   QUIT
:cancel         rts

* ASK_DISCARD -- carry set = proceed (clean, or user confirmed discard).
ASK_DISCARD     lda   EDITFLAGS
                and   #FL_DIRTY
                beq   :yes
                lda   #<MSG_DISCARD
                ldx   #>MSG_DISCARD
                jmp   CONFIRM                   ; returns carry = answer
:yes            sec
                rts

* CLEAR_PATHNAME -- empty the active pathname and document name.
CLEAR_PATHNAME  stz   PATHBUF
                stz   DOCNAME
                rts

HASNAME         dfb   0                         ; 1 once the document has a disk name
MSG_DISCARD     asc   "Discard unsaved changes?",00
