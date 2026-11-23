#!/usr/bin/env python3
"""The PCW's discs: a bootable CPC Lisp disc, or a look into one.

    tools/pcw/mkdisk.py -o lisp.dsk --boot BOOT.BIN --resident RESIDENT.BIN
                        [--hook] FILE[:NAME]...
    tools/pcw/mkdisk.py -o data.dsk FILE[:NAME]...     a data disc
    tools/pcw/mkdisk.py --list disc.dsk
    tools/pcw/mkdisk.py --get disc.dsk NAME [out]

The disc is the PCW 8256's own, 180 KB: one side, 40 tracks of nine
sectors of 512 bytes (numbered 1-9, interleaved as CP/M has them), the
specification in its first sector's first 16 bytes -- the boot sector's,
BOOT.BIN's (mach/pcw/boot.asm): its byte 15 is set here to make the
sector's bytes add up to &FF, which the boot program asks. Track 0 is
reserved: sector 1 the boot sector, 2-5 the loader (the rest of BOOT.BIN),
6-9 the resident part (RESIDENT.BIN). Then CP/M's file system: 1 KB
blocks, the directory in blocks 0 and 1 (64 entries), the files after it,
each in one piece (the loader reads LISP.IMG through the directory all
the same). --hook sets the resident part's RS_HARN to 1: the test
harness's disc (tools/pcw/pcw.py), whose Lisp writes its transcript into
the ring the harness reads. A file's name is its own, in capitals, unless
NAME says another; a text file's last record is padded with ^Z.

The image is an EXTENDED CPC DSK, as ZEsarUX and a Gotek (FlashFloppy)
read it.
"""
import argparse, os, sys

SPT, SECSIZE, TRACKS = 9, 512, 40
ORDER = [1, 6, 2, 7, 3, 8, 4, 9, 5]     # the sectors along a track
SPEC = bytes([0, 0, 40, 9, 2, 1, 3, 2, 0x2A, 0x52, 0, 0, 0, 0, 0, 0])
BLS = 1024
DIRBLOCKS = 2
RS_HARN = 0x86                         # mach/pcw/jumps.asm


def geometry(spec):
    sides = 2 if spec[1] & 3 else 1
    tracks, spt, off, bsh, dirb = spec[2], spec[3], spec[5], spec[6], spec[7]
    bls = 128 << bsh
    dsm = (tracks * sides - off) * spt * SECSIZE // bls
    return dict(sides=sides, tracks=tracks, spt=spt, off=off, bls=bls, dirb=dirb,
                dsm=dsm, wide=dsm > 255)


class Disc:
    def __init__(self, spec=SPEC):
        self.spec = spec
        g = geometry(spec)
        assert g["sides"] == 1 and g["spt"] == SPT
        self.g = g
        self.sec = [bytearray(b"\xE5" * SECSIZE) for _ in range(g["tracks"] * SPT)]

    def block(self, b):
        """the logical sectors of block b"""
        spb = self.g["bls"] // SECSIZE
        first = self.g["off"] * SPT + b * spb
        return range(first, first + spb)

    def write_block(self, b, data):
        data = data.ljust(self.g["bls"], b"\x1A" if False else b"\0")
        for i, ls in enumerate(self.block(b)):
            self.sec[ls][:] = data[i * SECSIZE:(i + 1) * SECSIZE]

    def read_block(self, b):
        return b"".join(bytes(self.sec[ls]) for ls in self.block(b))

    def directory(self):
        d = b"".join(self.read_block(b) for b in range(self.g["dirb"]))
        return [bytearray(d[i:i + 32]) for i in range(0, len(d), 32)]

    def put_directory(self, ents):
        d = b"".join(bytes(e) for e in ents)
        n = self.g["bls"]
        for b in range(self.g["dirb"]):
            self.write_block(b, d[b * n:(b + 1) * n])

    def used(self):
        u = set(range(self.g["dirb"]))
        for e in self.directory():
            if e[0] < 16:
                u |= set(self.al(e))
        return u

    def al(self, e):
        if self.g["wide"]:
            return [b for b in (e[16 + 2 * i] | e[17 + 2 * i] << 8 for i in range(8)) if b]
        return [b for b in e[16:32] if b]

    def add(self, name, data, text):
        recs = (len(data) + 127) // 128
        if text and len(data) % 128:
            data = data + b"\x1A" * (128 - len(data) % 128)
        data = data.ljust(recs * 128, b"\0")
        used = self.used()
        nb = (len(data) + self.g["bls"] - 1) // self.g["bls"]
        # one piece: the first run of nb free blocks
        start = self.g["dirb"]
        while any(b in used for b in range(start, start + nb)):
            start += 1
        if start + nb > self.g["dsm"]:
            sys.exit("mkdisk.py: the disc is full (%s)" % name)
        blocks = list(range(start, start + nb))
        for i, b in enumerate(blocks):
            self.write_block(b, data[i * self.g["bls"]:(i + 1) * self.g["bls"]])
        ents = self.directory()
        per = 8 if self.g["wide"] else 16
        nm = cpm_name(name)
        k = 0
        while True:
            free = next((i for i, e in enumerate(ents) if e[0] == 0xE5), None)
            if free is None:
                sys.exit("mkdisk.py: the directory is full (%s)" % name)
            e = bytearray(32)
            e[1:12] = nm
            e[12] = k & 31
            e[14] = k >> 5
            r = min(128, recs - 128 * k)
            e[15] = r
            bl = blocks[k * per:(k + 1) * per]
            for i, b in enumerate(bl):
                if self.g["wide"]:
                    e[16 + 2 * i], e[17 + 2 * i] = b & 255, b >> 8
                else:
                    e[16 + i] = b
            ents[free] = e
            k += 1
            if 128 * k >= recs:
                break
        self.put_directory(ents)

    def files(self):
        out = {}
        for e in self.directory():
            if e[0] == 0:
                nm = bytes(c & 0x7F for c in e[1:12])
                ext = e[12] & 31 | e[14] << 5
                out.setdefault(nm, []).append((ext, e))
        return out

    def get(self, name):
        exts = self.files().get(cpm_name(name))
        if not exts:
            return None
        data = b""
        for ext, e in sorted(exts, key=lambda x: x[0]):
            part = b"".join(self.read_block(b) for b in self.al(e))
            data += part[:e[15] * 128]
        return data

    def dsk(self):
        h = bytearray(256)
        h[0:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
        h[0x22:0x30] = b"CPC Lisp PCW  "
        h[0x30] = self.g["tracks"]
        h[0x31] = 1
        size = 256 + SPT * SECSIZE
        for t in range(self.g["tracks"]):
            h[0x34 + t] = size // 256
        out = bytes(h)
        for t in range(self.g["tracks"]):
            ti = bytearray(256)
            ti[0:12] = b"Track-Info\r\n"
            ti[0x10], ti[0x11], ti[0x14], ti[0x15], ti[0x16], ti[0x17] = t, 0, 2, SPT, 0x4E, 0xE5
            data = b""
            for i, s in enumerate(ORDER):
                ti[0x18 + 8 * i:0x20 + 8 * i] = bytes([t, 0, s, 2, 0, 0, SECSIZE & 255, SECSIZE >> 8])
                data += bytes(self.sec[t * SPT + s - 1])
            out += bytes(ti) + data
        return out

    @classmethod
    def load(cls, path):
        d = open(path, "rb").read()
        ext = d[:8] == b"EXTENDED"
        ntr = d[0x30]
        off = 0x100
        secs = {}
        for t in range(ntr * d[0x31]):
            size = d[0x34 + t] * 256 if ext else d[0x32] | d[0x33] << 8
            if not size:
                continue
            ti = d[off:off + 256]
            p = off + 256
            for i in range(ti[0x15]):
                e = ti[0x18 + 8 * i:0x20 + 8 * i]
                ln = (e[6] | e[7] << 8) if ext else 128 << e[3]
                secs[(ti[0x10], ti[0x11], e[2])] = d[p:p + ln]
                p += ln
            off += size
        spec = secs[(0, 0, 1)][:16]
        if spec[0] not in (0, 3):
            spec = SPEC
        disc = cls(bytes(spec))
        for (t, sd, s), b in secs.items():
            if sd == 0 and 1 <= s <= SPT and t < disc.g["tracks"]:
                disc.sec[t * SPT + s - 1][:] = b[:SECSIZE].ljust(SECSIZE, b"\xE5")
        return disc


def cpm_name(name):
    name = os.path.basename(name).upper()
    base, _, ext = name.partition(".")
    assert 0 < len(base) <= 8 and len(ext) <= 3, name
    return (base.ljust(8) + ext.ljust(3)).encode("ascii")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out")
    ap.add_argument("--boot", help="BOOT.BIN: the boot sector and the loader")
    ap.add_argument("--resident", help="RESIDENT.BIN")
    ap.add_argument("--hook", action="store_true", help="the test harness's disc")
    ap.add_argument("--list", metavar="DSK")
    ap.add_argument("--get", nargs="+", metavar="ARG", help="DSK NAME [out]")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    if a.list:
        d = Disc.load(a.list)
        for nm, exts in sorted(d.files().items()):
            recs = sum(e[15] for _, e in exts)
            print("%s.%s %7d" % (nm[:8].decode(), nm[8:].decode(), recs * 128))
        print("%dK free" % ((d.g["dsm"] - len(d.used())) * d.g["bls"] // 1024))
        return
    if a.get:
        d = Disc.load(a.get[0])
        data = d.get(a.get[1])
        if data is None:
            sys.exit("mkdisk.py: no %s" % a.get[1])
        if data.find(b"\x1A") >= 0 and a.get[1].upper().endswith((".LSP", ".FAS", ".TXT")):
            data = data[:data.find(b"\x1A")]
        (open(a.get[2], "wb") if len(a.get) > 2 else sys.stdout.buffer).write(data)
        return
    disc = Disc()
    if a.boot:
        boot = open(a.boot, "rb").read()
        assert len(boot) <= 512 + 4 * SECSIZE, len(boot)
        boot = bytearray(boot.ljust(512 + 4 * SECSIZE, b"\0"))
        assert boot[:15] == SPEC[:15], boot[:16].hex()
        boot[15] = 0
        boot[15] = (0xFF - sum(boot[:512])) & 0xFF
        assert sum(boot[:512]) & 0xFF == 0xFF
        for i in range(5):
            disc.sec[i][:] = boot[i * SECSIZE:(i + 1) * SECSIZE]
        res = bytearray(open(a.resident, "rb").read())
        assert len(res) <= 4 * SECSIZE, len(res)
        if a.hook:
            res[RS_HARN] = 1
        res = bytes(res).ljust(4 * SECSIZE, b"\0")
        for i in range(4):
            disc.sec[5 + i][:] = res[i * SECSIZE:(i + 1) * SECSIZE]
    else:
        disc.sec[0][:16] = SPEC
    for f in a.files:
        path, _, name = f.partition(":")
        data = open(path, "rb").read()
        name = name or os.path.basename(path)
        text = not name.upper().endswith((".IMG", ".BIN", ".COM"))
        disc.add(name, data, text)
    open(a.out, "wb").write(disc.dsk())


if __name__ == "__main__":
    main()
