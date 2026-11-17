#!/usr/bin/env python3
"""Renumber FutureOS's four ROMs by hand, as its installer does.

    tools/futureos/fosroms.py SRCDIR OUTDIR A B C D [--plus]
                              [--no-fbee] [--no-fbfe] [--msr-mask] [--card]

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
unused port &FFEE (nothing decodes it; a read gave &78 on Mike's 464, &FF
in MAME -- not the LS3's &20): FutureOS then finds no LambdaSpeak. Its LambdaSpeak III code (the eight bytes |OS sends at
&F592, the probe in ROM C at &F9E4 -- a read of &20 is an LS3 -- the
clock at &DEFD/&DF3C: &F3, &D5, &D4... and speech) speaks the LS3's
protocol -- which the LambdaSpeak 4 implements, clock included (&D2-&D9
getters, &DB/&DA setters: the card session, its ls4_proto.c), and FutureOS
did speak through it. The hang on Mike's 464, 2026-11-16, came from the
ROMs being in the card's slots (the select timing), not from this: so
--no-fbee is a precaution, and FutureOS's speech and clock through the
card are untested -- build without it to try. (The card's one restart
that evening was an expansion card on the wrong pins, not FutureOS.)
The card session keeps these patches documented in its repo
(lambdaspeak4: docs/futureos.md, tools/fosroms.py).

--no-fbfe moves the DK'tronics speech probe (ROM C &FA15, `ld bc,&FBFE`:
idle, busy after a write, idle again -- the only &FBFE access in the four
ROMs) to &FFFE: neither a floating &78 nor &FF passes it, so FutureOS
finds no DK'tronics. On a LambdaSpeak 4 the probe passed, and every access
to &FBFE made the card hand its drive's responders back to speech: the next
FDC status read found nothing (the card session, 2026-11-17).

--msr-mask: ROM B's disc loop dispatches on the FDC's status byte --
`ld hl,&FE10` (&C1B6), then `dec c : in l,(c) : inc c : jp (hl)` at &FE10/
30/50/70 (wait), &FEF0 a byte in, &FEB0 a byte out, &FED0 the results. A
status value no µPD765 shows -- the &7E a starved LambdaSpeak 4 serves,
the &78 of a floating bus -- lands mid-instruction (&FE7E: `out
(&FBFF),&84`, an early return, a half-read DIR). This adds `dec c : in
a,(c) : and &F0 : ld l,a : inc c : jp (hl)` at &FE23 (the zeros after
&FE20's `jp &EF7F`: status &23, unreachable once masked) and sends the
four wait entries there (`jr`) and the byte paths' next status read
(`jp &FE24`). &7E and &78 then read as &70: wait. A is free there (the
data is stored first; &C1C4 and &EF7F do not use it). It costs 6 us a
wait and 3 us a byte: 22 us at worst from a byte's arrival to its
read, inside the 32 us of a double-density byte. Checked in MAME, where
the FDC stops a read on an overrun.
Before every DIR, ROM B checks the internal FDC once (&EE3C: `ld
bc,&FB7E : in a,(c) : cp &80`; &FF is no FDC, bit 7 clear "skip it") --
one starved read there and the DIR is not read at all, the screen
showing old memory as its entries. That `ld bc / in` becomes `call
&FE43 : nop : nop`, and &FE43 (more zeros out of the masked dispatch's
reach) reads up to 251 times, ~2 ms, until bit 7 is set: `ld bc,&FB7E :
ld e,b : in a,(c) : ret m : dec e : jr nz : ret`. E is free there
(each drive's block, and &EF58, load HL and DE first; &FCFF uses A and
BC). ROM C's check at boot (&F95A) is the same, but ROM C has no room:
left as it is.

--card is all three, for a CPC with a LambdaSpeak 4.

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

# (ROM, address, the bytes there now, the bytes it gets)
PATCHES = {
    '--no-fbfe': [('C', 0xFA15, '01 FE FB ED 78 CB 7F', '01 FE FF')],
    '--msr-mask': [
        ('B', 0xFE20, 'C3 7F EF 00 00 00 00 00 00 00 00',
         'C3 7F EF 0D ED 78 E6 F0 6F 0C E9'),       # &FE23: the masked read
        ('B', 0xFE10, '0D ED 68 0C E9', '18 11'),  # jr &FE23
        ('B', 0xFE30, '0D ED 68 0C E9', '18 F1'),
        ('B', 0xFE50, '0D ED 68 0C E9', '18 D1'),
        ('B', 0xFE70, '0D ED 68 0C E9', '18 B1'),
        ('B', 0xFEB0, '1A ED 79 13 0D ED 68 0C E9',
         '1A ED 79 13 0D C3 24 FE'),                # out, then jp &FE24
        ('B', 0xFEF0, 'ED 78 12 13 0D ED 68 0C E9',
         'ED 78 12 13 0D C3 24 FE'),                # in, then jp &FE24
        ('B', 0xC1B6, '21 10 FE', '21 10 FE'),     # the one entry: as it was
        ('B', 0xFE40, 'C3 7F EF 00 00 00 00 00 00 00 00 00 00 00 00 00',
         'C3 7F EF 01 7E FB 58 ED 78 F8 1D 20 FA C9'),  # &FE43: the retry
        ('B', 0xEE3C, '01 7E FB ED 78 FE 80', 'CD 43 FE 00 00'),
    ],
}
FLAGS = ('--plus', '--no-fbee', '--no-fbfe', '--msr-mask', '--card')


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
    args = [a for a in sys.argv[1:] if a not in FLAGS]
    if len(args) != 6 or any(a.startswith('--') for a in args):
        sys.exit(__doc__)
    flags = set(sys.argv[1:]) & set(FLAGS)
    if '--card' in flags:
        flags |= {'--no-fbee', '--no-fbfe', '--msr-mask'}
    src, out = args[:2]
    nums = dict(zip('ABCD', (int(n, 0) for n in args[2:])))
    if not 0 <= nums['A'] <= 15 or not all(1 <= nums[r] <= 255 for r in 'BCD'):
        sys.exit('fosroms: ROM A is 0-15, B, C, D 1-255 (as the installer asks)')
    if len(set(nums.values())) != 4:
        sys.exit('fosroms: four different numbers, please')
    kind = 'FOSP' if '--plus' in flags else 'FOSC'
    if kind == 'FOSP' and flags & {'--no-fbfe', '--msr-mask'}:
        sys.exit('fosroms: --no-fbfe and --msr-mask are worked out on the '
                 'CPC ROMs (FOSC) only')
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
        if '--no-fbee' in flags:
            k = d.find(b'\x01\xEE\xFB')
            while k >= 0:
                d[k + 2] = 0xFF
                moved += 1
                k = d.find(b'\x01\xEE\xFB', k + 3)
        done = []
        for flag in ('--no-fbfe', '--msr-mask'):
            if flag not in flags:
                continue
            for r, addr, now, new in PATCHES[flag]:
                if r != rom:
                    continue
                now, new, o = bytes.fromhex(now), bytes.fromhex(new), addr - 0xC000
                if d[o:o + len(now)] != now:
                    sys.exit(f'fosroms: {kind}-{rom}: &{addr:04X} is not '
                             f'{now.hex(" ")} -- another version? not touching it')
                d[o:o + len(new)] = new
                if flag[2:] not in done:
                    done.append(flag[2:])
        d[0x3FFF] = sum(d[:0x3FFF]) & 0xFF
        name = os.path.join(out, f'FOS-{rom}.ROM')
        open(name, 'wb').write(d)
        print(f'{name}: ROM {nums[rom]}, {len(sites)} numbers, '
              + (f'{moved} &FBEE -> &FFEE, ' if '--no-fbee' in flags else '')
              + (f'{"/".join(done)}, ' if done else '')
              + f'checksum {d[0x3FFF]:02X}')


main()
