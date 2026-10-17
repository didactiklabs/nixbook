#!/usr/bin/env python3
"""Images for the contacts photo tests, without image libraries.

  test-image.py png PATH   a 1600x800 PNG, red, its bottom half transparent
  test-image.py size PATH  a JPEG's size, WxH
"""
import struct
import sys
import zlib


def png(path, w=1600, h=800):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    rows = b"".join(b"\0" + bytes([200, 30, 30, 255 if y < h // 2 else 0]) * w for y in range(h))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def jpeg_size(path):
    data = open(path, "rb").read()
    if data[:2] != b"\xff\xd8":
        return "not a JPEG"
    i = 2
    while i + 9 < len(data):
        marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return f"{w}x{h}"
        i += 2 + length
    return "no size"


if __name__ == "__main__":
    if sys.argv[1] == "png":
        png(sys.argv[2])
    else:
        print(jpeg_size(sys.argv[2]))
