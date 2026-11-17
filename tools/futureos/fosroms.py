#!/usr/bin/env python3
"""Renumber FutureOS's four ROMs by hand, as its installer does.

    tools/futureos/fosroms.py SRCDIR OUTDIR A B C D [--plus] [--no-fbee]

reads FOSC-A.ROM ... FOSC-D.ROM (FOSP-* with --plus; with or without
their AMSDOS header) from SRCDIR, as they come on the installer disc --
built for ROM numbers 10, 11, 12, 13 -- and writes FOS-A.ROM ... FOS-D.ROM
(16384 bytes each) for the numbers A B C D to OUTDIR.

What the installer (DISC, "ROM-Nummern anpassen", 2026-11-15) changes:

* in every ROM, the 28 `ld bc,&DFnn` stubs of the API page at &FF00-&FFFF
  (ROM_A, ROM_A2B, OSRON_A...): their nn is the physical number of ROM
  A, B, C or D -- the installer's lines 590-890 poke exactly these;
* in ROM A, four `ld c,&0A : out (c),c` at &FD88, &FDA1, &FDBA, &FDD3
  (the byte after &0E: &FD89 ...), ROM A's number (line 3380);
* the last byte, &FFFF: the sum of the other 16383 bytes, mod 256
  (FLASHALL.Z80's routine at &3425, "Pruefsummen anpassen").

--no-fbee moves every `ld bc,&FBEE` (four in ROM A, one in ROM C) to the
unused port &FFEE, where a read gives &FF: FutureOS then finds no
LambdaSpeak. Its LambdaSpeak III code (the eight bytes |OS sends at
&F592, the probe in ROM C at &F9E4 -- a read of &20 is an LS3 -- the
clock at &DEFD/&DF3C: &F3, &D5, &D4... and speech) speaks the LS3's
protocol, and a LambdaSpeak 4 takes &Dx otherwise (&D0: a ROM number
and a reset): on Mike's 464, 2026-11-16, the desktop came up, spoke, and
hung or ended in DECtalk output. (The card's one restart that evening was
an expansion card on the wrong pins, not FutureOS.)

No other `ld a/c,10-13` in the four ROMs selects a ROM (checked: they
are writes to expansion ports). Nothing of FutureOS is in this file: the
ROMs are TFM's, from futureos.de, free for non-commercial use.

A 464 initialises only ROMs 1-7 (KL ROM WALK: `ld c,7 ... dec c`), so
ROM A must be below 8 there for |OS; 0 is the installer's autostart.
"""
import os, sys

STUBS = {  # the API page: where each ROM's physical number is built in
    'A': (0xFF01, 0xFF24, 0xFF36, 0xFF48, 0xFF50, 0xFF86, 0xFFBC),
    'B': (0xFF07, 0xFF1A, 0xFF5A, 0xFF6C, 0xFF7E, 0xFF98, 0xFFCE),
    'C': (0xFF0D, 0xFF2C, 0xFF62, 0xFF90, 0xFFA2, 0xFFB4, 0xFFE0),
    'D': (0xFF13, 0xFF3E, 0xFF74, 0xFFAA, 0xFFC6, 0xFFD8, 0xFFEA),
}
ROM_A_SELECTS = (0xFD89, 0xFDA2, 0xFDBB, 0xFDD4)
DEFAULT = {'A': 10, 'B': 11, 'C': 12, 'D': 13}


def image(path):
    raw = open(path, 'rb').read()
    if len(raw) > 16384:                       # an AMSDOS header in front
        h = raw[:128]
        if (sum(h[:67]) & 0xFFFF) != (h[67] | h[68] << 8):
            sys.exit(f'fosroms: {path}: not 16 KB, and no AMSDOS header')
        raw = raw[128:128 + (h[0x40] | h[0x41] << 8 | h[0x42] << 16)]
    if len(raw) != 16384:
        sys.exit(f'fosroms: {path}: {len(raw)} bytes, not 16384')
    return bytearray(raw)


def main():
    args = [a for a in sys.argv[1:] if a not in ('--plus', '--no-fbee')]
    if len(args) != 6:
        sys.exit(__doc__)
    src, out = args[:2]
    nums = dict(zip('ABCD', (int(n, 0) for n in args[2:])))
    if not 0 <= nums['A'] <= 15 or not all(1 <= nums[r] <= 255 for r in 'BCD'):
        sys.exit('fosroms: ROM A is 0-15, B, C, D 1-255 (as the installer asks)')
    if len(set(nums.values())) != 4:
        sys.exit('fosroms: four different numbers, please')
    kind = 'FOSP' if '--plus' in sys.argv else 'FOSC'
    os.makedirs(out, exist_ok=True)
    for rom in 'ABCD':
        d = image(os.path.join(src, f'{kind}-{rom}.ROM'))
        sites = [(a, r) for r in 'ABCD' for a in STUBS[r]]
        if rom == 'A':
            sites += [(a, 'A') for a in ROM_A_SELECTS]
        for addr, r in sites:
            o = addr - 0xC000
            if d[o] != DEFAULT[r] or (addr in ROM_A_SELECTS and d[o - 1] != 0x0E) \
                    or (addr not in ROM_A_SELECTS and (d[o - 1], d[o + 1]) != (0x01, 0xDF)):
                sys.exit(f'fosroms: {kind}-{rom}: &{addr:04X} is not ROM {r}\'s '
                         f'number {DEFAULT[r]} -- another version? not touching it')
            d[o] = nums[r]
        moved = 0
        if '--no-fbee' in sys.argv:
            k = d.find(b'\x01\xEE\xFB')
            while k >= 0:
                d[k + 2] = 0xFF
                moved += 1
                k = d.find(b'\x01\xEE\xFB', k + 3)
        d[0x3FFF] = sum(d[:0x3FFF]) & 0xFF
        name = os.path.join(out, f'FOS-{rom}.ROM')
        open(name, 'wb').write(d)
        print(f'{name}: ROM {nums[rom]}, {len(sites)} numbers, '
              + (f'{moved} &FBEE -> &FFEE, ' if '--no-fbee' in sys.argv else '')
              + f'checksum {d[0x3FFF]:02X}')


main()
