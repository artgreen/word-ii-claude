*-----------------------------------------------------------------------
* const.s -- hardware, ROM, ProDOS, MouseText, geometry, and key constants.
* EQU only; emits no bytes. PUT first so every module sees these names.
*-----------------------------------------------------------------------

* --- Keyboard / strobe ---
KBD             equ   $c000             ; b7=key ready, b0-6 = code
KBDSTRB         equ   $c010             ; any access clears the strobe
BUTTON0         equ   $c061             ; Open-Apple / paddle-0 button (b7)
BUTTON1         equ   $c062             ; Closed-Apple / paddle-1 button (b7)

* --- Video soft switches (write to set; status at $C01x bit 7) ---
CLR80STORE      equ   $c000
SET80STORE      equ   $c001
RDMAINRAM       equ   $c002             ; RAMRD off (read main)
RDCARDRAM       equ   $c003             ; RAMRD on  (read aux)
WRMAINRAM       equ   $c004             ; RAMWRT off (write main)
WRCARDRAM       equ   $c005             ; RAMWRT on  (write aux)
CLR80COL        equ   $c00c
SET80COL        equ   $c00d
CLRALTCHAR      equ   $c00e
SETALTCHAR      equ   $c00f
RD80COL         equ   $c01f             ; b7 = 80-col on
RDALTCHAR       equ   $c01e             ; b7 = altcharset on
TXTPAGE1        equ   $c054             ; PAGE2 off (main half of $0400 window)
TXTPAGE2        equ   $c055             ; PAGE2 on  (aux  half of $0400 window)
TXTSET          equ   $c051             ; text mode on
MIXCLR          equ   $c052             ; full-screen
LORES           equ   $c056             ; graphics latch -> lo-res (text covers)
SETALTZP        equ   $c009
CLRALTZP        equ   $c008

* --- Aux-memory firmware mover (IIe/IIc) ---
AUXMOVE         equ   $c311             ; C set: main->aux, clear: aux->main
A1L             equ   $3c               ; AUXMOVE source start (lo/hi)
A1H             equ   $3d
A2L             equ   $3e               ; AUXMOVE source end
A2H             equ   $3f
A4L             equ   $42               ; AUXMOVE destination
A4H             equ   $43

* --- ProDOS MLI ---
MLI             equ   $bf00
DEVNUM          equ   $bf30             ; last-accessed unit number
MACHID          equ   $bf98             ; machine id bits
BITMAP          equ   $bf58             ; system memory bitmap (24 bytes)
MLI_CREATE      equ   $c0
MLI_DESTROY     equ   $c1
MLI_RENAME      equ   $c2
MLI_SETINFO     equ   $c3
MLI_GETINFO     equ   $c4
MLI_ONLINE      equ   $c5
MLI_SETPREFIX   equ   $c6
MLI_GETPREFIX   equ   $c7
MLI_OPEN        equ   $c8
MLI_NEWLINE     equ   $c9
MLI_READ        equ   $ca
MLI_WRITE       equ   $cb
MLI_CLOSE       equ   $cc
MLI_FLUSH       equ   $cd
MLI_SETMARK     equ   $ce
MLI_GETMARK     equ   $cf
MLI_SETEOF      equ   $d0
MLI_GETEOF      equ   $d1
MLI_QUIT        equ   $65

* --- MouseText screen codes (write raw to text RAM with ALTCHARSET on).
*     Verified empirically in microM8 (see docs / memory). ---
MT_CAPPLE       equ   $40               ; closed apple
MT_OAPPLE       equ   $41               ; open apple
MT_CHECK        equ   $44               ; checkmark
MT_LEFT         equ   $48               ; left arrow
MT_DOWN         equ   $4a               ; down arrow
MT_UP           equ   $4b               ; up arrow
MT_HLINE        equ   $4c               ; horizontal line (top of cell)
MT_RETURN       equ   $4d               ; return arrow
MT_BLOCK        equ   $4e               ; solid block
MT_RIGHT        equ   $55               ; right arrow
MT_VLINE        equ   $5f               ; vertical line (right aligned)
MT_VLINEL       equ   $5a               ; vertical line (left aligned)
MT_DIAMOND      equ   $5b               ; diamond / bullet

* --- Screen geometry (80x24) ---
SCRNW           equ   80
SCRNH           equ   24
ROW_MENU        equ   0                 ; menu bar
ROW_TOP         equ   1                 ; first row below the menu (pull-down anchor)
ROW_TXT0        equ   1                 ; first text row (directly under the menu bar)
ROW_TXT1        equ   21                ; last text row
NTXTROWS        equ   21                ; ROW_TXT0..ROW_TXT1
ROW_BOT         equ   22                ; window bottom border
ROW_STAT        equ   23                ; status line
COL_SB          equ   79                ; scrollbar column
TXTWIDTH        equ   79                ; text columns 0..78

* --- Document storage regions (main RAM for M2-M4; text heap moves to aux in
*     M5). loc/len in each 4-byte line-table entry: loc=heap address, len=bytes.
IOBUF_A         equ   $0800             ; ProDOS I/O buffer (open file), 1K aligned
IOBUF_B         equ   $0c00             ; ProDOS I/O buffer (directory), 1K aligned
CLIPBUF         equ   $1000             ; clipboard (cut/copy)
CLIPMAX         equ   1024
UNDOBUF         equ   $1400             ; one-level undo snapshot of the current paragraph
RENDBUF         equ   $1800             ; materialized current paragraph for rendering
EDITBUF         equ   $1c00             ; current-paragraph working buffer
EDITMAX         equ   1024              ; max paragraph length
LINETBL         equ   $6000             ; line table base (grows up)
LINETBL_END     equ   $6fff             ; -> 4096/4 = 1024 paragraphs
LT_ENTSZ        equ   4                 ; loc(2) + len(2)
MAXLINES        equ   1024
TEXTHEAP        equ   $7000             ; paragraph text heap base
TEXTHEAP_END    equ   $beff             ; ~$4F00 = ~20K of paragraph text
HEAP_LIMIT      equ   $bf00             ; TEXTHEAP_END+1 (allocation must stay below)
HEAPCAP         equ   HEAP_LIMIT-TEXTHEAP ; text-heap capacity in bytes ($4F00)
EDIT_LIMIT      equ   $0401             ; EDITMAX+1
DEF_MARGIN      equ   76                ; default word-wrap right margin
DEF_TABW        equ   8                 ; default tab width

* --- Character constants ---
SPC             equ   $a0               ; normal-video space (high-bit)
CR              equ   $0d               ; internal/file carriage return
HTAB            equ   $09               ; tab

* --- Internal result codes (RETCODE) ---
OK              equ   0
ERR_DOCFULL     equ   $80               ; aux/main text heap exhausted
ERR_LINEFULL    equ   $81               ; line table full (too many paragraphs)
ERR_PARAFULL    equ   $82               ; paragraph would exceed EDITMAX

* --- Command IDs (issued by menu selection and Open-Apple shortcuts) ---
CMD_NONE        equ   0
CMD_NEW         equ   1
CMD_OPEN        equ   2
CMD_SAVE        equ   3
CMD_SAVEAS      equ   4
CMD_CLOSE       equ   5
CMD_RENAME      equ   6
CMD_DELETE      equ   7
CMD_QUIT        equ   8
CMD_UNDO        equ   9
CMD_CUT         equ   10
CMD_COPY        equ   11
CMD_PASTE       equ   12
CMD_SELALL      equ   13
CMD_FIND        equ   14
CMD_FINDNEXT    equ   15
CMD_REPLACE     equ   16
CMD_REFLOW      equ   17
CMD_GOTO        equ   18
CMD_WORDCOUNT   equ   19
CMD_INSOVR      equ   20
CMD_MARGINS     equ   21
CMD_TABS        equ   22
CMD_ABOUT       equ   23
CMD_KEYS        equ   24

NMENUS          equ   6

* --- Key codes as read from $C000 (high bit set) ---
K_RETURN        equ   $8d
K_ESC           equ   $9b
K_LEFT          equ   $88               ; left arrow / Ctrl-H
K_RIGHT         equ   $95               ; right arrow / Ctrl-U
K_UP            equ   $8b               ; up arrow / Ctrl-K
K_DOWN          equ   $8a               ; down arrow / Ctrl-J
K_DELETE        equ   $ff               ; DELETE
K_BS            equ   $88               ; backspace (= left)
K_TAB           equ   $89
