#!/usr/bin/env python3
"""An AY log with times -> each channel's state when it changes:

    LISP_AYLOG=ay.log LISP_AYTIME=1 tools/run.sh sounds.lsp
    tools/aytimes.py ay.log

prints "t  A:period/volume B:... C:..." ('-' a silent channel, 'n' noise
on) for each burst of sound, its times in 1/100 s from the burst's start.
Two runs of one file -- the ROM version (the firmware's own sound manager)
and a port's -- compare with diff, to within 1/100 s (the stamps jitter by
one: the CPC's 300 Hz interrupts are 300.48 Hz)."""
import sys
regs = [0]*16
regs[7] = 0x3F
def state():
    out = []
    for c in range(3):
        vol = regs[8+c] & 15
        tone = not (regs[7] >> c) & 1
        noise = not (regs[7] >> (c+3)) & 1
        if vol == 0 or not (tone or noise):
            out.append('-')
        else:
            p = regs[2*c] | (regs[2*c+1] & 15) << 8
            out.append('%d/%d%s' % (p if tone else 0, vol, 'n' if noise else ''))
    return out
events = {}
order = []
for w in open(sys.argv[1]).read().split():
    t, rv = w.split(':')
    r, v = rv.split('=')
    t = int(t); regs[int(r, 16)] = int(v, 16)
    events[t] = state()
    if not order or order[-1] != t:
        order.append(t)
last = None; start = None; burst = 0
for t in order:
    s = events[t]
    if s == last:
        continue
    silent = all(x == '-' for x in s)
    if start is None and not silent:
        start = t; burst += 1; print('-- burst', burst)
    if start is not None:
        print('%4d  A:%-8s B:%-8s C:%-8s' % (t - start, *s))
    if silent:
        start = None
    last = s
