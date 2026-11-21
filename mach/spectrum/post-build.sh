# sourced by tools/build.sh once the six images are in $OUT: the machine
# pages (LISPM.ROM: page A, then page B), the resident part

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
    grep -i -E "warning|machine page|resident part" <<<"$log" || true
}

asm_any mach/spectrum/page.asm "$OUT/LISPM.ROM" -s -sa -os "$OUT/lispm.sym"
asm_any mach/spectrum/resident.asm "$OUT/resident.bin" -s -sa -os "$OUT/resident.sym"
