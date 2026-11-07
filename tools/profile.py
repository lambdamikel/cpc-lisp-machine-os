#!/usr/bin/env python3
"""Summarise a profile from tools/run.sh -p.

    tools/profile.py profile.txt [N] [-l]

Instructions executed, by routine (the nearest label before each address,
in the symbol file of the ROM it was in), most first; N lines (30). -l
counts local labels (.loop etc.) as routines of their own.
"""
import sys, collections

def symbols(path, local):
    syms = []
    for line in open(path):
        f = line.split()
        if len(f) >= 4 and f[3] == 'L' and (local or '.' not in f[0]):
            syms.append((int(f[1].lstrip('#'), 16), f[0]))
    syms.sort()
    return syms

def name(syms, addr):
    lo, hi = 0, len(syms)
    while lo < hi:
        mid = (lo + hi) // 2
        if syms[mid][0] <= addr:
            lo = mid + 1
        else:
            hi = mid
    return syms[lo - 1][1] if lo else '?'

args = [a for a in sys.argv[1:] if not a.startswith('-')]
local = '-l' in sys.argv
top = int(args[1]) if len(args) > 1 else 30
tabs = {'core': symbols('build/lisp.sym', local), 'lib1': symbols('build/lisplib.sym', local),
        'lib2': symbols('build/lisplib2.sym', local)}
count = collections.Counter()
total = 0
for line in open(args[0]):
    addr, rom, n = line.split()
    addr, n = int(addr, 16), int(n)
    total += n
    if rom in tabs:
        count[f'{rom}:{name(tabs[rom], addr)}'] += n
    elif rom == 'ram' and 0xB080 <= addr < 0xB100:
        count['trampoline'] += n
    else:
        count[rom] += n
print(f'{total} instructions')
for k, n in count.most_common(top):
    print(f'{100 * n / total:6.2f}%  {n:9d}  {k}')
