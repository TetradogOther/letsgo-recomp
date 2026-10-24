#!/usr/bin/env python3
"""A fake main.npdm (the NACP of the program) with a given program id: the setup checks it to know which game it is
(tools/linux/smoketest.sh uses it: the launcher has to accept the folder as Let's Go, Eevee!)."""
import struct
import sys

TITLES = {
    "eevee": 0x0100187003A36000,
    "pikachu": 0x010003F003A34000,
}

name = sys.argv[1] if len(sys.argv) > 1 else "eevee"
out = sys.argv[2] if len(sys.argv) > 2 else "main.npdm"
title = TITLES.get(name, TITLES["eevee"])

# META: the header of the NACP ('META'), with the ACI0 block at 0x70
meta = bytearray(0x80)
meta[0:4] = b"META"
struct.pack_into("<I", meta, 0x70, 0x80)
# ACI0: the program id at +0x10
aci = bytearray(0x18)
aci[0:4] = b"ACI0"
struct.pack_into("<Q", aci, 0x10, title)

with open(out, "wb") as f:
    f.write(meta)
    f.write(aci)
print(f"{out}: the program id of {name} (0x{title:016x})")
