#!/usr/bin/env python3
"""Install CPC Lisp on a LambdaSpeak 4 card, all in one.

    python3 tools/install-card.py              look, show the plan, ask, install
    python3 tools/install-card.py --dry-run    look and show the plan only
    python3 tools/install-card.py --basic      BASIC back: the core's slot silent
    ... -p PORT          the card's serial port (needed when two cards are on USB)
    ... --yes            no questions: only empty slots and CPC Lisp's own are
                         written (other ROMs only when named with --replace)
    ... --replace 3,5    slots of other ROMs that may make room for Lisp
    ... --build          your own images from build/, not roms/ and discs/
    ... --drive KIND     the disc for the card's drive: classics (the default),
                         demos, test or none
    ... --no-discs       the ROMs only
    ... --ls4 DIR        the LambdaSpeak 4 tools' folder, if not found by itself

With the CPC switched OFF and the card on USB, it:

  1. finds the card, and checks that the CPC is off before every write;
  2. reads the card's eight ROM slots. It writes only to empty slots and to
     slots holding a CPC Lisp ROM it knows by its checksum; any other ROM
     (Parados, the LS AI ROM, yours) stays unless you agree to let it go;
  3. puts the six CPC Lisp ROMs there: the core as ROM 0, so the CPC starts
     in Lisp, the five library ROMs at free numbers of 1-6. A slot that has
     the same image already is left alone, or only renumbered;
  4. stores the Lisp discs as flash discs -- the ROM test (HWTEST, APFEL),
     the demos and the classics -- over older CPC Lisp discs of the same kind
     or in free slots, never over another disc; older 512K and 6128 disc
     versions it finds are brought up to date too;
  5. puts the classics in the card's drive, so drive A has them;
  6. reads back every checksum.

It needs Python 3 with pyserial (pip install pyserial) and the LambdaSpeak
4 tools: clone https://github.com/lambdamikel/lambdaspeak4 beside this
repository. Their uploaders do the writing; this script sends no data of
its own. On a 664 or 6128 the card needs its 664/6128 firmware
(lambdaspeak4's docs/two-firmwares.md): that firmware has no flash discs,
so step 4 and 5 are skipped there.
"""
import argparse, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# image, the slot and ROM number it gets if free: the README's table
ROMS = [('LISP.ROM', 2, 0), ('LISPLIB.ROM', 5, 4), ('LISPLIB2.ROM', 0, 5),
        ('LISPLIB3.ROM', 7, 6), ('LISPDEMO.ROM', 3, 3), ('LISPVM.ROM', 1, 1)]
# disc kind, file, label, whether every card gets it (or only an update)
DISCS = [('test', 'cpclisp-hwtest.dsk', 'CPC Lisp {v} ROM test (HWTEST, APFEL)', True),
         ('demos', 'cpclisp-demo.dsk', 'CPC Lisp {v} demos: (load "apfel")', True),
         ('classics', 'cpclisp-classics.dsk', 'CPC Lisp {v} classics (load "classics")', True),
         ('512K', 'cpclisp512.dsk', 'CPC Lisp {v} 512K (RUN"LISP)', False),
         ('6128', 'cpclisp6128.dsk', 'CPC Lisp {v} 6128 (RUN"LISP)', False)]
KEYS = {'test': 'rom test', 'demos': 'demos', 'classics': 'classics',
        '512K': '512k', '6128': '6128'}     # in an older disc's label
EMPTY_SUM = 16384 * 0xFF                    # an erased slot: all FF
# Every CPC Lisp ROM in roms/ since 0.9 (git log -- roms/), by its byte sum:
# a slot holding one of these is CPC Lisp's to replace. A clone adds its
# git history; the images being installed are added too.
KNOWN_LISP = {int(x, 16) for x in '''
0014f3b8 0014f41d 0014f430 0014f452 00158c22 00158d3f 00158d65 00158d71
00158dab 0015c195 00171dfe 00171e63 00171e76 00174cd4 00174d10 00174d4a
00174d60 001765d1 0018491f 00184959 001849af 001849e5 00184a4a 00184a5f
00184a7f 00184a93 00184b11 00184b37 0019fa8b 001ca00c 001ca046 001ca058
001ca07a 001ca1c1 001ca226 001ca255 001ca25b 001cc82b 001cd275 001cedcb
001cedf2 001cf28e 001cf2c9 001d138f 001d13f5 001d1428 001d14e3 001dbdc4
001dbe29 001dbe50 001dbe5e 001df38e 001df3c8 001df43e 001df464 001e0990
001e2399 001fecc4 0023f686 00248fa5'''.split()}


def die(msg):
    sys.exit('install: ' + msg)


def git_sums(repo, paths):
    """The byte sums of every committed version of these files ({} without git)."""
    out = set()
    try:
        for f in paths:
            revs = subprocess.run(['git', '-C', repo, 'log', '--format=%h', '--', f],
                                  capture_output=True, text=True, timeout=20).stdout.split()
            for r in revs:
                d = subprocess.run(['git', '-C', repo, 'show', f'{r}:{f}'],
                                   capture_output=True, timeout=20).stdout
                if len(d) == 16384:
                    out.add(sum(d))
    except (OSError, subprocess.SubprocessError):
        pass
    return out


def find_ls4(arg):
    cands = [arg] if arg else []
    if os.environ.get('LS4_TOOLS'):
        cands.append(os.environ['LS4_TOOLS'])
    cands += [os.path.join(os.path.dirname(ROOT), 'lambdaspeak4', 'tools'),
              os.path.expanduser('~/git/lambdaspeak4/tools')]
    for c in cands:
        if c and os.path.isfile(os.path.join(c, 'romloader.py')):
            return os.path.abspath(c)
    die('the LambdaSpeak 4 tools are not here: clone\n'
        '  https://github.com/lambdamikel/lambdaspeak4\n'
        'beside this repository, or give --ls4 with its tools/ folder')


def load_tools(ls4):
    sys.path.insert(0, ls4)
    try:
        import serial  # noqa: F401
    except ImportError:
        die('needs pyserial: pip install pyserial')
    try:
        import romloader, kitloader, dskloader
    except ImportError as e:
        die(f'cannot load the LambdaSpeak 4 tools in {ls4}: {e}')
    need = [(romloader.Card, ['send_rom', 'set_number', 'read_slots', '_open']),
            (kitloader, ['cpc_is_off']),
            (dskloader, ['open_card', 'listing', 'upload_slot', 'wait_job',
                         'command', 'collect', 'REASONS'])]
    for mod, names in need:
        missing = [n for n in names if not hasattr(mod, n)]
        if missing:
            die(f'the LambdaSpeak 4 tools in {ls4} are older or newer than this '
                f'script knows ({getattr(mod, "__name__", mod)} has no '
                + ', '.join(missing) + ')')
    return romloader, kitloader, dskloader


def find_port(arg):
    from serial.tools import list_ports
    every = list(list_ports.comports())
    if arg:
        p = next((p for p in every if p.device == arg), None)
        if p is None:
            die(f'no {arg} -- is the card plugged in over USB?')
        return arg, p.serial_number or '?'
    cards = [p for p in every if p.vid == 0x2E8A]
    if not cards:
        die('no LambdaSpeak card on USB (a Raspberry Pi device, 2E8A) -- '
            'is it plugged in?')
    if len(cards) > 1:
        print('More than one card is on USB:')
        for p in cards:
            print(f'  {p.device}  serial {p.serial_number}')
        die('pick one with -p PORT')
    return cards[0].device, cards[0].serial_number or '?'


class Rom:
    """The ROM side: the ROM loader's Card, its port closed when not in use
    (two handles on one port would race for the card's replies)."""
    def __init__(self, romloader, kitloader, port):
        self.card, self.kit, self.port = romloader.Card(), kitloader, port

    def close(self):
        if self.card.port:
            self.card.port.close()
            self.card.port = None

    def drain(self, until, timeout=60):
        t0 = time.time()
        while time.time() - t0 < timeout:
            try:
                kind, payload = self.card.out.get(timeout=0.5)
            except Exception:
                continue
            if kind == 'error':
                die(payload)
            if kind == until:
                return payload
        die(f'no {until!r} from the card')

    def off(self):
        return self.kit.cpc_is_off(self.card._open(self.port))

    def slots(self):
        self.card.read_slots(self.port)
        rows, _, text = self.drain('slots')
        sums = {int(m.group(1)): int(m.group(2), 16) for m in
                re.finditer(r'slot (\d+): .*?sum32 ([0-9a-f]{8})', text)}
        if len(rows) != 8 or len(sums) != 8:
            die("the card's slot report is not what this script expects -- "
                'is its firmware older than the sum32 report?')
        for r in rows:
            r['sum'] = sums[r['slot']]
        return rows

    def upload(self, slot, num, data):
        for _ in range(6):
            self.card.send_rom(self.port, slot, num, data)
            text = self.drain('done', 120)
            if 'still speaking' not in text:
                return 'stored' in text
            time.sleep(3)              # the card was talking: try again
        return False

    def number(self, slot, num):
        self.card.set_number(self.port, slot, num)
        return self.drain('note')


def version(core):
    return f'{core[1]}.{core[2]}' + (f'.{core[3]}' if core[3] else '')


def describe(r, lsai):
    num = 'silent' if r['rom'] is None else f"ROM {r['rom']}"
    if r['header'].startswith('ff ff ff ff') and r['sum'] == EMPTY_SUM:
        return num, 'empty'
    if r['sum'] in lsai:
        return num, 'the LS AI ROM'
    if r['rom'] == 7:
        return num, "ROM 7, the disc ROM's number"
    return num, 'another ROM'


def plan_roms(rows, images, known, lsai, replace, ask):
    """[(slot, action, image, ROM number)], what each slot holds, the slots kept."""
    by = {r['slot']: r for r in rows}
    what = {}
    for r in rows:
        if r['header'].startswith('ff ff ff ff') and r['sum'] == EMPTY_SUM:
            what[r['slot']] = 'empty'
        elif r['sum'] in known:
            what[r['slot']] = 'CPC Lisp'
        else:
            what[r['slot']] = describe(r, lsai)[1]
    usable = [s for s in by if what[s] in ('empty', 'CPC Lisp')]
    for s in sorted(replace):
        if s in by and s not in usable:
            usable.append(s)
    # not enough room: offer the unknown ROMs first, LS AI and ROM 7 never
    for s in by:
        if len(usable) >= 6:
            break
        if s in usable or what[s] != 'another ROM' or not ask:
            continue
        num = describe(by[s], lsai)[0]
        if ask(f"Slot {s} holds a ROM this script does not know ({num}, header "
               f"{by[s]['header']}). Let CPC Lisp have the slot?"):
            usable.append(s)
    if len(usable) < 6:
        die(f'CPC Lisp needs six ROM slots, and {len(usable)} can be used: '
            'name the slots of ROMs that may go with --replace')
    kept = [s for s in by if s not in usable]
    for s in kept:
        if by[s]['rom'] == 0:
            die(f'slot {s} answers ROM 0, which the CPC would start instead of '
                f'Lisp: let it go (--replace {s}) or renumber it first')
    taken = {by[s]['rom'] for s in kept if by[s]['rom'] is not None}
    free = [n for n in range(1, 7) if n not in taken]
    if len(free) < 5:
        die('the ROMs kept answer numbers CPC Lisp needs: it wants five free '
            f'numbers of 1-6, and only {free} are')

    where = {}
    for name, (s32, _) in images.items():            # the same image already there
        s = next((s for s in usable if by[s]['sum'] == s32
                  and s not in where.values()), None)
        if s is not None:
            where[name] = s
    for name, slot, _ in ROMS:                       # the README's slot
        if name not in where and slot in usable and slot not in where.values():
            where[name] = slot
    for name, _, _ in ROMS:                          # any other
        if name not in where:
            where[name] = next(s for s in usable if s not in where.values())
    nums = {'LISP.ROM': 0}
    for name, _, pref in ROMS[1:]:                   # its number, else the README's
        r = by[where[name]]
        cands = ([r['rom']] if r['sum'] == images[name][0] else []) + [pref] + free
        nums[name] = next(n for n in cands if n in free and n not in nums.values())

    plan = []
    for name, _, _ in ROMS:
        s, n = where[name], nums[name]
        if by[s]['sum'] != images[name][0]:
            act = 'upload'
        else:
            act = 'keep' if by[s]['rom'] == n else 'number'
        plan.append((s, act, name, n))
    for s in usable:
        if s not in where.values() and what[s] == 'CPC Lisp' and by[s]['rom'] is not None:
            plan.append((s, 'silence', None, 255))  # an older build's, left over
    return plan, what


def plan_discs(lst, discdir, v):
    """[(kind, path, label, slot, action)] for the flash discs."""
    n_slots = int((re.search(r'(\d+) slots of', lst['summary']) or [0, 54])[1])
    used = set()
    for d in lst['slots']:
        used.update(range(d['slot'], d['slot'] + d['span']))
    plan, chosen = [], set()
    for kind, fname, label, always in DISCS:
        path = os.path.join(discdir, fname)
        if not os.path.isfile(path):
            continue
        img = open(path, 'rb').read()
        same = [d for d in lst['slots'] if d['len'] == len(img)
                and d['sum'] == sum(img) & 0xFFFFFFFF and d['slot'] not in chosen]
        older = [d for d in lst['slots'] if d['span'] == 1 and d['slot'] not in chosen
                 and d['label'].lower().startswith('cpc lisp')
                 and KEYS[kind] in d['label'].lower()]
        label = label.format(v=v)
        if same:
            slot, act = same[0]['slot'], 'keep'
        elif older:
            slot, act = older[0]['slot'], 'replace'
        elif always:
            free = [s for s in range(1, n_slots + 1) if s not in used and s not in chosen]
            if not free:
                print(f'  (no free flash disc slot for the {kind} disc: left out)')
                continue
            slot, act = free[0], 'store'
        else:
            continue
        plan.append((kind, path, label, slot, act))
        chosen.add(slot)
    return plan


def yes_no(q):
    try:
        return input(q + ' [y/N] ').strip().lower() in ('y', 'yes')
    except EOFError:
        return False


def basic(rom, known):
    """--basic: the slot answering ROM 0 made silent -- the CPC starts in BASIC."""
    if not rom.off():
        die('the CPC is on -- switch it off first')
    r = next((r for r in rom.slots() if r['rom'] == 0), None)
    if r is None:
        print('No slot answers ROM 0: the CPC starts in BASIC already.')
        return
    if r['sum'] not in known and not yes_no(
            f"Slot {r['slot']} answers ROM 0 but is not a CPC Lisp ROM this "
            'script knows. Make it silent anyway?'):
        die('nothing written')
    print(rom.number(r['slot'], 255))
    print('Done: the CPC starts in BASIC. Run this script again for Lisp, or '
          f"type |BOOTLISP,{r['slot']} in BASIC.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-p', '--port')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--yes', action='store_true')
    ap.add_argument('--replace', default='')
    ap.add_argument('--build', action='store_true')
    ap.add_argument('--drive', default='classics',
                    choices=['classics', 'demos', 'test', 'none'])
    ap.add_argument('--no-discs', action='store_true')
    ap.add_argument('--basic', action='store_true')
    ap.add_argument('--ls4')
    a = ap.parse_args()
    try:
        replace = {int(x) for x in a.replace.split(',') if x.strip()}
    except ValueError:
        die('--replace takes slot numbers, as in --replace 3,5')

    ls4 = find_ls4(a.ls4)
    romloader, kitloader, dskloader = load_tools(ls4)
    romdir = os.path.join(ROOT, 'build' if a.build else 'roms')
    discdir = os.path.join(ROOT, 'build' if a.build else 'discs')
    images = {}
    for name, _, _ in ROMS:
        path = os.path.join(romdir, name)
        if not os.path.isfile(path):
            die(f'no {path}' + (' -- run tools/build.sh first' if a.build else ''))
        d = open(path, 'rb').read()
        if len(d) != 16384:
            die(f'{path} is {len(d)} bytes, not 16384')
        images[name] = (sum(d), d)
    v = version(images['LISP.ROM'][1])
    known = (KNOWN_LISP | {s for s, _ in images.values()}
             | git_sums(ROOT, [f'roms/{n}' for n, _, _ in ROMS]))
    lsai = git_sums(os.path.dirname(ls4), ['roms/LSAI.ROM'])
    lsai_rom = os.path.join(os.path.dirname(ls4), 'roms', 'LSAI.ROM')
    if os.path.isfile(lsai_rom):
        lsai.add(sum(open(lsai_rom, 'rb').read()))

    port, serno = find_port(a.port)
    print(f'CPC Lisp {v} -> the LambdaSpeak card on {port} (serial {serno})')
    rom = Rom(romloader, kitloader, port)
    if a.basic:
        return basic(rom, known)
    if not rom.off():
        die('the CPC is on -- switch it off first (the card stalls while it '
            'writes flash, and a CPC running from it goes down)')
    rows = rom.slots()
    ask = None if (a.yes or a.dry_run) else yes_no
    rplan, what = plan_roms(rows, images, known, lsai, replace, ask)
    rom.close()

    dplan, lst, nolib = [], None, False
    if not a.no_discs:
        p = dskloader.open_card(port)
        lst = dskloader.listing(p)
        if not lst['summary']:
            p.reset_input_buffer()
            p.write(b'LL'); p.flush()
            nolib = 'library disabled' in dskloader.collect(p, 3.0, b'\n')
            if not nolib:
                p.close()
                die("no answer to the flash disc listing -- is the card's "
                    'firmware older than its flash disc library?')
        p.close()
        if not nolib:
            dplan = plan_discs(lst, discdir, v)
            home, changed = lst['drive'], lst['changed']
            if changed and home == 0 and a.drive != 'none':
                die("the card's drive holds a disc uploaded from a PC, and the "
                    'CPC wrote to it: copy it off first (the ROM loader\'s Flash '
                    'discs tab), or give --drive none')
            for d in list(dplan):
                if d[3] == home and changed and d[4] != 'keep':
                    if not (ask and ask(
                            f'The CPC wrote to the disc in the drive (flash disc '
                            f'{home}), not saved yet. Replacing that disc loses '
                            'what it wrote. Replace it anyway?')):
                        print(f'  flash disc {home}: kept, with what the CPC wrote')
                        dplan.remove(d)

    print('\nROM slots:')
    for r in rows:
        s = r['slot']
        num = 'silent' if r['rom'] is None else f"ROM {r['rom']}"
        todo = next((x for x in rplan if x[0] == s), None)
        if not todo:
            print(f'  slot {s}: {num:7s} {what[s]} -- kept')
            continue
        _, act, name, n = todo
        print(f'  slot {s}: {num:7s} {what[s]} -> ' + {
            'keep': f'{name} as ROM {n}: there already',
            'number': f'{name} there already, now as ROM {n}',
            'upload': f'{name} as ROM {n}',
            'silence': 'silent (an older CPC Lisp ROM)'}[act])
    drive = None
    if nolib:
        print("\nFlash discs: none -- this card has its 664/6128 firmware, which "
              'has no flash discs (load discs from the PC: lambdaspeak4\'s '
              'romloader, or use your own drive).')
    elif not a.no_discs:
        print('\nFlash discs:')
        for kind, path, label, slot, act in dplan:
            old = next((d['label'] for d in lst['slots'] if d['slot'] == slot), '')
            print(f'  {slot:2d}: {label} -- ' + {
                'keep': 'there already', 'replace': f'over "{old}"',
                'store': 'in a free slot'}[act])
        drive = next((d[3] for d in dplan if d[0] == a.drive), None)
        if drive:
            print(f'  the drive: flash disc {drive}')
    stores = [d for d in dplan if d[4] != 'keep']
    reload_drive = bool(drive) and (lst['drive'] != drive
                                    or any(d[3] == drive for d in stores))
    if a.dry_run:
        print('\n(--dry-run: nothing written)')
        return
    if not [x for x in rplan if x[1] != 'keep'] and not stores and not reload_drive:
        print('\nNothing to do: the card has all of it.')
        return
    core = next(x[0] for x in rplan if x[2] == 'LISP.ROM')
    print(f'\nIf the CPC then starts in neither Lisp nor BASIC: switch it off '
          f'and run\n  python3 tools/install-card.py --basic\n(the core in slot '
          f'{core} goes silent and BASIC is back; (basic) in Lisp does the same).')
    if not a.yes and not yes_no('\nGo ahead?'):
        die('nothing written')

    # the ROMs, through the ROM loader's own upload
    for s, act, name, n in rplan:
        if act == 'keep':
            continue
        if not rom.off():
            die('the CPC is on -- stopping (switch it off and run this again)')
        if act == 'upload':
            print(f'{name} -> slot {s}, ROM {n}')
            if not rom.upload(s, n, images[name][1]):
                die(f'slot {s}: not stored -- stopping')
        else:
            print(f'slot {s} -> ' + ('silent' if n == 255 else f'ROM {n}'))
            print('  ' + rom.number(s, n).replace('\n', '\n  '))
    by = {r['slot']: r for r in rom.slots()}
    rom.close()
    bad = [f'{s} ({name})' for s, act, name, n in rplan if name and
           (by[s]['sum'] != images[name][0] or by[s]['rom'] != n)]
    if bad:
        die('these slots did not read back right: ' + ', '.join(bad))
    print('ROMs: every checksum and number read back right.')

    if nolib or a.no_discs:
        return done(v, rplan)
    p = dskloader.open_card(port)
    home = cur = lst['drive']

    def load(n):
        reply = dskloader.command(p, b'LG', n)
        if '-> ok' not in reply:
            die(f'the drive: the card said {reply!r}')
        code = dskloader.wait_job(p)
        if code != 0:
            die('the drive: ' + dskloader.REASONS.get(code, f'status {code}'))

    for kind, path, label, slot, act in stores:
        if not kitloader.cpc_is_off(p):
            die('the CPC is on -- stopping (switch it off and run this again)')
        print(f'{os.path.basename(path)} -> flash disc {slot}')
        out = dskloader.upload_slot(p, slot, open(path, 'rb').read(), label)
        if '-> ok' not in out:
            die(f'flash disc {slot}: the card said {out.strip()!r}')
        code = dskloader.wait_job(p)
        if code != 0:
            die(f'flash disc {slot}: ' + dskloader.REASONS.get(code, f'status {code}'))
        if slot == home:
            # the drive still holds the old copy, homed here: load the new one
            # at once, before anything could write the old one back over it
            print(f'  and into the drive again (it held flash disc {slot})')
            load(slot)
            cur = slot
    if drive and cur != drive:
        print(f'flash disc {drive} -> the drive')
        load(drive)
    lst = dskloader.listing(p)
    p.close()
    got = {d['slot']: d for d in lst['slots']}
    for kind, path, label, slot, act in dplan:
        img = open(path, 'rb').read()
        d = got.get(slot)
        if not d or d['len'] != len(img) or d['sum'] != sum(img) & 0xFFFFFFFF:
            die(f'flash disc {slot} did not read back right')
    if drive and lst['drive'] != drive:
        die(f"the drive holds flash disc {lst['drive']}, not {drive}")
    print('Flash discs: every length and checksum read back right'
          + (f'; the drive holds flash disc {drive}.' if drive else '.'))
    done(v, rplan, drive and a.drive == 'classics')


def done(v, rplan, classics=False):
    nums = sorted(n for _, _, name, n in rplan if name)
    print(f'\nDone. Switch the CPC on: it starts in CPC Lisp {v}.'
          + ('\nThe classics are in drive A: (load "classics").' if classics else '')
          + f'\nCPC Lisp answers ROM numbers {", ".join(map(str, nums))}: '
          'keep any other ROM board off them.')


if __name__ == '__main__':
    main()
