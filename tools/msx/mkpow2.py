#!/usr/bin/env python3
"""The powers of two the MSX's floats need, as the Math-Pack's numbers:
2^k for k = -160 to 160, each 8 bytes -- the sign and exponent (64 for
0.d1d2... x 10^0), then 14 digits of BCD, rounded to the nearest. Entry i
is 2^(i-160): a CPC real's mantissa m times entry e is its value (m x
2^(e-160)), and a value times entry 192-E is 2^32 times its fraction of
2^E (mach/msx/fpmsx.asm).

    python3 tools/msx/mkpow2.py > build/msx/pow2.inc
"""
from decimal import Decimal, getcontext, ROUND_HALF_EVEN

getcontext().prec = 80


def bcd(x):
    """x > 0 as the Math-Pack's 8 bytes"""
    t = Decimal(x).normalize()
    # 0.d1d2...d14 x 10^p
    p = t.adjusted() + 1
    m = (t / (Decimal(10) ** p)).quantize(Decimal(1).scaleb(-14), rounding=ROUND_HALF_EVEN)
    if m >= 1:                          # rounded up to 1.000...: 0.1 x 10^(p+1)
        m, p = Decimal("0.1"), p + 1
    d = str(m)[2:].ljust(14, "0")[:14]
    assert -64 <= p <= 63
    return [64 + p] + [int(d[i]) * 16 + int(d[i + 1]) for i in range(0, 14, 2)]


def main():
    print(";; made by tools/msx/mkpow2.py: 2^k, k = -160..160, the Math-Pack's way")
    print("pow2tab:")
    for k in range(-160, 161):
        b = bcd(Decimal(2) ** k)
        print("    db " + ",".join("#%02X" % v for v in b) + "    ; 2^%d" % k)


if __name__ == "__main__":
    main()
