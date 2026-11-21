#!/usr/bin/env python3
"""LISP.TAP: CPC Lisp for the ZX Spectrum on a tape image, for esxDOS's
tape emulation (the NMI browser, or .tapein then LOAD "" from 128 BASIC or
the Loader) or a real tape.

    tools/spectrum/mktap.py BUILD_DIR      -> BUILD_DIR/LISP.TAP

The blocks: a BASIC program "LISP" that starts itself (10 CLEAR VAL
"28671": LOAD ""CODE : RANDOMIZE USR VAL "28672"), the loader's code at
&7000 (mach/spectrum/loader.asm), then headerless blocks the loader reads
itself with the ROM's LD-BYTES: the machine pages (LISPM.ROM), the six
images in bank order -- the core, library parts 0-3, the VM -- and the
resident part (it goes over BASIC's program, so last).
"""
import os, sys

LOADER = 0x7000


def block(flag, data):
    b = bytes([flag]) + data
    x = 0
    for c in b:
        x ^= c
    b += bytes([x])
    return len(b).to_bytes(2, "little") + b


def header(kind, name, length, p1, p2):
    n = name.encode("ascii").ljust(10)[:10]
    return block(0, bytes([kind]) + n + length.to_bytes(2, "little")
                 + p1.to_bytes(2, "little") + p2.to_bytes(2, "little"))


def basic():
    """10 CLEAR VAL "28671": LOAD ""CODE : RANDOMIZE USR VAL "28672" """
    CLEAR, VAL, LOAD, CODE, RANDOMIZE, USR = 0xFD, 0xB0, 0xEF, 0xAF, 0xF9, 0xC0
    q = b'"'
    body = (bytes([CLEAR, VAL]) + q + str(LOADER - 1).encode() + q + b":"
            + bytes([LOAD]) + q + q + bytes([CODE]) + b":"
            + bytes([RANDOMIZE, USR, VAL]) + q + str(LOADER).encode() + q + b"\r")
    return (10).to_bytes(2, "big") + len(body).to_bytes(2, "little") + body


def main():
    d = sys.argv[1]
    rd = lambda f: open(os.path.join(d, f), "rb").read()
    prog = basic()
    loader = rd("loader.bin")
    out = header(0, "LISP", len(prog), 10, len(prog)) + block(0xFF, prog)
    out += header(3, "lisploader", len(loader), LOADER, 32768) + block(0xFF, loader)
    m = rd("LISPM.ROM")
    assert len(m) == 16384
    out += block(0xFF, m)
    for f in ("LISP.ROM", "LISPLIB.ROM", "LISPLIB2.ROM", "LISPLIB3.ROM", "LISPDEMO.ROM",
              "LISPVM.ROM"):
        b = rd(f)
        assert len(b) == 16384, f
        out += block(0xFF, b)
    out += block(0xFF, rd("resident.bin"))
    open(os.path.join(d, "LISP.TAP"), "wb").write(out)


if __name__ == "__main__":
    main()
