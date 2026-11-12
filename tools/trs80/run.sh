#!/bin/bash
# Type a file at CPC Lisp on an emulated TRS-80 Model I with X-MEM/80
# (trs80gp), and print the transcript.
#
#     tools/trs80/run.sh file.lsp
#
# MACH=trs80 tools/build.sh first. LDOS boots from build/trs80/lisp-a.dsk
# (lisp-b.dsk in drive 1), is given a date and time, runs LISP; the file's
# lines are typed as the Lisp asks for them ('!' lines, the CPC harness's
# key actions, are left out) and (quit) ends it. With trs80gp's -ee the
# machine page copies all the Lisp prints to the printer, and typed lines
# as they are entered: that file is the transcript.
set -e
cd "$(dirname "$0")/../.."
GP=${TRS80GP:-$HOME/claude/midi80/gp.sh}
B=$PWD/build/trs80
src=$(realpath "$1")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{ grep -v '^!' "$src" || true; echo "(quit)"; } > "$tmp/input.txt"
( cd "$tmp" && timeout "${TIMEOUT:-900}" "$GP" -m1 -mem xmem80 -ee -batch -turbo \
    -d0 "$B/lisp-a.dsk" -d1 "$B/lisp-b.dsk" \
    -iw "Date ?" -i '11/11/86\r' -iw "Time ?" -i '12:00:00\r' -iw "Ready" -i 'LISP\r' \
    -iw "LISP>" -if input.txt > /dev/null 2>&1 ) || echo "run.sh: trs80gp did not finish" >&2
# the printer has CR as a new line, then the LF: one new line each
python3 -c '
import sys
d = open(sys.argv[1], "rb").read().decode("latin-1")
d = d.replace("\r\n\n", "\n").replace("\r\n", "\n").replace("\r", "\n")
sys.stdout.write(d)' "$tmp/trs80-printer.txt" 2>/dev/null || true
