#!/bin/bash
# Type a file at CPC Lisp on FutureOS itself (mach/fos) in MAME, and print
# the transcript -- as tools/futureos/run.sh, with the native build:
#
#     tools/fos/run.sh [-m 6128] [-f frames] [-s shot.png] file.lsp
#
# MACH=fos tools/build.sh first. A 464 with 576K (a 512K expansion),
# a DDI-1 with build/fos/cpclispfos-n.dsk in drive A, and behind it
# MAME's ROM box with FutureOS's four ROMs renumbered 1-4 (FOS_ROMS, by
# default ~/claude/cpc/futureos/mame-1234: tools/futureos/fosroms.py SRC
# OUT 1 2 3 4 -- they are TFM's, never in this repository). emu/repl.lua
# types |OS at BASIC's EDIT; on the desktop it reads drive A's directory
# (SPACE, A, D), moves the pointer onto LISP.64K (the third file, after
# APFEL.LSP and HWTEST.LSP), tags it (COPY) and runs it (X), as a user
# does: FutureOS loads LISP.64K, and LISP.64K the images through FutureOS
# (LADE_N) from that drive. Then the file's lines are typed when Lisp
# asks for them. FOS_DIR=0 starts LISP.64K without a directory read
# instead -- put at &8000 and started from the RUN menu (X, 3: a RAM
# application at &9000, block &C0): the images come through the disc ROM
# (AMSDOS) then, LISP.64K's fallback.
set -e
cd "$(dirname "$0")/../.."
FRAMES=30000 SHOT= M=464
while getopts "m:f:s:" o; do
    case $o in
        m) M=$OPTARG ;;
        f) FRAMES=$OPTARG ;;
        s) SHOT=$(realpath -m "$OPTARG") ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
IN=${1:-/dev/null}
B=${FOS_BUILD:-build/fos}
R=${FOS_ROMS:-$HOME/claude/cpc/futureos/mame-1234}
[ -f "$B/cpclispfos-n.dsk" ] || { echo "run: $B/cpclispfos-n.dsk is missing -- MACH=fos tools/build.sh" >&2; exit 1; }
[ -f "$R/FOS-A.ROM" ] || { echo "run: no FutureOS ROMs in $R" >&2; exit 1; }
EDIT=0x$(awk '$1 == "EDHOOK" { sub("#", "", $2); print $2 }' "$B/lisp.sym")
TXTOUT=0x$(awk '$1 == "TXT_OUTPUT" { sub("#", "", $2); print $2 }' "$B/lisp.sym")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$B/cpclispfos-n.dsk" "$tmp/disc.dsk"
{
    echo '|OS'
    if [ "${FOS_DIR:-1}" = 0 ]; then
        echo "!poke 700 8000 $(realpath "$B/LISP64K.BIN")"
        printf '%s\n' '!press 63 30' '!press 57 60' \
            '!press 33 60' '!press 32 20' '!press 32 20' '!press 32 20' '!press 18 20' \
            '!press 62 60' '!press 32 20' '!press 18 20'
    else
        printf '%s\n' '!press 47 700' '!press 69 30' '!press 61 30' \
            '!press 2 200' '!press 2 10' '!press 2 10' \
            '!press 1 10' '!press 1 10' '!press 1 10' '!press 1 10' \
            '!press 2 10' '!press 2 10' '!press 2 10' '!press 2 10' \
            '!press 9 20' '!press 63 30'
    fi
    cat "$IN"
} > "$tmp/in.lsp"
# the 464 with a DDI-1 and the ROM box behind it; the 6128 with its own
# drive and the ROM box (BASIC's EDIT is &BD5E there)
FOS="-rom1 $R/FOS-A.ROM -rom2 $R/FOS-B.ROM -rom3 $R/FOS-C.ROM -rom4 $R/FOS-D.ROM"
case $M in
    464)  SYS="cpc464 -ramsize 576K -exp ddi1 -flop $tmp/disc.dsk -exp:ddi1:exp rom $FOS"; EDIT2=0xBD3A ;;
    6128) SYS="cpc6128 -ramsize 576K -flop1 $tmp/disc.dsk -exp rom $FOS"; EDIT2=0xBD5E ;;
    *) echo "run: -m 464 or 6128" >&2; exit 2 ;;
esac
LISP_IN=$tmp/in.lsp LISP_OUT=$tmp/out LISP_SHOT=$SHOT LISP_FRAMES=$FRAMES LISP_EDIT=$EDIT LISP_EDIT2=$EDIT2 LISP_TXTOUT=$TXTOUT LISP_AYLOG=$LISP_AYLOG \
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 timeout 600 xvfb-run -a \
    /usr/games/mame -rompath $HOME/claude/cpc/mame-roms -video none -sound none -nothrottle \
    -skip_gameinfo $SYS \
    -autoboot_script "${REPL_LUA:-emu/repl.lua}" 2>&1 \
  | grep -v -E "^Warning: -video none|^Average speed|WRONG CHECKSUMS|EXPECTED: CRC|FOUND: CRC|might not run correctly" >&2 || true
cat "$tmp/out"
