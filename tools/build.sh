#!/bin/bash
# Assemble the Lisp ROM and splice it over BASIC in private MAME romsets.
#
#     tools/build.sh
#
# MAME's ROM box numbers its filled sockets 1, 2, 3... in order and never
# answers ROM 0, so it cannot stand in for a card ROM that replaces BASIC.
# What ROMDIS does on the real machine -- BASIC's ROM goes quiet and ours
# answers 0 -- is done here by building a copy of each system ROM with
# BASIC's 16 KB replaced by ours. MAME warns about the checksum and runs it.
#
#   build/LISP.ROM                  the core ROM
#   build/LISPLIB.ROM, LISPLIB2.ROM, LISPLIB3.ROM
#                                   the library ROMs (parts 0, 1, 2), for
#                                   any other ROM numbers
#   build/LISPDEMO.ROM              the demo ROM (part 3)
#   build/LISPVM.ROM                the VM ROM: runs compiled functions
#   build/lisp.sym, lisplib*.sym    their symbols (rasm -s format)
#   build/mame/cpc464/cpc464.rom    464 OS + LISP     (rompath build/mame)
#   build/mame/cpc6128/...          6128 OS + LISP, and the 6128's AMSDOS
#   build/mame/cpc_ddi1/            the DDI-1's AMSDOS, for -exp ddi1
set -e
cd "$(dirname "$0")/.."
RASM=${RASM:-$HOME/claude/midi80/toolchain/rasm/rasm}
ROMS=${ROMS:-$HOME/claude/cpc/mame-roms}
# the machine: mach/$MACH holds everything that depends on it
export MACH=${MACH:-cpc}
# where the ROMs go: build/ for the CPC, build/<machine>/ for another
if [ "$MACH" = cpc ]; then OUT=build; else OUT=build/$MACH; fi
export OUT
mkdir -p "$OUT"

# All the ROMs get the same build number: the library calls the core by
# address, so the core only uses a library from its own build.
BUILD_ID=${BUILD_ID:-$(( $(date +%s) % 32000 + 1 ))}

# rasm reports a failed assembly on stdout and still exits 0.
asm() {  # asm source output symfile [rasm options]
    local src=$1 out=$2 sym=$3; shift 3
    local log
    log=$("$RASM" "$src" -I src -I "$OUT" -I "mach/$MACH" -ob "$out" -s -sa -os "$sym" -DBUILD_ID=$BUILD_ID "$@" 2>&1) || true
    log=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$log")
    if ! grep -q "Write binary file" <<<"$log"; then
        echo "$log" >&2
        echo "build: $src FAILED" >&2
        exit 1
    fi
    grep -i -E "warning|used:" <<<"$log" || true
    [ "$(stat -c %s "$out")" = 16384 ] || { echo "build: $out is not 16 KB" >&2; exit 1; }
}

asm src/lisp.asm $OUT/LISP.ROM $OUT/lisp.sym

# the core's symbols, for the library: labels and constants, not locals
awk '$3 == "B0" && ($4 == "L" || $4 == "A") && $1 !~ /\./ && $1 != "BUILD_ID" && $1 != "SYNCHRO" && $1 != "RASM_VERSION" \
     { print $1 " equ " $2 }' $OUT/lisp.sym > $OUT/core.inc
python3 tools/bootstrap.py lib/compiler.lsp lib/vm.asm $OUT/vmcode.asm
python3 tools/mklib.py $OUT lib/lib.asm lib/lib2.asm lib/lib3.asm lib/demo.asm --vm lib/vm.asm lib/lib2.asm
asm lib/lib.asm $OUT/LISPLIB.ROM $OUT/lisplib.sym -I lib
asm lib/lib2.asm $OUT/LISPLIB2.ROM $OUT/lisplib2.sym -I lib
asm lib/lib3.asm $OUT/LISPLIB3.ROM $OUT/lisplib3.sym -I lib
asm lib/demo.asm $OUT/LISPDEMO.ROM $OUT/lispdemo.sym -I lib
asm lib/vm.asm $OUT/LISPVM.ROM $OUT/lispvm.sym -I lib

# what the machine makes of them: on the CPC, MAME romsets
if [ -f "mach/$MACH/post-build.sh" ]; then
    . "mach/$MACH/post-build.sh"
fi
echo "build: ok"
