*-----------------------------------------------------------------------
* docstore.s -- the document model.
*
* A document is a sequence of CR-delimited paragraphs. Each paragraph has a
* 4-byte line-table entry { loc(2), len(2) }; the bytes live in the text heap
* (main RAM now; aux in M5). The cursor's paragraph is held in EDITBUF as a
* GAP BUFFER so edits are O(1):
*   EDITBUF: [0..GAPSTART) before | [GAPSTART..GAPEND) gap | [GAPEND..EDITMAX) after
* The paragraph length = GAPSTART + (EDITMAX - GAPEND); the cursor column in the
* paragraph = GAPSTART.
*
* FETCHPARA/STOREPARA are the ONLY routines that touch the heap, so M5 can
* re-back the heap with aux/+RAM by changing just those two.
*-----------------------------------------------------------------------

*-----------------------------------------------------------------------
* DOC_NEW -- start a fresh, empty one-paragraph document.
*-----------------------------------------------------------------------
DOC_NEW         lda   #DEF_MARGIN
                sta   MARGIN
                lda   #DEF_TABW
                sta   TABW
                stz   EDITFLAGS
                LDI16 TEXTHEAP;HEAPTOP
                LDI16 1;NLINES
                stz   DOCLINE
                stz   DOCLINE+1
                stz   VPTOP
                stz   VPTOP+1
                jsr   LT_PTR_CUR          ; entry 0
                MOV16 HEAPTOP;PTR0        ; loc = heap base
                jsr   LT_SETLOC
                stz   COUNTL
                stz   COUNTH
                jsr   LT_SETLEN           ; len = 0
                jsr   FETCHPARA           ; load the empty paragraph
                rts

*-----------------------------------------------------------------------
* LT_PTR -- LTPTR := LINETBL + SCRATCH16*4   (line-table entry address).
* LT_PTR_CUR -- same for the current paragraph (DOCLINE).
*-----------------------------------------------------------------------
LT_PTR_CUR      MOV16 DOCLINE;SCRATCH16
LT_PTR          lda   SCRATCH16
                sta   LTPTR
                lda   SCRATCH16+1
                sta   LTPTR+1
                asl   LTPTR
                rol   LTPTR+1
                asl   LTPTR
                rol   LTPTR+1             ; *4
                clc
                lda   LTPTR
                adc   #<LINETBL
                sta   LTPTR
                lda   LTPTR+1
                adc   #>LINETBL
                sta   LTPTR+1
                rts

* These operate on the entry at LTPTR.
LT_GETLOC       ldy   #0
                lda   (LTPTR),y
                sta   PTR0
                iny
                lda   (LTPTR),y
                sta   PTR0+1
                rts
LT_SETLOC       ldy   #0
                lda   PTR0
                sta   (LTPTR),y
                iny
                lda   PTR0+1
                sta   (LTPTR),y
                rts
LT_GETLEN       ldy   #2
                lda   (LTPTR),y
                sta   COUNTL
                iny
                lda   (LTPTR),y
                sta   COUNTH
                rts
LT_SETLEN       ldy   #2
                lda   COUNTL
                sta   (LTPTR),y
                iny
                lda   COUNTH
                sta   (LTPTR),y
                rts

*-----------------------------------------------------------------------
* HEAP_ALLOC -- reserve COUNT bytes; PTR0 := start, HEAPTOP advances.
*   Carry clear = success, set = heap full (HEAPTOP rolled back).
*-----------------------------------------------------------------------
HEAP_ALLOC      MOV16 HEAPTOP;PTR0
                ADD16 COUNTL;HEAPTOP
                lda   HEAPTOP+1
                cmp   #>HEAP_LIMIT
                bcc   :ok
                bne   :fail
                lda   HEAPTOP
                cmp   #<HEAP_LIMIT
                bcc   :ok
:fail           MOV16 PTR0;HEAPTOP        ; roll back
                sec
                rts
:ok             clc
                rts

*-----------------------------------------------------------------------
* HEAP_ALLOC_CMP -- reserve COUNT bytes, COMPACTING the heap on first failure.
*   The bump allocator abandons a paragraph's old slot whenever the paragraph
*   grows past it, so the heap accrues dead space; compaction reclaims it.
*   PTR0 := start, carry clear = success, set = truly full (even after compaction).
*   Callers MUST have a fully consistent line table (every entry valid; a slot
*   being (re)allocated must read len 0 so the compactor leaves it alone), and
*   must re-derive any index/pointer they keep -- compaction clobbers scratch.
*-----------------------------------------------------------------------
HEAP_ALLOC_CMP  jsr   HEAP_ALLOC
                bcc   :done              ; fit on the first try, no compaction
                MOV16 COUNTL;TMPPTR       ; stash the request across compaction
                jsr   HEAP_COMPACT
                MOV16 TMPPTR;COUNTL
                jsr   HEAP_ALLOC          ; retry against the reclaimed heap
:done           rts

*-----------------------------------------------------------------------
* HEAP_COMPACT -- pack every live paragraph down to the base of the heap,
*   removing the dead slots left behind by grow-reallocations, and reset
*   HEAPTOP to the true used size. Paragraphs are relocated in ascending-loc
*   order so a copy-down never overruns a not-yet-moved paragraph (live slots
*   are disjoint, so the cumulative packed size never passes the next source).
*   Length-0 entries hold no bytes; they are skipped and pointed at the base.
*   Scratch (second band, no MLI/render active here): MLITMP0=dst, MLITMP1=prevloc,
*   RENDLEN=minloc, RENDSRC=minlen, ROWPARA=minidx, RENDOFF=idx, ROWCOUNT=found.
*-----------------------------------------------------------------------
HEAP_COMPACT    LDI16 TEXTHEAP;MLITMP0    ; dst = heap base
                stz   MLITMP1            ; prevloc = 0 (below TEXTHEAP)
                stz   MLITMP1+1
:pass           stz   ROWCOUNT           ; found = 0 (no candidate yet this pass)
                stz   RENDOFF            ; idx = 0
                stz   RENDOFF+1
:scan           CMP16 RENDOFF;NLINES      ; idx >= NLINES -> scan done
                bcs   :endscan
                MOV16 RENDOFF;SCRATCH16
                jsr   LT_PTR             ; LTPTR -> entry idx
                jsr   LT_GETLEN          ; COUNT = len
                lda   COUNTL
                ora   COUNTH
                beq   :nextscan          ; len 0 -> ignore in the pack pass
                jsr   LT_GETLOC          ; PTR0 = loc (COUNT still = len)
                lda   MLITMP1+1          ; need loc > prevloc
                cmp   PTR0+1
                bcc   :cand
                bne   :nextscan
                lda   MLITMP1
                cmp   PTR0
                bcs   :nextscan          ; prevloc >= loc -> already placed/behind
:cand           lda   ROWCOUNT           ; first candidate, or a smaller loc?
                beq   :take
                lda   PTR0+1
                cmp   RENDLEN+1
                bcc   :take
                bne   :nextscan
                lda   PTR0
                cmp   RENDLEN
                bcs   :nextscan
:take           MOV16 PTR0;RENDLEN        ; minloc = loc
                MOV16 COUNTL;RENDSRC       ; minlen = len
                MOV16 RENDOFF;ROWPARA      ; minidx = idx
                lda   #1
                sta   ROWCOUNT           ; found = 1
:nextscan       INC16 RENDOFF
                bra   :scan
:endscan        lda   ROWCOUNT
                beq   :finish            ; nothing left above prevloc -> done
                MOV16 RENDLEN;SRCPTR       ; copy minlen bytes minloc -> dst
                MOV16 MLITMP0;DSTPTR
                MOV16 RENDSRC;COUNTL
                jsr   MEMCPY_FWD
                MOV16 ROWPARA;SCRATCH16    ; entry[minidx].loc = dst
                jsr   LT_PTR
                MOV16 MLITMP0;PTR0
                jsr   LT_SETLOC
                MOV16 RENDLEN;MLITMP1      ; prevloc = this loc (strictly advances)
                ADD16 RENDSRC;MLITMP0      ; dst += minlen
                jmp   :pass
:finish         MOV16 MLITMP0;HEAPTOP      ; HEAPTOP = true used size
                stz   RENDOFF            ; point every len-0 entry at the base
                stz   RENDOFF+1
:zloop          CMP16 RENDOFF;NLINES
                bcs   :zdone
                MOV16 RENDOFF;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLEN
                lda   COUNTL
                ora   COUNTH
                bne   :znext
                LDI16 TEXTHEAP;PTR0
                jsr   LT_SETLOC
:znext          INC16 RENDOFF
                bra   :zloop
:zdone          rts

*-----------------------------------------------------------------------
* HEAP_USED -- COUNT := total live document bytes = sum of every paragraph's
*   length, but using the live EDITBUF length (PARALEN) for the cursor's
*   paragraph, whose line-table len is stale until the next STOREPARA. This is
*   what the status line reports as used, so deletes shrink it immediately.
*   Scratch: MLITMP0 = accumulator, MLITMP1 = index.
*-----------------------------------------------------------------------
HEAP_USED       stz   MLITMP0
                stz   MLITMP0+1
                stz   MLITMP1
                stz   MLITMP1+1
:loop           CMP16 MLITMP1;NLINES      ; index >= NLINES -> done
                bcs   :done
                CMP16 MLITMP1;DOCLINE      ; cursor's paragraph?
                bne   :other
                jsr   PARALEN            ; COUNT = live length from EDITBUF
                bra   :add
:other          MOV16 MLITMP1;SCRATCH16
                jsr   LT_PTR
                jsr   LT_GETLEN          ; COUNT = stored length
:add            ADD16 COUNTL;MLITMP0
                INC16 MLITMP1
                bra   :loop
:done           MOV16 MLITMP0;COUNTL
                rts

*-----------------------------------------------------------------------
* PARALEN -- COUNT := length of the paragraph currently in EDITBUF.
*-----------------------------------------------------------------------
PARALEN         sec
                lda   #<EDITMAX
                sbc   GAPEND
                sta   COUNTL
                lda   #>EDITMAX
                sbc   GAPEND+1
                sta   COUNTH              ; after-length
                clc
                lda   COUNTL
                adc   GAPSTART
                sta   COUNTL
                lda   COUNTH
                adc   GAPSTART+1
                sta   COUNTH              ; + before-length
                rts

*-----------------------------------------------------------------------
* FETCHPARA -- load paragraph DOCLINE into EDITBUF, cursor at column 0.
*   (before-region empty; paragraph bytes packed at the end of EDITBUF.)
*-----------------------------------------------------------------------
FETCHPARA       jsr   LT_PTR_CUR
                jsr   LT_GETLEN           ; COUNT = len
                jsr   LT_GETLOC           ; PTR0 = loc
                stz   GAPSTART
                stz   GAPSTART+1
                sec
                lda   #<EDITMAX
                sbc   COUNTL
                sta   GAPEND
                lda   #>EDITMAX
                sbc   COUNTH
                sta   GAPEND+1            ; GAPEND = EDITMAX - len
                MOV16 PTR0;SRCPTR
                clc
                lda   #<EDITBUF
                adc   GAPEND
                sta   DSTPTR
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   DSTPTR+1            ; DSTPTR = EDITBUF + GAPEND
                jsr   MEMCPY_FWD
                stz   EDITDIRTY
                rts

*-----------------------------------------------------------------------
* STOREPARA -- flush EDITBUF back to the heap for DOCLINE if dirty.
*   On heap-full leaves data in EDITBUF and sets RETCODE=ERR_DOCFULL.
*-----------------------------------------------------------------------
STOREPARA       lda   EDITDIRTY
                bne   :do
                clc                       ; nothing to flush = success
                rts
:do             jsr   PARALEN             ; COUNT = new length
                MOV16 COUNTL;TMPPTR       ; save new length
                jsr   LT_PTR_CUR
                ldy   #2                  ; old length -> SCRATCH16
                lda   (LTPTR),y
                sta   SCRATCH16
                iny
                lda   (LTPTR),y
                sta   SCRATCH16+1
                lda   COUNTH              ; newlen <= oldlen ?
                cmp   SCRATCH16+1
                bcc   :reuse
                bne   :alloc
                lda   COUNTL
                cmp   SCRATCH16
                beq   :reuse
                bcc   :reuse
:alloc          ldy   #2                  ; the old slot is dead -- mark this entry len 0
                lda   #0                  ;   so a compaction fully reclaims it (the
                sta   (LTPTR),y           ;   live bytes are safe in EDITBUF)
                iny
                sta   (LTPTR),y
                MOV16 TMPPTR;COUNTL        ; COUNT = newlen (compaction clobbers COUNT)
                jsr   HEAP_ALLOC_CMP      ; PTR0 = new loc, reclaiming dead space first
                bcc   :setloc
                lda   #ERR_DOCFULL
                sta   RETCODE
                sec                       ; heap full: keep EDITDIRTY; EDITBUF intact
                rts
:setloc         jsr   LT_PTR_CUR          ; re-fetch LTPTR (compaction moved scratch)
                jsr   LT_SETLOC
                bra   :write
:reuse          jsr   LT_GETLOC           ; PTR0 = existing loc
:write          MOV16 GAPSTART;COUNTL     ; before-part: GAPSTART bytes
                LDI16 EDITBUF;SRCPTR
                MOV16 PTR0;DSTPTR
                jsr   MEMCPY_FWD
                clc                        ; after-part src = EDITBUF + GAPEND
                lda   #<EDITBUF
                adc   GAPEND
                sta   SRCPTR
                lda   #>EDITBUF
                adc   GAPEND+1
                sta   SRCPTR+1
                clc                        ; after-part dst = loc + GAPSTART
                lda   PTR0
                adc   GAPSTART
                sta   DSTPTR
                lda   PTR0+1
                adc   GAPSTART+1
                sta   DSTPTR+1
                sec                        ; count = EDITMAX - GAPEND
                lda   #<EDITMAX
                sbc   GAPEND
                sta   COUNTL
                lda   #>EDITMAX
                sbc   GAPEND+1
                sta   COUNTH
                jsr   MEMCPY_FWD
                jsr   LT_PTR_CUR           ; refresh LTPTR, set new length
                MOV16 TMPPTR;COUNTL
                jsr   LT_SETLEN
                stz   EDITDIRTY
                clc                       ; flushed successfully
                rts

*-----------------------------------------------------------------------
* LINE_INSERT -- open a hole in the line table at index SCRATCH16 (entries
*   shift up); NLINES++. The new entry is left uninitialised for the caller.
*   Carry set = line table full.
*-----------------------------------------------------------------------
LINE_INSERT     lda   NLINES+1
                cmp   #>MAXLINES
                bcc   :ok
                bne   :full
                lda   NLINES
                cmp   #<MAXLINES
                bcc   :ok
:full           lda   #ERR_LINEFULL
                sta   RETCODE
                sec
                rts
:ok             MOV16 NLINES;PTR1         ; PTR1 = NLINES*4
                asl   PTR1
                rol   PTR1+1
                asl   PTR1
                rol   PTR1+1
                clc                        ; SRCPTR = LINETBL + NLINES*4 - 1
                lda   #<LINETBL
                adc   PTR1
                sta   SRCPTR
                lda   #>LINETBL
                adc   PTR1+1
                sta   SRCPTR+1
                lda   SRCPTR
                bne   :s1
                dec   SRCPTR+1
:s1             dec   SRCPTR
                clc                        ; DSTPTR = SRCPTR + 4
                lda   SRCPTR
                adc   #4
                sta   DSTPTR
                lda   SRCPTR+1
                adc   #0
                sta   DSTPTR+1
                sec                        ; PTR2 = (NLINES - index)*4
                lda   NLINES
                sbc   SCRATCH16
                sta   PTR2
                lda   NLINES+1
                sbc   SCRATCH16+1
                sta   PTR2+1
                asl   PTR2
                rol   PTR2+1
                asl   PTR2
                rol   PTR2+1
                MOV16 PTR2;COUNTL
                jsr   MEMCPY_BWD
                INC16 NLINES
                clc
                rts

*-----------------------------------------------------------------------
* LINE_DELETE -- remove the line-table entry at index SCRATCH16 (entries
*   shift down); NLINES--.
*-----------------------------------------------------------------------
LINE_DELETE     MOV16 SCRATCH16;PTR1       ; DSTPTR = LINETBL + index*4
                asl   PTR1
                rol   PTR1+1
                asl   PTR1
                rol   PTR1+1
                clc
                lda   #<LINETBL
                adc   PTR1
                sta   DSTPTR
                lda   #>LINETBL
                adc   PTR1+1
                sta   DSTPTR+1
                clc                        ; SRCPTR = DSTPTR + 4
                lda   DSTPTR
                adc   #4
                sta   SRCPTR
                lda   DSTPTR+1
                adc   #0
                sta   SRCPTR+1
                sec                        ; PTR2 = (NLINES - index - 1)*4
                lda   NLINES
                sbc   SCRATCH16
                sta   PTR2
                lda   NLINES+1
                sbc   SCRATCH16+1
                sta   PTR2+1
                lda   PTR2
                bne   :m1
                dec   PTR2+1
:m1             dec   PTR2
                asl   PTR2
                rol   PTR2+1
                asl   PTR2
                rol   PTR2+1
                MOV16 PTR2;COUNTL
                jsr   MEMCPY_FWD
                DEC16 NLINES
                rts
