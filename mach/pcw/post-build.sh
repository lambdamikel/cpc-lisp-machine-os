# sourced by tools/build.sh once the six images are in $OUT: the machine
# pages (LISPM.ROM: page A, then page B), BOOT.BIN (the boot sector and
# the loader), RESIDENT.BIN (the resident part), LISP.IMG (the six images,
# then the two pages: what the loader reads into blocks 8-15), and the
# discs (tools/pcw/mkdisk.py): cpclisp-pcw.dsk -- it boots: LISP.IMG,
# HWTEST.LSP, APFEL.LSP -- and cpclisp-pcw-classics.dsk, the examples

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
    grep -i -E "warning|machine page|resident part|boot sector|loader" <<<"$log" || true
}

python3 tools/pcw/mkfpconst.py > "$OUT/fpconst.inc"
# the core's ESC countdown, which page A's keys make 1 at once (k_queue)
vbrk=$(awk '$1 == "V_BRK" { print substr($2, 2) }' "$OUT/lisp.sym")
asm_any mach/pcw/page.asm "$OUT/LISPM.ROM" -s -sa -os "$OUT/lispm.sym" -DV_BRK=$((16#$vbrk))
[ "$(stat -c %s "$OUT/LISPM.ROM")" = 32768 ] || { echo "build: LISPM.ROM is not 32 KB" >&2; exit 1; }
asm_any mach/pcw/resident.asm "$OUT/RESIDENT.BIN" -s -sa -os "$OUT/resident.sym"
asm_any mach/pcw/boot.asm "$OUT/BOOT.BIN" -s -sa -os "$OUT/boot.sym"
cat "$OUT/LISP.ROM" "$OUT/LISPLIB.ROM" "$OUT/LISPLIB2.ROM" "$OUT/LISPLIB3.ROM" \
    "$OUT/LISPDEMO.ROM" "$OUT/LISPVM.ROM" "$OUT/LISPM.ROM" > "$OUT/LISP.IMG"
[ "$(stat -c %s "$OUT/LISP.IMG")" = 131072 ] || { echo "build: LISP.IMG is not 128 KB" >&2; exit 1; }
python3 tools/pcw/mkdisk.py -o "$OUT/cpclisp-pcw.dsk" --boot "$OUT/BOOT.BIN" \
    --resident "$OUT/RESIDENT.BIN" "$OUT/LISP.IMG" mach/pcw/hwtest.lsp:HWTEST.LSP \
    examples/apfel.lsp
cls=()
for f in examples/*.lsp; do
    cls+=("$f:$(basename "$f" | tr a-z A-Z)")
done
python3 tools/pcw/mkdisk.py -o "$OUT/cpclisp-pcw-classics.dsk" "${cls[@]}"
