#!/usr/bin/env python3
"""An SD card image for ZEsarUX's DivMMC with the real esxDOS: a FAT16
partition (an MBR, one partition, 2 KB clusters) holding the files of one
or more folders, merged at the card's root -- 8.3 names, upper case.

    tools/spectrum/mkmmc.py out.mmc [-m MB] folder...

e.g. esxDOS's own SYS and BIN (from its distribution: not ours, never in
this repo) and build/spectrum/sd. ZEsarUX: --enable-divmmc --enable-mmc
--mmc-file out.mmc, without its esxDOS handler.
"""
import argparse, os, struct, sys

SEC = 512
SPC = 4                         # sectors a cluster
START = 2048                    # the partition's first sector
ROOTENTS = 512


def name83(n):
    n = n.upper()
    if n in (".", ".."):
        return n.ljust(11).encode()
    base, dot, ext = n.rpartition(".")
    if not dot:
        base, ext = n, ""
    if not base or len(base) > 8 or len(ext) > 3:
        sys.exit("mkmmc.py: not an 8.3 name: " + n)
    return (base.ljust(8) + ext.ljust(3)).encode("ascii")


class Fat16:
    def __init__(self, mb):
        self.total = mb * 1024 * 1024 // SEC
        self.psize = self.total - START
        est = self.psize // SPC
        self.fatsecs = (est * 2 + SEC - 1) // SEC + 1
        self.rootsec = 1 + 2 * self.fatsecs
        self.datasec = self.rootsec + ROOTENTS * 32 // SEC
        self.nclus = (self.psize - self.datasec) // SPC
        assert 4085 <= self.nclus < 65525, "not a FAT16 size"
        self.img = bytearray(self.total * SEC)
        self.fat = [0xFFF8, 0xFFFF] + [0] * self.nclus
        self.next = 2

    def at(self, sector):
        return (START + sector) * SEC

    def alloc(self, n):
        """n clusters (at least one) in a chain -> the first"""
        n = max(n, 1)
        first = self.next
        if first + n > self.nclus + 2:
            sys.exit("mkmmc.py: the card is full")
        for c in range(first, first + n - 1):
            self.fat[c] = c + 1
        self.fat[first + n - 1] = 0xFFFF
        self.next += n
        return first

    def csec(self, c):
        return self.datasec + (c - 2) * SPC

    def write(self, c, data):
        p = self.at(self.csec(c))
        self.img[p:p + len(data)] = data

    @staticmethod
    def entry(name, attr, clus, size):
        return struct.pack("<11sBBBHHHHHHHI", name, attr, 0, 0, 0, 0x5B75, 0x5B75,
                           0, 0, 0x5B75, clus, size)

    def dir(self, tree, parent=0):
        """the entries for a {name: bytes or dict} tree; subfolders and
        files written"""
        out = []
        for name in sorted(tree):
            v = tree[name]
            if isinstance(v, dict):
                n = len(v) + 2
                clus = self.alloc((n * 32 + SPC * SEC - 1) // (SPC * SEC))
                body = self.entry(name83("."), 0x10, clus, 0) + \
                    self.entry(name83(".."), 0x10, parent, 0) + \
                    b"".join(self.dir(v, clus))
                self.write(clus, body)
                out.append(self.entry(name83(name), 0x10, clus, 0))
            else:
                clus = self.alloc((len(v) + SPC * SEC - 1) // (SPC * SEC)) if v else 0
                if v:
                    self.write(clus, v)
                out.append(self.entry(name83(name), 0x20, clus, len(v)))
        return out

    def finish(self, tree):
        root = b"".join(self.dir(tree))
        if len(root) > ROOTENTS * 32:
            sys.exit("mkmmc.py: too many files at the root")
        p = self.at(self.rootsec)
        self.img[p:p + len(root)] = root
        fat = b"".join(struct.pack("<H", e) for e in self.fat)
        for k in range(2):
            p = self.at(1 + k * self.fatsecs)
            self.img[p:p + len(fat)] = fat
        # the boot sector
        bs = bytearray(SEC)
        bs[0:3] = b"\xeb\x3c\x90"
        bs[3:11] = b"MSWIN4.1"
        struct.pack_into("<HBHBHHBHHHII", bs, 11, SEC, SPC, 1, 2, ROOTENTS,
                         0 if self.psize >= 65536 else self.psize, 0xF8,
                         self.fatsecs, 63, 255, START,
                         self.psize if self.psize >= 65536 else 0)
        struct.pack_into("<BBBI11s8s", bs, 36, 0x80, 0, 0x29, 0x1D5C0A11,
                         b"NO NAME    ", b"FAT16   ")
        bs[510:512] = b"\x55\xaa"
        p = self.at(0)
        self.img[p:p + SEC] = bs
        # the MBR: one FAT16 partition
        self.img[446:462] = struct.pack("<B3sB3sII", 0, b"\xfe\xff\xff", 0x06,
                                        b"\xfe\xff\xff", START, self.psize)
        self.img[510:512] = b"\x55\xaa"
        return self.img


def read_tree(path, tree):
    for n in os.listdir(path):
        p = os.path.join(path, n)
        if os.path.isdir(p):
            read_tree(p, tree.setdefault(n.upper(), {}))
        else:
            tree[n.upper()] = open(p, "rb").read()
    return tree


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("-m", "--mb", type=int, default=32)
    ap.add_argument("folders", nargs="+")
    a = ap.parse_args()
    tree = {}
    for f in a.folders:
        read_tree(f, tree)
    open(a.out, "wb").write(Fat16(a.mb).finish(tree))


if __name__ == "__main__":
    main()
