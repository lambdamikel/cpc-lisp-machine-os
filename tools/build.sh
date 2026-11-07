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
#   build/LISP.ROM                  the ROM itself
#   build/lisp.sym                  its symbols (rasm -s format)
#   build/mame/cpc464/cpc464.rom    464 OS + LISP     (rompath build/mame)
#   build/mame/cpc6128/...          6128 OS + LISP, and the 6128's AMSDOS
#   build/mame/cpc_ddi1/            the DDI-1's AMSDOS, for -exp ddi1
set -e
cd "$(dirname "$0")/.."
RASM=${RASM:-$HOME/claude/midi80/toolchain/rasm/rasm}
ROMS=${ROMS:-$HOME/claude/cpc/mame-roms}
mkdir -p build

# rasm reports a failed assembly on stdout and still exits 0.
out=$("$RASM" src/lisp.asm -I src -ob build/LISP.ROM -s -sa -os build/lisp.sym "$@" 2>&1) || true
if ! grep -q "Write binary file" <<<"$out"; then
    sed 's/\x1b\[[0-9;]*m//g' <<<"$out" >&2
    echo "build: assembly FAILED" >&2
    exit 1
fi
sed 's/\x1b\[[0-9;]*m//g' <<<"$out" | grep -i -E "warning|ROM used|free" || true
[ "$(stat -c %s build/LISP.ROM)" = 16384 ] || { echo "build: LISP.ROM is not 16 KB" >&2; exit 1; }

mkdir -p build/mame/cpc464 build/mame/cpc6128 build/mame/cpc_ddi1
{ head -c 16384 "$ROMS/cpc464/cpc464.rom"; cat build/LISP.ROM; } > build/mame/cpc464/cpc464.rom
{ head -c 16384 "$ROMS/cpc6128/cpc6128.rom"; cat build/LISP.ROM; } > build/mame/cpc6128/cpc6128.rom
cp "$ROMS/cpc6128/cpcados.rom" build/mame/cpc6128/
cp "$ROMS/cpc_ddi1/cpcados.rom" build/mame/cpc_ddi1/
echo "build: ok"
