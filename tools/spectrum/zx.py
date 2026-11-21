#!/usr/bin/env python3
"""Type a file at CPC Lisp on an emulated ZX Spectrum +2A with a DivMMC
(ZEsarUX, headless), and print the transcript.

    tools/spectrum/zx.py [-b build/spectrum] [-d sd-dir] [-t seconds] file.lsp

MACH=spectrum tools/build.sh first. ZEsarUX starts a +2A (ROM 4.1) with no
video or sound, its remote protocol (ZRCP) on a free port, the DivMMC's
paging and esxDOS's calls served from a folder (-d; a fresh one if not
given), and its debug ports. Once its menu is up, the six images go into
their banks, the machine pages into the DivMMC's RAM and the resident part
at &5D00, all through ZRCP, and the CPU is sent to RS_BOOT -- the loader's
work done by hand (the real loader is tested on its own: -T LISP.TAP
through the +2A's Loader and ZEsarUX's tape traps; or -M card.mmc -B
steps, the real esxDOS on an SD card image (mkmmc.py), LISP.TAP from its
NMI browser by a user's steps -- esxtest.sh).

The file's lines are typed one at a time, each when the Lisp asks for one:
a breakpoint at EDHOOK (the REPL calls it before every line) makes ZEsarUX
set RS_HOOK, which this polls; the line goes into the machine page's paste
buffer (PA_BUF: page.asm), whence KEY_READ takes it as if typed, and the
machine page writes it into the transcript as its return is read -- typed
with a space in front, as the CPC's harness types it (read-line sees it),
which the transcript leaves out. Lines
starting with ! are the CPC harness's actions (emu/repl.lua), N frames (of
1/50 s, the Lisp's own clock) after the line before them was typed:

    !type N text   text given to the keys ({ENTER} is a return)
    !esc N         BREAK
    !press K N     the CPC's key K: its code given to the keys, if it has one
    !shot N file   a screenshot (.png), as -S
    !steps S       a user's steps (-B's), at once after the line before:
                   after a (quit), loading LISP.TAP again with -M
    !ppoke SYM HEX bytes into machine page A at its symbol, before the next
                   line: "!ppoke c_echo 00" makes (quit) reset the machine,
                   as on a real one, not end ZEsarUX

Everything the Lisp prints goes to ZEsarUX's debug byte file: the transcript,
CR LF made LF. After the last line, the next prompt ends it. Exit status 0;
"zx.py: TIMEOUT" (and the screen's text) on stderr if it stopped.
"""
import argparse, os, re, shutil, socket, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zrcp import Zrcp

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ZDIR = os.environ.get("ZESARUX_DIR",
                      os.path.expanduser("~/claude/spectrum/zesarux/ZEsarUX-13.0"))
MP_A = 14                       # the machine pages' DivMMC pages (firmware.asm)
BANKS = [("LISP.ROM", 0), ("LISPLIB.ROM", 1), ("LISPLIB2.ROM", 3),
         ("LISPLIB3.ROM", 4), ("LISPDEMO.ROM", 6), ("LISPVM.ROM", 7)]
# the CPC's key numbers (emu/repl.lua's !press) as the codes the keys give:
# the cursor keys up, right, down, left (+4 with SHIFT, 21; +8 with CTRL,
# 23), COPY, CLR, RETURN, ENTER, ESC, TAB, DEL
CPCKEYS = {0: 0xF0, 1: 0xF3, 2: 0xF1, 8: 0xF2, 9: 0xE0, 16: 0x10, 18: 13,
           6: 13, 66: 0xFC, 68: 9, 79: 0x7F}
CURSORS = (0, 1, 2, 8)


def syms(path):
    d = {}
    for l in open(path):
        f = l.split()
        if len(f) >= 2 and f[1].startswith("#"):
            d[f[0].upper()] = int(f[1][1:], 16)
    return d


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


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
            out.append((int(m.group(1)), "shot", m.group(2)))
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


class Spectrum:
    def __init__(self, build, sd, speed, log, tape=None, mmc=None):
        self.build = build
        self.port = free_port()
        self.trans = os.path.join(log, "transcript.bin")
        open(self.trans, "wb").close()
        self.out = open(os.path.join(log, "zesarux.log"), "wb")
        z = os.path.join(ZDIR, "zesarux")
        self.p = subprocess.Popen(
            [z, "--noconfigfile", "--machine", "P2A41", "--vo", "null", "--ao", "null",
             "--nowelcomemessage", "--quickexit",
             "--enable-remoteprotocol", "--remoteprotocol-port", str(self.port),
             "--hardware-debug-ports", "--hardware-debug-ports-byte-file", self.trans,
             "--divmmc-rom", os.path.join(ZDIR, "esxmmc085.rom")]
            + (["--enable-divmmc", "--enable-mmc", "--mmc-file", mmc] if mmc else
               ["--enable-divmmc-paging", "--enable-esxdos-handler", "--esxdos-root-dir", sd])
            + ["--emulatorspeed", str(speed)]
            + (["--tape", tape] if tape else [])
            + os.environ.get("ZX_ARGS", "").split(),
            stdout=self.out, stderr=subprocess.STDOUT, cwd=log)
        self.z = Zrcp(port=self.port, wait=15)
        self.lisp = syms(os.path.join(build, "lisp.sym"))
        self.page = syms(os.path.join(build, "lispm.sym"))
        self.res = syms(os.path.join(build, "resident.sym"))

    def boot_tape(self):
        """the tape loaded as a user loads it: ENTER at the +2A's menu, on
        its Loader (LOAD ""); ZEsarUX reads the tape through its ROM traps"""
        z = self.z
        time.sleep(0.5)
        z.cmd("send-keys-ascii 100 13")
        z.cmd("enable-breakpoints")
        z.cmd("set-breakpoint 1 PC=%XH" % self.lisp["EDHOOK"])
        z.cmd("set-breakpointaction 1 write %d 1" % self.res["RS_HOOK"])

    def steps(self, steps):
        """a user's steps at the machine, ;-separated: "w S" waits S
        seconds, "nmi" presses the DivMMC's NMI button, "k C..." gives the
        keys these characters (decimal codes), each held "kt MS" ms (60;
        at ten times the speed, a key held long repeats), "e K" a key event (ZRCP's
        send-keys-event: K, pressed then released), "shot F" a screenshot,
        "z CMD" any ZRCP command (its answer to stderr)"""
        kt = 60
        for st in steps.split(";"):
            st = st.strip()
            if not st:
                continue
            op, _, arg = st.partition(" ")
            if op == "w":
                time.sleep(float(arg))
            elif op == "nmi":
                self.z.cmd("generate-nmi")
            elif op == "kt":
                kt = int(arg)
            elif op == "k":
                self.z.cmd("send-keys-ascii %d %s" % (kt, arg))
            elif op == "e":
                self.z.cmd("send-keys-event %s 1" % arg)
                time.sleep(0.06)
                self.z.cmd("send-keys-event %s 0" % arg)
            elif op == "shot":
                shot(self, os.path.abspath(arg))
            elif op == "z":
                sys.stderr.write(self.z.cmd(arg))

    def hook(self):
        z = self.z
        z.cmd("enable-breakpoints")
        z.cmd("set-breakpoint 1 PC=%XH" % self.lisp["EDHOOK"])
        z.cmd("set-breakpointaction 1 write %d 1" % self.res["RS_HOOK"])

    def boot(self):
        time.sleep(0.5)               # the +2A's menu up (10x its speed)
        z = self.z
        z.cmd("enter-cpu-step")
        z.cmd("set-memory-zone 0")
        for f, bank in BANKS:
            z.cmd("load-binary %s %d 0" % (os.path.join(self.build, f), bank * 16384))
        z.cmd("set-memory-zone 3")
        z.cmd("load-binary %s %d 0" % (os.path.join(self.build, "LISPM.ROM"), MP_A * 8192))
        z.cmd("set-memory-zone -1")
        z.cmd("load-binary %s %d 0" % (os.path.join(self.build, "resident.bin"), 0x5D00))
        z.cmd("enable-breakpoints")
        z.cmd("set-breakpoint 1 PC=%XH" % self.lisp["EDHOOK"])
        z.cmd("set-breakpointaction 1 write %d 1" % self.res["RS_HOOK"])
        z.cmd("set-register PC=%XH" % self.res["RS_BOOT"])
        z.cmd("exit-cpu-step")

    def peek(self, addr, n=1):
        self.z.cmd("set-memory-zone -1")
        r = self.z.cmd("read-memory %d %d" % (addr, n)).strip()
        return bytes.fromhex(r[:2 * n])

    def poke(self, addr, data):
        self.z.cmd("set-memory-zone -1")
        self.z.cmd("write-memory-raw %d %s" % (addr, data.hex()))

    def ppoke(self, addr, data):
        """data into machine page A's RAM at its address (&2000-&3FFF)"""
        self.z.cmd("set-memory-zone 3")
        self.z.cmd("write-memory-raw %d %s" % (MP_A * 8192 + addr - 0x2000, data.hex()))

    def ppeek(self, addr, n=1):
        self.z.cmd("set-memory-zone 3")
        r = self.z.cmd("read-memory %d %d" % (MP_A * 8192 + addr - 0x2000, n)).strip()
        return bytes.fromhex(r[:2 * n])

    def frames(self):
        """the Lisp's clock, in frames (1/50 s)"""
        return int.from_bytes(self.peek(self.res["RS_FRAMES"], 4), "little") // 6

    def hooked(self):
        a = self.res["RS_HOOK"]
        if self.peek(a)[0]:
            self.poke(a, b"\0")
            return True
        return False

    def pasted(self):
        """the paste buffer empty again?"""
        return self.ppeek(self.page["PA_LEN"])[0] == 0

    def paste(self, text, record):
        """text given to the keys; record = n+1: into the transcript from
        its byte n on, 0: not"""
        b = text.encode("latin-1")[:255]
        self.ppoke(self.page["PA_BUF"], b)
        self.ppoke(self.page["PA_POS"], bytes([0, record]))
        self.ppoke(self.page["PA_LEN"], bytes([len(b)]))

    def screen(self):
        """the text on the screen, from the machine page's shadow"""
        d = self.ppeek(self.page["SHADOW"], 40 * 24)
        return "\n".join("|" + "".join(chr(c) if 32 <= c < 127 else "#"
                                       for c in d[r * 40:r * 40 + 40]) + "|"
                         for r in range(24))

    def close(self):
        try:
            if self.p.poll() is None:
                self.z.cmd("exit-emulator")
        except Exception:
            pass
        try:
            self.p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
        self.out.close()


ZXRGB = [(0, 0, 0), (0, 0, 0xD7), (0xD7, 0, 0), (0xD7, 0, 0xD7),
         (0, 0xD7, 0), (0, 0xD7, 0xD7), (0xD7, 0xD7, 0), (0xD7, 0xD7, 0xD7),
         (0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF),
         (0, 0xFF, 0), (0, 0xFF, 0xFF), (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)]


def shot(zx, path):
    """the screen's memory (bank 5 at &4000), drawn as the ULA shows it:
    a PNG twice the size, with a border"""
    from PIL import Image
    zx.z.cmd("set-memory-zone -1")
    m = bytearray()
    for a in range(0x4000, 0x5B00, 0x400):
        r = zx.z.cmd("read-memory %d %d" % (a, 0x400)).strip()
        m += bytes.fromhex(r[:0x800])
    try:
        border = zx.ppeek(zx.page["C_BORDER"])[0] & 7   # the Lisp's (page A)
    except Exception:
        border = 1
    img = Image.new("RGB", (256 + 32, 192 + 32), ZXRGB[border])
    px = img.load()
    for y in range(192):
        line = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for xb in range(32):
            b = m[line + xb]
            at = m[0x1800 + (y >> 3) * 32 + xb]
            br = 8 if at & 0x40 else 0
            ink, paper = ZXRGB[(at & 7) + br], ZXRGB[((at >> 3) & 7) + br]
            for i in range(8):
                px[16 + xb * 8 + i, 16 + y] = ink if b & (0x80 >> i) else paper
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(path)


def run(args):
    lines = open(args.file, encoding="latin-1").read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    log = tempfile.mkdtemp(prefix="zx-")
    sd = args.sd or os.path.join(log, "sd")
    os.makedirs(sd, exist_ok=True)
    tape = os.path.abspath(args.tape) if args.tape else None
    mmc = os.path.abspath(args.mmc) if args.mmc else None
    zx = Spectrum(os.path.abspath(args.build), os.path.abspath(sd), args.speed, log, tape, mmc)
    why = "done"
    try:
        deadline = time.time() + args.timeout
        if args.steps is not None:
            zx.hook()                   # first: the Lisp may start at once
            zx.steps(args.steps)
            while os.path.getsize(zx.trans) == 0 and time.time() < deadline:
                time.sleep(0.05)
        elif tape:
            zx.boot_tape()
            # RS_HOOK is BASIC's RAM until the Lisp starts (rs_boot clears
            # it): it counts once the banner is in the transcript
            while os.path.getsize(zx.trans) == 0 and time.time() < deadline:
                time.sleep(0.05)
        else:
            zx.boot()
        i = 0                       # the next line
        todo = []                   # actions: (frame, kind, data)
        done_at = None
        while True:
            if zx.p.poll() is not None:
                why = "quit"            # (quit): the emulator has ended
                break
            if time.time() > deadline:
                why = "TIMEOUT"
                break
            now = None
            if todo:
                now = zx.frames()
                while todo and todo[0][0] <= now and zx.pasted():
                    _, kind, data = todo.pop(0)     # in order, one at a time
                    if kind == "shot":
                        shot(zx, os.path.abspath(data))
                    else:
                        zx.paste(data, 0)
            if done_at is not None:
                if not todo and time.time() >= done_at:
                    break
                time.sleep(0.01)
                continue
            try:
                hooked = zx.hooked()
            except (EOFError, OSError):
                why = "quit"
                break
            if hooked:
                while i < len(lines) and lines[i].startswith("!"):
                    m = re.match(r"^!ppoke (\S+) ([0-9A-Fa-f]+)$", lines[i])
                    if m:
                        zx.ppoke(zx.page[m.group(1).upper()], bytes.fromhex(m.group(2)))
                    i += 1
                if i >= len(lines):
                    done_at = time.time() + 0.2
                    continue
                while not zx.pasted():
                    time.sleep(0.005)
                zx.paste(" " + lines[i] + "\r", 2)
                t = zx.frames()
                for n, kind, data in actions(lines, i):
                    t += n
                    todo.append((t, kind, data))
                i += 1
                if i < len(lines) and lines[i].startswith("!steps "):
                    # RS_HOOK is BASIC's RAM until the Lisp starts again:
                    # it counts once the new banner is in the transcript
                    size = os.path.getsize(zx.trans)
                    zx.steps(lines[i][7:])
                    while os.path.getsize(zx.trans) == size and time.time() < deadline:
                        time.sleep(0.05)
                    time.sleep(0.2)
            else:
                time.sleep(0.005)
        if args.shot:
            shot(zx, os.path.abspath(args.shot))
        for pk in args.peek or []:
            a, _, n = pk.partition(":")
            sys.stderr.write("zx.py: &%s: %s\n" % (a, zx.peek(int(a, 16), int(n or 1)).hex(" ")))
    finally:
        if why == "TIMEOUT":
            try:
                sys.stderr.write("zx.py: TIMEOUT; the screen:\n" + zx.screen() + "\n")
                r = zx.z.cmd("get-registers")
                sys.stderr.write("zx.py: " + r.strip() + "\n")
                sys.stderr.write("zx.py: RS_HOOK %d, PA_LEN %d, breakpoints: %s\n" % (
                    zx.peek(zx.res["RS_HOOK"])[0], zx.ppeek(zx.page["PA_LEN"])[0],
                    " ".join(l for l in zx.z.cmd("get-breakpoints").split("\n")
                             if "Enabled" in l or "1:" in l)[:300]))
            except Exception as e:
                sys.stderr.write("zx.py: TIMEOUT (%s)\n" % e)
        zx.close()
    d = open(zx.trans, "rb").read().decode("latin-1")
    d = d.replace("\r\n", "\n").replace("\r", "\n")
    sys.stdout.write(d)
    if not args.keep:
        shutil.rmtree(log, ignore_errors=True)
    else:
        sys.stderr.write("zx.py: kept " + log + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-b", "--build", default=os.environ.get("SPECTRUM_BUILD",
                                                         os.path.join(ROOT, "build", "spectrum")))
    ap.add_argument("-d", "--sd", help="the folder esxDOS serves (a fresh one if not given)")
    ap.add_argument("-t", "--timeout", type=float, default=float(os.environ.get("TIMEOUT", 300)))
    ap.add_argument("-s", "--speed", type=int, default=int(os.environ.get("ZX_SPEED", 1000)),
                    help="ZEsarUX's speed, in percent")
    ap.add_argument("-k", "--keep", action="store_true", help="keep the log folder")
    ap.add_argument("-S", "--shot", help="a screenshot at the end (.png)")
    ap.add_argument("-T", "--tape", help="load from this tape (LISP.TAP) as the machine would,"
                    " not through ZRCP")
    ap.add_argument("-M", "--mmc", help="an SD card image (mkmmc.py) for the real esxDOS,"
                    " not ZEsarUX's handler of its calls")
    ap.add_argument("-B", "--steps", help="boot by a user's steps (Spectrum.steps) and wait"
                    " for the banner, not through ZRCP")
    ap.add_argument("-P", "--peek", action="append",
                    help="HEX[:N]: N bytes of memory there, shown at the end")
    ap.add_argument("file")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
