#!/bin/bash
# Type a file at the 512K CPC Lisp in MAME, and print the transcript:
#
#     tools/cpc512/run.sh [-m 464|6128] [-f frames] [-s shot.png] file.lsp
#
# MACH=cpc512 tools/build.sh first. MAME's own romsets (BASIC at ROM 0),
# 576K of RAM (a 512K expansion), build/cpc512/cpclisp512.dsk in drive A
# (a DDI-1's on the 464); emu/repl.lua types RUN"LISP at BASIC's EDIT,
# then the file's lines when Lisp asks for them, as tools/run.sh does.
# VARIANT=cpc6128 (tools/cpc6128/run.sh): the plain 6128's version, with
# 128K (MACH=cpc6128 tools/build.sh, build/cpc6128/cpclisp6128.dsk).
set -e
cd "$(dirname "$0")/../.."
MACH=6128 FRAMES=30000 SHOT=
while getopts "m:f:s:" o; do
    case $o in
        m) MACH=$OPTARG ;;
        f) FRAMES=$OPTARG ;;
        s) SHOT=$(realpath -m "$OPTARG") ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
IN=${1:-/dev/null}
VARIANT=${VARIANT:-cpc512}
case $VARIANT in
    cpc512)  RAM=576K ;;
    cpc6128) RAM=128K ;;
    *) echo "run: VARIANT is cpc512 or cpc6128" >&2; exit 2 ;;
esac
B=${CPC512_BUILD:-build/$VARIANT}
DSK=cpclisp${VARIANT#cpc}.dsk
[ -f "$B/$DSK" ] || { echo "run: $B/$DSK is missing -- MACH=$VARIANT tools/build.sh" >&2; exit 1; }
EDIT=0x$(awk '$1 == "EDHOOK" { sub("#", "", $2); print $2 }' "$B/lisp.sym")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$B/$DSK" "$tmp/disc.dsk"
case $MACH in
    464)  DEV="cpc464 -ramsize $RAM -exp ddi1 -flop $tmp/disc.dsk"; EDIT2=0xBD3A ;;
    6128) DEV="cpc6128 -ramsize $RAM -flop1 $tmp/disc.dsk"; EDIT2=0xBD5E ;;
    *) echo "run: -m 464 or 6128" >&2; exit 2 ;;
esac
{ echo 'run"lisp'; cat "$IN"; } > "$tmp/in.lsp"      # BASIC's line first
LISP_IN=$tmp/in.lsp LISP_OUT=$tmp/out LISP_SHOT=$SHOT LISP_FRAMES=$FRAMES LISP_EDIT=$EDIT LISP_EDIT2=$EDIT2 \
LISP_CARDLOG=${LISP_CARDLOG:-} \
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 timeout 600 xvfb-run -a \
    /usr/games/mame -rompath $HOME/claude/cpc/mame-roms -video none -sound none -nothrottle \
    -skip_gameinfo $DEV -autoboot_script emu/repl.lua 2>&1 \
  | grep -v -E "^Warning: -video none|^Average speed" >&2 || true
cat "$tmp/out"
