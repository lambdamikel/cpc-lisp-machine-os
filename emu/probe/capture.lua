-- Capture text output: tap opcode fetches of the TXT OUTPUT vector (&BB5A)
-- and record A. Exits after FRAMES frames; writes OUT (or stdout).
CPU = manager.machine.devices[":maincpu"]
MEM = CPU.spaces["program"]
OUTBUF = {}
TAPX = MEM:install_read_tap(0xBB5A, 0xBB5A, "txtout", function(offset, data, mask)
  local pc = CPU.state["PC"].value
  if pc == 0xBB5A or pc == 0xBB5B then
    OUTBUF[#OUTBUF + 1] = string.char(CPU.state["A"].value & 0xFF)
  end
  return data
end)
F = 0
NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F == 200 then
    manager.machine.screens[":screen"]:snapshot("probe.png")
    io.write("=== captured:\n" .. table.concat(OUTBUF):gsub("\r", "") .. "\n=== end\n")
    manager.machine:exit()
  end
end)
