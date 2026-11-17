#!/usr/bin/env python3
"""Copy the files of an AMSDOS data-format .dsk onto a Vortex-format .dsk.

    tools/futureos/vortexdisk.py IN.dsk OUT.dsk

For CPC Lisp under FutureOS on Mike's 464: FutureOS reads the card's
Vortex drive as drive E, and VDOS (the card's ROM 7 after |VORTEX,7) loads
Lisp's images from it. Each file is copied byte for byte, AMSDOS header
and all, as iDSK put it on IN.dsk.

The Vortex format is VDOS's own parameter block (VDOS 2.0 &C133, as
lambdaspeak4's tools/mkvortex.py has it: SPT 36, BSH 5, BLM 31, EXM 3,
DSM 176, DRM 127, AL0 &80, OFF 2):
  * 80 cylinders, 2 sides, 9 sectors of 512 bytes, ids 1-9; logical track
    t is cylinder t/2, head t%2, and the sector ids carry C and H;
  * two reserved tracks, then 4 KB blocks, block 0 the directory (128
    entries);
  * EXM 3: a directory entry holds 16 blocks, 64 KB -- four logical
    extents of 16 KB. EX is the highest logical extent the entry covers
    and RC the records (128 bytes) in it -- as TFM's own Vortex discs
    have it (their FUTUREOS.TXT: EX 3 RC 128, EX 7 RC 128, EX 8 RC 33).
    lambdaspeak4's mkvortex.py writes files up to 16 KB only; Lisp's
    images are 16 KB and a header.

The result is read back here with a reader written apart from the writer,
and compared file by file.
"""
import struct, sys

CYLS, HEADS, SPT, SECSZ = 80, 2, 9, 512
OFF, BLOCK, DSM, NDIR = 2, 4096, 176, 128


def read_data_dsk(path):
    """{name: bytes} from an AMSDOS data-format .dsk (ids &C1-&C9, 1 KB
    blocks, EXM 0), standard or extended."""
    d = open(path, 'rb').read()
    ext = d[:8] == b'EXTENDED'
    ntr, nsd = d[0x30], d[0x31]
    secs, off = {}, 0x100
    for t in range(ntr * nsd):
        size = d[0x34 + t] * 256 if ext else d[0x32] | d[0x33] << 8
        if not size:
            continue
        tib = d[off:off + size]
        p = off + 0x100
        for i in range(tib[0x15]):
            c, h, r, n = tib[0x18 + 8 * i:0x1c + 8 * i]
            sl = (tib[0x1e + 8 * i] | tib[0x1f + 8 * i] << 8) if ext else 128 << n
            secs[(c, r)] = d[p:p + sl]
            p += sl
        off += size
    block = lambda b: b''.join(secs[((b * 2 + k) // 9, 0xC1 + (b * 2 + k) % 9)]
                               for k in (0, 1))
    dirb = block(0) + block(1)
    files = {}
    for i in range(64):
        e = dirb[32 * i:32 * i + 32]
        if e[0] == 0xE5:
            continue
        name = (e[1:9].decode('latin1').rstrip(), bytes(x & 0x7F for x in e[9:12]).decode().rstrip())
        files.setdefault(name, []).append(e)
    out = {}
    for name, ents in files.items():
        ents.sort(key=lambda e: e[12] | e[14] << 5)
        data = b''
        for e in ents:
            data += b''.join(block(b) for b in e[16:32] if b)[:e[15] * 128]
        out[name] = data
    return out


def build(files):
    """The Vortex disc's logical sectors, in logical order."""
    img = bytearray([0xE5]) * (CYLS * HEADS * SPT * SECSZ)

    def put_block(b, data):
        data = data.ljust(BLOCK, b'\x1a')
        for k in range(BLOCK // SECSZ):
            o = (OFF * SPT + b * (BLOCK // SECSZ) + k) * SECSZ
            img[o:o + SECSZ] = data[k * SECSZ:(k + 1) * SECSZ]

    dirent = bytearray([0xE5]) * BLOCK
    nb, ne = 1, 0
    for (base, ext), data in files:
        recs = max(1, (len(data) + 127) // 128)
        data = data.ljust(recs * 128, b'\x1a')
        for j in range(0, recs, 512):           # an entry: 512 records
            part = data[j * 128:(j + 512) * 128]
            n = len(part) // 128
            blocks = []
            for k in range(0, len(part), BLOCK):
                assert nb <= DSM, 'the disc is full'
                put_block(nb, part[k:k + BLOCK])
                blocks.append(nb)
                nb += 1
            assert ne < NDIR, 'the directory is full'
            e = bytearray(32)
            e[1:9] = base.ljust(8).encode()
            e[9:12] = ext.ljust(3).encode()
            last = j // 128 + (n - 1) // 128       # the highest logical extent
            e[12], e[14] = last & 0x1F, last >> 5
            e[15] = n - (n - 1) // 128 * 128
            e[16:16 + len(blocks)] = bytes(blocks)
            dirent[ne * 32:ne * 32 + 32] = e
            ne += 1
    put_block(0, bytes(dirent))
    return img


def write_dsk(img, path):
    """A standard (MV - CPCEMU) .dsk: as lambdaspeak4's mkvortex.py."""
    tracksz = 0x100 + SPT * SECSZ
    out = bytearray(0x100)
    out[0:34] = b'MV - CPCEMU Disk-File\r\nDisk-Info\r\n'
    out[0x30], out[0x31] = CYLS, HEADS
    struct.pack_into('<H', out, 0x32, tracksz)
    for c in range(CYLS):
        for h in range(HEADS):
            t = c * HEADS + h
            ti = bytearray(0x100)
            ti[0:12] = b'Track-Info\r\n'
            ti[0x10], ti[0x11] = c, h
            ti[0x14], ti[0x15], ti[0x16], ti[0x17] = 2, SPT, 0x2A, 0xE5
            for s in range(SPT):
                ti[0x18 + s * 8:0x1c + s * 8] = bytes([c, h, 1 + s, 2])
            out += ti + img[t * SPT * SECSZ:(t + 1) * SPT * SECSZ]
    open(path, 'wb').write(bytes(out))


def read_vortex_dsk(path):
    """{name: bytes} from a Vortex .dsk -- written apart from build(): by
    the sector ids in the track headers, and CP/M's rules for EX and RC."""
    d = open(path, 'rb').read()
    tracksz = d[0x32] | d[0x33] << 8
    secs = {}
    for t in range(d[0x30] * d[0x31]):
        ti = d[0x100 + t * tracksz:0x100 + (t + 1) * tracksz]
        for s in range(ti[0x15]):
            c, h, r, n = ti[0x18 + 8 * s:0x1c + 8 * s]
            secs[(c, h, r)] = ti[0x100 + s * 512:0x100 + (s + 1) * 512]

    def block(b):
        out = b''
        for k in range(8):
            ls = OFF * SPT + b * 8 + k
            t = ls // SPT
            out += secs[(t // 2, t % 2, 1 + ls % SPT)]
        return out
    dirb = block(0)
    files = {}
    for i in range(NDIR):
        e = dirb[32 * i:32 * i + 32]
        if e[0] > 15:
            continue
        name = (e[1:9].decode().rstrip(), e[9:12].decode().rstrip())
        files.setdefault(name, []).append(e)
    out = {}
    for name, ents in files.items():
        ents.sort(key=lambda e: e[12] | e[14] << 5)
        data, total = b'', 0
        for e in ents:
            last = e[12] | e[14] << 5
            total = last * 128 + e[15]           # records up to this entry
            data += b''.join(block(b) for b in e[16:32] if b)
        out[name] = data[:total * 128]
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    files = sorted(read_data_dsk(sys.argv[1]).items())
    write_dsk(build(files), sys.argv[2])
    back = read_vortex_dsk(sys.argv[2])
    for name, data in files:
        pad = data.ljust((len(data) + 127) // 128 * 128, b'\x1a')
        if back.get(name) != pad:
            sys.exit(f'vortexdisk: {name} does not read back')
    print(f'{sys.argv[2]}: Vortex 80x2x9x512, {len(files)} files, read back equal')


if __name__ == '__main__':
    main()
