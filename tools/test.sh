#!/bin/bash
# Run the regression tests in MAME and compare against expected transcripts.
#
#     tools/test.sh [-m 464|6128] [-u] [name...]
#
# Each test/NAME.lsp is typed at the REPL; the transcript from the first
# prompt on (the banner's free-cell count differs between machines) must
# match test/NAME.out. -u writes the transcripts as the new expectations --
# read them before committing. Several tests run at once.
cd "$(dirname "$0")/.."
MACH=464 UPDATE=
while getopts "m:u" o; do
    case $o in
        m) MACH=$OPTARG ;;
        u) UPDATE=1 ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
names=("$@")
if [ ${#names[@]} = 0 ]; then
    for f in test/*.lsp; do names+=("$(basename "$f" .lsp)"); done
fi
tools/build.sh >/dev/null || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for n in "${names[@]}"; do
    ( tools/run.sh -m "$MACH" -f 400000 "test/$n.lsp" 2>"$tmp/$n.err" \
        | sed -n '/^LISP> /,$p' > "$tmp/$n.got" ) &
done
wait
fail=0
for n in "${names[@]}"; do
    if grep -q TIMEOUT "$tmp/$n.err"; then
        echo "TIMEOUT $n"; fail=1; continue
    fi
    if [ -n "$UPDATE" ]; then
        cp "$tmp/$n.got" "test/$n.out"; echo "wrote test/$n.out"
    elif diff -u "test/$n.out" "$tmp/$n.got" > "$tmp/$n.diff"; then
        echo "ok      $n"
    else
        echo "FAIL    $n"; cat "$tmp/$n.diff"; fail=1
    fi
done
exit $fail
