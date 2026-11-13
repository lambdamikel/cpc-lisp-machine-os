#!/bin/bash
# Type a file at CPC Lisp on an emulated TRS-80 Model 4 with 128 KB
# (trs80gp, headless), and print the transcript.
#
#     tools/trs80m4/run.sh file.lsp
#
# MACH=trs80m4 tools/build.sh first. LS-DOS 6.3.1 boots from
# build/trs80m4/lisp-m4.dsk, is given a date and time, runs LISP; the
# file's lines are typed as the Lisp asks for them and (quit) ends it.
# The CPC harness's key actions, '!' lines while the line before runs,
# are trs80gp's input commands: "!esc N" waits N frames and holds BREAK
# for 8, "!type N text" waits and types it ({ENTER} is ENTER); "!press"
# and "!shot" are left out. With trs80gp's -ee the machine page copies
# all the Lisp prints to the printer, and typed lines as they are
# entered: that file is the transcript. If it stops taking input, the
# screen as it was is shown.
set -e
cd "$(dirname "$0")/../.."
GP=${TRS80GP:-$HOME/claude/midi80/gp.sh}
B=${TRS80M4_BUILD:-$PWD/build/trs80m4}
src=$(realpath "$1")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# the lines as input files, the actions between them as commands
mapfile -d '' INPUT < <(python3 - "$src" "$tmp" <<'PY'
import re, sys
src, tmp = sys.argv[1], sys.argv[2]
args, seg, n = [], [], 0
def flush():
    global seg, n
    if seg:
        n += 1
        f = '%s/in%d.txt' % (tmp, n)
        open(f, 'w').write(''.join(seg))
        args.extend(['-if', f])
        seg = []
for line in open(src).read().splitlines() + ['(quit)']:
    m = re.match(r'!esc (\d+)', line) or re.match(r'!press 66 (\d+)', line)
    t = re.match(r'!type (\d+) (.*)', line)
    if m:
        flush()
        args += ['-id', m.group(1), '-ik', '6', '4', '-id', '8', '-ik', '6', '0']
    elif t:
        flush()
        args += ['-id', t.group(1), '-i', t.group(2).replace('{ENTER}', '\r')]
    elif not line.startswith('!'):
        seg.append(line + '\n')
flush()
sys.stdout.write('\0'.join(args) + '\0')
PY
)
( cd "$tmp" && timeout "${TIMEOUT:-900}" "$GP" ${M4MODEL:--m4} -mem 128 -ee -batch -turbo \
    -d0 "$B/lisp-m4.dsk" \
    -iw "Date" -i '11/13/86\r' -iw "Time" -i '12:00:00\r' -iw "Ready" -i 'LISP\r' \
    -iw "LISP>" -itime "${ITIME:-30000}" "${INPUT[@]}" -it -ix > /dev/null 2>&1 ) \
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
