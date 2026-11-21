#!/bin/bash
# The regression tests on the emulated ZX Spectrum +2A with a DivMMC
# (ZEsarUX, headless): test/NAME.lsp typed at the Lisp (tools/spectrum/
# zx.py), the transcript from the first prompt on compared with
# test/NAME.spectrum.out, or test/NAME.out where the Spectrum says the same
# as the CPC.
#
#     tools/spectrum/test.sh [-u] [-j N] [name...]
#
# -u writes the transcripts as the new expectations (as NAME.spectrum.out
# where they differ from NAME.out) -- read them before committing. Each
# test gets a folder of its own for esxDOS to serve: empty, or for classic*
# the example programs (examples/*.lsp, named in capitals). test/
# skip.spectrum lists the tests left out (the CPC's own hardware); N run at
# once (4). Build elsewhere meanwhile with OUT=build/spectrum-dev and run
# with SPECTRUM_BUILD=...: the images are read as each test starts.
cd "$(dirname "$0")/../.."
UPDATE= JOBS=4
while getopts "uj:" o; do
    case $o in
        u) UPDATE=1 ;;
        j) JOBS=$OPTARG ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
names=("$@")
if [ ${#names[@]} = 0 ]; then
    for f in test/*.lsp; do
        n=$(basename "$f" .lsp)
        grep -qx "$n" test/skip.spectrum 2>/dev/null || names+=("$n")
    done
fi
if [ -z "$SPECTRUM_BUILD" ]; then
    MACH=spectrum tools/build.sh >/dev/null || exit 1
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
run_one() {
    local n=$1
    mkdir -p "$tmp/$n/sd"
    if [[ $n == classic* ]]; then
        for f in examples/*.lsp; do
            cp "$f" "$tmp/$n/sd/$(basename "$f" | tr a-z A-Z)"
        done
    fi
    tools/spectrum/zx.py -d "$tmp/$n/sd" "test/$n.lsp" 2>"$tmp/$n.err" > "$tmp/$n.raw"
    # from the first prompt on, as the CPC harness's transcripts are
    python3 -c '
import sys
d = open(sys.argv[1], encoding="latin-1").read()
i = d.find("LISP> ")
sys.stdout.write(d[i:] if i >= 0 else "")' "$tmp/$n.raw" > "$tmp/$n.got"
}
for n in "${names[@]}"; do
    while [ "$(jobs -r | wc -l)" -ge "$JOBS" ]; do wait -n; done
    run_one "$n" &
done
wait
fail=0
for n in "${names[@]}"; do
    if grep -q "TIMEOUT" "$tmp/$n.err"; then
        echo "TIMEOUT $n"; sed 's/^/    /' "$tmp/$n.err" | grep -v '^    |  *|$' | tail -30; fail=1
        continue
    fi
    exp=test/$n.out
    [ -f "test/$n.spectrum.out" ] && exp=test/$n.spectrum.out
    if [ -n "$UPDATE" ]; then
        if [ "$exp" = "test/$n.out" ] && cmp -s "$exp" "$tmp/$n.got"; then
            echo "same    $n"
        else
            cp "$tmp/$n.got" "test/$n.spectrum.out"; echo "wrote test/$n.spectrum.out"
        fi
    elif diff -u "$exp" "$tmp/$n.got" > "$tmp/$n.diff"; then
        echo "ok      $n"
    else
        echo "FAIL    $n"; cat "$tmp/$n.diff"; fail=1
    fi
done
exit $fail
