#!/bin/sh
# The real esxDOS 0.8.5 in ZEsarUX, not its handler of esxDOS's calls: an
# SD card image (mkmmc.py) with esxDOS's SYS, BIN and TMP (ESXDOS_DIR, from
# its distribution at esxdos.org -- not ours: never in this repo) and the
# Lisp's files in a folder LISP. As a user does it: esxDOS starts the +2A in
# 48 BASIC; NMI, the browser into LISP, the cursor onto LISP.TAP, ENTER;
# (hwtest); (quit) -- a real reset, esxDOS again -- NMI (the browser
# opens in LISP now), LISP.TAP, ENTER, (hwtest2). Prints the transcript;
# exit status 0 if both said all yes.
#
#   tools/spectrum/esxtest.sh            (MACH=spectrum tools/build.sh first)
set -e
cd "$(dirname "$0")/../.."
ESXDOS_DIR=${ESXDOS_DIR:-$HOME/claude/spectrum/esxdos/card}
B=${SPECTRUM_BUILD:-build/spectrum}
T=$(mktemp -d /tmp/zx-esx-XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/card"
cp -r "$B/sd" "$T/card/LISP"
python3 tools/spectrum/mkmmc.py "$T/sd.mmc" "$ESXDOS_DIR" "$T/card"
# the browser lists names in order: LISP among the root's, LISP.TAP among
# the folder's after ".." -- that many cursor downs (6, each let go)
down() {
    i=0
    while [ $i -lt "$1" ]; do printf 'k 54; w 0.1; '; i=$((i + 1)); done
}
r=$( (ls "$ESXDOS_DIR"; echo LISP) | sort | grep -n '^LISP$' | cut -d: -f1)
f=$(ls "$B/sd" | sort | grep -n '^LISP.TAP$' | cut -d: -f1)
BOOT="w 1; nmi; w 0.4; kt 30; $(down $((r - 1)))k 13; w 0.4; $(down "$f")w 0.2; k 13"
# after a reset the browser opens where it was: in LISP
AGAIN="w 2; nmi; w 0.4; kt 30; $(down "$f")w 0.2; k 13"
cat > "$T/test.lsp" <<EOF
(load "hwtest")
(hwtest)
!ppoke c_echo 00
(quit)
!steps $AGAIN
(load "hwtest")
(hwtest2)
EOF
tools/spectrum/zx.py -M "$T/sd.mmc" -t 300 -B "$BOOT" "$T/test.lsp" | tee "$T/out"
grep -q "^10 yes, 0 NO" "$T/out" && grep -q "^2 yes, 0 NO" "$T/out"
