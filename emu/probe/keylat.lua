-- Key latency: press keys through the matrix, log when the ROM next asks
-- for a key (KM WAIT CHAR, &BB06) and how many characters it wrote.
--   LAT_SCRIPT  file of lines: "type <text>" (natkeyboard, then ENTER),
--               "key <n> <frames to wait>", "shot <file>"
CPU = manager.machine.devices[":maincpu"]
MEM = CPU.spaces["program"]
SCR = manager.machine.screens[":screen"]
NK = manager.machine.natkeyboard; NK.in_use = true
KEYFIELD = {}
for row = 0, 9 do
  local port = manager.machine.ioport.ports[string.format(":kbrow.%d", row)]
  for name, f in pairs(port.fields) do
    if name ~= "Keyboard" then
      for bit = 0, 7 do if f.mask == (1 << bit) then KEYFIELD[row * 8 + bit] = f end end
    end
  end
end
WAITS, WRITES = {}, 0
TAPW = MEM:install_read_tap(0xBB06, 0xBB06, "km", function(o, d, m)
  local pc = CPU.state["PC"].value
  if pc == 0xBB06 or pc == 0xBB07 then WAITS[#WAITS + 1] = F end
  return d
end)
TAPC = MEM:install_read_tap(0xBB5D, 0xBB5D, "wr", function(o, d, m)
  local pc = CPU.state["PC"].value
  if pc == 0xBB5D or pc == 0xBB5E then WRITES = WRITES + 1 end
  return d
end)
STEPS = {}
for l in io.lines(os.getenv("LAT_SCRIPT")) do STEPS[#STEPS + 1] = l end
F, I, NEXTF, PRESSED = 0, 1, 100, nil
NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if PRESSED and F == PRESSED[2] then KEYFIELD[PRESSED[1]]:set_value(0) end
  if F < NEXTF or NK.is_posting then return end
  local s = STEPS[I]
  if not s then
    io.write("done\n"); manager.machine:exit(); return
  end
  I = I + 1
  local text = s:match("^type (.*)$")
  if text then
    NK:post_coded(" " .. text .. "{ENTER}"); NEXTF = F + 400
    TYPEDAT, TYPEDN = F, #WAITS
    return
  end
  local k, w = s:match("^key (%d+) (%d+)$")
  if k then
    local n0, w0 = #WAITS, WRITES
    KEYFIELD[tonumber(k)]:set_value(1)
    PRESSED = { tonumber(k), F + 3 }
    local start = F
    -- report when the next wait comes, from the frame notifier below
    PEND = { start, n0, w0, k }
    NEXTF = F + tonumber(w)
    return
  end
  local a, n = s:match("^dump (%x+) (%d+)$")
  if a then
    local t = {}
    for i = 0, tonumber(n) - 1 do t[#t + 1] = string.format("%02X", MEM:read_u8(tonumber(a, 16) + i)) end
    io.write("dump " .. a .. ": " .. table.concat(t, " ") .. "\n"); NEXTF = F + 1; return
  end
  local f = s:match("^shot (.*)$")
  if f then SCR:snapshot(f); NEXTF = F + 5; return end
end)
REPORT = emu.add_machine_frame_notifier(function()
  if TYPEDAT and not NK.is_posting then TYPEDONE, TYPEDAT = F, nil; TYPEDN = #WAITS end
  if TYPEDONE and #WAITS > TYPEDN then
    io.write(string.format("line typed: ready for a key %d frames after\n", WAITS[#WAITS] - TYPEDONE))
    TYPEDONE = nil
  end
  if PEND and #WAITS > PEND[2] then
    io.write(string.format("key %s: ready again after %d frames, %d chars written\n",
      PEND[4], WAITS[#WAITS] - PEND[1], WRITES - PEND[3]))
    PEND = nil
  end
end)
