#!/usr/bin/env python3
"""The Model 4's FreHD image: a bootable LS-DOS 6.3.1 hard disc (xtrs's
.hdv, which the FreHD reads) with LISP/CMD, the six images and HWTEST/LSP.

    mkhdv.py OUT              -- reads OUT/LISP.CMD and OUT/LISP*.ROM, writes
                                 OUT/lisp-m4.hdv
    mkhdv.py --base FROM TO   -- the base itself, from an LS-DOS 6.3.1 FreHD
                                 image: only LS-DOS's own files kept

The base: $LSDOS631HD, else tools/trs80m4/ls631-frehd.hdv.gz -- made with
--base from the LS-DOS 6.3.1 image on Mike's FreHD card (2026-11-13): the
files of LS-DOS 6.3.1's disc (at its Level 1K: SYS0, SYS3, SYS6, SYS7 and
BACKUP patched; SYS13 the disc's, not the shell that was there), its Radio
Shack hard disc driver (RSHARD6/DCT, RSFORM6/CMD: the FreHD answers as
that controller) and the CONFIG/SYS that loads it; everything else
deleted, and every sector no file holds zeroed. 202 cylinders of 32
sectors (256 in the file, the rest unused), 8 granules of 4 sectors a
cylinder, the directory on 101: 1.6 MB. Then, booted in trs80gp
(-frehd_dir, -frehd_menu), SYSTEM (DRIVE=1,DISABLE), the same for 2 and
3, and SYSGEN (2026-11-13, Mike: the FreHD's drives :1-:3 showed junk
with only this image behind :0): its CONFIG/SYS has :0, the hard disc,
and the floppies :4 and :5. --base alone does not do that step. On
the FreHD's card its boot menu lists it (header byte 8 bit 0: it boots,
byte 11: LS-DOS 6.3.1).
"""
import gzip, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkdisk                   # this directory's (it puts tools/trs80 on the path)
import ldoswrite as L

HERE = os.path.dirname(os.path.abspath(__file__))
BASES = [os.environ.get('LSDOS631HD', ''), os.path.join(HERE, 'ls631-frehd.hdv.gz')]
KEEP_TOO = [('CONFIG', 'SYS'), ('RSHARD6', 'DCT'), ('RSFORM6', 'CMD')]

def entries(img):
    """[(sector, index, entry)] of the files in use"""
    out = []
    for s in range(2, 2 + img.ndir):
        blk = img.rd(img.dirtrack, s)
        for e in range(8):
            ent = blk[e*32:(e+1)*32]
            if ent[0] & 0x10:
                out.append((s, e, bytes(ent)))
    return out

def key(ent):
    return (ent[5:13].decode('latin-1').strip(), ent[13:16].decode('latin-1').strip())

def granules(img, ent):
    """a file's granules, in order: [(cylinder, granule)]"""
    out, i = [], 22
    while i < 32 and ent[i] != 0xFF:
        t, g, n = ent[i], (ent[i+1] >> 5) & 7, (ent[i+1] & 31) + 1
        for k in range(n):
            tt, gg = t, g + k
            while gg >= img.gpt:
                gg -= img.gpt; tt += 1
            out.append((tt, gg))
        i += 2
    return out

def read(img, ent):
    out = b''
    for t, g in granules(img, ent):
        for k in range(img.spg):
            out += bytes(img.rd(t, g*img.spg + k))
    ern, eof = ent[20] | ent[21] << 8, ent[3]
    return out[:(ern - 1)*256 + eof if eof else ern*256]

def shrink(img, s, e, data):
    """a file's data replaced by shorter data, in its first granules"""
    blk = bytearray(img.rd(img.dirtrack, s))
    ent = blk[e*32:(e+1)*32]
    grs = granules(img, ent)
    need = -(-len(data) // (img.spg*256))
    assert need <= (ent[23] & 31) + 1, 'shrink: the first extent is too short'
    for n, (t, g) in enumerate(grs[:need]):
        for k in range(img.spg):
            p = (n*img.spg + k) * 256
            img.wr(t, g*img.spg + k, data[p:p+256])
    gat = bytearray(img.rd(img.dirtrack, 0))
    for t, g in grs[need:]:
        gat[t] &= ~(1 << g) & 0xFF
    img.wr(img.dirtrack, 0, bytes(gat))
    ern = -(-len(data) // 256)
    ent[3], ent[20], ent[21] = len(data) % 256, ern & 0xFF, ern >> 8
    ent[23] = (ent[23] & 0xE0) | (need - 1)
    ent[24:32] = b'\xff' * 8
    blk[e*32:(e+1)*32] = ent
    img.wr(img.dirtrack, s, bytes(blk))
    print('  = %s/%s  LS-DOS\'s own, %d bytes' % (key(ent) + (len(data),)))

def make_base(src, dst):
    img = L.Img(src)
    assert img.kind == 'hdv', 'not an .hdv'
    floppy = L.Img(mkdisk.BASES[1])
    keep = set(KEEP_TOO) | {key(ent) for s, e, ent in entries(floppy)}
    stock = {}
    for s, e, ent in entries(floppy):
        stock[key(ent)] = read(floppy, ent)
    for s, e, ent in entries(img):
        if ent[0] & 0x80:
            sys.exit('mkhdv: an extended directory entry: not handled')
        if key(ent) not in keep:
            L.delete_file(img, *key(ent))
        elif key(ent) == ('SYS13', 'SYS') and read(img, ent) != stock[key(ent)]:
            shrink(img, s, e, stock[key(ent)])     # LS-DOS's own, not a shell
    # what no file holds: free granules, the directory cylinder past the
    # directory, slack after each file's end, empty directory slots
    gat = img.rd(img.dirtrack, 0)
    held = {}
    for s, e, ent in entries(img):
        if key(ent) == ('DIR', 'SYS'):
            continue
        ern = ent[20] | ent[21] << 8
        eof = ent[3]
        for n, (t, g) in enumerate(granules(img, ent)):
            for k in range(img.spg):
                held[(t, g*img.spg + k)] = (n*img.spg + k, ern, eof)
    zero = bytes(256)
    for t in range(1, img.tracks):          # cylinder 0 is the boot's: its
        for s in range(img.spt):            # sectors 4-13 too, which the GAT
            g = s // img.spg                # does not mark
            if t == img.dirtrack:
                if s >= 2 + img.ndir:
                    img.wr(t, s, zero)
            elif not (gat[t] >> g) & 1:
                img.wr(t, s, zero)
            elif (t, s) in held:
                rec, ern, eof = held[(t, s)]
                if rec >= ern:
                    img.wr(t, s, zero)
                elif rec == ern - 1 and eof:
                    img.wr(t, s, img.rd(t, s)[:eof])
    hb, stride = img.d[4] * 256, img.d[29] or 256   # the sectors LS-DOS does
    for t in range(img.tracks):                     # not use, and past the
        a = hb + (t * stride + img.spt) * 256       # last cylinder
        img.d[a:a + (stride - img.spt) * 256] = bytes((stride - img.spt) * 256)
    end = hb + img.tracks * stride * 256
    img.d[end:] = bytes(len(img.d) - end)
    hit = bytearray(img.rd(img.dirtrack, 1))
    used = {(s, e) for s, e, ent in entries(img)}
    for s in range(2, 2 + img.ndir):
        blk = bytearray(img.rd(img.dirtrack, s))
        for e in range(8):
            if (s, e) not in used:
                blk[e*32:(e+1)*32] = bytes(32)
                hit[e*32 + s - 2] = 0
        img.wr(img.dirtrack, s, bytes(blk))
    img.wr(img.dirtrack, 1, bytes(hit))
    # no AUTO command (it ran the FreHD's VHDUTL, not on this disc)
    b = bytearray(img.rd(0, 2))
    b[32:64] = b'\r' + bytes(31)
    img.wr(0, 2, bytes(b))
    with gzip.GzipFile(dst, 'wb', mtime=0) as f:
        f.write(bytes(img.d))
    print('mkhdv: kept', ', '.join('%s/%s' % key(ent) for s, e, ent in entries(img)))

def main():
    if sys.argv[1] == '--base':
        return make_base(sys.argv[2], sys.argv[3])
    out = sys.argv[1]
    base = next((b for b in BASES if b and os.path.exists(b)), None)
    if not base:
        sys.exit('mkhdv: no base (tools/trs80m4/ls631-frehd.hdv.gz)')
    raw = gzip.open(base).read() if base.endswith('.gz') else open(base, 'rb').read()
    tmp = os.path.join(out, 'base.hdv')
    open(tmp, 'wb').write(raw)
    img = L.Img(tmp)
    os.remove(tmp)
    for name, ext, data in mkdisk.lisp_files(out):
        if L.find_entry(img, name, ext):
            L.delete_file(img, name, ext)
        L.add_file(img, name, ext, data)
    img.save(os.path.join(out, 'lisp-m4.hdv'))

if __name__ == '__main__':
    main()
