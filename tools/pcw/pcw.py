#!/usr/bin/env python3
"""Type a file at CPC Lisp on an emulated Amstrad PCW 8256 (ZEsarUX,
headless), and print the transcript.

    tools/pcw/pcw.py [-b build/pcw] [-f file:NAME]... [-t seconds] file.lsp

MACH=pcw tools/build.sh first. A disc is made for the run (mkdisk.py: the
boot sector, the loader, the resident part with RS_HARN set -- the
harness's mark --, LISP.IMG, and the -f files) and ZEsarUX boots it as a
PCW boots: its boot program, our boot sector, the loader. -m 8512: an
8512 (512 KB). -k keeps the run's folder (the disc as Lisp left it is
disc.dsk there: ZEsarUX writes it back).

The file's lines are typed one at a time, each when the Lisp asks for one:
a breakpoint at EDHOOK (the REPL calls it before every line) makes ZEsarUX
set RS_HOOK, which this polls; the line goes into machine page A's paste
buffer (PA_BUF: page.asm), whence KEY_READ takes it as if typed, and the
page writes it into the transcript as its return is read -- typed with a
space in front, as the CPC's harness types it (read-line sees it), which
the transcript leaves out. Everything the Lisp prints goes into the
transcript's ring (T_BUF, T_IN, T_OUT in page A), which this empties as
it goes (the Lisp waits while it is full); CR LF made LF. Lines starting
with ! are the CPC harness's actions (emu/repl.lua), N frames (of 1/50 s,
the Lisp's own clock: RS_FRAMES / 6) after the line before them was typed:

    !type N text   text given to the keys ({ENTER} is a return)
    !esc N         STOP
    !press K N     the CPC's key K: its code given to the keys, if it has one
    !shot N file   a screenshot (.png), as -S

After the last line, the next prompt ends it; (quit) ends it too
(RS_QUITF). Exit status 0; "pcw.py: TIMEOUT" (and the screen's text) on
stderr if it stopped.
"""
import argparse, os, re, shutil, socket, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "spectrum"))
from zrcp import Zrcp

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ZDIR = os.environ.get("ZESARUX_DIR",
                      os.path.expanduser("~/claude/spectrum/zesarux/ZEsarUX-13.0"))
BL_LO, BL_PA = 4, 14                    # mach/pcw/firmware.asm
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


class PCW:
    def __init__(self, build, files, speed, log, machine):
        self.build = build
        self.port = free_port()
        self.disc = os.path.join(log, "disc.dsk")
        subprocess.check_call(
            [sys.executable, os.path.join(ROOT, "tools", "pcw", "mkdisk.py"), "-o", self.disc,
             "--boot", os.path.join(build, "BOOT.BIN"),
             "--resident", os.path.join(build, "RESIDENT.BIN"), "--hook",
             os.path.join(build, "LISP.IMG")] + files)
        self.out = open(os.path.join(log, "zesarux.log"), "wb")
        z = os.path.join(ZDIR, "zesarux")
        self.p = subprocess.Popen(
            [z, "--noconfigfile", "--machine", machine, "--vo", "null", "--ao", "null",
             "--nowelcomemessage", "--quickexit",
             "--enable-remoteprotocol", "--remoteprotocol-port", str(self.port),
             "--emulatorspeed", str(speed),
             "--enable-dsk", "--dsk-file", self.disc, "--dsk-persistent-writes",
             "--dsk-pcw-no-failback-cpm-when-no-boot"]
            + os.environ.get("ZX_ARGS", "").split(),
            stdout=self.out, stderr=subprocess.STDOUT, cwd=log)
        self.z = Zrcp(port=self.port, wait=15)
        self.lisp = syms(os.path.join(build, "lisp.sym"))
        self.page = syms(os.path.join(build, "lispm.sym"))
        self.res = syms(os.path.join(build, "resident.sym"))
        self.z.cmd("set-memory-zone 0")
        self.z.cmd("enable-breakpoints")
        self.z.cmd("set-breakpoint 1 PC=%XH" % self.lisp["EDHOOK"])
        self.z.cmd("set-breakpointaction 1 write %d 1" % self.res["RS_HOOK"])
        self.text = bytearray()

    # the RAM, by block (ZEsarUX's zone 0: block n at n * 16 KB)
    def peek(self, addr, n=1, block=BL_LO):
        off = block * 16384 + (addr & 0x3FFF)
        r = self.z.cmd("read-memory %d %d" % (off, n)).strip()
        return bytes.fromhex(r[:2 * n])

    def poke(self, addr, data, block=BL_LO):
        off = block * 16384 + (addr & 0x3FFF)
        self.z.cmd("write-memory-raw %d %s" % (off, data.hex()))

    def ppeek(self, addr, n=1):
        return self.peek(addr, n, BL_PA)

    def ppoke(self, addr, data):
        self.poke(addr, data, BL_PA)

    def frames(self):
        """the Lisp's clock, in frames (1/50 s)"""
        return int.from_bytes(self.peek(self.res["RS_FRAMES"], 4), "little") // 6

    def hooked(self):
        a = self.res["RS_HOOK"]
        if self.peek(a)[0]:
            self.poke(a, b"\0")
            return True
        return False

    def quitted(self):
        return self.peek(self.res["RS_QUITF"])[0] != 0

    def drain(self):
        """the transcript's ring emptied into self.text; True if it had
        something. T_IN is read until two reads agree (the machine may be
        between its two bytes)."""
        size = 0x1000
        while True:
            a = self.ppeek(self.page["T_IN"], 4)
            b = self.ppeek(self.page["T_IN"], 4)
            if a[:2] == b[:2]:
                break
        t_in, t_out = a[0] | a[1] << 8, a[2] | a[3] << 8
        if t_in == t_out:
            return False
        base = self.page["T_BUF"]
        if t_in > t_out:
            self.text += self.big(base + t_out, t_in - t_out)
        else:
            self.text += self.big(base + t_out, size - t_out)
            if t_in:
                self.text += self.big(base, t_in)
        self.ppoke(self.page["T_OUT"], bytes([t_in & 255, t_in >> 8]))
        return True

    def big(self, addr, n):
        """n bytes of page A from addr, in pieces"""
        out = b""
        while n > 0:
            k = min(n, 1024)
            out += self.ppeek(addr, k)
            addr += k
            n -= k
        return out

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
        d = self.ppeek(self.page["SHADOW"], 90 * 32)
        return "\n".join("|" + "".join(chr(c) if 32 <= c < 127 else "#"
                                       for c in d[r * 90:r * 90 + 90]) + "|"
                         for r in range(32))

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


def shot(pc, path):
    """the screen as the PCW shows it, from its memory: the roller RAM (port
    &F5 is not readable: Lisp's place for it, block 3 at &1E00), the top
    line page A's c_top * 8; green on black, each line twice (the PCW's
    pixels are twice as high as wide)"""
    from PIL import Image
    top = pc.ppeek(pc.page["C_TOP"])[0] * 8
    roller = pc.peek(0x1E00, 512, 3)
    blocks = {}

    def blk(b):
        if b not in blocks:
            blocks[b] = b"".join(pc.peek(a, 4096, b) for a in range(0, 16384, 4096))
        return blocks[b]
    img = Image.new("RGB", (720, 512))
    px = img.load()
    for y in range(256):
        w = roller[2 * ((y + top) & 255)] | roller[2 * ((y + top) & 255) + 1] << 8
        b, a = (w >> 13) & 7, (w & 7) + 2 * (w & 0x1FF8)
        mem = blk(b)
        for xb in range(90):
            v = mem[(a + 8 * xb) & 0x3FFF]
            for i in range(8):
                c = (0x40, 0xFF, 0x40) if v & (0x80 >> i) else (0, 0, 0)
                px[xb * 8 + i, 2 * y] = c
                px[xb * 8 + i, 2 * y + 1] = c
    img.save(path)


def run(args):
    lines = open(args.file, encoding="latin-1").read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    log = tempfile.mkdtemp(prefix="pcw-")
    pc = PCW(os.path.abspath(args.build), args.files or [], args.speed, log,
             "PCW8512" if args.machine == "8512" else "PCW8256")
    why = "done"
    try:
        deadline = time.time() + args.timeout
        i = 0                       # the next line
        todo = []                   # actions: (frame, kind, data)
        done_at = None
        while True:
            if pc.p.poll() is not None:
                why = "ended"
                break
            if time.time() > deadline:
                why = "TIMEOUT"
                break
            try:
                busy = pc.drain()
                if pc.quitted():
                    pc.drain()
                    why = "quit"
                    break
            except (EOFError, OSError):
                why = "ended"
                break
            if todo:
                now = pc.frames()
                while todo and todo[0][0] <= now and pc.pasted():
                    _, kind, data = todo.pop(0)     # in order, one at a time
                    if kind == "shot":
                        shot(pc, os.path.abspath(data))
                    else:
                        pc.paste(data, 0)
            if done_at is not None:
                # keys still to give the last line's input (read-line's:
                # the editor's hook, as the prompt's): the end is the prompt
                # after them (or 3 s without one)
                if todo:
                    after_keys = True
                elif after_keys:
                    if hook_by is None:
                        hook_by = time.time() + 3
                    if pc.hooked() or time.time() > hook_by:
                        pc.drain()
                        break
                elif time.time() >= done_at:
                    pc.drain()
                    break
                time.sleep(0.01)
                continue
            if pc.hooked():
                while i < len(lines) and lines[i].startswith("!"):
                    i += 1
                if i >= len(lines):
                    done_at = time.time() + 0.2
                    after_keys, hook_by = bool(todo), None
                    continue
                while not pc.pasted() and time.time() < deadline:
                    pc.drain()
                    time.sleep(0.005)
                pc.paste(" " + lines[i] + "\r", 2)
                t = pc.frames()
                for n, kind, data in actions(lines, i):
                    t += n
                    todo.append((t, kind, data))
                i += 1
            elif not busy:
                time.sleep(0.005)
        if args.shot:
            shot(pc, os.path.abspath(args.shot))
        for pk in args.peek or []:
            a, _, n = pk.partition(":")
            sys.stderr.write("pcw.py: &%s: %s\n" % (a, pc.peek(int(a, 16), int(n or 1)).hex(" ")))
    finally:
        if why != "done":
            sys.stderr.write("pcw.py: the run %s\n" % why)
        if why == "TIMEOUT":
            try:
                sys.stderr.write("pcw.py: TIMEOUT; the screen:\n" + pc.screen() + "\n")
                r = pc.z.cmd("get-registers")
                sys.stderr.write("pcw.py: " + r.strip() + "\n")
                sys.stderr.write("pcw.py: RS_HOOK %d, PA_LEN %d\n" % (
                    pc.peek(pc.res["RS_HOOK"])[0], pc.ppeek(pc.page["PA_LEN"])[0]))
            except Exception as e:
                sys.stderr.write("pcw.py: TIMEOUT (%s)\n" % e)
        pc.close()
    d = pc.text.decode("latin-1")
    d = d.replace("\r\n", "\n").replace("\r", "\n")
    sys.stdout.write(d)
    if args.get:
        for spec in args.get:
            name, _, out = spec.partition(":")
            subprocess.call([sys.executable, os.path.join(ROOT, "tools", "pcw", "mkdisk.py"),
                             "--get", pc.disc, name, out or name])
    if not args.keep:
        shutil.rmtree(log, ignore_errors=True)
    else:
        sys.stderr.write("pcw.py: kept " + log + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-b", "--build", default=os.environ.get("PCW_BUILD",
                                                         os.path.join(ROOT, "build", "pcw")))
    ap.add_argument("-f", "--files", action="append",
                    help="FILE[:NAME]: a file for the disc, beside LISP.IMG")
    ap.add_argument("-m", "--machine", default=os.environ.get("PCW_MACHINE", "8256"))
    ap.add_argument("-t", "--timeout", type=float, default=float(os.environ.get("TIMEOUT", 300)))
    ap.add_argument("-s", "--speed", type=int, default=int(os.environ.get("ZX_SPEED", 1000)),
                    help="ZEsarUX's speed, in percent")
    ap.add_argument("-k", "--keep", action="store_true", help="keep the run's folder")
    ap.add_argument("-S", "--shot", help="a screenshot at the end (.png)")
    ap.add_argument("-g", "--get", action="append",
                    help="NAME[:out]: a file from the disc as Lisp left it, at the end")
    ap.add_argument("-P", "--peek", action="append",
                    help="HEX[:N]: N bytes of the Lisp's RAM there, shown at the end")
    ap.add_argument("file")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
