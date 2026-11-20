#!/bin/bash
# Pocket Lisp's regression tests: CPC Lisp's test/*.lsp through the Linux
# build, against test/NAME.pocket.out where Pocket Lisp differs, else
# test/NAME.out -- the transcript from the first prompt on.
#
#     pocket/tools/test.sh [-u] [-v] [name...]
#
# -u writes what came out as NAME.pocket.out where it differs from
# NAME.out (read the diff first); -v shows each failure's diff. Each test
# runs in an empty directory, its disc; a classic* one gets examples/.
# '!' lines (the CPC harness's key actions) are left out. pocket/test.skip
# lists the tests that need the CPC (the card, its keys, its screen).
cd "$(dirname "$0")/../.." || exit 1
ROOT=$PWD
P=$ROOT/pocket/pocket
UPDATE= VERBOSE=
while getopts "uv" o; do
    case $o in u) UPDATE=1 ;; v) VERBOSE=1 ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
make -s -C pocket >&2 || exit 1
if [ $# -gt 0 ]; then names=("$@"); else
    names=(); for f in test/*.lsp; do names+=("$(basename "$f" .lsp)"); done
fi
pass=0 fail=0 skipped=0 failed=()
for n in "${names[@]}"; do
    if [ $# -eq 0 ] && grep -qx "$n" pocket/test.skip 2>/dev/null; then
        skipped=$((skipped + 1)); continue
    fi
    tmp=$(mktemp -d)
    mkdir "$tmp/disc"
    if [[ $n == classic* ]]; then
        for f in examples/*.lsp; do cp "$f" "$tmp/disc/$(basename "$f" | tr a-z A-Z)"; done
    fi
    ( cd "$tmp/disc" && grep -v '^!press\|^!shot\|^!dump\|^!poke\|^!disc' "$ROOT/test/$n.lsp" \
        | POCKET_COLS=40 POCKET_DISC_K=178 POCKET_RAMDISC_K=400 timeout 120 "$P" -l "$ROOT/lib" 2>"$tmp/err" ) | sed -n '/^LISP> /,$p' > "$tmp/got"
    exp=test/$n.out                     # (no generic one: the 512K's, the
    [ -f "$exp" ] || exp=test/$n.cpc512.out   #   nearest of the CPC's)
    [ -f "test/$n.pocket.out" ] && exp=test/$n.pocket.out
    if [ -n "$UPDATE" ]; then
        if [ "$exp" = "test/$n.out" ] && cmp -s "$exp" "$tmp/got"; then
            echo "ok      $n"
        else
            cp "$tmp/got" "test/$n.pocket.out"; echo "wrote test/$n.pocket.out"
        fi
    elif diff -u "$exp" "$tmp/got" > "$tmp/diff"; then
        echo "ok      $n"; pass=$((pass + 1))
    else
        echo "FAIL    $n"; fail=$((fail + 1)); failed+=("$n")
        [ -n "$VERBOSE" ] && head -40 "$tmp/diff"
    fi
    rm -rf "$tmp"
done
[ -z "$UPDATE" ] && echo "$pass ok, $fail failed, $skipped skipped${failed:+: ${failed[*]}}"
