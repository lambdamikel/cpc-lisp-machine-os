# sourced by tools/build.sh once the six ROMs are in $OUT: MAME romsets
# in which the core replaces BASIC, what ROMDIS does on a real CPC (MAME's
# ROM box cannot answer ROM 0)
mkdir -p build/mame/cpc464 build/mame/cpc6128 build/mame/cpc_ddi1
{ head -c 16384 "$ROMS/cpc464/cpc464.rom"; cat build/LISP.ROM; } > build/mame/cpc464/cpc464.rom
{ head -c 16384 "$ROMS/cpc6128/cpc6128.rom"; cat build/LISP.ROM; } > build/mame/cpc6128/cpc6128.rom
cp "$ROMS/cpc6128/cpcados.rom" build/mame/cpc6128/
cp "$ROMS/cpc_ddi1/cpcados.rom" build/mame/cpc_ddi1/
# a disc for the real machine: the test of the RAM expansion's use,
# HWTEST.LSP -- (load "hwtest"), (hwtest)
IDSK=${IDSK:-$HOME/claude/midi80/toolchain/idsk/iDSK}
rm -f build/cpclisp-hwtest.dsk
"$IDSK" build/cpclisp-hwtest.dsk -n >/dev/null
cp mach/cpc/hwtest.lsp build/HWTEST.LSP
( cd build && "$IDSK" cpclisp-hwtest.dsk -i HWTEST.LSP -t 0 >/dev/null 2>&1 )
# and the Apfelmaennchen: (load "apfel"), (apfel)
cp examples/apfel.lsp build/APFEL.LSP
( cd build && "$IDSK" cpclisp-hwtest.dsk -i APFEL.LSP -t 0 >/dev/null 2>&1 )
# the demo disc: the programs of examples/ -- the Apfelmaennchen
rm -f build/cpclisp-demo.dsk
"$IDSK" build/cpclisp-demo.dsk -n >/dev/null
( cd build && "$IDSK" cpclisp-demo.dsk -i APFEL.LSP -t 0 >/dev/null 2>&1 )
