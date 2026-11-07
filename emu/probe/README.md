# Probes

What settled the MAME and firmware questions at the start (2026-11-06). Kept
because they answer questions that will come up again.

* `probe.asm` -- a background ROM whose init prints the ROM number it was
  given and the memory limits. Three copies in rom1, rom2, rom8 showed that
  MAME's ROM box numbers its filled sockets 1, 2, 3 in order, never 0.
* `probe0.asm` -- a foreground ROM for ROM 0 that prints the registers the
  firmware enters it with, before and after KL ROM WALK.
* `capture.lua` -- prints what went through TXT OUTPUT (&BB5A).
* `dumpjb.lua` -- dumps the RAM jumpblocks &B900-&BDFF after boot, which is
  how the 464/6128 differences past &BD37 were found.

    rasm -DTAG=0x41 probe.asm -ob PROBEA.ROM
