#!/usr/bin/env python3
"""The TRS-80 discs: LDOS 5.3.1 for the Model I (tools/trs80/ldos-m1.dsk, a
JV1 system disc with nothing else on it) with LISP/CMD and the images.

    mkdisk.py OUT  -- reads OUT/LISP.CMD and OUT/LISP*.ROM, writes
                      OUT/lisp-a.dsk (it boots) and OUT/lisp-b.dsk

What does not fit on the first goes on the second: LDOS looks in every
drive for a file.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import ldoswrite as L

BASE = os.path.join(os.path.dirname(__file__), 'ldos-m1.dsk')
IMAGES = [('LISP0', 'LISP.ROM'), ('LISP1', 'LISPLIB.ROM'), ('LISP2', 'LISPLIB2.ROM'),
          ('LISP3', 'LISPLIB3.ROM'), ('LISP4', 'LISPDEMO.ROM'), ('LISP5', 'LISPVM.ROM'),
          ('LISPM', 'LISPM.ROM')]

def granules(img, n):
    g = img.spg * 256
    return (n + g - 1) // g

def main():
    out = sys.argv[1]
    files = [('LISP', 'CMD', open(os.path.join(out, 'LISP.CMD'), 'rb').read())]
    for name, rom in IMAGES:
        data = open(os.path.join(out, rom), 'rb').read().rstrip(b'\xff')
        files.append((name, 'IMG', data))
    discs = [L.Img(BASE), L.Img(BASE)]
    k = 0
    for name, ext, data in files:
        while granules(discs[k], len(data)) > len(L.free_granules(discs[k])):
            k += 1
            if k == len(discs):
                sys.exit('mkdisk: the files do not fit on two discs')
        L.add_file(discs[k], name, ext, data)
    for img, tag in zip(discs, 'ab'):
        img.save(os.path.join(out, f'lisp-{tag}.dsk'))

if __name__ == '__main__':
    main()
