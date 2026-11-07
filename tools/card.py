#!/usr/bin/env python3
"""Put the Lisp ROMs on the LambdaSpeak 4 card, from the command line.

    tools/card.py [-p PORT] slots                    the card's slot report
    tools/card.py [-p PORT] upload SLOT NUM FILE ... store images (CPC off!)
    tools/card.py [-p PORT] lisp                     the usual set, below
    tools/card.py [-p PORT] number SLOT NUM          renumber a slot
    tools/card.py [-p PORT] basic                    BASIC back (core slot 255)

This is not an uploader of its own: it drives the GUI's Card class
(~/git/lambdaspeak4/tools/romloader.py) -- its wait_idle() and send_rom(),
the ones that are known to keep the card's console in step -- and refuses
to write flash unless kitloader.cpc_is_off() says the CPC is off.

`lisp` stores build/LISP.ROM in slot 4 as ROM 0 (the CPC then boots into
Lisp), LISPLIB.ROM in slot 5 as ROM 4 and LISPLIB2.ROM in slot 7 as ROM 5:
slots 4, 5 and 7 held old silent images on 2026-11-07 (check `slots`
first). `basic` silences slot 4 again.
"""
import os, sys, time

LS4 = os.path.expanduser('~/git/lambdaspeak4/tools')
sys.path.insert(0, LS4)
import romloader, kitloader            # noqa: E402

LISP_SET = [(4, 0, 'build/LISP.ROM'), (5, 4, 'build/LISPLIB.ROM'),
            (7, 5, 'build/LISPLIB2.ROM')]
CORE_SLOT = 4


def drain(card, until, timeout=60):
    """Print what the card's methods said; return the payload of `until`."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            kind, payload = card.out.get(timeout=0.5)
        except Exception:
            continue
        if kind == 'progress':
            print(f'\r  {int(payload * 100):3d}%', end='', flush=True)
            continue
        if kind == 'error':
            sys.exit(f'card: {payload}')
        if kind == until:
            return payload
        print(f'{kind}: {payload}')
    sys.exit(f'card: no {until!r} from the card')


def slots(card, port):
    card.read_slots(port)
    rows, asked, text = drain(card, 'slots')
    for r in rows:
        num = 'silent' if r['rom'] is None else f"ROM {r['rom']}"
        print(f"slot {r['slot']}: {num:7s} header {r['header']}")
    return rows


def upload(card, port, jobs):
    images = []
    for slot, num, path in jobs:
        data = open(path, 'rb').read()
        if len(data) != 16384:
            sys.exit(f'card: {path} is {len(data)} bytes, not 16384')
        if not 0 <= slot <= 7 or not (0 <= num <= 15 or num == 255):
            sys.exit(f'card: slot {slot} / ROM {num}?')
        images.append((slot, num, path, data))
    s = card._open(port)
    if not kitloader.cpc_is_off(s):
        sys.exit('card: the CPC is on -- switch it off first (flash writes '
                 'stall the card, and a CPC running from it goes down)')
    for slot, num, path, data in images:
        print(f'{path} -> slot {slot}, ROM {num}')
        card.send_rom(port, slot, num, data)
        text = drain(card, 'done')
        print('\r' + text.strip())
        if 'stored' not in text:
            sys.exit('card: not stored -- stopping')
    slots(card, port)


def main():
    args = sys.argv[1:]
    port = None
    if args[:1] == ['-p']:
        port, args = args[1], args[2:]
    if not args:
        sys.exit(__doc__)
    port = port or romloader.ports()[0]
    if not os.path.exists(port) and os.name != 'nt':
        sys.exit(f'card: no {port} -- is the card plugged in over USB?')
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    card = romloader.Card()
    cmd = args[0]
    if cmd == 'slots':
        slots(card, port)
    elif cmd == 'upload' and len(args) >= 4 and len(args) % 3 == 1:
        upload(card, port, [(int(args[k]), int(args[k + 1]), args[k + 2])
                            for k in range(1, len(args), 3)])
    elif cmd == 'lisp':
        upload(card, port, LISP_SET)
    elif cmd in ('number', 'basic'):
        slot, num = (CORE_SLOT, 255) if cmd == 'basic' else map(int, args[1:3])
        card.set_number(port, slot, num)
        print(drain(card, 'note'))
        slots(card, port)
    else:
        sys.exit(__doc__)


main()
