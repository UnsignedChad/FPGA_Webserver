#!/usr/bin/env python3
# poke the fpga over ethernet and check the http server actually works.
# usage: verify_fpga.py 10.0.0.10
# assumes the host is on the same /24 (so the os arp table will resolve).
import socket, subprocess, sys, time

def ok(msg): print("[ok]   " + msg)
def fail(msg): print("[fail] " + msg); sys.exit(1)

def ping(ip, n=3):
    r = subprocess.run(
        ["ping", "-c", str(n), "-W", "2", ip],
        capture_output=True, text=True)
    if r.returncode != 0:
        fail("ping failed: " + r.stdout.strip().splitlines()[-1])
    ok("ping {} x {}".format(ip, n))

def http_get(ip, port=80, timeout=3.0):
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

def check_http(ip):
    body = http_get(ip)
    if not body:
        fail("no bytes from {}:80".format(ip))
    if not body.startswith(b"HTTP/1.0 200 OK"):
        fail("not an http/1.0 200 response, got: " + body[:40].decode("latin1"))
    if b"FPGA" not in body:
        fail("response missing the FPGA marker")
    ok("http get returned {} bytes, starts ok".format(len(body)))

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: verify_fpga.py <ip>"); sys.exit(2)
    ip = sys.argv[1]
    ping(ip)
    check_http(ip)
    print("all checks passed")
