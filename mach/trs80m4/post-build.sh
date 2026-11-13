# sourced by tools/build.sh once the images are in $OUT: the machine page,
# the loader with the resident part (LISP/CMD), and the disc

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
    grep -i -E "warning|machine page|resident|loader" <<<"$log" || true
}

asm_any mach/trs80m4/page.asm "$OUT/LISPM.ROM"
asm_any mach/trs80m4/resident.asm "$OUT/resident.bin"
asm_any mach/trs80m4/loader.asm "$OUT/loader.bin"
python3 tools/trs80/cmd.py "$OUT/LISP.CMD" 0x3000 "$OUT/loader.bin@0x3000" "$OUT/resident.bin@0x3800"
python3 tools/trs80m4/mkdisk.py "$OUT"
