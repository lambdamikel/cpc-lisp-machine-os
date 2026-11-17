#!/usr/bin/env python3
"""The times in a log of tools/bench/cpm.lua.

    tools/bench/cpmtime.py [--typed] [--skip TEXT] LOG [FORM...]

For each line typed (or only those starting with one of the FORMs): the
frames from the RETURN that ended it to the first character of its
result, and that result's line. The RETURN is the first CR the program
echoes after the line was typed, or with --typed the frame the harness
let its last key go (a program whose echo is not logged: LinguaSoft
Lisp). --skip TEXT: what the program prints before it evaluates (LISP/80's
">", LinguaSoft's "Value is..."): the time is that of the first character
after it. MAME's CPC runs 50 frames a second.
"""
import sys

args = sys.argv[1:]
typed, skip = False, ''
while args and args[0].startswith('--'):
    if args[0] == '--typed':
        typed, args = True, args[1:]
    elif args[0] == '--skip':
        skip, args = args[1], args[2:]
ev = []                     # ('IN', frame, line), ('T', frame), ('C', frame, char)
for l in open(args[0], newline='\n'):
    p = l.rstrip('\n').split('\t')
    if p[0] == 'IN':
        ev.append(('IN', int(p[1]), p[2]))
    elif p[0] == 'TYPED':
        ev.append(('T', int(p[1])))
    elif p[0].isdigit():
        ev.append(('C', int(p[0]), chr(int(p[1], 16))))
forms = args[1:]


def result(k):
    """The text of the line printed from ev[k] on."""
    res, m = '', k
    while m < len(ev) and ev[m][0] != 'IN' and (ev[m][0] != 'C' or ev[m][2] != '\r'):
        if ev[m][0] == 'C' and ev[m][2] != '\n':
            res += ev[m][2]
        m += 1
    return res.strip(), m


for i, e in enumerate(ev):
    if e[0] != 'IN' or (forms and not any(e[2].startswith(f) for f in forms)):
        continue
    j, t0 = i + 1, None
    while j < len(ev) and ev[j][0] != 'IN' and t0 is None:
        if typed and ev[j][0] == 'T':
            t0 = ev[j][1]
        elif not typed and ev[j][0] == 'C' and ev[j][2] == '\r':
            # the echoed RETURN: a CR after which something is printed
            n = j + 1
            while n < len(ev) and ev[n][0] != 'IN' and (ev[n][0] != 'C' or ev[n][2] in '\r\n'):
                n += 1
            if n < len(ev) and ev[n][0] == 'C':
                t0 = ev[j][1]
        j += 1
    if t0 is None:
        continue
    # the characters printed after t0 up to the next line typed, CR/LF out;
    # the first one after the skipped text gives the time
    cs = []
    while j < len(ev) and ev[j][0] != 'IN':
        if ev[j][0] == 'C' and ev[j][2] not in '\r\n':
            cs.append(ev[j])
        j += 1
    text = ''.join(c[2] for c in cs)
    k = len(skip) if skip and text.startswith(skip) else 0
    if k >= len(cs):
        continue
    res = text[k:]
    last = e[2][-28:]
    print('%-28s %6d frames  %7.2f s  -> %s' % (last, cs[k][1] - t0, (cs[k][1] - t0) / 50, res[:40]))
