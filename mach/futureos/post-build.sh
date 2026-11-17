# sourced by tools/build.sh once the six images are in $OUT: the resident
# part (a link to mach/cpc512's, built with this machine's variant.asm:
# FUTUREOS), LISP.64K -- the stub FutureOS starts, then the 512K CPC's
# loader carrying the resident part -- and the disc, cpclispfos.dsk:
# LISP.64K, the six images LISP0.IMG-LISP5.IMG, HWTEST.LSP, APFEL.LSP

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

asm_any mach/futureos/resident.asm "$OUT/resident.bin"
asm_any mach/futureos/loader.asm "$OUT/LISP64K.BIN"
IDSK=${IDSK:-$HOME/claude/midi80/toolchain/idsk/iDSK}
dsk="$OUT/cpclispfos.dsk"
rm -f "$dsk"
"$IDSK" "$dsk" -n >/dev/null
cp "$OUT/LISP64K.BIN" "$OUT/LISP.64K"
( cd "$OUT" && "$IDSK" cpclispfos.dsk -i LISP.64K -t 1 -c 8000 -e 9000 >/dev/null 2>&1 )
k=0
for rom in LISP.ROM LISPLIB.ROM LISPLIB2.ROM LISPLIB3.ROM LISPDEMO.ROM LISPVM.ROM; do
    cp "$OUT/$rom" "$OUT/LISP$k.IMG"
    ( cd "$OUT" && "$IDSK" cpclispfos.dsk -i "LISP$k.IMG" -t 1 -c 4000 >/dev/null 2>&1 )
    k=$((k + 1))
done
cp mach/futureos/hwtest.lsp "$OUT/HWTEST.LSP"
( cd "$OUT" && "$IDSK" cpclispfos.dsk -i HWTEST.LSP -t 0 >/dev/null 2>&1 )
cp examples/apfel.lsp "$OUT/APFEL.LSP"
( cd "$OUT" && "$IDSK" cpclispfos.dsk -i APFEL.LSP -t 0 >/dev/null 2>&1 )
# the same files on a Vortex disc, for VDOS and FutureOS's drive E (the
# card's drive after |VORTEX,7): cpclispfos-vortex.dsk
python3 tools/futureos/vortexdisk.py "$dsk" "$OUT/cpclispfos-vortex.dsk"
