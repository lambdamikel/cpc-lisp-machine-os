#!/usr/bin/env python3
"""The times in a log of tools/bench/cpm.lua.

    tools/bench/cpmtime.py LOG [FORM...]

For each line typed (or only those starting with one of the FORMs): the
frames from the RETURN that ended it -- its echo, the first CR printed
after it was typed -- to the first character of what came after, the
result; and that result's line. MAME's CPC runs 50 frames a second.
"""
import sys

ev = []                     # ('IN', frame, line) or ('C', frame, char)
for l in open(sys.argv[1]):
    p = l.rstrip('\n').split('\t')
    if p[0] == 'IN':
        ev.append(('IN', int(p[1]), p[2]))
    elif p[0].isdigit():
        ev.append(('C', int(p[0]), chr(int(p[1], 16))))
forms = sys.argv[2:]
for i, e in enumerate(ev):
    if e[0] != 'IN' or (forms and not any(e[2].startswith(f) for f in forms)):
        continue
    # the line's last CR echoed: the CRs printed before the next IN, the
    # first one after which something other than CR/LF is printed
    j, t0 = i + 1, None
    while j < len(ev) and ev[j][0] != 'IN':
        if ev[j][2] == '\r':
            t0 = ev[j][1]
            k = j + 1
            while k < len(ev) and ev[k][0] == 'C' and ev[k][2] in '\r\n':
                k += 1
            if k < len(ev) and ev[k][0] == 'C':
                res, m = '', k
                while m < len(ev) and ev[m][0] == 'C' and ev[m][2] != '\r':
                    res += ev[m][2]; m += 1
                last = e[2].replace('\r', ' ').split('\n')[-1]
                if not res.strip().startswith('$') or True:
                    print('%-28s %6d frames  %7.2f s  -> %s' % (
                        last[-28:], ev[k][1] - t0, (ev[k][1] - t0) / 50, res.strip()[:40]))
                break
        j += 1
