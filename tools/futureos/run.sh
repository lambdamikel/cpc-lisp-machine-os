#!/bin/bash
# Type a file at CPC Lisp under FutureOS in MAME, and print the transcript:
#
#     tools/futureos/run.sh [-f frames] [-s shot.png] file.lsp
#
# MACH=futureos tools/build.sh first. A 464 with 576K (a 512K expansion),
# a DDI-1 with build/futureos/cpclispfos.dsk in drive A, and behind it
# MAME's ROM box with FutureOS's four ROMs renumbered 1-4 (FOS_ROMS, by
# default ~/claude/cpc/futureos/mame-1234: tools/futureos/fosroms.py SRC
# OUT 1 2 3 4 -- they are TFM's, never in this repository). emu/repl.lua
# types |OS at BASIC's EDIT; on the desktop LISP.64K is put at &8000 and
# started from the RUN menu (X, 3: a RAM application at &9000, block
# &C0); then the file's lines are typed when Lisp asks for them.
set -e
cd "$(dirname "$0")/../.."
FRAMES=30000 SHOT=
while getopts "f:s:" o; do
    case $o in
        f) FRAMES=$OPTARG ;;
        s) SHOT=$(realpath -m "$OPTARG") ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
IN=${1:-/dev/null}
B=${FUTUREOS_BUILD:-build/futureos}
R=${FOS_ROMS:-$HOME/claude/cpc/futureos/mame-1234}
[ -f "$B/cpclispfos.dsk" ] || { echo "run: $B/cpclispfos.dsk is missing -- MACH=futureos tools/build.sh" >&2; exit 1; }
[ -f "$R/FOS-A.ROM" ] || { echo "run: no FutureOS ROMs in $R" >&2; exit 1; }
EDIT=0x$(awk '$1 == "EDHOOK" { sub("#", "", $2); print $2 }' "$B/lisp.sym")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$B/cpclispfos.dsk" "$tmp/disc.dsk"
{
    echo '|OS'
    echo "!poke 700 8000 $(realpath "$B/LISP64K.BIN")"
    printf '%s\n' '!press 63 30' '!press 57 60' \
        '!press 33 60' '!press 32 20' '!press 32 20' '!press 32 20' '!press 18 20' \
        '!press 62 60' '!press 32 20' '!press 18 20'
    cat "$IN"
} > "$tmp/in.lsp"
LISP_IN=$tmp/in.lsp LISP_OUT=$tmp/out LISP_SHOT=$SHOT LISP_FRAMES=$FRAMES LISP_EDIT=$EDIT LISP_EDIT2=0xBD3A \
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 timeout 600 xvfb-run -a \
    /usr/games/mame -rompath $HOME/claude/cpc/mame-roms -video none -sound none -nothrottle \
    -skip_gameinfo cpc464 -ramsize 576K -exp ddi1 -flop "$tmp/disc.dsk" \
    -exp:ddi1:exp rom -rom1 "$R/FOS-A.ROM" -rom2 "$R/FOS-B.ROM" -rom3 "$R/FOS-C.ROM" -rom4 "$R/FOS-D.ROM" \
    -autoboot_script emu/repl.lua 2>&1 \
  | grep -v -E "^Warning: -video none|^Average speed|WRONG CHECKSUMS|EXPECTED: CRC|FOUND: CRC|might not run correctly" >&2 || true
cat "$tmp/out"
