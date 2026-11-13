#!/bin/bash
# Type a file at CPC Lisp on an emulated TRS-80 Model 4 with 128 KB
# (trs80gp, headless), and print the transcript.
#
#     tools/trs80m4/run.sh file.lsp
#
# MACH=trs80m4 tools/build.sh first. LS-DOS 6.3.1 boots from
# build/trs80m4/lisp-m4.dsk, is given a date and time, runs LISP; the
# file's lines are typed as the Lisp asks for them ('!' lines, the CPC
# harness's key actions, are left out) and (quit) ends it. With
# trs80gp's -ee the machine page copies all the Lisp prints to the
# printer, and typed lines as they are entered: that file is the
# transcript. If it stops taking input, the screen as it was is shown.
set -e
cd "$(dirname "$0")/../.."
GP=${TRS80GP:-$HOME/claude/midi80/gp.sh}
B=${TRS80M4_BUILD:-$PWD/build/trs80m4}
src=$(realpath "$1")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{ grep -v '^!' "$src" || true; echo "(quit)"; } > "$tmp/input.txt"
( cd "$tmp" && timeout "${TIMEOUT:-900}" "$GP" -m4 -mem 128 -ee -batch -turbo \
    -d0 "$B/lisp-m4.dsk" \
    -iw "Date" -i '11/13/86\r' -iw "Time" -i '12:00:00\r' -iw "Ready" -i 'LISP\r' \
    -iw "LISP>" -itime "${ITIME:-30000}" -if input.txt -it -ix > /dev/null 2>&1 ) \
    || echo "run.sh: trs80gp did not finish" >&2
if [ -f "$tmp/trs80-text-0.bin" ] && ! grep -q "(quit)" "$tmp/trs80-printer.txt" 2>/dev/null; then
    echo "run.sh: it stopped taking input; the screen:" >&2
    python3 -c '
import sys
d = open(sys.argv[1], "rb").read()
for r in range(24):
    print("|" + "".join(chr(c) if 32 <= c < 127 else "#" for c in d[r*80:r*80+80]) + "|")' "$tmp/trs80-text-0.bin" >&2
fi
python3 -c '
import sys
d = open(sys.argv[1], "rb").read().decode("latin-1")
d = d.replace("\r\n\n", "\n").replace("\r\n", "\n").replace("\r", "\n")
sys.stdout.write(d)' "$tmp/trs80-printer.txt" 2>/dev/null || true
