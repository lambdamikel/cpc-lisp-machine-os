#!/bin/bash
# The regression tests on the 512K CPC in MAME: test/*.lsp through
# tools/cpc512/run.sh, against test/*.out (or test/NAME.cpc512.out).
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
MACH=cpc512 tools/build.sh >/dev/null || exit 1
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
    [ -f "test/$n.cpc512.out" ] && exp=test/$n.cpc512.out
    if diff -u "$exp" "$tmp/$n.got" > "$tmp/$n.diff"; then
        echo "ok      $n"
    else
        echo "FAIL    $n"; cat "$tmp/$n.diff"; fail=1
    fi
done
exit $fail
