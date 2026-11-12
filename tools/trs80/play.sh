#!/bin/bash
# CPC Lisp on an emulated TRS-80 Model I with X-MEM/80, in a trs80gp window
# to play in: LDOS boots from build/trs80/lisp-a.dsk (lisp-b.dsk in drive
# 1), is told the date and time, and runs LISP.
#
#     MACH=trs80 tools/build.sh      (first)
#     tools/trs80/play.sh
#
# (quit) goes back to LDOS. TRS80GP names the emulator.
cd "$(dirname "$0")/../.."
GP=${TRS80GP:-$HOME/claude/midi80/toolchain/trs80gp/linux-64/trs80gp}
B=$PWD/build/trs80
exec env GDK_BACKEND=x11 "$GP" -m1 -mem xmem80 -dt \
    -d0 "$B/lisp-a.dsk" -d1 "$B/lisp-b.dsk" \
    -iw "Date ?" -i "$(date +%m/%d)/86\r" -iw "Time ?" -i "$(date +%H:%M:%S)\r" \
    -iw "Ready" -i 'LISP\r' "$@"
