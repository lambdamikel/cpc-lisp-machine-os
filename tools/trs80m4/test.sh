#!/bin/bash
# The regression tests on the emulated TRS-80 Model 4 (trs80gp, headless):
# test/NAME.lsp typed at the Lisp (tools/trs80m4/run.sh), the transcript
# from the first prompt on compared with test/NAME.trs80m4.out, or
# test/NAME.out where the Model 4 says the same as the CPC.
#
#     tools/trs80m4/test.sh [-u] [-j N] [name...]
#
# -u writes the transcripts as the new expectations (as NAME.trs80m4.out
# where they differ from NAME.out) -- read them before committing. Each
# test gets a copy of the disc. test/skip.trs80m4 lists the tests left out
# (the compiler, the RAM disc, the CPC's own hardware); N run at once (3).
cd "$(dirname "$0")/../.."
UPDATE= JOBS=3
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
        grep -qx "$n" test/skip.trs80m4 2>/dev/null || names+=("$n")
    done
fi
MACH=trs80m4 tools/build.sh >/dev/null || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
run_one() {
    local n=$1
    mkdir -p "$tmp/$n"
    cp build/trs80m4/lisp-m4.dsk "$tmp/$n/"
    TRS80M4_BUILD=$tmp/$n tools/trs80m4/run.sh "test/$n.lsp" 2>"$tmp/$n.err" \
        > "$tmp/$n.raw"
    # from the first prompt on, ending at the prompt (quit) was typed at --
    # as the CPC harness's transcripts end
    python3 -c '
import sys
d = open(sys.argv[1], encoding="latin-1").read()
i = d.find("LISP> ")
d = d[i:] if i >= 0 else ""
j = d.rfind("LISP> (quit)")
if j >= 0: d = d[:j] + "LISP> "
sys.stdout.write(d)' "$tmp/$n.raw" > "$tmp/$n.got"
}
for n in "${names[@]}"; do
    while [ "$(jobs -r | wc -l)" -ge "$JOBS" ]; do wait -n; done
    run_one "$n" &
done
wait
fail=0
for n in "${names[@]}"; do
    if grep -q "stopped taking input\|did not finish" "$tmp/$n.err"; then
        echo "STUCK   $n"; sed 's/^/    /' "$tmp/$n.err" | grep -v '^    |  *|$'; fail=1
        continue
    fi
    exp=test/$n.out
    [ -f "test/$n.trs80m4.out" ] && exp=test/$n.trs80m4.out
    if [ -n "$UPDATE" ]; then
        if [ "$exp" = "test/$n.out" ] && cmp -s "$exp" "$tmp/$n.got"; then
            echo "same    $n"
        else
            cp "$tmp/$n.got" "test/$n.trs80m4.out"; echo "wrote test/$n.trs80m4.out"
        fi
    elif diff -u "$exp" "$tmp/$n.got" > "$tmp/$n.diff"; then
        echo "ok      $n"
    else
        echo "FAIL    $n"; cat "$tmp/$n.diff"; fail=1
    fi
done
exit $fail
