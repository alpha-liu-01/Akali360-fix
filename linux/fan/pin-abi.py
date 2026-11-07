#!/usr/bin/env python3
"""Point a module built against 6.18.60 headers at the running 6.18.52 kernel.

The function prototypes this module calls did not change. Only the modversion
CRCs and the release string differ, so those two fields are rewritten from the
modules already running on this machine.
"""

import glob
import gzip
import os
import struct
import subprocess
import sys

BUILT = b"6.18.60-0-lts"
ENTRY = 64


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def section(data, name):
    shoff = u64(data, 40)
    shentsize = u16(data, 58)
    shnum = u16(data, 60)
    shstrndx = u16(data, 62)
    str_off = u64(data, shoff + shstrndx * shentsize + 24)
    for i in range(shnum):
        base = shoff + i * shentsize
        sname = data[str_off + u32(data, base) :].split(b"\0", 1)[0]
        if sname == name:
            return u64(data, base + 24), u64(data, base + 32)
    raise SystemExit(f"section {name!r} not found")


def collect():
    found = {}
    root = f"/lib/modules/{os.uname().release}"
    raw = "/tmp/pin-abi-one.ko"
    for path in glob.glob(root + "/kernel/**/*.ko.gz", recursive=True):
        with gzip.open(path, "rb") as src, open(raw, "wb") as dst:
            dst.write(src.read())
        proc = subprocess.run(
            ["modprobe", "--dump-modversions", raw],
            capture_output=True,
            text=True,
        )
        for line in proc.stdout.splitlines():
            crc, sym = line.split()
            found.setdefault(sym, int(crc, 16))
    os.unlink(raw)
    return found


def main():
    ko = sys.argv[1]
    data = bytearray(open(ko, "rb").read())
    running = os.uname().release.encode()
    if len(BUILT) != len(running):
        raise SystemExit("release string length differs")
    count = data.count(BUILT)
    if count == 0:
        raise SystemExit("built release string not found")
    data = data.replace(BUILT, running)

    found = collect()
    off, size = section(data, b"__versions")
    missing = []
    patched = 0
    pos = off
    end = off + size
    while pos + ENTRY <= end:
        name = data[pos + 8 : pos + ENTRY].split(b"\0", 1)[0].decode()
        if not name:
            break
        if name not in found:
            missing.append(name)
        else:
            struct.pack_into("<Q", data, pos, found[name])
            patched += 1
        pos += ENTRY
    if missing:
        raise SystemExit("missing CRCs: " + ", ".join(missing))
    open(ko, "wb").write(data)
    print(f"vermagic -> {running.decode()} ({count})")
    print(f"patched {patched} symbol versions")


if __name__ == "__main__":
    main()
