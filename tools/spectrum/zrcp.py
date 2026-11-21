#!/usr/bin/env python3
"""A client for ZEsarUX's remote protocol (ZRCP, TCP): send a command, get
what it answers up to the next "command> " prompt.

    from zrcp import Zrcp
    z = Zrcp(port=10000)
    print(z.cmd("get-registers"))

As a script: tools/spectrum/zrcp.py PORT command... (each argument one
command), the answers on stdout."""
import re, socket, sys, time

PROMPT = re.compile(rb"command(@cpu-step)?> ")

class Zrcp:
    def __init__(self, host="127.0.0.1", port=10000, timeout=20.0, wait=10.0):
        t0 = time.time()
        while True:
            try:
                self.s = socket.create_connection((host, port), timeout=timeout)
                break
            except OSError:
                if time.time() - t0 > wait:
                    raise
                time.sleep(0.1)
        self.buf = b""
        self._until_prompt()          # the welcome text

    def _until_prompt(self):
        while True:
            m = PROMPT.search(self.buf)
            if m:
                break
            d = self.s.recv(65536)
            if not d:
                raise EOFError("ZRCP closed")
            self.buf += d
        out, self.buf = self.buf[:m.start()], self.buf[m.end():]
        return out.decode("latin-1")

    def cmd(self, line):
        self.s.sendall(line.encode("latin-1") + b"\n")
        return self._until_prompt()

    def close(self):
        try:
            self.s.sendall(b"quit\n")
        except OSError:
            pass
        self.s.close()

if __name__ == "__main__":
    z = Zrcp(port=int(sys.argv[1]))
    for c in sys.argv[2:]:
        sys.stdout.write(z.cmd(c))
    z.close()
