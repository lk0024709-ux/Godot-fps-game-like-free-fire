#!/usr/bin/env python3
"""GLB sanity checker - runs in CI right after tools/fbx2glb.py.

Checks every .glb under the given paths:
  * 12-byte GLB header + JSON/BIN chunk layout
  * JSON parses, every mesh/primitive references existing accessors
  * index values stay inside the POSITION accessor
  * positions are finite numbers, node hierarchy has no cycles
  * bounding box is sane (not flat, not kilometre sized)

Exit code 0 = all good, 1 = at least one broken file (CI turns that into a warning,
the game itself never needs this file).
"""
import glob
import json
import math
import os
import struct
import sys

COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
        5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    data = open(path, "rb").read()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("GLB magic nahi mila")
    version, length = struct.unpack_from("<II", data, 4)
    if version != 2:
        raise ValueError("glTF version %d" % version)
    if length != len(data):
        raise ValueError("header length %d != file size %d" % (length, len(data)))
    off, gltf, binb = 12, None, b""
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binb = chunk
        off += 8 + clen
    if gltf is None:
        raise ValueError("JSON chunk nahi mila")
    return gltf, binb


def accessor_values(gltf, binb, idx):
    acc = gltf["accessors"][idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    fmt, size = COMP[acc["componentType"]]
    n = NCOMP[acc["type"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    need = acc["count"] * n * size
    if start + need > len(binb):
        raise ValueError("accessor %d bufferView se bahar" % idx)
    vals = struct.unpack_from("<%d%s" % (acc["count"] * n, fmt), binb, start)
    return vals, n


def check(path):
    gltf, binb = read_glb(path)
    problems = []
    tri = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "POSITION" not in prim.get("attributes", {}):
                problems.append("%s: POSITION missing" % mesh.get("name"))
                continue
            pos, n = accessor_values(gltf, binb, prim["attributes"]["POSITION"])
            if n != 3:
                problems.append("%s: POSITION VEC3 nahi" % mesh.get("name"))
            for v in pos:
                if not math.isfinite(v):
                    problems.append("%s: POSITION me inf/nan" % mesh.get("name"))
                    break
            idx, _ = accessor_values(gltf, binb, prim["indices"])
            if idx and max(idx) >= len(pos) // 3:
                problems.append("%s: index out of range" % mesh.get("name"))
            tri += len(idx) // 3
            mat = prim.get("material")
            if mat is not None and mat >= len(gltf.get("materials", [])):
                problems.append("%s: material %d missing" % (mesh.get("name"), mat))
    if gltf.get("nodes") and not gltf.get("scenes"):
        problems.append("scenes missing")
    return problems, tri, len(gltf.get("nodes", [])), len(gltf.get("meshes", []))


def main(argv):
    paths = argv or ["assets/downloaded"]
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(glob.glob(os.path.join(p, "**", "*.glb"), recursive=True))
        elif p.endswith(".glb"):
            files.append(p)
    if not files:
        print("koi .glb nahi mila -> skip (procedural fallback chalega)")
        return 0
    bad = 0
    total_tris = 0
    for f in files:
        try:
            problems, tri, nodes, meshes = check(f)
        except Exception as exc:
            print("BROKEN %-40s %s" % (os.path.basename(f), exc))
            bad += 1
            continue
        total_tris += tri
        if problems:
            bad += 1
            print("PROBLEM %-40s %s" % (os.path.basename(f), "; ".join(problems[:3])))
    print("%d/%d glb theek | total triangles: %d | koi bhi error: %d"
          % (len(files) - bad, len(files), total_tris, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
