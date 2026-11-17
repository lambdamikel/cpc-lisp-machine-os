# sourced by tools/build.sh once the six images are in $OUT: the machine
# page, the loader with the resident part (LISP/CMD), and the discs

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
    grep -i -E "warning|machine page" <<<"$log" || true
}

asm_any mach/trs80/page.asm "$OUT/LISPM.ROM"
asm_any mach/trs80/resident.asm "$OUT/resident.bin"
asm_any mach/trs80/loader.asm "$OUT/loader.bin"
python3 tools/trs80/cmd.py "$OUT/LISP.CMD" 0x7000 "$OUT/resident.bin@0x5200" "$OUT/loader.bin@0x7000"
python3 tools/trs80/mkdisk.py "$OUT"
# the classics discs, for the Model I, III and 4: the same programs on
# LDOS and LS-DOS data discs (classics-m1/m3/m4.dsk), and their HFEs
python3 tools/trs80/mkclassics.py "$OUT" >/dev/null
HXC=${HXCFE:-$HOME/claude/midi80/toolchain/hxc/build/hxcfe}
if [ -x "$HXC" ]; then
    for m in m1 m3 m4; do
        LD_LIBRARY_PATH=$(dirname "$HXC") "$HXC" -finput:"$OUT/classics-$m.dsk" \
            -conv:HXC_HFE -foutput:"$OUT/classics-$m.hfe" >/dev/null 2>&1 \
            || echo "build: hxcfe failed (classics-$m.hfe)" >&2
    done
fi
