# sourced by tools/build.sh once the six images are in $OUT (MACH=fos):
# the resident part, the machine page (LISP6.IMG), LISP.64K and the disc,
# cpclispfos-n.dsk: LISP.64K, LISP0.IMG-LISP6.IMG, APFEL.LSP

asm_fos() {  # source output [rasm options]
    local src=$1 out=$2; shift 2
    local log
    log=$("$RASM" "$src" -I "mach/$MACH" -I "$OUT" -ob "$out" "$@" 2>&1) || true
    log=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$log")
    if ! grep -q "Write binary file" <<<"$log"; then
        echo "$log" >&2
        echo "build: $src FAILED" >&2
        exit 1
    fi
    grep -i -E "warning|resident:|page:" <<<"$log" || true
}

asm_fos mach/fos/resident.asm "$OUT/resident.bin" -s -sa -os "$OUT/resident.sym"
# its labels, for the page and LISP.64K (not the locals, not the equates)
awk '$3 == "B0" && $4 == "L" && $1 !~ /\./ { print $1 " equ " $2 }' "$OUT/resident.sym" > "$OUT/resident.inc"
asm_fos mach/fos/page.asm "$OUT/LISP6.IMG" -s -sa -os "$OUT/page.sym"
[ "$(stat -c %s "$OUT/LISP6.IMG")" = 16384 ] || { echo "build: LISP6.IMG is not 16 KB" >&2; exit 1; }
asm_fos mach/fos/loader.asm "$OUT/LISP64K.BIN" -s -sa -os "$OUT/loader.sym"
IDSK=${IDSK:-$HOME/claude/midi80/toolchain/idsk/iDSK}
dsk="$OUT/cpclispfos-n.dsk"
rm -f "$dsk"
"$IDSK" "$dsk" -n >/dev/null
cp "$OUT/LISP64K.BIN" "$OUT/LISP.64K"
( cd "$OUT" && "$IDSK" cpclispfos-n.dsk -i LISP.64K -t 1 -c 8000 -e 9000 >/dev/null 2>&1 )
k=0
for rom in LISP.ROM LISPLIB.ROM LISPLIB2.ROM LISPLIB3.ROM LISPDEMO.ROM LISPVM.ROM; do
    cp "$OUT/$rom" "$OUT/LISP$k.IMG"
    k=$((k + 1))
done
for k in 0 1 2 3 4 5 6; do
    ( cd "$OUT" && "$IDSK" cpclispfos-n.dsk -i "LISP$k.IMG" -t 1 -c 4000 >/dev/null 2>&1 )
done
cp examples/apfel.lsp "$OUT/APFEL.LSP"
( cd "$OUT" && "$IDSK" cpclispfos-n.dsk -i APFEL.LSP -t 0 >/dev/null 2>&1 )
cp mach/futureos/hwtest.lsp "$OUT/HWTEST.LSP"
( cd "$OUT" && "$IDSK" cpclispfos-n.dsk -i HWTEST.LSP -t 0 >/dev/null 2>&1 )
