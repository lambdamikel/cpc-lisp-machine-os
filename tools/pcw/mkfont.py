#!/usr/bin/env python3
"""The PCW's text font: the Spectrum's (mach/spectrum/font.inc, our own:
five pixels by seven in a cell of six by eight), made bold for the PCW's
pixels -- twice as high as they are wide, so a stroke one pixel wide looks
thin -- and set in the PCW's cell of eight by eight: each row ORed with
itself one pixel to the right (six pixels wide), then one pixel in from
the left. Writes mach/pcw/font.inc: characters 32-127, eight bytes each.

    tools/pcw/mkfont.py [out.inc]
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")


def main():
    src = os.path.join(ROOT, "mach", "spectrum", "font.inc")
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "mach", "pcw", "font.inc")
    lines = []
    for l in open(src):
        m = re.match(r"\s*db (#[0-9A-F]{2}(?:,#[0-9A-F]{2}){7})\s*;\s*(\d+)\s*(.*)$", l)
        if not m:
            continue
        rows = [int(v[1:], 16) for v in m.group(1).split(",")]
        bold = [((r | (r >> 1)) >> 1) & 0xFF for r in rows]
        lines.append("    db " + ",".join("#%02X" % b for b in bold)
                     + "   ; " + m.group(2) + " " + m.group(3) + "\n")
    assert len(lines) == 96, len(lines)
    with open(out, "w") as f:
        f.write(";; made by tools/pcw/mkfont.py: characters 32-127, the Spectrum's font\n"
                ";; made bold, in a cell of eight by eight\n")
        f.writelines(lines)


if __name__ == "__main__":
    main()
