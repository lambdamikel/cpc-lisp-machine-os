# sourced by tools/build.sh once the six ROMs are in $OUT: MAME romsets
# in which the core replaces BASIC, what ROMDIS does on a real CPC (MAME's
# ROM box cannot answer ROM 0)
mkdir -p build/mame/cpc464 build/mame/cpc6128 build/mame/cpc_ddi1
{ head -c 16384 "$ROMS/cpc464/cpc464.rom"; cat build/LISP.ROM; } > build/mame/cpc464/cpc464.rom
{ head -c 16384 "$ROMS/cpc6128/cpc6128.rom"; cat build/LISP.ROM; } > build/mame/cpc6128/cpc6128.rom
cp "$ROMS/cpc6128/cpcados.rom" build/mame/cpc6128/
cp "$ROMS/cpc_ddi1/cpcados.rom" build/mame/cpc_ddi1/
