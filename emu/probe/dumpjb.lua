-- Dump RAM &B900-&BDFF (the jumpblocks) after boot to jb_<system>.bin
CPU = manager.machine.devices[":maincpu"]
MEM = CPU.spaces["program"]
F = 0
NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F == 150 then
    local t = {}
    for a = 0xB900, 0xBDFF do t[#t+1] = string.char(MEM:read_u8(a)) end
    local f = io.open("jb_" .. manager.machine.system.name .. ".bin", "wb")
    f:write(table.concat(t)); f:close()
    manager.machine:exit()
  end
end)
