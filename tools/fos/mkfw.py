#!/usr/bin/env python3
"""CPC Lisp on FutureOS itself (mach/fos): the CPC firmware's names, made
from mach/cpc/firmware.asm into

    mach/fos/firmware.asm  -- each routine's name is a trampoline in the
                              resident part (FWJB + 5k)
    mach/fos/fwtab.inc     -- the resident part's trampolines: "call fwp :
                              dw &C000+3k", into the machine page, or a jump
                              to a routine of the resident part's own (OWN)
    mach/fos/nfw.asm       -- NFW, how many: LISP.64K calls &C000 + 3 * NFW
    mach/fos/pagetab.inc   -- the machine page's jump table, at &C000: "jp
                              p_NAME", one for each name, in that order

There is no firmware under FutureOS: the machine page (page.asm, its own
16 KB image) has a routine of the same contract for each name. The maths
package (M_...) is the lower ROM's, called by fp.asm at its real
addresses; FIRM_464_PROBE and KL_ROM_WALK are not used here.
"""
import os, re
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..', '..')
src = open(os.path.join(root, 'mach', 'cpc', 'firmware.asm')).read().splitlines()
SKIP = re.compile(r'^(M_|FIRM_464_PROBE$|KL_ROM_WALK$)')
# the resident part's own: what needs no page, or must not change the
# configuration (the lower ROM's switch: the function editor's renderer
# reads the font with the screen's RAM at &C000)
OWN = {'KL_L_ROM_ENABLE': 'r_lromon', 'KL_ROM_RESTORE': 'r_romrest',
       'KL_ROM_SELECT': 'r_romsel', 'KL_CURR_SELECTION': 'r_romcur',
       'KL_TIME_PLEASE': 'r_time', 'MC_WAIT_FLYBACK': 'r_flyback',
       'KM_TEST_KEY': 'r_testkey'}
out, tab, page, k = [], [], [], 0
head = (";; CPC Lisp on FutureOS -- the CPC firmware's names (made by\n"
        ";; tools/fos/mkfw.py from mach/cpc/firmware.asm: do not edit). A\n"
        ";; routine's name is its trampoline in the resident part, which calls\n"
        ";; the machine page's routine of that contract (page.asm).\n\n"
        "    include \"jumps.asm\"\n\n")
for line in src:
    m = re.match(r'^([A-Z_0-9]+)(\s+)equ\s+(#[0-9A-Fa-f]+)(.*)$', line)
    if not m:
        out.append(line); continue
    name, sp, addr, rest = m.groups()
    if SKIP.match(name):
        out.append(line); continue
    if any(t.endswith('; ' + name) for t in tab):   # (CAS_IN_OPEN twice)
        continue
    out.append('%s%sequ FWJB+5*%d%s' % (name, sp, k, rest))
    if name in OWN:
        tab.append('    assert $ == FWJB+5*%d\n    jp %s : db 0,0             ; %s' % (k, OWN[name], name))
        page.append('    jp p_none                   ; %s (the resident part\'s)' % name)
    else:
        tab.append('    assert $ == FWJB+5*%d\n    call fwp : dw #C000+3*%d     ; %s' % (k, k, name))
        page.append('    jp p_%s' % name)
    k += 1
open(os.path.join(root, 'mach', 'fos', 'firmware.asm'), 'w').write(head + '\n'.join(out) + '\n')
open(os.path.join(root, 'mach', 'fos', 'fwtab.inc'), 'w').write(
    ";; the trampolines (made by tools/fos/mkfw.py: do not edit)\n" + '\n'.join(tab) + '\n')
open(os.path.join(root, 'mach', 'fos', 'nfw.asm'), 'w').write(
    ";; how many names (made by tools/fos/mkfw.py: do not edit): the page's\n"
    ";; p_init follows their jump table, at &C000 + 3 * NFW\nNFW equ %d\n" % k)
open(os.path.join(root, 'mach', 'fos', 'pagetab.inc'), 'w').write(
    ";; the machine page's jump table (made by tools/fos/mkfw.py: do not edit)\n" + '\n'.join(page) + '\n')
print('mkfw: %d names' % k)
