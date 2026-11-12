#!/bin/bash
# Run the regression tests in MAME and compare against expected transcripts.
#
#     tools/test.sh [-m 464|6128] [-u] [name...]
#
# Each test/NAME.lsp is typed at the REPL; the transcript from the first
# prompt on (the banner's free-cell count differs between machines) must
# match test/NAME.out -- or test/NAME.464.out, NAME.6128.out where the
# machines differ. -u writes the transcripts as the new expectations --
# read them before committing. Several tests run at once. A test whose name
# starts with "disc" gets a blank disc in drive A (a DDI-1 on the 464).
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
IDSK=${IDSK:-$HOME/claude/midi80/toolchain/idsk/iDSK}
for n in "${names[@]}"; do
    disc=()
    if [[ $n == disc* ]]; then
        "$IDSK" "$tmp/$n.dsk" -n >/dev/null 2>&1
        disc=(-d "$tmp/$n.dsk")
    fi
    # card*: what was written to the LambdaSpeak card (&FBEE) goes at the
    # end of the transcript, in hex
    ( if [[ $n == card* ]]; then export LISP_CARDLOG=$tmp/$n.card; fi
      tools/run.sh -m "$MACH" "${disc[@]}" -f 400000 "test/$n.lsp" 2>"$tmp/$n.err" \
        | sed -n '/^LISP> /,$p' > "$tmp/$n.got"
      if [ -n "${LISP_CARDLOG:-}" ]; then
          { echo; echo "card:"; fold -w 48 "$LISP_CARDLOG"; } >> "$tmp/$n.got"
      fi ) &
done
wait
fail=0
for n in "${names[@]}"; do
    if grep -q TIMEOUT "$tmp/$n.err"; then
        echo "TIMEOUT $n"; fail=1; continue
    fi
    exp=test/$n.out                     # or one for this machine
    [ -f "test/$n.$MACH.out" ] && exp=test/$n.$MACH.out
    if [ -n "$UPDATE" ]; then
        cp "$tmp/$n.got" "$exp"; echo "wrote $exp"
    elif diff -u "$exp" "$tmp/$n.got" > "$tmp/$n.diff"; then
        echo "ok      $n"
    else
        echo "FAIL    $n"; cat "$tmp/$n.diff"; fail=1
    fi
done
exit $fail
