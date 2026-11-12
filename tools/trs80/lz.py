#!/usr/bin/env python3
"""The TRS-80 images' compression: an LZ77 with optimal parsing, decoded
by the loader (mach/trs80/loader.asm, lz_dec).

The format: two bytes, the length decoded (low first); then the first
byte as it is; then tokens until that many bytes are out. Bits come MSB
first from a byte taken from the stream when the last one is used up;
literal bytes and offset bytes are taken from the stream where they fall.

    0, a byte                  a literal
    1, gamma(n - 1), offset    a match: n >= 2 bytes from o back

gamma(v), v >= 1: for each bit of v after its leading 1, a 0 and that bit;
then a 1. An offset o of 1-128 is one byte, o - 1; a longer one, up to
FAR, is a byte 128 + (o - 129) >> BITS, then the BITS bits below.

    lz.py compress IN OUT, lz.py test FILE...
"""
import sys

BITS = 5
FAR = 128 + (128 << BITS)       # the farthest offset


def gamma_bits(v):
    return 2 * (v.bit_length() - 1) + 1


def matches(data):
    """For each position, the longest match within 128 back and within FAR
    back: (near_len, near_off, far_len, far_off)."""
    n = len(data)
    heads = {}
    best = [(0, 0, 0, 0)] * n
    for i in range(n):
        if i + 1 < n:
            key = data[i:i + 2]
            chain = heads.setdefault(key, [])
            nl = no = fl = fo = 0
            for j in reversed(chain):
                o = i - j
                if o > FAR:
                    break
                k = 2
                while i + k < n and data[j + k] == data[i + k]:
                    k += 1
                if o <= 128:
                    if k > nl:
                        nl, no = k, o
                if k > fl:
                    fl, fo = k, o
            best[i] = (nl, no, fl, fo)
            chain.append(i)
    return best


def compress(data):
    n = len(data)
    best = matches(data)
    # cost[i]: the fewest bits for data[i:]; choice[i]: how
    INF = 1 << 60
    cost = [INF] * (n + 1)
    choice = [None] * (n + 1)
    cost[n] = 0
    for i in range(n - 1, 0, -1):
        c = 9 + cost[i + 1]
        ch = None
        nl, no, fl, fo = best[i]
        for L in range(2, fl + 1):
            if L <= nl:
                o, ob = no, 8
            else:
                o, ob = fo, (8 if fo <= 128 else 8 + BITS)
            cc = 1 + gamma_bits(L - 1) + ob + cost[i + L]
            if cc < c:
                c, ch = cc, (L, o)
        cost[i], choice[i] = c, ch
    out = bytearray([n & 255, n >> 8, data[0]])
    state = {'pos': None, 'k': 0}

    def bit(b):
        if state['k'] == 0:
            state['pos'] = len(out)
            out.append(0)
            state['k'] = 8
        state['k'] -= 1
        if b:
            out[state['pos']] |= 1 << state['k']

    def gamma(v):
        for b in bin(v)[3:]:
            bit(0)
            bit(int(b))
        bit(1)

    i = 1
    while i < n:
        ch = choice[i]
        if ch is None:
            bit(0)
            out.append(data[i])
            i += 1
        else:
            L, o = ch
            bit(1)
            gamma(L - 1)
            if o <= 128:
                out.append(o - 1)
            else:
                v = o - 129
                out.append(128 + (v >> BITS))
                for k in range(BITS - 1, -1, -1):
                    bit((v >> k) & 1)
            i += L
    return bytes(out)


def decompress(z):
    n = z[0] + 256 * z[1]
    out = bytearray([z[2]])
    p = 3
    buf = {'b': 0, 'k': 0}

    def bit():
        nonlocal p
        if buf['k'] == 0:
            buf['b'] = z[p]
            p += 1
            buf['k'] = 8
        buf['k'] -= 1
        return (buf['b'] >> buf['k']) & 1

    def gamma():
        v = 1
        while not bit():
            v = 2 * v + bit()
        return v

    while len(out) < n:
        if not bit():
            out.append(z[p])
            p += 1
        else:
            L = gamma() + 1
            b = z[p]
            p += 1
            if b < 128:
                o = b + 1
            else:
                v = b - 128
                for _ in range(BITS):
                    v = 2 * v + bit()
                o = v + 129
            for _ in range(L):
                out.append(out[-o])
    return bytes(out)


def main():
    if sys.argv[1] == 'compress':
        data = open(sys.argv[2], 'rb').read()
        z = compress(data)
        assert decompress(z) == data
        open(sys.argv[3], 'wb').write(z)
    else:
        for f in sys.argv[2:]:
            data = open(f, 'rb').read().rstrip(b'\xff')
            z = compress(data)
            assert decompress(z) == data, f
            print(f, len(data), len(z))


if __name__ == '__main__':
    main()
