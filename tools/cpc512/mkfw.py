#!/usr/bin/env python3
"""The 512K CPC's firmware names: mach/cpc/firmware.asm made into

    mach/cpc512/firmware.asm  -- each routine's name is a trampoline in the
                                 resident part (FWJB + 5k), which maps the
                                 screen's RAM in at &C000 (configuration C0)
                                 for the call and the Lisp's bank back after
    mach/cpc512/fwreal.asm    -- the real addresses, for the resident part
    mach/cpc512/fwtab.inc     -- the resident table: "call fwc : dw address"

The maths package (M_...) is called directly: it touches no screen, and the
464 and 6128 addresses are worked out at run time (fp.asm). So are the data
address FIRM_464_PROBE and the ROM routines the resident part does itself.
"""
import os, re
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..', '..')
src = open(os.path.join(root, 'mach', 'cpc', 'firmware.asm')).read().splitlines()
DIRECT = re.compile(r'^(M_|FIRM_464_PROBE$|KL_ROM_WALK$|KL_L_ROM_ENABLE$|KL_ROM_RESTORE$|KL_ROM_SELECT$|KL_CURR_SELECTION$)')
out, real, tab, k = [], [], [], 0
head = (";; CPC Lisp -- the 512K CPC's firmware names (made by tools/cpc512/mkfw.py\n"
        ";; from mach/cpc/firmware.asm: do not edit). A routine's name is its\n"
        ";; trampoline in the resident part, which calls it with the screen's RAM\n"
        ";; at &C000; the maths package and the ROM routines are called directly.\n\n"
        "    include \"jumps.asm\"\n\n")
for line in src:
    m = re.match(r'^([A-Z_0-9]+)(\s+)equ\s+(#[0-9A-Fa-f]+)(.*)$', line)
    real.append(line)
    if not m:
        out.append(line); continue
    name, sp, addr, rest = m.groups()
    if DIRECT.match(name):
        out.append(line); continue
    out.append('%s%sequ FWJB+5*%d%s' % (name, sp, k, rest))
    tab.append('    assert $ == FWJB+5*%d\n    call fwc : dw %s           ; %s' % (k, addr, name))
    k += 1
open(os.path.join(root, 'mach', 'cpc512', 'firmware.asm'), 'w').write(head + '\n'.join(out) + '\n')
open(os.path.join(root, 'mach', 'cpc512', 'fwreal.asm'), 'w').write(
    ";; The CPC's firmware addresses as they are, for the 512K CPC's resident\n"
    ";; part (made by tools/cpc512/mkfw.py: do not edit)\n\n" + '\n'.join(real) + '\n')
open(os.path.join(root, 'mach', 'cpc512', 'fwtab.inc'), 'w').write(
    ";; the trampolines (made by tools/cpc512/mkfw.py: do not edit)\n" + '\n'.join(tab) + '\nNFW equ %d\n' % k)
print('mkfw: %d trampolines' % k)
