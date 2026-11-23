#!/usr/bin/env python3
"""The PCW's float constants (mach/pcw/fppcw.asm): the series' coefficients
and the constants the reductions use, as the CPC's five-byte reals --
four bytes of mantissa, least significant first, the top bit of the last
the sign (the mantissa's leading 1 is implied), then the exponent, &80 + e
for a mantissa in [0.5, 1) times 2^e. Written to stdout: an include.

    tools/pcw/mkfpconst.py > fpconst.inc
"""
import math
from fractions import Fraction


def real(v):
    """v as the CPC's five bytes, rounded to the nearest"""
    if v == 0:
        return [0, 0, 0, 0, 0]
    sign = 0x80 if v < 0 else 0
    v = abs(Fraction(v))
    e = 0
    while v >= 1:
        v /= 2
        e += 1
    while v < Fraction(1, 2):
        v *= 2
        e -= 1
    m = v * (1 << 32)
    mi = int(m)
    if m - mi >= Fraction(1, 2):
        mi += 1
    if mi == 1 << 32:
        mi >>= 1
        e += 1
    assert (1 << 31) <= mi < (1 << 32) and -127 <= e <= 127
    b = [mi & 255, (mi >> 8) & 255, (mi >> 16) & 255, ((mi >> 24) & 0x7F) | sign]
    return b + [e + 128]


def back(b):
    """the five bytes as a float (to check)"""
    if b[4] == 0:
        return 0.0
    mi = b[0] | b[1] << 8 | b[2] << 16 | ((b[3] | 0x80) << 24)
    v = mi / 2 ** 32 * 2.0 ** (b[4] - 128)
    return -v if b[3] & 0x80 else v


def line(name, v, note):
    b = real(v)
    assert abs(back(b) - float(v)) <= abs(float(v)) * 2 ** -31 + 1e-300
    return "%-11s db %s   ; %s\n" % (name + ":" if name else "", ",".join("#%02X" % x for x in b), note)


def table(name, coeffs, note):
    out = "%s:                         ; %s\n" % (name, note)
    for c, n in coeffs:
        out += line("", c, n)
    return out


def main():
    pi = Fraction(math.pi)       # (as a double: more digits than 32 bits)
    # the reductions' splits: a part exact in few bits, and the rest
    ln2 = Fraction(math.log(2))
    ln2_hi = Fraction(math.floor(math.log(2) * 2 ** 15), 2 ** 15)
    pio2 = Fraction(math.pi / 2)
    pio2_hi = Fraction(math.floor(math.pi / 2 * 2 ** 15), 2 ** 15)
    o = ";; made by tools/pcw/mkfpconst.py: the PCW's float constants\n"
    o += line("fc_one", 1, "1")
    o += line("fc_half", Fraction(1, 2), "0.5")
    o += line("fc_rt2h", Fraction(math.sqrt(0.5)), "sqrt(1/2): log's split")
    o += line("fc_ln2", ln2, "ln 2")
    o += line("fc_ln2h", ln2_hi, "ln 2, its first 15 bits (exact times n)")
    o += line("fc_ln2l", ln2 - ln2_hi, "  and the rest")
    o += line("fc_iln2", 1 / ln2, "1 / ln 2")
    o += line("fc_2opi", 1 / pio2, "2 / pi")
    o += line("fc_pio2h", pio2_hi, "pi / 2, its first 15 bits")
    o += line("fc_pio2l", pio2 - pio2_hi, "  and the rest")
    o += line("fc_pio2", pio2, "pi / 2")
    o += line("fc_pio6", Fraction(math.pi / 6), "pi / 6")
    o += line("fc_rt3", Fraction(math.sqrt(3)), "sqrt 3")
    o += line("fc_t12", Fraction(math.tan(math.pi / 12)), "tan(pi / 12)")
    # the series, the highest power first
    o += table("fc_log", [(Fraction(1, k), "1/%d" % k) for k in (13, 11, 9, 7, 5, 3, 1)],
               "log: ln m = 2t P(t^2), t = (m-1)/(m+1)")
    o += table("fc_exp", [(Fraction(1, math.factorial(k)), "1/%d!" % k) for k in range(11, -1, -1)],
               "exp: e^r, |r| <= ln2/2")
    o += table("fc_sin", [(Fraction((-1) ** i, math.factorial(2 * i + 1)), "(-1)^%d/%d!" % (i, 2 * i + 1))
                          for i in range(6, -1, -1)], "sin: r S(r^2), |r| <= pi/4")
    o += table("fc_cos", [(Fraction((-1) ** i, math.factorial(2 * i)), "(-1)^%d/%d!" % (i, 2 * i))
                          for i in range(7, -1, -1)], "cos: C(r^2)")
    o += table("fc_atn", [(Fraction((-1) ** i, 2 * i + 1), "(-1)^%d/%d" % (i, 2 * i + 1))
                          for i in range(8, -1, -1)], "atan: z A(z^2), |z| <= tan(pi/12)")
    print(o, end="")


if __name__ == "__main__":
    main()
