#!/usr/bin/env python3
"""Type a file at CPC Lisp on an emulated MSX1 (openMSX, headless), and
print the transcript.

    tools/msx/msx.py [-b build/msx] [-d dir] [-t seconds] [-S shot.png] file.lsp

MACH=msx tools/build.sh first. openMSX starts a Toshiba HX-10 (Mike's
machine: its ROM, his dump, in ~/claude/msx/home -- OPENMSX_HOME) with a 512
KB memory mapper and a Sunrise IDE with Nextor 2.1.0 (its ROM and DOS files
from Konamiman's release, ~/claude/msx/files: none of it ours, never in this
repo), no video or sound, its throttle off. The hard disc is made afresh
(tools/spectrum/mkmmc.py: FAT16): NEXTOR.SYS and COMMAND2.COM, an
AUTOEXEC.BAT of "CD LISP" and "LISP /T", and the folder LISP -- the SD
card's files (build/msx/sd). So Lisp starts as a user starts it; /T sends
everything it prints to port &2F too: the transcript. With -d, LISP.COM and
LISP.IMG are in the folder BIN instead, started from LISP (\\BIN\\LISP /T),
which holds that folder's files alone (the tests: (dir) shows theirs).

openMSX runs a Tcl script made here, in step with the emulation: a
watchpoint on port &2F writes the transcript, one on &2E ((quit) under the
harness) ends it; a breakpoint at EDHOOK (the REPL calls it before every
line) gives the next line to machine page A's paste buffer (PA_BUF: page.asm,
in its mapper segment, written through openMSX's debuggable of the mapper's
RAM), whence KEY_READ takes it as if typed, and the machine page writes it
into the transcript as its return is read -- typed with a space in front, as
the CPC's harness types it (read-line sees it), which the transcript leaves
out. Lines starting with ! are the CPC harness's actions (emu/repl.lua), N
frames (1/50 s) after the line before them was typed:

    !type N text   text given to the keys ({ENTER} is a return)
    !esc N         ESC
    !press K N     the CPC's key K: its code given to the keys, if it has one
    !shot N file   a screenshot (.png), as -S
    !ppoke SYM HEX bytes into machine page A at its symbol, before the next
                   line

After the last line, the next prompt ends it. Exit status 0; "msx.py:
TIMEOUT" (and the screen's text) on stderr if it stopped.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MSXDIR = os.path.expanduser(os.environ.get("MSX_DIR", "~/claude/msx"))
MACHINE = os.environ.get("MSX_MACHINE", "Toshiba_HX-10")
RAMEXT = "ram512k"
RAMDBG = "512k External RAM"   # openMSX's debuggable of the mapper's RAM
RS_SEGS = 0x0123                # jumps.asm: RESIDENT+35; SEG_A = +6
# the CPC's key numbers (emu/repl.lua's !press) as the codes the keys give:
# the cursor keys up, right, down, left (+4 with SHIFT, 21; +8 with CTRL,
# 23), COPY, CLR, RETURN, ENTER, ESC, TAB, DEL
CPCKEYS = {0: 0xF0, 1: 0xF3, 2: 0xF1, 8: 0xF2, 9: 0xE0, 16: 0x10, 18: 13,
           6: 13, 66: 0xFC, 68: 9, 79: 0x7F}
CURSORS = (0, 1, 2, 8)
# the VDP's colours (TMS9918), for screenshots
VDPRGB = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
          (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
          (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
          (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]


def syms(path):
    d = {}
    for l in open(path):
        f = l.split()
        if len(f) >= 2 and f[1].startswith("#"):
            d[f[0].upper()] = int(f[1][1:], 16)
    return d


def actions(lines, i):
    """The ! lines after line i: [(frames, kind, data)]"""
    out = []
    j = i + 1
    while j < len(lines) and lines[j].startswith("!"):
        l = lines[j]
        m = re.match(r"^!type (\d+) (.*)$", l)
        if m:
            out.append((int(m.group(1)), "type", m.group(2).replace("{ENTER}", "\r")))
        m = re.match(r"^!shot (\d+) (\S+)$", l)
        if m:
            out.append((int(m.group(1)), "shot", os.path.abspath(m.group(2))))
        m = re.match(r"^!esc (\d+)", l)
        if m:
            out.append((int(m.group(1)), "type", "\xfc"))
        m = re.match(r"^!press ([\d+]+) (\d+)", l)
        if m:
            ks = [int(k) for k in m.group(1).split("+")]
            code = CPCKEYS.get(ks[-1])
            if code is not None and ks[-1] in CURSORS:
                code += 4 * (21 in ks) + 8 * (23 in ks)
            if code is not None:
                out.append((int(m.group(2)), "type", chr(code)))
        j += 1
    return out


def tcl_str(s):
    """s (bytes 0-255) as a Tcl word"""
    out = []
    for c in s:
        o = ord(c)
        if c.isascii() and (c.isalnum() or c in " .,:;-_+*/=<>()'\"!?&%#@~^|`"):
            out.append("\\" + c if c in '"' else c)
        else:
            out.append("\\x%02x" % o)
    return '"' + "".join(out).replace("$", "\\$").replace("[", "\\[").replace("]", "\\]") + '"'


def script(lines, core, page, log, timeout, shot):
    """the Tcl that runs the session: [(kind, data)] for each step"""
    steps = []                  # per REPL line: (ppokes, text, actions)
    i = 0
    while i < len(lines):
        pp = []
        while i < len(lines) and lines[i].startswith("!"):
            m = re.match(r"^!ppoke (\S+) ([0-9A-Fa-f]+)$", lines[i])
            if m:
                pp.append((page[m.group(1).upper()], bytes.fromhex(m.group(2))))
            i += 1
        if i >= len(lines):
            break
        steps.append((pp, " " + lines[i] + "\r", actions(lines, i)))
        i += 1
    t = []
    w = t.append
    w("set throttle off")
    w("set ::log %s" % tcl_str(log))
    w("set ::trans [open [file join $::log trans.bin] w]")
    w("fconfigure $::trans -translation binary -encoding binary")
    w("set ::started 0")
    w("set ::step 0")
    w("set ::done 0")
    w("set ::nshot 0")
    w("set ::pending 0")
    w("set ::RS_SEGS %d" % RS_SEGS)
    for n in ("PA_BUF", "PA_LEN", "PA_POS", "PA_REC", "SHADOW", "C_BORDER"):
        w("set ::%s %d" % (n, page[n] - 0x8000))
    w("set ::steps {}")
    for pp, text, acts in steps:
        ppl = " ".join("[list %d %s]" % (a - 0x8000, tcl_str("".join(map(chr, d)))) for a, d in pp)
        al = " ".join("[list %d %s %s]" % (n, k, tcl_str(d)) for n, k, d in acts)
        w("lappend ::steps [list [list %s] %s [list %s]]" % (ppl, tcl_str(text), al))
    w(r"""
proc segbase {} { return [expr {[debug read memory [expr {$::RS_SEGS + 6}]] * 16384}] }
proc pwrite {off data} { debug write_block {%s} [expr {[segbase] + $off}] $data }
proc pread {off} { return [debug read {%s} [expr {[segbase] + $off}]] }
proc pasted {} {
  set n [pread $::PA_LEN]
  return [expr {$n == 0 || [pread $::PA_POS] >= $n}]
}
proc paste {text rec} {
  pwrite $::PA_LEN "\x00"
  pwrite $::PA_BUF $text
  pwrite $::PA_REC [format %%c $rec]
  pwrite $::PA_POS "\x00"
  pwrite $::PA_LEN [format %%c [string length $text]]
}
proc tchar {} {
  puts -nonewline $::trans [format %%c $::wp_last_value]
  set ::started 1
}
proc quitnow {} {
  if {$::done} return
  set ::done 1
  if {[info exists ::endshot]} { shot "$::endshot.vram" }
  flush $::trans
  close $::trans
  exit
}
proc shot {path} {
  set f [open $path w]
  fconfigure $f -translation binary -encoding binary
  puts -nonewline $f [debug read_block VRAM 0 16384]
  puts -nonewline $f [format %%c [pread $::C_BORDER]]
  close $f
}
proc act {kind data} {
  if {$kind eq "shot"} { incr ::nshot; shot "$data.vram"; incr ::pending -1; return }
  if {![pasted]} { after time 0.02 [list act $kind $data]; return }
  paste $data 0
  incr ::pending -1
}
proc ending {} {
  if {$::pending > 0} { after time 0.05 ending; return }
  after time 20 quitnow
}
proc hook {} {
  if {!$::started} return
  if {$::step >= [llength $::steps]} {
    # the prompt after the last line ends it -- once its keys are given
    if {$::pending == 0} { after time 0.05 quitnow } else { ending }
    return
  }
  lassign [lindex $::steps $::step] pp text acts
  incr ::step
  foreach p $pp { lassign $p off data; pwrite $off $data }
  paste $text 2
  set d 0.0
  foreach a $acts {
    lassign $a n kind data
    set d [expr {$d + $n / 50.0}]
    incr ::pending
    after time $d [list act $kind $data]
  }
}
proc timeout {} {
  set f [open [file join $::log timeout.txt] w]
  puts $f "pc [format %%04X [reg pc]] sp [format %%04X [reg sp]]"
  if {[catch {set s [get_screen]}] == 0} { puts $f "screen 0:\n$s" }
  if {$::started} {
    set sh ""
    for {set r 0} {$r < 24} {incr r} {
      for {set c 0} {$c < 40} {incr c} {
        append sh [format %%c [pread [expr {$::SHADOW + 40 * $r + $c}]]]
      }
      append sh "\n"
    }
    puts $f "shadow:\n$sh"
  }
  close $f
  quitnow
}
debug set_watchpoint write_io 0x2F {} tchar
debug set_watchpoint write_io 0x2E {} {after time 0.05 quitnow}
debug set_bp %d {} hook
after realtime %d timeout
""" % (RAMDBG, RAMDBG, core["EDHOOK"], int(timeout)))
    if shot:
        t.insert(1, "set ::endshot %s" % tcl_str(os.path.abspath(shot)))
    return "\n".join(t) + "\n"


def vram_png(vram, path):
    """screen 2 from a VRAM dump (+ the border's colour), as the VDP shows it:
    a PNG twice the size, with a border"""
    from PIL import Image
    border = VDPRGB[vram[16384] & 15] if len(vram) > 16384 else VDPRGB[4]
    img = Image.new("RGB", (256 + 32, 192 + 32), border)
    px = img.load()
    for y in range(192):
        for xb in range(32):
            off = (y >> 3) * 256 + xb * 8 + (y & 7)
            b, col = vram[off], vram[0x2000 + off]
            fg, bg = VDPRGB[col >> 4] if col >> 4 else border, VDPRGB[col & 15] if col & 15 else border
            for i in range(8):
                px[16 + xb * 8 + i, 16 + y] = fg if b & (0x80 >> i) else bg
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(path)


def disc(build, folder, out):
    """the hard disc: DOS, AUTOEXEC.BAT and Lisp -- in the folder LISP with
    the SD card's files, as a user has it; or, with a folder given (-d), in
    BIN, and LISP holding that folder's files only (the tests': (dir) shows
    theirs alone)"""
    stage = os.path.join(os.path.dirname(out), "stage")
    lisp = os.path.join(stage, "LISP")
    os.makedirs(lisp)
    for f in ("NEXTOR.SYS", "COMMAND2.COM"):
        shutil.copy(os.path.join(MSXDIR, "files", f), stage)
    sd = os.path.join(build, "sd")
    if folder:
        bin_ = os.path.join(stage, "BIN")
        os.makedirs(bin_)
        for f in ("LISP.COM", "LISP.IMG"):
            shutil.copy(os.path.join(sd, f), bin_)
        run = b"\\BIN\\LISP /T"
        src = folder
    else:
        run = b"LISP /T"
        src = sd
    with open(os.path.join(stage, "AUTOEXEC.BAT"), "wb") as f:
        f.write(b"CD LISP\r\n" + run + b"\r\n")
    for n in os.listdir(src):
        p = os.path.join(src, n)
        if os.path.isfile(p):
            shutil.copy(p, os.path.join(lisp, n.upper()))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "spectrum", "mkmmc.py"),
                    out, "-m", "32", stage], check=True)


def run(args):
    lines = open(args.file, encoding="latin-1").read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    build = os.path.abspath(args.build)
    log = tempfile.mkdtemp(prefix="msx-")
    hd = os.path.join(log, "hd.dsk")
    disc(build, os.path.abspath(args.dir) if args.dir else None, hd)
    core = syms(os.path.join(build, "lisp.sym"))
    page = syms(os.path.join(build, "lispm.sym"))
    tcl = os.path.join(log, "run.tcl")
    with open(tcl, "w", encoding="latin-1") as f:
        f.write(script(lines, core, page, log, args.timeout, args.shot))
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy",
               OPENMSX_HOME=os.path.join(MSXDIR, "home"))
    why = "done"
    with open(os.path.join(log, "openmsx.log"), "w") as olog:
        p = subprocess.Popen(["openmsx", "-machine", MACHINE, "-ext", RAMEXT,
                              "-ext", "SunriseIDE_Nextor", "-hda", hd,
                              "-command", "set renderer none", "-script", tcl],
                             cwd=log, env=env, stdout=olog, stderr=subprocess.STDOUT)
        try:
            p.wait(timeout=args.timeout + 30)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
            why = "TIMEOUT"
    tf = os.path.join(log, "timeout.txt")
    if os.path.exists(tf):
        why = "TIMEOUT"
        sys.stderr.write("msx.py: TIMEOUT\n" + open(tf, encoding="latin-1").read())
    elif why == "TIMEOUT":
        sys.stderr.write("msx.py: TIMEOUT (openMSX killed)\n")
    # screenshots: VRAM dumps made into PNGs
    shots = []
    for l in lines:
        m = re.match(r"^!shot \d+ (\S+)$", l)
        if m:
            shots.append(os.path.abspath(m.group(1)))
    if args.shot:
        shots.append(os.path.abspath(args.shot))
    for s in shots:
        if os.path.exists(s + ".vram"):
            vram_png(open(s + ".vram", "rb").read(), s)
            os.remove(s + ".vram")
    tr = os.path.join(log, "trans.bin")
    d = open(tr, "rb").read().decode("latin-1") if os.path.exists(tr) else ""
    d = d.replace("\r\n", "\n").replace("\r", "\n")
    sys.stdout.write(d)
    if args.keep or why == "TIMEOUT" and os.environ.get("MSX_KEEP"):
        sys.stderr.write("msx.py: kept " + log + "\n")
    else:
        shutil.rmtree(log, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-b", "--build", default=os.environ.get("MSX_BUILD",
                                                         os.path.join(ROOT, "build", "msx")))
    ap.add_argument("-d", "--dir", help="the folder LISP's files (Lisp itself in BIN then)")
    ap.add_argument("-t", "--timeout", type=float, default=float(os.environ.get("TIMEOUT", 300)))
    ap.add_argument("-k", "--keep", action="store_true", help="keep the log folder")
    ap.add_argument("-S", "--shot", help="a screenshot at the end (.png)")
    ap.add_argument("file")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
