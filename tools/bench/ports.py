#!/usr/bin/env python3
"""The ports compared: tools/bench/ports.lsp typed at each port's
emulator, the results as a table of speeds relative to the CPC 464.

    tools/bench/ports.py [-j N] [-o dir] [port...]
    tools/bench/ports.py --table dir      the table again from saved runs

Each port must be built first (tools/build.sh, MACH=... tools/build.sh).
Every benchmark is timed by the Lisp's own clock, (time), in 1/300 s of the
emulated machine, so an emulator's own speed does not matter. A port
without the compiler (the plain 6128) skips the compiled part. The
transcripts and results.json go to -o (a fresh temporary folder if not
given); N ports run at once (4).
"""
import argparse, json, math, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# name: (what it is, command, has the compiler)
PORTS = {
    "cpc464":   ("CPC 464, ROMs", ["tools/run.sh", "-m", "464", "-f", "90000"], True),
    "cpc6128":  ("CPC 6128, ROMs", ["tools/run.sh", "-m", "6128", "-f", "90000"], True),
    "cpc512":   ("CPC 464 + 512K, disc", ["tools/cpc512/run.sh", "-m", "464", "-f", "90000"], True),
    "plain6128": ("CPC 6128, disc (no compiler)", ["tools/cpc6128/run.sh", "-f", "90000"], False),
    "futureos": ("CPC 464 + 512K, FutureOS island", ["tools/futureos/run.sh", "-f", "90000"], True),
    "fos":      ("CPC 464 + 512K, FutureOS native", ["tools/fos/run.sh", "-f", "90000"], True),
    "trs80":    ("TRS-80 Model I + X-MEM/80", ["tools/trs80/run.sh"], True),
    "trs80m4":  ("TRS-80 Model 4 (no compiler)", ["tools/trs80m4/run.sh"], False),
    "spectrum": ("ZX Spectrum +2A + DivMMC", ["tools/spectrum/zx.py", "-t", "2400"], True),
    "msx":      ("MSX1 (HX-10) + mapper", ["tools/msx/msx.py", "-t", "2400"], True),
    "pcw":      ("Amstrad PCW 8256", ["tools/pcw/pcw.py", "-t", "2400"], True),
}
BENCHES = [
    ("fib-i", "(fib 17) x2, interpreted"),
    ("tak-i", "(tak 14 8 4), interpreted"),
    ("deriv-i", "deriv x200, interpreted"),
    ("fib-c", "(fib 20), compiled"),
    ("tak-c", "(tak 15 10 5) x2, compiled"),
    ("deriv-c", "deriv x300, compiled"),
    ("torus", "(torus): floats and plots"),
    ("text", "50 lines printed"),
    ("lines", "100 lines drawn"),
]


def source(compiled):
    """ports.lsp with the torus's text put in (its comment lines left out)
    and, without the compiler, the compiled part left out."""
    out = []
    for line in open(os.path.join(ROOT, "tools/bench/ports.lsp")):
        if line.startswith(";@include "):
            for l in open(os.path.join(ROOT, line.split()[1])):
                if l.strip() and not l.lstrip().startswith(";"):
                    out.append(l)
        elif line.startswith(";@compiled"):
            if not compiled:
                break
        elif line.strip() and not line.startswith(";"):
            out.append(line)
    return "".join(out)


def run(port, outdir):
    what, cmd, compiled = PORTS[port]
    lsp = os.path.join(outdir, port + ".lsp")
    with open(lsp, "w") as f:
        f.write(source(compiled))
    env = dict(os.environ, TIMEOUT="2400")
    p = subprocess.run(cmd + [lsp], cwd=ROOT, env=env, capture_output=True,
                       text=True, errors="replace")
    with open(os.path.join(outdir, port + ".out"), "w") as f:
        f.write(p.stdout)
    with open(os.path.join(outdir, port + ".err"), "w") as f:
        f.write(p.stderr)
    return port, parse(p.stdout)


def parse(text):
    r = {}
    for m in re.finditer(r"BENCH (\S+) ([0-9.]+)", text):
        r[m.group(1)] = float(m.group(2)) / 300
    m = re.search(r"Done in: ([0-9.]+) seconds", text)
    if m:
        r["torus"] = float(m.group(1))
    return r


def gmean(xs):
    return math.exp(sum(map(math.log, xs)) / len(xs)) if xs else 0


def table(results):
    """Markdown: each port's speed against the CPC 464 (its time / this
    one's), and two indices, geometric means: the Lisp's own work (fib,
    tak, deriv) and everything; then the seconds."""
    ref = results.get("cpc464", {})
    names = " | ".join(f"`{b}`" for b, _ in BENCHES)
    rows = [f"| | {names} | Lisp | **all** |", "|---" * (len(BENCHES) + 3) + "|"]
    secs = [f"| | {names} |", "|---" * (len(BENCHES) + 1) + "|"]
    for port in PORTS:
        if port not in results:
            continue
        r, lisp, every, cells, scells = results[port], [], [], [], []
        for b, _ in BENCHES:
            if b in r and b in ref and r[b] > 0:
                q = ref[b] / r[b]
                every.append(q)
                if b.endswith(("-i", "-c")):
                    lisp.append(q)
                cells.append(f"{q:.2f}")
                scells.append(f"{r[b]:.1f}")
            else:
                cells.append("--")
                scells.append("--")
        rows.append(f"| {PORTS[port][0]} | " + " | ".join(cells)
                    + f" | {gmean(lisp):.2f} | **{gmean(every):.2f}** |")
        secs.append(f"| {PORTS[port][0]} | " + " | ".join(scells) + " |")
    return "\n".join(rows) + "\n\nSeconds:\n\n" + "\n".join(secs) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=4)
    ap.add_argument("-o")
    ap.add_argument("--table")
    ap.add_argument("ports", nargs="*")
    a = ap.parse_args()
    if a.table:
        print(table(json.load(open(os.path.join(a.table, "results.json")))))
        return
    outdir = a.o or tempfile.mkdtemp(prefix="ports-")
    os.makedirs(outdir, exist_ok=True)
    rf = os.path.join(outdir, "results.json")
    results = json.load(open(rf)) if os.path.exists(rf) else {}
    ports = a.ports or list(PORTS)
    with ThreadPoolExecutor(a.j) as ex:
        for port, r in ex.map(lambda p: run(p, outdir), ports):
            print(port, r, file=sys.stderr, flush=True)
            results[port] = r
            json.dump(results, open(rf, "w"), indent=1)
    print(table(results))
    print("transcripts in", outdir, file=sys.stderr)


if __name__ == "__main__":
    main()
