#!/usr/bin/env python3
"""The classics disc for the TRS-80s: the example programs on a data disc.

    tools/trs80/mkclassics.py OUTDIR

writes, each with the classic programs of examples/ as NAME/LSP (and
CLASSICS/LSP, their menu):
  OUTDIR/classics-m1.dsk   Model I, LDOS 5.3.1 single density (JV1)
  OUTDIR/classics-m3.dsk   Model III, LDOS 5.1.4 double density (JV3)
  OUTDIR/classics-m4.dsk   Model 4, LS-DOS 6.3.1 (JV3)
A data disc is the system disc it is made from (tools/trs80/ldos-m1.dsk,
ldos-m3.dsk, discs/ld4-631.dsk) with every file taken off but BOOT/SYS and
DIR/SYS: it goes in another drive, and LDOS looks in every drive for a
file, so (load "eliza") finds ELIZA/LSP there.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import ldoswrite as L

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
BASES = [('classics-m1.dsk', os.path.join(HERE, 'ldos-m1.dsk')),
         ('classics-m3.dsk', os.path.join(HERE, 'ldos-m3.dsk')),
         ('classics-m4.dsk', os.path.join(ROOT, 'discs', 'ld4-631.dsk'))]
KEEP = {('BOOT', 'SYS'), ('DIR', 'SYS')}


def files_on(img):
    """[(name, ext)] of the directory's entries in use"""
    out = []
    for s in range(2, 2 + img.ndir):
        if (img.dirtrack, s) not in img.sectors:
            break
        blk = img.rd(img.dirtrack, s)
        for e in range(8):
            ent = blk[e * 32:(e + 1) * 32]
            if ent[0] and ent[0] & 0x10 and not ent[0] & 0x80:   # in use, not
                out.append((ent[5:13].decode('latin-1').strip(),  # an extension
                            ent[13:16].decode('latin-1').strip()))
    return out


def main():
    out = sys.argv[1]
    programs = [os.path.join(ROOT, 'examples', f + '.lsp') for f in
                ('classics', 'eliza', 'deriv', 'animals', 'meval', 'life')]
    for disc, base in BASES:
        img = L.Img(base)
        for name, ext in files_on(img):
            if (name, ext) not in KEEP:
                L.delete_file(img, name, ext)
        for path in programs:
            name = os.path.splitext(os.path.basename(path))[0].upper()
            L.add_file(img, name, 'LSP', open(path, 'rb').read())
        img.save(os.path.join(out, disc))
        print('%s: %d programs, %d granules free' % (disc, len(programs),
                                                     len(L.free_granules(img))))


if __name__ == '__main__':
    main()
