#!/usr/bin/env python3
"""wraps a raw binary (linked at 0, see link.ld) in a bFLT v4 header: loaded entirely into ram, no relocations.
usage: mkflat.py <in.bin> <out.flat> <bss bytes> [stack bytes]"""
import struct, sys
src, dst, bss = sys.argv[1], sys.argv[2], int(sys.argv[3])
stack = int(sys.argv[4]) if len(sys.argv) > 4 else 4096
body = open(src, 'rb').read()
HDR = 64
end = HDR + len(body)
FLAT_FLAG_RAM = 1
hdr = b'bFLT' + struct.pack('>IIIIIIIIII', 4, HDR, end, end, end + bss, stack, end, 0, FLAT_FLAG_RAM, 0) + bytes(20)
assert len(hdr) == HDR
open(dst, 'wb').write(hdr + body)
