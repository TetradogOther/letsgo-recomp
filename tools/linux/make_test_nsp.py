#!/usr/bin/env python3
"""make_test_nsp.py: a synthetic .nsp (the PFS0 container) to test the runtime's unpacking, without the game.

    tools/linux/make_test_nsp.py <out.nsp> [--encrypted]

The container holds the exefs (main, main.npdm, rtld, sdk, subsdk0, subsdk1), a romfs.bin and a language folder.
With --encrypted the NSO's flags say the code is encrypted with the title key (what the runtime must tell apart).
"""
import os
import struct
import sys


def nso(encrypted):
    # an NSO header (the runtime reads the flags at 0x0C: the first bit = encrypted with the title key)
    head = bytearray(0x400)
    head[0:4] = b"NSO0"
    struct.pack_into("<I", head, 0x0C, 1 if encrypted else 0)
    struct.pack_into("<I", head, 0x10, 0x400)  # the first segment's offset
    return bytes(head) + b"\0" * 1024


def npdm():
    # a main.npdm with the Eevee's program id (what the runtime checks)
    meta = bytearray(0x80)
    meta[0:4] = b"META"
    struct.pack_into("<I", meta, 0x70, 0x100)  # the ACI0's offset
    aci = bytearray(0x18)
    aci[0:4] = b"ACI0"
    struct.pack_into("<Q", aci, 0x10, 0x0100187003A36000)
    data = bytearray(0x100 + len(aci))
    data[0:0x80] = meta
    data[0x100:] = aci
    return bytes(data)


def pfs0(files):
    # the container: the header, the file table, the names, then the data
    names = b""
    entries = b""
    data = b""
    for name, content in files:
        soff = len(names)
        names += name.encode() + b"\0"
        entries += struct.pack("<QQII", len(data), len(content), soff, len(name))
        data += content
    head = b"PFS0" + struct.pack("<II", len(files), len(names)) + b"\0" * 4
    return head + entries + names + data


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    out = sys.argv[1]
    encrypted = "--encrypted" in sys.argv
    layered = "--layered" in sys.argv
    if layered:
        # a "layered" package: the game is inside content archives (.nca), encrypted with the console's keys
        files = [
            ("54f05545f49ff824ac7cc426bd0d5026.cnmt.xml", b"<meta/>" * 64),
            ("1b34ffd5f31b16a437523c5ecda66bac.nca", b"\0" * 4096),
            ("514bcc037a4aaf9001bf11da737c0dfe.nca", b"\0" * 512),
        ]
    else:
        files = [
            ("main", nso(encrypted)),
            ("main.npdm", npdm()),
            ("rtld", nso(encrypted)),
            ("sdk", nso(encrypted)),
            ("subsdk0", nso(encrypted)),
            ("subsdk1", nso(encrypted)),
            ("romfs.bin", b"ROMFS" + b"\0" * 4092),
            ("English", b"language" * 64),
        ]
    with open(out, "wb") as f:
        f.write(pfs0(files))
    print("%s: %d bytes%s" % (out, os.path.getsize(out), " (encrypted)" if encrypted else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
