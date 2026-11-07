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
--
-- Output is caught by tapping opcode fetches at &BB5A, the TXT OUTPUT
-- vector: whoever prints through the firmware passes there, and A holds the
-- character. Input is typed through natkeyboard, which drops the first
-- character of a posted string often enough to matter, so every line is
-- posted with a leading space -- harmless to a Lisp reader.
--
-- A line "!esc N" is not typed: it holds ESC down (through the key matrix,
-- for 10 frames) N frames after the line before it has been typed -- while
-- that line is running. natkeyboard's press would be too brief for a ROM
-- that polls the key with KM TEST KEY.
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
ESCAT, ESCDELAY = nil, nil

-- ESC is key 66: row 8, bit 2
ESCFIELD = nil
for name, f in pairs(manager.machine.ioport.ports[":kbrow.8"].fields) do
  if f.mask == 4 and name ~= "Keyboard" then ESCFIELD = f end
end

LINES = {}
if INFILE then
  for l in io.lines(INFILE) do LINES[#LINES + 1] = l end
end

OUT = {}
TAPO = MEM:install_read_tap(0xBB5A, 0xBB5A, "txtout", function(offset, data, mask)
  local pc = CPU.state["PC"].value
  if pc == 0xBB5A or pc == 0xBB5B then
    OUT[#OUT + 1] = string.char(CPU.state["A"].value & 0xFF)
  end
  return data
end)

WAITING = false      -- the ROM has entered EDIT and nothing is typed yet
EDITS = 0
TAPE = MEM:install_read_tap(EDITV, EDITV, "edit", function(offset, data, mask)
  local pc = CPU.state["PC"].value
  if pc == EDITV or pc == EDITV + 1 then
    WAITING = true
    EDITS = EDITS + 1
    if T0 then TIMES[#TIMES + 1] = (F - T0) .. "\t" .. LINES[NEXT - 1]; T0 = nil end
  end
  return data
end)

-- Typing a key is several frames; CPC text is CR LF. natkeyboard's coded
-- strings use {ENTER}; braces in the text itself are escaped as {{ and }}.
local function coded(s)
  s = s:gsub("{", "\1"):gsub("}", "\2")
  s = s:gsub("\1", "{{"):gsub("\2", "}}")
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
  io.stderr:write("repl.lua: " .. why .. " after " .. F .. " frames\n")
  manager.machine:exit()
end

F, NEXT, SETTLE, DONEAT = 0, 1, 0, nil
NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F >= MAXF then finish("TIMEOUT") return end
  if TYPED and not NK.is_posting then
    TYPED, T0 = false, F
    if ESCDELAY then ESCAT, ESCDELAY = F + ESCDELAY, nil end
  end
  if ESCAT then
    if F == ESCAT then ESCFIELD:set_value(1) end
    if F == ESCAT + 10 then ESCFIELD:set_value(0); ESCAT = nil end
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
        DONEAT = F + 10
      else
        local l = LINES[NEXT]; NEXT = NEXT + 1
        OUT[#OUT + 1] = l       -- the ROM's own newline follows
        NK:post_coded(" " .. coded(l) .. "{ENTER}")
        TYPED = true
        local esc = LINES[NEXT] and LINES[NEXT]:match("^!esc (%d+)")
        if esc then ESCDELAY = tonumber(esc); NEXT = NEXT + 1 end
      end
    end
  end
end)
