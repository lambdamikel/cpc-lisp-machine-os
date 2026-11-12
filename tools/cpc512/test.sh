#!/bin/bash
# The regression tests on the 512K CPC in MAME: test/*.lsp through
# tools/cpc512/run.sh, against test/*.out (or test/NAME.cpc512.out).
# VARIANT=cpc6128 (tools/cpc6128/test.sh): the plain 6128's, against
# test/NAME.cpc6128.out where there is one, without the tests named in
# test/skip.cpc6128.
#
#     tools/cpc512/test.sh [-m 464|6128] [name...]
cd "$(dirname "$0")/../.."
MACH=6128
while getopts "m:" o; do
    case $o in m) MACH=$OPTARG ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
names=("$@")
if [ ${#names[@]} = 0 ]; then
    for f in test/*.lsp; do names+=("$(basename "$f" .lsp)"); done
fi
export VARIANT=${VARIANT:-cpc512}
if [ -f "test/skip.$VARIANT" ]; then     # tests this variant cannot run
    keep=()
    for n in "${names[@]}"; do
        grep -qx "$n" "test/skip.$VARIANT" || keep+=("$n")
    done
    names=("${keep[@]}")
fi
MACH=$VARIANT tools/build.sh >/dev/null || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for n in "${names[@]}"; do
    ( if [[ $n == card* ]]; then export LISP_CARDLOG=$tmp/$n.card; fi
      tools/cpc512/run.sh -m "$MACH" -f 400000 "test/$n.lsp" 2>"$tmp/$n.err" \
        | sed -n '/^LISP> /,$p' > "$tmp/$n.got"
      if [ -n "${LISP_CARDLOG:-}" ]; then
          { echo; echo "card:"; fold -w 48 "$LISP_CARDLOG"; } >> "$tmp/$n.got"
      fi ) &
    # (at most four MAMEs at once)
    while [ "$(jobs -r | wc -l)" -ge 4 ]; do wait -n; done
done
wait
fail=0
for n in "${names[@]}"; do
    if grep -q TIMEOUT "$tmp/$n.err"; then echo "TIMEOUT $n"; fail=1; continue; fi
    exp=test/$n.out
    [ -f "test/$n.$VARIANT.out" ] && exp=test/$n.$VARIANT.out
    if diff -u "$exp" "$tmp/$n.got" > "$tmp/$n.diff"; then
        echo "ok      $n"
    else
        echo "FAIL    $n"; cat "$tmp/$n.diff"; fail=1
    fi
done
exit $fail
