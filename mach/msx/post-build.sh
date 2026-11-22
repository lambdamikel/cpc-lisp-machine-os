# sourced by tools/build.sh once the six images are in $OUT: the machine
# pages (LISPM.ROM: page A, then page B), LISP.COM (the resident part and
# the loader), LISP.IMG (the six images, then the two pages: what the
# loader reads into the mapper's segments), and sd/ -- the files for the
# SD card's folder

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
    grep -i -E "warning|machine page|resident part|LISP.COM" <<<"$log" || true
}

asm_any mach/msx/page.asm "$OUT/LISPM.ROM" -s -sa -os "$OUT/lispm.sym"
[ "$(stat -c %s "$OUT/LISPM.ROM")" = 32768 ] || { echo "build: LISPM.ROM is not 32 KB" >&2; exit 1; }
asm_any mach/msx/resident.asm "$OUT/LISP.COM" -s -sa -os "$OUT/resident.sym"
cat "$OUT/LISP.ROM" "$OUT/LISPLIB.ROM" "$OUT/LISPLIB2.ROM" "$OUT/LISPLIB3.ROM" \
    "$OUT/LISPDEMO.ROM" "$OUT/LISPVM.ROM" "$OUT/LISPM.ROM" > "$OUT/LISP.IMG"
# what goes in the SD card's folder: the program, its images, the hardware
# test, the examples (the Apfelmaennchen, the classics) -- names in capitals
rm -rf "$OUT/sd"
mkdir -p "$OUT/sd"
cp "$OUT/LISP.COM" "$OUT/LISP.IMG" "$OUT/sd/"
cp mach/msx/hwtest.lsp "$OUT/sd/HWTEST.LSP"
for f in examples/*.lsp; do
    cp "$f" "$OUT/sd/$(basename "$f" | tr a-z A-Z)"
done
