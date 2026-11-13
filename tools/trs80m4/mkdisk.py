#!/usr/bin/env python3
"""The Model 4's disc: LS-DOS 6.3.1's system disc (ld4-631.dsk, JV3 double
density), without BASIC and some utilities for the room, with LISP/CMD
and the images (compressed, tools/trs80/lz.py):

    mkdisk.py OUT  -- reads OUT/LISP.CMD and OUT/LISP*.ROM, writes
                      OUT/lisp-m4.dsk

The base disc: $LSDOS631, else tools/trs80m4/ld4-631.dsk, else
~/claude/trs80m4/ld631/unz/ld4-631.dsk (Tim Mann's ld4-631.zip; Roy
Soltoff and William Schroeder allow it to be passed on with its notice).
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'trs80'))
import ldoswrite as L
import lz

HERE = os.path.dirname(os.path.abspath(__file__))
BASES = [os.environ.get('LSDOS631', ''), os.path.join(HERE, 'ld4-631.dsk'),
         os.path.expanduser('~/claude/trs80m4/ld631/unz/ld4-631.dsk')]
IMAGES = [('LISP0', 'LISP.ROM'), ('LISP1', 'LISPLIB.ROM'), ('LISP2', 'LISPLIB2.ROM'),
          ('LISP3', 'LISPLIB3.ROM'), ('LISP4', 'LISPDEMO.ROM'), ('LISPM', 'LISPM.ROM')]
DROP = [('DOS', 'HLP'), ('BASIC', 'CMD'), ('BASIC', 'OV1'), ('BASIC', 'OV2'),
        ('BREF', 'CMD'), ('MODELA', 'III'), ('TAPE100', 'CMD'), ('COMM', 'CMD'),
        ('COM', 'DVR'), ('HELP', 'CMD'), ('TED', 'CMD'), ('DATECONV', 'CMD'),
        ('CONV', 'CMD')]

def main():
    out = sys.argv[1]
    base = next((b for b in BASES if b and os.path.exists(b)), None)
    if not base:
        sys.exit('mkdisk: no LS-DOS 6.3.1 disc (ld4-631.dsk): see the top of tools/trs80m4/mkdisk.py')
    img = L.Img(base)
    for name, ext in DROP:
        if L.find_entry(img, name, ext):
            L.delete_file(img, name, ext)
    files = [('LISP', 'CMD', open(os.path.join(out, 'LISP.CMD'), 'rb').read())]
    for name, rom in IMAGES:
        data = lz.compress(open(os.path.join(out, rom), 'rb').read().rstrip(b'\xff'))
        files.append((name, 'IMG', data))
    test = os.path.join(HERE, '..', '..', 'mach', 'trs80m4', 'hwtest.lsp')
    if os.path.exists(test):            # the test of the real machine
        lines = open(test).read().split('\n')
        text = '\n'.join(l.strip() for l in lines
                         if l.strip() and not l.strip().startswith(';'))
        files.append(('HWTEST', 'LSP', (text + '\n').encode()))
    for name, ext, data in files:
        L.add_file(img, name, ext, data)
    img.save(os.path.join(out, 'lisp-m4.dsk'))

if __name__ == '__main__':
    main()
