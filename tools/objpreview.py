#!/usr/bin/env python3
"""OBJ ka side-view render + montage (pure python, koi numpy/PIL nahi).

Kyun: `assets/downloaded_obj/Weapons/` ke models ka **barrel kis taraf hai** ye verify
karne ke liye. Ye ek offline check hai (CI me nahi chalta) — output `docs/renders/` me
committed montages hain, unhi se `tools/obj2glb.py` ka "+X = muzzle" rule aaya hai.

    python3 tools/objpreview.py assets/downloaded_obj/Weapons/*.obj --out /tmp/all.png --cols 5
    python3 tools/objpreview.py assets/downloaded_obj/Weapons/Pistol_1.obj --out /tmp/p1.png

Har tile ke **daaye kinare pe hara bar** hai = model ka +X sirra (is pack me barrel wahi
hota hai, aur converter usko -Z pe ghumata hai).
"""

import argparse
import math
import os
import struct
import sys
import zlib


def load_obj(path):
    verts, faces = [], []
    for line in open(path, errors="replace"):
        if line.startswith("v "):
            p = line.split()
            verts.append((float(p[1]), float(p[2]), float(p[3])))
        elif line.startswith("f "):
            idx = []
            for tok in line.split()[1:]:
                idx.append(int(tok.split("/")[0]) - 1)
            if len(idx) >= 3:
                faces.append(idx)
    return verts, faces


def write_png(path, w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw += bytes(pixels[y][x])

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


BG = (18, 20, 26)


def render_tile(path, W, H):
    """Side view (camera -Z se): screen X = model X, screen Y = model Y."""
    verts, faces = load_obj(path)
    if not verts:
        return [[BG] * W for _ in range(H)]
    xs = [p[0] for p in verts]
    ys = [p[1] for p in verts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    s = min((W - 24) / max(x1 - x0, 1e-6), (H - 26) / max(y1 - y0, 1e-6))
    ox = (W - (x1 - x0) * s) / 2 - x0 * s
    oy = (H - (y1 - y0) * s) / 2 + y1 * s
    img = [[BG] * W for _ in range(H)]
    zbuf = [[-1e18] * W for _ in range(H)]

    # painter's algorithm: depth (z) ke hisaab se sort, phir flat shading
    tris = []
    for f in faces:
        for i in range(1, len(f) - 1):
            tri = (verts[f[0]], verts[f[i]], verts[f[i + 1]])
            tris.append((sum(p[2] for p in tri) / 3.0, tri))
    tris.sort(key=lambda t: t[0])
    light = (-0.4, 0.7, 0.6)
    for depth, tri in tris:
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
        u = (bx - ax, by - ay, bz - az)
        v = (cx - ax, cy - ay, cz - az)
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        ln = math.sqrt(sum(c * c for c in n)) or 1.0
        n = (n[0] / ln, n[1] / ln, n[2] / ln)
        lum = max(0.15, abs(n[0] * light[0] + n[1] * light[1] + n[2] * light[2]))
        col = (int(60 + 165 * lum), int(56 + 158 * lum), int(62 + 150 * lum))
        pix = [(ox + p[0] * s, oy - p[1] * s) for p in tri]
        minx = max(0, int(min(p[0] for p in pix)))
        maxx = min(W - 1, int(max(p[0] for p in pix)) + 1)
        miny = max(0, int(min(p[1] for p in pix)))
        maxy = min(H - 1, int(max(p[1] for p in pix)) + 1)
        for py in range(miny, maxy + 1):
            for px in range(minx, maxx + 1):
                x, y = px + 0.5, py + 0.5
                d = []
                for i in range(3):
                    xa, ya = pix[i]
                    xb, yb = pix[(i + 1) % 3]
                    d.append((xb - xa) * (y - ya) - (yb - ya) * (x - xa))
                if (all(t >= 0 for t in d) or all(t <= 0 for t in d)) and depth > zbuf[py][px]:
                    zbuf[py][px] = depth
                    img[py][px] = col

    # +X kinare pe hara bar (is pack me barrel/muzzle wahi hota hai) + halka border
    for y in range(H):
        for x in range(W - 4, W):
            img[y][x] = (40, 200, 90)
    for x in range(W):
        img[0][x] = (70, 74, 86)
        img[H - 1][x] = (70, 74, 86)
    return img


def montage(paths, out, cols=3, tw=420, th=170):
    rows = (len(paths) + cols - 1) // cols
    W, H = cols * tw, rows * th
    img = [[(10, 11, 15)] * W for _ in range(H)]
    for i, p in enumerate(paths):
        tile = render_tile(p, tw, th)
        r, c = divmod(i, cols)
        for y in range(th):
            for x in range(tw):
                img[r * th + y][c * tw + x] = tile[y][x]
    write_png(out, W, H, img)
    print("montage: %s  (%d cols x %d rows)  order:" % (out, cols, rows))
    for i, p in enumerate(paths):
        r, c = divmod(i, cols)
        print("  row%d col%d: %s" % (r + 1, c + 1, os.path.splitext(os.path.basename(p))[0]))


def main(argv):
    ap = argparse.ArgumentParser(description="OBJ side-view render / montage")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--tile-w", type=int, default=420)
    ap.add_argument("--tile-h", type=int, default=170)
    args = ap.parse_args(argv)
    paths = []
    for entry in args.inputs:
        if os.path.isdir(entry):
            paths += [os.path.join(entry, n) for n in sorted(os.listdir(entry))
                      if n.lower().endswith(".obj")]
        else:
            paths.append(entry)
    if not paths:
        print("koi .obj nahi mila")
        return 1
    montage(paths, args.out, args.cols, args.tile_w, args.tile_h)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
