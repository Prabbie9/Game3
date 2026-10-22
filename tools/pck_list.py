#!/usr/bin/env python3
"""List files inside a Godot 4 .pck (format v2/v3): path and size. Usage: pck_list.py file.pck"""
import struct, sys


def entries(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"GDPC", "not a pck"
        fmt, major, minor, patch = struct.unpack("<IIII", f.read(16))
        flags = struct.unpack("<I", f.read(4))[0]
        base = struct.unpack("<Q", f.read(8))[0]
        if fmt >= 3:
            dir_ofs = struct.unpack("<Q", f.read(8))[0]
            f.seek(dir_ofs)
        else:
            f.read(16 * 4)
        count = struct.unpack("<I", f.read(4))[0]
        out = []
        for _ in range(count):
            n = struct.unpack("<I", f.read(4))[0]
            name = f.read(n).rstrip(b"\0").decode()
            ofs, size = struct.unpack("<QQ", f.read(16))
            f.read(16)  # md5
            f.read(4)   # flags
            out.append((name, size))
        return out


if __name__ == "__main__":
    for name, size in sorted(entries(sys.argv[1]), key=lambda x: -x[1]):
        print(f"{size:12d} {name}")
