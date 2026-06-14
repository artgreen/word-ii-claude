*-----------------------------------------------------------------------
* macros.s -- 16-bit helpers. Merlin32 macro-local labels use '@'.
* Args are separated by ';' (not ','). PUT before any module that uses them.
*-----------------------------------------------------------------------

* INC16 addr -- increment the 16-bit little-endian value at addr.
INC16           MAC
                inc   ]1
                bne   @d
                inc   ]1+1
@d              <<<

* DEC16 addr -- decrement the 16-bit value at addr.
DEC16           MAC
                lda   ]1
                bne   @s
                dec   ]1+1
@s              dec   ]1
                <<<

* MOV16 src;dst -- copy 16-bit value src -> dst.
MOV16           MAC
                lda   ]1
                sta   ]2
                lda   ]1+1
                sta   ]2+1
                <<<

* LDI16 imm;dst -- store 16-bit immediate imm -> dst.
LDI16           MAC
                lda   #<]1
                sta   ]2
                lda   #>]1
                sta   ]2+1
                <<<

* CMP16 a;b -- unsigned compare 16-bit a vs b. After: C set if a>=b, Z if a==b.
CMP16           MAC
                lda   ]1+1
                cmp   ]2+1
                bne   @e
                lda   ]1
                cmp   ]2
@e              <<<

* ADD16 src;dst -- dst := dst + src (16-bit).
ADD16           MAC
                clc
                lda   ]2
                adc   ]1
                sta   ]2
                lda   ]2+1
                adc   ]1+1
                sta   ]2+1
                <<<

* DOMLI cmd;parmblock -- issue a ProDOS MLI call. Carry set on return = error
* (A = ProDOS error code). The call number and parm pointer follow the JSR inline.
DOMLI           MAC
                jsr   MLI
                dfb   ]1
                da    ]2
                <<<
