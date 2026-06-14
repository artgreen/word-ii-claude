*-----------------------------------------------------------------------
* zp.s -- zero-page variable map. A DUM section assigns real addresses AND
* exports the labels as symbols (so unit tests can name them). The whole map
* lives in $06-$3F and $50-$5F, leaving $40-$4F to ProDOS MLI (volatile).
* Mirror of docs/MEMORY-MAP.md; keep the two in sync.
*-----------------------------------------------------------------------
                dum   $06
* --- 16-bit pointers ($06-$1B) ---
PTR0            ds    2                 ; $06 general pointer
PTR1            ds    2                 ; $08 general pointer
PTR2            ds    2                 ; $0A general pointer
PTR3            ds    2                 ; $0C general pointer
SCRPTR          ds    2                 ; $0E screen line base (PUTRAW)
STRPTR          ds    2                 ; $10 string source (print)
SRCPTR          ds    2                 ; $12 generic source
DSTPTR          ds    2                 ; $14 generic destination
AUXPTR          ds    2                 ; $16 aux/heap pointer
LTPTR           ds    2                 ; $18 line-table pointer
TMPPTR          ds    2                 ; $1A temp pointer

* --- screen / cursor state ($1C-$23) ---
CURROW          ds    1                 ; $1C text row for PUTRAW (0-23)
CURCOL          ds    1                 ; $1D text col for PUTRAW (0-79)
TMPA            ds    1                 ; $1E byte scratch
TMPB            ds    1                 ; $1F byte scratch
TMPC            ds    1                 ; $20 byte scratch
TMPD            ds    1                 ; $21 byte scratch
SAVEX           ds    1                 ; $22 register stash
SAVEY           ds    1                 ; $23 register stash

* --- editor / document state ($24-$3F) ---
* The cursor's paragraph (DOCLINE) is held in EDITBUF as a GAP BUFFER:
*   [0..GAPSTART) before-cursor | [GAPSTART..GAPEND) free gap | [GAPEND..EDITMAX) after
* so the cursor column within the paragraph = GAPSTART and edits are O(1).
DOCLINE         ds    2                 ; $24 logical paragraph index of cursor
VPTOP           ds    2                 ; $26 first paragraph shown in viewport
VPROW           ds    1                 ; $28 cursor's screen row in viewport
VPCOL           ds    1                 ; $29 cursor's screen col in viewport
EDITFLAGS       ds    1                 ; $2A b0=dirty b1=overwrite b2=selecting
COUNTL          ds    1                 ; $2B 16-bit loop counter
COUNTH          ds    1                 ; $2C
RETCODE         ds    1                 ; $2D last MLI / op result code
EDTMP0          ds    2                 ; $2E editor temp (survives STOREPARA/LINE_*)
NLINES          ds    2                 ; $30 paragraph count in the document
HEAPTOP         ds    2                 ; $32 bump-allocator tip (heap address)
GAPSTART        ds    2                 ; $34 cursor offset in current paragraph
GAPEND          ds    2                 ; $36 first byte after the gap in EDITBUF
EDITDIRTY       ds    1                 ; $38 EDITBUF changed since FETCHPARA
MARGIN          ds    1                 ; $39 word-wrap right margin (columns)
TABW            ds    1                 ; $3A tab width (columns)
SCRATCH16       ds    2                 ; $3B 16-bit scratch for math
EDTMP1          ds    2                 ; $3D editor temp (survives STOREPARA/LINE_*)
                ds    1                 ; $3F reserved
                dend

* --- second band ($50-$5F): safe again below the MLI scratch block ---
                dum   $50
MLITMP0         ds    2                 ; $50 scratch around MLI calls
MLITMP1         ds    2                 ; $52
LOOPI           ds    1                 ; $54 general loop index
LOOPJ           ds    1                 ; $55
RENDLEN         ds    2                 ; $56 length of paragraph being rendered
RENDSRC         ds    2                 ; $58 pointer to paragraph bytes being rendered
ROWPARA         ds    2                 ; $5A paragraph index for the current screen row
RENDOFF         ds    2                 ; $5C running byte offset within paragraph during render
ROWCOUNT        ds    1                 ; $5E characters placed on the current wrapped row
                ds    1                 ; $5F reserved
                dend

* Editor flag bit masks (for EDITFLAGS)
FL_DIRTY        equ   %00000001
FL_OVERWRITE    equ   %00000010
FL_SELECTING    equ   %00000100
