#!/bin/bash
# Boot the Lisp ROM in MAME, type a file at it, print the transcript.
#
#     tools/run.sh [-m 464|6128] [-n] [-d disc.dsk] [-s shot.png] [-f frames] [-t times.txt] input.lsp
#
# -d puts a disc in drive A: the 6128's own, or on a 464 a DDI-1 with the
# ROM box behind it.
# The library ROM goes in MAME's ROM box (which makes it ROM 1); -n leaves
# it out.
# The ROM must be built first (tools/build.sh). It boots as ROM 0 from the
# spliced romsets in build/mame, so this is what a CPC with the ROM at 0 and
# ROMDIS asserted sees. Lines of input.lsp are typed one per EDIT call; the
# transcript (everything printed through TXT OUTPUT, with each typed line
# after its prompt) goes to stdout.
set -e
cd "$(dirname "$0")/.."
MACH=464 SHOT= FRAMES=30000 TIMES= LIB=1 DISC=
while getopts "m:s:f:t:nd:" o; do
    case $o in
        m) MACH=$OPTARG ;;
        s) SHOT=$(realpath -m "$OPTARG") ;;
        f) FRAMES=$OPTARG ;;
        t) TIMES=$(realpath -m "$OPTARG") ;;
        n) LIB= ;;
        d) DISC=$(realpath "$OPTARG") ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
IN=${1:-/dev/null}
[ -f build/LISP.ROM ] || { echo "run: build/LISP.ROM is missing -- tools/build.sh" >&2; exit 1; }
case $MACH in
    464)  SYS=cpc464 ;;
    6128) SYS=cpc6128 ;;
    *) echo "run: -m 464 or 6128" >&2; exit 2 ;;
esac
# the REPL calls EDHOOK, a RET in RAM, before reading each line
EDIT=0x$(awk '$1 == "EDHOOK" { sub("#", "", $2); print $2 }' build/lisp.sym)
ROMBOX=
[ -n "$LIB" ] && ROMBOX="-exp rom -rom1 build/LISPLIB.ROM"
if [ -n "$DISC" ]; then
    if [ "$MACH" = 6128 ]; then
        ROMBOX="$ROMBOX -flop1 $DISC"
    else
        ROMBOX="-exp ddi1 -flop $DISC"
        [ -n "$LIB" ] && ROMBOX="$ROMBOX -exp:ddi1:exp rom -rom1 build/LISPLIB.ROM"
    fi
fi
OUTF=$(mktemp)
trap 'rm -f "$OUTF"' EXIT
LISP_IN=$(realpath "$IN") LISP_OUT=$OUTF LISP_SHOT=$SHOT LISP_FRAMES=$FRAMES LISP_EDIT=$EDIT LISP_TIMES=$TIMES \
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 timeout 600 xvfb-run -a \
    /usr/games/mame -rompath build/mame -video none -sound none -nothrottle \
    -skip_gameinfo $SYS $ROMBOX ${MAMEARGS} -autoboot_script emu/repl.lua 2>&1 \
  | grep -v -E "^Warning: -video none|WRONG CHECKSUMS|EXPECTED: CRC|FOUND: CRC|might not run correctly|^Average speed" >&2 || true
cat "$OUTF"
