# sourced by tools/build.sh once the images are in $OUT: the resident part
# (a link to mach/cpc512's: rasm reads its includes beside the link, so
# this machine's memmap.asm and mmacros.asm), the loader carrying it
# (LISP.BIN), and the disc, cpclisp6128.dsk: LISP.BIN and five images,
# LISP0.IMG-LISP4.IMG -- the core and the four parts; the VM ROM, the
# compiler, is left out (RUN"LISP)

asm_any() {  # source output [rasm options]
    local src=$1 out=$2; shift 2
    local log
    log=$("$RASM" "$src" -I "mach/$MACH" -I "$OUT" -ob "$out" "$@" 2>&1) || true
    log=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$log")
    if ! grep -q "Write binary file" <<<"$log"; then
        echo "$log" >&2
        echo "build: $src FAILED" >&2
        exit 1
    fi
    grep -i -E "warning|resident:" <<<"$log" || true
}

asm_any mach/cpc6128/resident.asm "$OUT/resident.bin"
asm_any mach/cpc6128/loader.asm "$OUT/LISP.BIN"
IDSK=${IDSK:-$HOME/claude/midi80/toolchain/idsk/iDSK}
dsk="$OUT/cpclisp6128.dsk"
rm -f "$dsk"
"$IDSK" "$dsk" -n >/dev/null
( cd "$OUT" && "$IDSK" cpclisp6128.dsk -i LISP.BIN -t 1 -c 8000 -e 8000 >/dev/null 2>&1 )
k=0
for rom in LISP.ROM LISPLIB.ROM LISPLIB2.ROM LISPLIB3.ROM LISPDEMO.ROM; do
    cp "$OUT/$rom" "$OUT/LISP$k.IMG"
    ( cd "$OUT" && "$IDSK" cpclisp6128.dsk -i "LISP$k.IMG" -t 1 -c 4000 >/dev/null 2>&1 )
    k=$((k + 1))
done
# the test for the real machine: (load "hwtest"), (hwtest)
cp mach/cpc6128/hwtest.lsp "$OUT/HWTEST.LSP"
( cd "$OUT" && "$IDSK" cpclisp6128.dsk -i HWTEST.LSP -t 0 >/dev/null 2>&1 )
