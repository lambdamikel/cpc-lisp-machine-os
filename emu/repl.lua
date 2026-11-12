-- Drive the Lisp REPL in MAME: type lines, capture what it prints.
--
--     tools/run.sh [464|6128] input.lsp      (sets the variables below)
--
--   LISP_IN     file of input lines, typed one at a time
--   LISP_OUT    transcript: everything printed through TXT OUTPUT, with
--               each typed line shown after the prompt it answered
--   LISP_SHOT   screenshot (PNG) taken at the end, optional
--   LISP_FRAMES give up after this many frames (default 30000)
--   LISP_EDIT   the address the REPL calls before reading each line (the
--               core's EDHOOK, a RET in RAM; tools/run.sh finds it)
--   LISP_TIMES  optional file: for each line, the frames (1/50 s of CPC
--               time) from the end of its typing to the next EDIT
--   LISP_PROF   optional file: a profile -- every instruction executed
--               while a line runs, counted by address ("addr rom count",
--               rom = core, lib1, lib2, or ram/firmware). tools/profile.py
--               reads it. Slow.
--
-- Output is caught by tapping opcode fetches at &BB5A, the TXT OUTPUT
-- vector: whoever prints through the firmware passes there, and A holds the
-- character. Input is typed through natkeyboard, which drops the first
-- character of a posted string often enough to matter, so every line is
-- posted with a leading space -- harmless to a Lisp reader.
--
-- Lines starting with ! are not typed. They happen while the line before
-- them runs, each N frames after the one before it (the first: N frames
-- after that line has been typed):
--
--   !press KEY N   hold CPC key number KEY (row*8+bit) for 8 frames -- or
--                  KEY+KEY..., together, CTRL (23) first -- through
--                  the key matrix: natkeyboard's press is too brief for a ROM
--                  that polls with KM TEST KEY, and cannot reach COPY
--   !esc N         !press 66 N
--   !type N text   type text with natkeyboard ({ENTER} etc. as it takes them)
--   !shot N        a screenshot, LISP_SHOT with -1, -2... before the .png
--
-- A line is typed only when the ROM is waiting for one, which is known by a
-- second tap on EDHOOK, which the REPL calls before every line.
--
-- Tap tokens and the frame notifier live in globals: a dropped token is
-- collected and the tap silently stops.

NK  = manager.machine.natkeyboard; NK.in_use = true
CPU = manager.machine.devices[":maincpu"]
MEM = CPU.spaces["program"]
SCR = manager.machine.screens[":screen"]

local function getenv(n, d) local v = os.getenv(n); if v == nil or v == "" then return d end; return v end
INFILE  = getenv("LISP_IN", nil)
OUTFILE = getenv("LISP_OUT", nil)
SHOT    = getenv("LISP_SHOT", nil)
MAXF    = tonumber(getenv("LISP_FRAMES", "30000"))
EDITV   = tonumber(getenv("LISP_EDIT", "0xBD3A"))
TIMESF  = getenv("LISP_TIMES", nil)
TIMES, TYPED, T0 = {}, false, nil
ACTIONS, PENDING, SHOTS = {}, nil, 0

LINES = {}
if INFILE then
  for l in io.lines(INFILE) do LINES[#LINES + 1] = l end
end

-- LISP_CARDLOG=file: every byte written to &FBEE (the LambdaSpeak card,
-- which MAME has not got), in hex, written to the file at the end
CARDLOG = getenv("LISP_CARDLOG", nil)
CARD = {}
if CARDLOG then
  IOS = CPU.spaces["io"]
  TAPC = IOS:install_write_tap(0xFBEE, 0xFBEE, "card", function(offset, data, mask)
    CARD[#CARD + 1] = string.format("%02X", data & 0xFF)
    return data
  end)
end

OUT = {}
TAPO = MEM:install_read_tap(0xBB5A, 0xBB5A, "txtout", function(offset, data, mask)
  local pc = CPU.state["PC"].value
  if pc == 0xBB5A or pc == 0xBB5B then
    OUT[#OUT + 1] = string.char(CPU.state["A"].value & 0xFF)
  end
  return data
end)

WAITING = false      -- the ROM wants a line and nothing is typed yet
EDITS = 0
-- a line is asked for when the CPU fetches at EDITV -- or at LISP_EDIT2,
-- a second address (the 512K CPC: BASIC's EDIT, for RUN"LISP, then
-- Lisp's EDHOOK)
local function edit_tap(addr)
  return function(offset, data, mask)
    local pc = CPU.state["PC"].value
    if pc == addr or pc == addr + 1 then
      WAITING = true
      EDITS = EDITS + 1
      ANSWERED = true
      if T0 then TIMES[#TIMES + 1] = (F - T0) .. "\t" .. LINES[NEXT - 1]; T0 = nil end
    end
    return data
  end
end
TAPE = MEM:install_read_tap(EDITV, EDITV, "edit", edit_tap(EDITV))
EDITV2 = tonumber(getenv("LISP_EDIT2", "0"))
if EDITV2 ~= 0 then
  TAPE2 = MEM:install_read_tap(EDITV2, EDITV2, "edit2", edit_tap(EDITV2))
end

PROFF = getenv("LISP_PROF", nil)
PROF = {}
if PROFF then
  local function load(p) local f = io.open(p, "rb"); local d = f:read("a"); f:close(); return d end
  ROMS = { { "core", load("build/LISP.ROM") }, { "vm", load("build/LISPVM.ROM") },
           { "lib1", load("build/LISPLIB.ROM") }, { "lib2", load("build/LISPLIB2.ROM") } }
  -- an opcode fetch is a read at PC; above &C000 the byte read tells the
  -- ROMs apart (the same byte in two of them is rare enough)
  TAPP = MEM:install_read_tap(0x0000, 0xFFFF, "prof", function(offset, data, mask)
    if T0 and offset == CPU.state["PC"].value then
      local key = offset
      if offset >= 0xC000 then
        local b = data & 0xFF
        for i, r in ipairs(ROMS) do
          if r[2]:byte(offset - 0xBFFF) == b then key = i * 0x10000 + offset; break end
        end
      end
      PROF[key] = (PROF[key] or 0) + 1
    end
    return data
  end)
end

-- the key matrix: CPC key number -> its field
KEYFIELD = {}
for row = 0, 9 do
  local port = manager.machine.ioport.ports[string.format(":kbrow.%d", row)]
  if port then
    for name, f in pairs(port.fields) do
      if name ~= "Keyboard" then
        for bit = 0, 7 do
          if f.mask == (1 << bit) then KEYFIELD[row * 8 + bit] = f end
        end
      end
    end
  end
end

-- the directives after line NEXT-1: a list of {delay, what, arg}
local function directives()
  local list = {}
  while LINES[NEXT] and LINES[NEXT]:sub(1, 1) == "!" do
    local l = LINES[NEXT]; NEXT = NEXT + 1
    local n = l:match("^!esc (%d+)")
    if n then list[#list + 1] = { tonumber(n), "press", { 66 } } end
    local k, d = l:match("^!press ([%d+]+) (%d+)")
    if k then
      local keys = {}
      for n in k:gmatch("%d+") do keys[#keys + 1] = tonumber(n) end
      list[#list + 1] = { tonumber(d), "press", keys }
    end
    local d2, text = l:match("^!type (%d+) (.*)$")
    if d2 then list[#list + 1] = { tonumber(d2), "type", text } end
    local d3 = l:match("^!shot (%d+)")
    if d3 then list[#list + 1] = { tonumber(d3), "shot" } end
  end
  return list
end

-- Typing is several frames a key; CPC text is CR LF. natkeyboard's coded
-- strings use {ENTER}; a brace that starts no code it knows is typed as it
-- is ("{{" is not an escape: it typed two).
local function coded(s)
  return s
end

local function finish(why)
  local text = table.concat(OUT):gsub("\r\n", "\n"):gsub("\r", "\n")
  if OUTFILE then
    local f = io.open(OUTFILE, "w"); f:write(text); f:close()
  else
    io.write(text)
  end
  if SHOT then SCR:snapshot(SHOT) end
  if TIMESF then
    local f = io.open(TIMESF, "w"); f:write(table.concat(TIMES, "\n") .. "\n"); f:close()
  end
  if PROFF then
    local f = io.open(PROFF, "w")
    for k, n in pairs(PROF) do
      local rom = k >> 16
      f:write(string.format("%04X %s %d\n", k & 0xFFFF,
        rom > 0 and ROMS[rom][1] or (k < 0x4000 and "firmware" or "ram"), n))
    end
    f:close()
  end
  if CARDLOG then
    local f = io.open(CARDLOG, "w")
    f:write(table.concat(CARD, " "), "\n")
    f:close()
  end
  -- LISP_DUMP="BC77-BC9F,B0C0-B0FF": RAM in hex on stderr, for debugging
  for a, b in (os.getenv("LISP_DUMP") or ""):gmatch("(%x+)-(%x+)") do
    local lo, hi = tonumber(a, 16), tonumber(b, 16)
    for row = lo, hi, 16 do
      local t = {}
      for i = row, math.min(row + 15, hi) do t[#t + 1] = string.format("%02X", MEM:read_u8(i)) end
      io.stderr:write(string.format("%04X: %s\n", row, table.concat(t, " ")))
    end
  end
  io.stderr:write("repl.lua: " .. why .. " after " .. F .. " frames\n")
  manager.machine:exit()
end

F, NEXT, SETTLE, DONEAT = 0, 1, 0, nil
NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F >= MAXF then finish("TIMEOUT") return end
  if TYPED and not NK.is_posting then
    -- a quick line may be answered before the typing is seen to end
    TYPED = false
    if ANSWERED then TIMES[#TIMES + 1] = "0\t" .. LINES[NEXT - 1] else T0 = F end
    if PENDING then
      local t = F
      for _, a in ipairs(PENDING) do
        t = t + a[1]
        ACTIONS[#ACTIONS + 1] = { t, a[2], a[3] }
        if a[2] == "press" then ACTIONS[#ACTIONS + 1] = { t + 8, "release", a[3] } end
      end
      PENDING = nil
    end
  end
  for i = #ACTIONS, 1, -1 do
    local a = ACTIONS[i]
    if a[1] == F then
      if a[2] == "press" then for _, k in ipairs(a[3]) do KEYFIELD[k]:set_value(1) end
      elseif a[2] == "release" then for _, k in ipairs(a[3]) do KEYFIELD[k]:set_value(0) end
      elseif a[2] == "type" then NK:post_coded(a[3])
      elseif a[2] == "shot" and SHOT then
        SHOTS = SHOTS + 1
        SCR:snapshot((SHOT:gsub("%.png$", "")) .. "-" .. SHOTS .. ".png")
      end
      table.remove(ACTIONS, i)
    end
  end
  if DONEAT then
    if F >= DONEAT then finish("done") end
    return
  end
  if WAITING and not NK.is_posting then
    SETTLE = SETTLE + 1
    -- The first keys after power-up are lost; give the machine a second.
    if SETTLE >= (NEXT == 1 and 50 or 3) then
      SETTLE, WAITING = 0, false
      if NEXT > #LINES then
        if #ACTIONS == 0 and not PENDING then DONEAT = F + 10
        else WAITING = true end      -- look again when they are done
      else
        local l = LINES[NEXT]; NEXT = NEXT + 1
        OUT[#OUT + 1] = l       -- the ROM's own newline follows
        NK:post_coded(" " .. coded(l) .. "{ENTER}")
        TYPED, ANSWERED = true, false
        local d = directives()
        if #d > 0 then PENDING = d end
      end
    end
  end
end)
