#!/bin/bash
# Play with the Lisp in a MAME window: the core at ROM 0, the library at
# ROMs 1 and 2, and a disc in drive A that keeps what is saved on it.
#
#     tools/mame.sh [-m 464|6128] [disc.mfi]
#
# The disc defaults to work.mfi here (made if it is missing; not in git).
# It must be .mfi: MAME writes those back when it quits, and treats .dsk as
# read-only -- a SAVE onto a .dsk is gone with the session. To use a .dsk:
#     floptool flopconvert dsk mfi old.dsk new.mfi
#
# The ROMs are copied first, so a rebuild cannot touch a running session.
# MAME starts in natural keyboard mode: type as on your own keyboard; End is
# COPY (which finishes the function editor). Scroll Lock gives MAME its keys
# back, Esc then quits.
set -e
cd "$(dirname "$0")/.."
MACH=464
while getopts "m:" o; do
    case $o in
        m) MACH=$OPTARG ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
DISC=$(realpath -m "${1:-work.mfi}")
IDSK=${IDSK:-$HOME/claude/midi80/toolchain/idsk/iDSK}
[ -f build/LISP.ROM ] || tools/build.sh
if [ ! -f "$DISC" ]; then
    tmp=$(mktemp -d)
    "$IDSK" "$tmp/blank.dsk" -n >/dev/null
    floptool flopconvert dsk mfi "$tmp/blank.dsk" "$DISC" >/dev/null
    rm -rf "$tmp"
    echo "mame: made a blank disc, $DISC"
fi
rm -rf build/mame-live
cp -r build/mame build/mame-live
cp build/LISPLIB.ROM build/LISPLIB2.ROM build/LISPLIB3.ROM build/LISPDEMO.ROM build/mame-live/
LIBS=(-rom1 build/mame-live/LISPLIB.ROM -rom2 build/mame-live/LISPLIB2.ROM -rom3 build/mame-live/LISPLIB3.ROM -rom4 build/mame-live/LISPDEMO.ROM)
case $MACH in
    464)  ARGS=(cpc464 -exp ddi1 -flop "$DISC" -exp:ddi1:exp rom "${LIBS[@]}") ;;
    6128) ARGS=(cpc6128 -flop1 "$DISC" -exp rom "${LIBS[@]}") ;;
    *) echo "mame: -m 464 or 6128" >&2; exit 2 ;;
esac
exec env -u WAYLAND_DISPLAY GDK_BACKEND=x11 /usr/games/mame -rompath build/mame-live \
    -window -skip_gameinfo -natural "${ARGS[@]}"
