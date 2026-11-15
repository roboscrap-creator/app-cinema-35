import os, struct, zlib, math

def make_png(size, path):
    w = h = size
    cx = cy = w / 2.0
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            # Fundo gradiente escuro
            dx, dy = (x - cx) / w, (y - cy) / h
            dist = math.sqrt(dx*dx + dy*dy)
            r = max(11, int(36 - dist * 35))
            g = max(12, int(14 - dist * 10))
            b = max(18, int(24 - dist * 12))

            # Anel dourado/vermelho sutil
            if 0.38 < dist < 0.41:
                r, g, b = 229, 9, 20

            # Triangulo Play central branco/vermelho
            nx, ny = (x - cx) / (w * 0.26), (y - cy) / (h * 0.26)
            if -0.55 <= nx <= 0.75:
                lim = 0.72 * (1.0 - (nx + 0.55) / 1.30)
                if abs(ny) <= lim:
                    r, g, b = 255, 255, 255
                    if nx > 0.15:
                        r, g, b = 255, 215, 0

            row.extend((r, g, b, 255))
        rows.append(bytes(row))
    raw = b"".join(rows)
    def chunk(tag, data):
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

for folder, sz in [("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)]:
    make_png(sz, f"android/app/src/main/res/{folder}/ic_launcher.png")
    make_png(sz, f"android/app/src/main/res/{folder}/ic_launcher_round.png")
