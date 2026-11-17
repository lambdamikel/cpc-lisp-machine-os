#!/usr/bin/env python3
"""Time one form on an emulated TRS-80 Model I (trs80gp, headless).

    tools/bench/bench80.py uo|cpc SETUP "FORM" RESULT [MAXFRAMES]

docs/benchmarks.md has the runs. STEP=n (default 25) sets the dumps'
spacing; SHOW=k,k... prints those dumps' screens.

Boots the Lisp (uo: TRSDOS 2.3 and UOLISP's LISP48; cpc: LDOS and CPC
Lisp on X-MEM/80), types SETUP.txt, then FORM, and dumps the screen every
STEP frames; the first dump whose screen shows RESULT on a line of its
own, after FORM's line, gives the time: printed as frames (an upper
bound, STEP frames' resolution; trs80gp's Model I runs about 60 a
second).

UOLISP_DIR (default ~/claude/trs80/uolisp) holds TRSDOS23.dmk and
UOLISP.dmk -- the Computer History Museum's Software Preservation
Group's images (softwarepreservation.computerhistory.org/LISP/utah/
uolisp/), not in this repository; TRS80_BUILD (default build/trs80) CPC
Lisp's lisp-a.dsk (MACH=trs80 tools/build.sh).
"""
import os, subprocess, sys, tempfile, glob

GP = os.path.expanduser('~/claude/midi80/gp.sh')
UO = os.path.expanduser(os.environ.get('UOLISP_DIR', '~/claude/trs80/uolisp'))
CPC = os.path.abspath(os.environ.get('TRS80_BUILD', os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'trs80')))
STEP = int(os.environ.get('STEP', '25'))


def screen(path):
    d = open(path, 'rb').read()
    return [''.join(chr(c + 64) if c < 32 else chr(c) if c < 127 else '#'
                    for c in d[r * 64:r * 64 + 64]).rstrip() for r in range(16)]


def main():
    kind, setup, form, result = sys.argv[1:5]
    maxf = int(sys.argv[5]) if len(sys.argv) > 5 else 6000
    tmp = tempfile.mkdtemp()
    open(os.path.join(tmp, 'setup.txt'), 'w').write(open(setup).read())
    # (UOLISP takes its file names padded: FLOAD "COMP " -- see the setups)
    if kind == 'uo':
        for f in ('TRSDOS23.dmk', 'UOLISP.dmk'):
            subprocess.run(['cp', os.path.join(UO, f), tmp])
        boot = ['-m1', '-d0', 'TRSDOS23.dmk', '-d1', 'UOLISP.dmk',
                '-id', '300', '-i', 'LISP48\\r', '-id', '200']
    else:
        subprocess.run(['cp', os.path.join(CPC, 'lisp-a.dsk'), tmp])
        boot = ['-m1', '-mem', 'xmem80', '-d0', 'lisp-a.dsk',
                '-iw', 'Date ?', '-i', '11/11/86\\r', '-iw', 'Time ?',
                '-i', '12:00:00\\r', '-iw', 'Ready', '-i', 'LISP\\r',
                '-iw', 'LISP>']
    dumps = []
    for _ in range(maxf // STEP):
        dumps += ['-id', str(STEP), '-it']
    cmd = [GP, '-batch', '-turbo', '-itime', '0'] + boot + \
          ['-if', 'setup.txt', '-i', form + '\\r'] + dumps + ['-ix']
    subprocess.run(cmd, cwd=tmp, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=3000)
    files = sorted(glob.glob(os.path.join(tmp, 'trs80-text-*.bin')),
                   key=lambda p: int(p.rsplit('-', 1)[1].split('.')[0]))
    key = form.upper() if kind == 'uo' else form
    for k, f in enumerate(files):
        s = screen(f)
        rows = [i for i, l in enumerate(s) if l.endswith(key) or key in l]
        if rows and any(l.strip() == result for l in s[rows[-1] + 1:]):
            print('%s %s: %d frames (dump %d of %d)' % (kind, form, (k + 1) * STEP, k, len(files)))
            if os.environ.get('SHOW'):
                for j in map(int, os.environ['SHOW'].split(',')):
                    print('-- dump %d' % j); print('\n'.join(screen(files[j])))
            return
    if os.environ.get('SHOW'):
        for k in map(int, os.environ['SHOW'].split(',')):
            if k < len(files):
                print('-- dump %d' % k); print('\n'.join(screen(files[k])))
    print('%s %s: no %s in %d dumps; last screen:' % (kind, form, result, len(files)))
    if files:
        print('\n'.join(screen(files[-1])))


main()
