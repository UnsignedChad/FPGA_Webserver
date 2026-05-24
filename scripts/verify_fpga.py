#!/usr/bin/env python3
# poke the fpga over ethernet and check the http server actually works.
# usage: verify_fpga.py [-v] <ip>
# assumes the host is on the same /24 (so the os arp table resolves).
import argparse, socket, subprocess, sys

def ok(msg): print("[ok]   " + msg)
def fail(msg): print("[fail] " + msg); sys.exit(1)
def info(msg, v):
    if v: print("       " + msg)

def ping(ip, v):
    r = subprocess.run(["ping", "-c", "3", "-W", "2", ip],
                       capture_output=True, text=True)
    if r.returncode != 0:
        info(r.stdout.strip(), v)
        fail("no ping reply from " + ip)
    if v:
        # last line has rtt stats
        last = [l for l in r.stdout.splitlines() if "rtt" in l or "min/avg" in l]
        if last: info(last[-1], v)
    ok("ping " + ip)

def http_get(ip, port, timeout):
    s = socket.create_connection((ip, port), timeout=timeout)
    s.sendall(b"GET / HTTP/1.0\r\n\r\n")
    chunks = []
    s.settimeout(timeout)
    try:
        while True:
            b = s.recv(4096)
            if not b: break
            chunks.append(b)
    except socket.timeout:
        pass
    s.close()
    return b"".join(chunks)

def check_http(ip, v):
    try:
        body = http_get(ip, 80, 3.0)
    except (ConnectionRefusedError, socket.timeout) as e:
        fail("tcp connect to {}:80 failed: {}".format(ip, e))
    if not body:
        fail("connected but got 0 bytes from {}:80".format(ip))
    info("first 80 bytes: " + repr(body[:80]), v)
    if not body.startswith(b"HTTP/1.0 200"):
        fail("response is not HTTP/1.0 200, got: " + body[:40].decode("latin1", "replace"))
    if b"FPGA" not in body:
        fail("response is missing the FPGA marker text")
    ok("http get returned {} bytes, looks ok".format(len(body)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ip", help="IP of the FPGA")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    ping(args.ip, args.verbose)
    check_http(args.ip, args.verbose)
    print("all checks passed")

if __name__ == "__main__":
    main()
