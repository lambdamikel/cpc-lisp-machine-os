-- CP/M on an emulated CPC in MAME: boot it (|CPM), type lines into a
-- program, and log what it prints, each character with its frame -- for
-- timing Lisps of the day that run under CP/M (docs/benchmarks.md).
--
--   CPM_IN      the lines to type, one at a time, each when the program
--               reads the console again (the CCP's first, e.g. LISP)
--   CPM_OUT     the log: "frame<TAB>hex" a character printed, "IN<TAB>
--               frame<TAB>line" a line typed
--   CPM_FRAMES  the most frames to run (default 30000)
--   CPM_BOOT    what to type at BASIC first (default |cpm)
--   CPM_SHOT    a screenshot at the end, optional
--   CPM_PROMPT  the program's prompt (muLISP: "$ "): the next line is typed
--               when the output ends in it -- for a program that calls
--               CONIN only once a key is waiting
--   CPM_EOL     what ends a typed line (default \r, the RETURN key)
--
-- A line ending in a backslash goes on with the next one, typed at once
-- (a definition longer than a line: the program does not prompt between)
--
-- Once CP/M is up -- a JP at &0000 into the top 16 KB, the BIOS's warm
-- boot -- its jump table is found from it: CONIN at BIOS+9, CONOUT at
-- BIOS+12. A tap on CONOUT's first fetch logs C, the character; one on
-- CONIN types the next line when nothing is being typed (CONIN is called
-- for each character of a line, so the rest of it is already on its way).
-- It ends when no line is left and CONIN has waited 300 frames.

NK  = manager.machine.natkeyboard; NK.in_use = true
CPU = manager.machine.devices[":maincpu"]
MEM = CPU.spaces["program"]
SCR = manager.machine.screens[":screen"]

local function getenv(n, d) local v = os.getenv(n); if v == nil or v == "" then return d end; return v end
INFILE = getenv("CPM_IN", nil)
OUTFILE = getenv("CPM_OUT", "/dev/stdout")
MAXF = tonumber(getenv("CPM_FRAMES", "30000"))
BOOT = getenv("CPM_BOOT", "|cpm")
SHOT = getenv("CPM_SHOT", nil)

LINES, NEXT = {}, 1
if INFILE then for l in io.lines(INFILE) do LINES[#LINES + 1] = l end end
LOG = {}
TAIL = ""
F = 0
HOOKED = false
LASTIN = 0          -- the frame CONIN was last entered
POSTED = -1000      -- the frame the last line was typed

local function finish(why)
  local f = io.open(OUTFILE, "w")
  f:write(table.concat(LOG, "\n") .. "\nEND\t" .. F .. "\t" .. why .. "\n")
  if os.getenv("CPM_DEBUG") then
    f:write(string.format("PC\t%04X SP %04X\n", CPU.state["PC"].value, CPU.state["SP"].value))
    local pc = CPU.state["PC"].value
    local t = {}
    for a = pc - 48, pc + 47 do t[#t + 1] = string.format("%02X", MEM:read_u8(a & 0xFFFF)) end
    f:write(string.format("MEM\t%04X\t%s\n", (pc - 48) & 0xFFFF, table.concat(t, " ")))
  end
  f:close()
  if SHOT then SCR:snapshot(SHOT) end
  manager.machine:exit()
end

local function nextline()
  local eol = os.getenv("CPM_EOL") or "\r"
  local l = LINES[NEXT]; NEXT = NEXT + 1
  while l:sub(-1) == "\\" and LINES[NEXT] do
    l = l:sub(1, -2) .. eol .. LINES[NEXT]; NEXT = NEXT + 1
  end
  return l, eol
end

local function hook(bios)
  local const, conin, conout = bios + 6, bios + 9, bios + 12
  LASTST = -1
  TAPS = MEM:install_read_tap(const, const, "const", function(offset, data, mask)
    if CPU.state["PC"].value == const and os.getenv("CPM_DEBUG") and F ~= LASTST then
      LASTST = F
      LOG[#LOG + 1] = string.format("ST\t%d", F)
    end
    return data
  end)
  TAPO = MEM:install_read_tap(conout, conout, "conout", function(offset, data, mask)
    if CPU.state["PC"].value == conout then
      local c = CPU.state["C"].value & 0xFF
      LOG[#LOG + 1] = string.format("%d\t%02X", F, c)
      LASTOUT = F
      TAIL = (TAIL .. string.char(c)):sub(-16)
    end
    return data
  end)
  TAPI = MEM:install_read_tap(conin, conin, "conin", function(offset, data, mask)
    if CPU.state["PC"].value == conin then
      if os.getenv("CPM_DEBUG") then LOG[#LOG + 1] = string.format("CI\t%d", F) end
      LASTIN = F
      if not NK.is_posting and F - POSTED > 25 and LINES[NEXT] then
        local l, eol = nextline()
        LOG[#LOG + 1] = string.format("IN\t%d\t%s", F, l)
        NK:post_coded(l .. eol)
        POSTED = F
      end
    end
    return data
  end)
  HOOKED = true
end

NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F == 60 then NK:post_coded(BOOT .. "{ENTER}") end
  if F >= MAXF then finish("TIMEOUT") return end
  if not HOOKED and F > 80 and MEM:read_u8(0) == 0xC3 then
    local w = MEM:read_u8(1) | (MEM:read_u8(2) << 8)
    if w >= 0xC003 then hook(w - 3) end
  end
  -- a program that calls CONIN only once a key is waiting (muLISP): the
  -- next line once the output ends in CPM_PROMPT and has been quiet a
  -- second -- after output that followed the last line typed
  local prompt = os.getenv("CPM_PROMPT")
  if HOOKED and prompt and LINES[NEXT] and not NK.is_posting and POSTED > 0
     and (LASTOUT or 0) > POSTED and F - LASTOUT > 50
     and TAIL:sub(-#prompt) == prompt then
    local l, eol = nextline()
    LOG[#LOG + 1] = string.format("IN\t%d\t%s", F, l)
    NK:post_coded(l .. eol)
    POSTED = F
  end
  if HOOKED and not LINES[NEXT] and not NK.is_posting and F - POSTED > 300 then
    if prompt then        -- the prompt back after the last line's output
      if (LASTOUT or 0) > POSTED and F - LASTOUT > 50
         and TAIL:sub(-#prompt) == prompt then finish("done") end
    elseif LASTIN > POSTED and F - LASTIN > 300 then
      finish("done")
    end
  end
end)
