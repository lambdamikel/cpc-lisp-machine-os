#!/usr/bin/env python3
"""Write a TRS-80 /CMD file: load records for binaries, then the entry.

    cmd.py out.cmd entry file@addr [file@addr...]

Each file is loaded at its address, in records of 252 bytes (type 1:
length = data + 2, the address, the data); the last record (type 2)
gives the address to start at.
"""
import sys

def records(data, addr):
    out = bytearray()
    for i in range(0, len(data), 252):
        chunk = data[i:i + 252]
        a = addr + i
        out += bytes([1, (len(chunk) + 2) & 0xFF, a & 0xFF, a >> 8]) + chunk
    return out

def main():
    out, entry = sys.argv[1], int(sys.argv[2], 0)
    body = bytearray()
    for spec in sys.argv[3:]:
        path, addr = spec.rsplit('@', 1)
        body += records(open(path, 'rb').read(), int(addr, 0))
    body += bytes([2, 2, entry & 0xFF, entry >> 8])
    open(out, 'wb').write(body)

if __name__ == '__main__':
    main()
