#!/usr/bin/env python3
"""The TRS-80's machine routines, numbered: makes mach/trs80/jumps.asm (or
another machine directory's, given: the Model 4's),
jumptab.inc (the jumpblock), mtab.inc (the machine page's table) and the
names in machine.asm from the list below. Add a routine here, run this,
and write m_<name, lower case> in page.asm. The interface names
(mach/README.md) come first; M_ ones are the TRS-80's own."""
import os, re

NAMES = """CON_PUTC CON_WRCH CON_RDCH CON_GETCUR CON_SETCUR CON_CURON CON_CUROFF CON_CURENA CON_CURDIS
CON_INVERSE CON_GETWIN CON_CLS CON_PEN CON_PAPER
KEY_READ KEY_WAIT KEY_UNREAD KEY_TEST
VID_MODE VID_INK VID_BORDER VID_FRAME VID_FILLBOX
GFX_PLOT GFX_PLOTR GFX_MOVE GFX_MOVER GFX_LINE GFX_LINER GFX_TEST GFX_TESTR GFX_WHERE GFX_ORIGIN
GFX_PEN GFX_PAPER GFX_CLEAR
SND_QUEUE
FILE_IOPEN FILE_ICLOSE FILE_IABANDON FILE_GETC FILE_OOPEN FILE_OCLOSE FILE_OABANDON FILE_PUTC FILE_CAT
FP_MOVE FP_INT2R FP_BIN2R FP_R2INT FP_R2BIN FP_FIX FP_INT FP_EXP10 FP_ADD FP_RSUB FP_MUL FP_DIV FP_CMP
FP_NEG FP_SGN FP_ANGLE FP_PI FP_SQR FP_POW FP_LOG FP_EXP FP_SIN FP_COS FP_TAN FP_ATN
SYS_TIME M_EDIT M_QUIT M_INKMODE M_RDIN M_RDOUT M_RDCAT M_DELETE M_FILL M_MIDI""".split()

import sys
# the machine directory: mach/trs80, or another (mkjumps.py mach/trs80m4)
D = (sys.argv[1] if len(sys.argv) > 1
     else os.path.join(os.path.dirname(__file__), '..', '..', 'mach', 'trs80'))

def main():
    assert len(NAMES) == len(set(NAMES)) and 2 * len(NAMES) < 256
    j = open(os.path.join(D, 'jumps.asm')).read()
    head = j[:j.index('J_')]
    open(os.path.join(D, 'jumps.asm'), 'w').write(
        head + ''.join(f'J_{n:<14} equ {k}\n' for k, n in enumerate(NAMES))
        + f'NJ             equ {len(NAMES)}\n')
    open(os.path.join(D, 'jumptab.inc'), 'w').write(
        ';; made by tools/trs80/mkjumps.py: the jumpblock (resident.asm)\n'
        + ''.join(f'    call mfar : db 2*J_{n}\n' for n in NAMES))
    open(os.path.join(D, 'mtab.inc'), 'w').write(
        ";; made by tools/trs80/mkjumps.py: the machine page's table (page.asm)\n"
        + ''.join(f'    assert $ == MTAB+2*J_{n}\n    dw m_{n.lower()}\n' for n in NAMES))
    m = open(os.path.join(D, 'machine.asm')).read()
    m = m[:m.index('\n' + NAMES[0])] + '\n' + ''.join(f'{n:<15} equ JB+4*J_{n}\n' for n in NAMES)
    open(os.path.join(D, 'machine.asm'), 'w').write(m)

if __name__ == '__main__':
    main()
