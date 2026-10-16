#!/usr/bin/env python3
"""OBJ (+MTL) -> GLB converter for the CC0 Quaternius weapon pack in assets/downloaded_obj/.

Why this exists
---------------
The game needs `assets/models/weapons/<Name>.glb` (Godot imports .glb natively and
`scripts/asset_loader.gd` loads those at runtime - exactly like the FBX pack in
`assets/downloaded/`). Godot 4.2 has no reliable .obj pipeline of its own, so the CI
workflow runs this script once per build (workflow step "7d-obj") and writes a .glb
next to every .obj. Pure Python 3 stdlib - no numpy, no external converter.

    python3 tools/obj2glb.py assets/downloaded_obj --out-root assets/models
    python3 tools/obj2glb.py assets/downloaded_obj/Weapons/Pistol_1.obj --out-dir /tmp/x

What it does per model
----------------------
* reads .obj (v / vn / f, `usemtl` groups) and the matching .mtl (Kd colour, Ns, d)
* **muzzle convention**: this pack models every gun with the barrel towards **+X**
  (verified visually for all 40 models - renders in docs/model-integration-report.md).
  The model is rotated so that +X goes to **-Z**, so the barrel points -Z like the
  game expects (same rule as the FBX pack: muzzle -Z, +Y up).
* **winding check (inside-out fix)**: the geometric normal of each triangle is compared
  with the .obj's own `vn` normals. If most faces disagree, the winding is flipped so
  the model is not rendered inside-out (Godot culls back faces by default).
* normalises size: longest side -> 1.0 m and the model is centred on its own origin.
  `scripts/assets.gd` then scales it to the per-weapon target length (pistol 0.30 m,
  rifle 1.20 m, ...), so the numbers here stay unit-free.
* normals are sanitised (zero/NaN -> face normal) - Godot warns about non-finite normals.

Nothing here touches gameplay: a model that fails to convert is simply skipped, and
`scripts/assets.gd` builds the procedural fallback shape for it.
"""

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fbx2glb import (GlbBuilder, aabb, axis_extent, build_primitives,  # noqa: E402
                     mat_apply, mat_identity, mat_rot_x, mat_rot_y)


# ------------------------------------------------------------------ parsing ---

def parse_mtl(path):
    """-> {material_name: (r, g, b)} (Kd; default mid grey)."""
    if not os.path.exists(path):
        return {}
    out = {}
    name = None
    for line in open(path, "r", errors="replace"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        key = parts[0].lower()
        if key == "newmtl":
            name = line[len(parts[0]):].strip()
            out.setdefault(name, (0.62, 0.62, 0.64))
        elif key == "kd" and name and len(parts) >= 4:
            try:
                out[name] = (float(parts[1]), float(parts[2]), float(parts[3]))
            except ValueError:
                pass
    return out


def parse_obj(path):
    """-> dict(verts, polys, poly_mats, poly_normals, mtl_file, counts)"""
    verts, normals = [], []
    polys, poly_mats, poly_normals = [], [], []
    mtl_file = ""
    cur_mat = ""
    for line in open(path, "r", errors="replace"):
        if line.startswith("v "):
            p = line.split()
            verts.append((float(p[1]), float(p[2]), float(p[3])))
        elif line.startswith("vn "):
            p = line.split()
            normals.append((float(p[1]), float(p[2]), float(p[3])))
        elif line.startswith("f "):
            v_idx, n_idx = [], []
            for tok in line.split()[1:]:
                bits = tok.split("/")
                if len(bits) >= 3 and bits[2]:
                    n_idx.append(int(bits[2]))
                else:
                    n_idx.append(0)
                v_idx.append(int(bits[0]))
            if len(v_idx) < 3:
                continue
            polys.append(v_idx)
            poly_mats.append(cur_mat)
            poly_normals.append(n_idx)
        elif line.startswith("usemtl"):
            cur_mat = line.split(None, 1)[1].strip() if len(line.split(None, 1)) > 1 else ""
        elif line.startswith("mtllib"):
            mtl_file = line.split(None, 1)[1].strip() if len(line.split(None, 1)) > 1 else ""

    def fix(idx, count):
        return idx - 1 if idx > 0 else count + idx        # OBJ 1-based / negative = relative

    verts = [tuple(v) for v in verts]
    flat_polys, flat_normals = [], []
    for p, n in zip(polys, poly_normals):
        tri_v, tri_n = [], []
        for vi, ni in zip(p, n):
            tri_v.append(fix(vi, len(verts)))
            tri_n.append(fix(ni, len(normals)) if ni else -1)
        flat_polys.append(tri_v)
        flat_normals.append(tri_n)
    return {"verts": verts, "polys": flat_polys, "poly_mats": poly_mats,
            "poly_normals": flat_normals, "normals": normals, "mtl_file": mtl_file}


# ---------------------------------------------------------------- geometry ----

def face_normal(a, b, c):
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    ln = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
    return (n[0] / ln, n[1] / ln, n[2] / ln) if ln > 1e-12 else None


def winding_is_inverted(data, sample=400):
    """Face winding vs the .obj ke `vn` normals. True = inside-out (winding flip chahiye)."""
    verts, normals = data["verts"], data["normals"]
    if not normals:
        return False, "vn nahi hain (skip)"
    agree = disagree = 0
    step = max(1, len(data["polys"]) // sample)
    for pi in range(0, len(data["polys"]), step):
        p, n = data["polys"][pi], data["poly_normals"][pi]
        if len(p) < 3 or any(x < 0 for x in n[:3]):
            continue
        a, b, c = verts[p[0]], verts[p[1]], verts[p[2]]
        fn = face_normal(a, b, c)
        if fn is None:
            continue
        vn = normals[n[0]]
        ln = math.sqrt(sum(x * x for x in vn)) or 1.0
        vn = (vn[0] / ln, vn[1] / ln, vn[2] / ln)
        dot = fn[0] * vn[0] + fn[1] * vn[1] + fn[2] * vn[2]
        if dot >= 0:
            agree += 1
        else:
            disagree += 1
    total = agree + disagree
    if total == 0:
        return False, "check nahi ho paya"
    ratio = agree / total
    return (ratio < 0.4), f"{agree}/{total} face normals match"


def orient_matrix(points, report):
    """Godot axes: +Y up, barrel -Z (is pack me barrel +X pe hota hai)."""
    lo, hi = aabb(points)
    ext = [hi[i] - lo[i] for i in range(3)]
    longest = max(range(3), key=lambda i: ext[i])
    if longest == 0:
        O = mat_rot_y(90.0)
        note = "length X -> Z (rotY 90: muzzle +X -> -Z)"
    elif longest == 1:
        O = mat_rot_x(-90.0)
        note = "length Y -> Z (rotX -90)"
    else:
        O = mat_identity()
        note = "length Z (as-is)"
    report["orient"] = note

    # ---- ambiguity warning (kabhi khud flip nahi karte — dekho docs) ----
    pts = [mat_apply(O, p) for p in points]
    lo2, hi2 = aabb(pts)
    span = hi2[2] - lo2[2]
    if span > 1e-6:
        slice_len = span * 0.15
        muzzle = axis_extent(pts, 2, lo2[2], lo2[2] + slice_len)
        stock = axis_extent(pts, 2, hi2[2] - slice_len, hi2[2])
        ratio = stock / max(muzzle, 1e-6)
        report["spread_ratio"] = round(ratio, 2)
        if ratio < 1.15:
            report["orient_warn"] = ("muzzle/stock ka farq kam hai (ratio %.2f) — "
                                     "manual review" % ratio)
    return O


def convert(path, pack_muzzle_axis="+x"):
    base = os.path.splitext(os.path.basename(path))[0]
    data = parse_obj(path)
    report = {"file": os.path.basename(path), "kind": "weapon",
              "src_bytes": os.path.getsize(path),
              "verts": len(data["verts"]), "polys": len(data["polys"])}
    if not data["verts"] or not data["polys"]:
        return None, report

    mtl_path = os.path.join(os.path.dirname(path), data["mtl_file"]) if data["mtl_file"] else \
        os.path.splitext(path)[0] + ".mtl"
    palette = parse_mtl(mtl_path)
    report["materials"] = sorted(palette.keys())
    report["mtl_found"] = bool(palette)

    flip, winding_note = winding_is_inverted(data)
    report["winding"] = ("ulta tha -> flip kiya (" + winding_note + ")") if flip \
        else ("theek (" + winding_note + ")")

    # ---- orientation + size ----
    O = orient_matrix(data["verts"], report)
    pts = [mat_apply(O, v) for v in data["verts"]]
    lo, hi = aabb(pts)
    ext = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    biggest = max(ext)
    s = 1.0 / biggest if biggest > 1e-6 else 1.0
    pivot = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    report["aabb_src"] = [[round(v, 2) for v in lo], [round(v, 2) for v in hi]]
    report["aabb_out"] = [round(v * s, 3) for v in ext]
    report["scale"] = round(s, 5)

    def xf(p):
        q = mat_apply(O, p)
        return ((q[0] - pivot[0]) * s, (q[1] - pivot[1]) * s, (q[2] - pivot[2]) * s)

    # ---- material slots (per polygon) ----
    used = []
    for m in data["poly_mats"]:
        if m not in used:
            used.append(m)
    slot_of = {name: i for i, name in enumerate(used)}
    slots = [slot_of[m] for m in data["poly_mats"]]
    mat_ids = list(range(len(used)))
    mat_lookup = {i: (name or "Default", palette.get(name, (0.62, 0.62, 0.64)))
                  for i, name in enumerate(used)}

    # per-polygon-vertex normals (flat array, jaise build_primitives expect karta hai)
    flat = []
    for p, n in zip(data["polys"], data["poly_normals"]):
        for ni in n:
            if 0 <= ni < len(data["normals"]):
                flat.append(mat_apply(O, data["normals"][ni]))
            else:
                flat.append((0.0, 1.0, 0.0))

    builder = GlbBuilder()
    prims = build_primitives(builder, data["verts"], data["polys"],
                             ("ByPolygonVertex", flat, None), None,
                             slots, mat_ids, mat_lookup, xf, flip, name=base)
    if not prims:
        return None, report
    mesh_idx = builder.add_mesh(base, prims)
    node = len(builder.nodes)
    builder.nodes.append({"name": base, "mesh": mesh_idx})
    builder.nodes.append({"name": base + "_root", "children": [node]})
    builder.root_nodes = [len(builder.nodes) - 1]
    data_glb = builder.to_glb()
    report["glb_bytes"] = len(data_glb)
    report["primitives"] = len(prims)
    return data_glb, report


# -------------------------------------------------------------------- main ----

def find_files(inputs, exts=(".obj",)):
    out = []
    for entry in inputs:
        if os.path.isdir(entry):
            for dirpath, _dirs, names in os.walk(entry):
                out += [os.path.join(dirpath, n) for n in sorted(names)
                        if n.lower().endswith(exts)]
        else:
            out.append(entry)
    return out


def main(argv):
    ap = argparse.ArgumentParser(description="OBJ+MTL -> GLB converter (CC0 weapon pack)")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out-dir", default=None, help="saari .glb ek hi folder me")
    ap.add_argument("--out-root", default=None,
                    help="<out-root>/<category>/<file>.glb (category = source folder, lowercase)")
    ap.add_argument("--muzzle-axis", default="+x", choices=["+x", "-x"],
                    help="source me barrel kis taraf hai (+x = default, is pack ka rule)")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--report", default="", help="JSON report ka path")
    args = ap.parse_args(argv)

    files = find_files(args.inputs)
    if not files:
        print("koi .obj nahi mila")
        return 0

    ok = 0
    total_in = total_out = 0
    reports = []
    warnings = 0
    for f in files:
        if args.out_root:
            out_dir = os.path.join(args.out_root, os.path.basename(os.path.dirname(f)).lower())
        else:
            out_dir = args.out_dir or os.path.dirname(f)
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, os.path.splitext(os.path.basename(f))[0] + ".glb")
        try:
            data, report = convert(f, args.muzzle_axis)
        except Exception as exc:                      # fail-soft: koi bhi galti -> skip
            print("FAIL %s: %r" % (f, exc))
            continue
        if data is None:
            print("SKIP %s" % f)
            continue
        with open(out_path, "wb") as fh:
            fh.write(data)
        ok += 1
        reports.append(report)
        total_in += report["src_bytes"]
        total_out += len(data)
        if not args.quiet:
            flag = ""
            if report.get("orient_warn"):
                flag = "  WARNING: " + report["orient_warn"]
                warnings += 1
            print("OK %-24s %6.1fKB -> %6.1fKB  v=%-5d f=%-5d mats=%d  winding=%s%s"
                  % (os.path.basename(f), report["src_bytes"] / 1024, len(data) / 1024,
                     report["verts"], report["polys"], len(report.get("materials", [])),
                     report["winding"], flag))
    print("\n%d/%d converted   %.2fMB -> %.2fMB   (warnings: %d)"
          % (ok, len(files), total_in / 1024 / 1024, total_out / 1024 / 1024, warnings))
    if args.report:
        with open(args.report, "w") as fh:
            json.dump({"converted": ok, "total": len(files), "src_bytes": total_in,
                       "glb_bytes": total_out, "models": reports}, fh, indent=1)
        print("report:", args.report)
    return 0 if ok == len(files) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
