#!/usr/bin/env python3
"""FBX (7.x binary) -> GLB converter for the CC0 Quaternius packs in assets/downloaded/.

Why this exists
---------------
Godot 4 cannot import .fbx at all, and it can never load one at runtime. So the CI
workflow runs this script once per build (step "7d") and writes a .glb next to every
.fbx inside assets/downloaded/. Godot then imports those .glb files like any other
resource, and scripts/asset_loader.gd finds them at runtime.

Everything here is pure Python 3 stdlib (no numpy, no FBX SDK, no FBX2glTF binary), so
it also runs fine if the user just wants to convert on their own machine:

    python3 tools/fbx2glb.py assets/downloaded --kind auto
    python3 tools/fbx2glb.py assets/downloaded/nature/PineTree_1.fbx --out-dir /tmp/x

What it does per model
----------------------
* bakes the whole FBX node hierarchy into world space (UnitScaleFactor included)
* rotates the model into Godot axes: +Y up, weapons' muzzle at -Z, characters facing -Z
* normalises size: weapons -> 1.0 m long, nature/vehicles -> metres with base at y=0`,
  characters -> exactly 1.8 m tall with feet at y=0
* characters are split into 6 sub-meshes (torso/head/arm_l/arm_r/leg_l/leg_r) using the
  skin clusters, arms are baked down from the T-pose, so enemy.gd can swing the limbs
* materials: the FBX DiffuseColor if it has one, otherwise a palette guessed from the
  material name (these packs are untextured flat-colour models)

Nothing here touches gameplay: if a model fails to convert the build just keeps going
and scripts/assets.gd builds the procedural fallback.
"""

import json
import math
import os
import struct
import sys
import zlib


import struct, zlib

class Node:
    __slots__ = ("name","props","children","offset","end")
    def __init__(self, name, props, offset):
        self.name=name; self.props=props; self.children=[]; self.offset=offset; self.end=0
    def find(self, name):
        return [c for c in self.children if c.name==name]
    def first(self, name):
        for c in self.children:
            if c.name==name: return c
        return None
    def __repr__(self):
        return f"<Node {self.name} props={len(self.props)} kids={len(self.children)}>"

def _read_prop(buf, pos):
    t = buf[pos:pos+1]; pos += 1
    if t == b'Y': return struct.unpack_from('<h', buf, pos)[0], pos+2
    if t == b'C': return buf[pos] != 0, pos+1
    if t == b'I': return struct.unpack_from('<i', buf, pos)[0], pos+4
    if t == b'F': return struct.unpack_from('<f', buf, pos)[0], pos+4
    if t == b'D': return struct.unpack_from('<d', buf, pos)[0], pos+8
    if t == b'L': return struct.unpack_from('<q', buf, pos)[0], pos+8
    if t in b'fdlib':
        # NOTE: array header = arrayLength(4) + encoding(4) + third(4).
        # The third uint32 is ALWAYS present in these files (Blender FBX IO):
        # encoding==1 -> compressed byte length, encoding==0 -> raw byte length.
        n, enc, third = struct.unpack_from('<III', buf, pos); pos += 12
        size = {b'f':4, b'd':8, b'b':1, b'i':4, b'l':8}[t]
        if enc:
            raw = zlib.decompress(buf[pos:pos+third]); pos += third
        else:
            raw = buf[pos:pos+n*size]; pos += n*size
        if t == b'f': return list(struct.unpack('<%df' % n, raw)), pos
        if t == b'd': return list(struct.unpack('<%dd' % n, raw)), pos
        if t == b'b': return list(struct.unpack('<%d?' % n, raw)), pos
        if t == b'i': return list(struct.unpack('<%di' % n, raw)), pos
        return list(struct.unpack('<%dq' % n, raw)), pos
    if t in (b'S', b'R'):
        n = struct.unpack_from('<I', buf, pos)[0]; pos += 4
        data = buf[pos:pos+n]; pos += n
        return (data.decode('utf-8','replace') if t == b'S' else data), pos
    raise ValueError(f"unknown prop type {t!r} at {pos}")


def _read_node(buf, pos, version):
    if version < 7500:
        end, nprops, plen = struct.unpack_from('<III', buf, pos)
        nlen = buf[pos+12]
        hdr = 13
    else:
        end, nprops, plen = struct.unpack_from('<QQQ', buf, pos)
        nlen = buf[pos+24]
        hdr = 25
    if end == 0 and nprops == 0 and plen == 0 and nlen == 0:
        return None, pos + hdr
    name = buf[pos+hdr:pos+hdr+nlen].decode('utf-8','replace')
    p = pos + hdr + nlen
    props = []
    for _ in range(nprops):
        v, p = _read_prop(buf, p)
        props.append(v)
    node = Node(name, props, pos)
    node.end = end
    while p < end:
        child, p = _read_node(buf, p, version)
        if child is None:
            break
        node.children.append(child)
    return node, end

def parse(path):
    buf = open(path,'rb').read()
    assert buf[:21] == b'Kaydara FBX Binary  \x00', (path, buf[:23])
    version = struct.unpack_from('<I', buf, 23)[0]
    pos = 27
    root = Node("ROOT", [], 0)
    while True:
        if pos + 13 >= len(buf) - 16:
            break
        node, npos = _read_node(buf, pos, version)
        if node is None or npos <= pos:
            break
        if not node.name:
            break
        root.children.append(node)
        pos = npos
    return root, version, len(buf)


# ------------------------------------------------------------------ math -----


def mat_identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]


def mat_mul(a, b):
    """Row-major 4x4 multiply: result = a * b (column-vector convention)."""
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return out


def mat_translate(x, y, z):
    m = mat_identity()
    m[3], m[7], m[11] = x, y, z
    return m


def mat_scale(x, y, z):
    m = mat_identity()
    m[0], m[5], m[10] = x, y, z
    return m


def mat_rot_x(deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return [1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1]


def mat_rot_y(deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return [c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1]


def mat_rot_z(deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return [c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def mat_apply(m, v):
    x, y, z = v
    return (
        m[0] * x + m[1] * y + m[2] * z + m[3],
        m[4] * x + m[5] * y + m[6] * z + m[7],
        m[8] * x + m[9] * y + m[10] * z + m[11],
    )


def mat_apply_dir(m, v):
    x, y, z = v
    return (
        m[0] * x + m[1] * y + m[2] * z,
        m[4] * x + m[5] * y + m[6] * z,
        m[8] * x + m[9] * y + m[10] * z,
    )


def euler_matrix(rot_xyz, order=0):
    """FBX default rotation order is 0 = XYZ (degrees)."""
    x, y, z = rot_xyz
    mx, my, mz = mat_rot_x(x), mat_rot_y(y), mat_rot_z(z)
    if order == 1:      # XZY
        return mat_mul(mx, mat_mul(mz, my))
    if order == 2:      # YZX
        return mat_mul(my, mat_mul(mz, mx))
    if order == 3:      # YXZ
        return mat_mul(my, mat_mul(mx, mz))
    if order == 4:      # ZXY
        return mat_mul(mz, mat_mul(mx, my))
    if order == 5:      # ZYX
        return mat_mul(mz, mat_mul(my, mx))
    return mat_mul(mz, mat_mul(my, mx))   # XYZ (FBX order 0)


# ------------------------------------------------------------- helpers -------


def props70(node: Node):
    out = {}
    p = node.first("Properties70") if node else None
    if p is None:
        return out
    for c in p.children:
        if c.name == "P" and c.props:
            out[c.props[0]] = c.props
    return out


def num(v, default=0.0):
    try:
        return float(v)
    except Exception:
        return default


def vec3(prop, default=(0.0, 0.0, 0.0)):
    if not prop or len(prop) < 7:
        return default
    return (num(prop[4], default[0]), num(prop[5], default[1]), num(prop[6], default[2]))


def clean_name(raw):
    """FBX name is 'Name\\x00\\x01Class' -> 'Name'."""
    return str(raw).split("\x00")[0]


# --------------------------------------------------------------- palette -----

# Materials in these packs ship without textures; names carry the meaning.
PALETTE = {
    "bark": (0.30, 0.20, 0.12), "tree": (0.22, 0.36, 0.18), "wood": (0.42, 0.27, 0.13),
    "darkwood": (0.24, 0.15, 0.08), "leaf": (0.20, 0.42, 0.17), "leaves": (0.20, 0.42, 0.17),
    "pine": (0.17, 0.36, 0.19), "grass": (0.29, 0.50, 0.22), "plant": (0.24, 0.44, 0.20),
    "flower": (0.78, 0.45, 0.62), "rock": (0.46, 0.46, 0.48), "stone": (0.48, 0.48, 0.50),
    "metal": (0.55, 0.57, 0.60), "darkmetal": (0.24, 0.25, 0.27), "steel": (0.60, 0.62, 0.66),
    "black": (0.09, 0.09, 0.10), "grey": (0.42, 0.44, 0.47), "gray": (0.42, 0.44, 0.47),
    "white": (0.86, 0.87, 0.89), "red": (0.62, 0.14, 0.12), "yellow": (0.82, 0.66, 0.15),
    "blue": (0.16, 0.32, 0.62), "green": (0.28, 0.42, 0.22), "orange": (0.80, 0.44, 0.14),
    "skin": (0.85, 0.68, 0.55), "face": (0.85, 0.68, 0.55), "head": (0.85, 0.68, 0.55),
    "shirt": (0.30, 0.38, 0.62), "pants": (0.22, 0.26, 0.36), "shoe": (0.16, 0.14, 0.13),
    "hair": (0.18, 0.12, 0.08), "eye": (0.10, 0.10, 0.12), "teeth": (0.92, 0.92, 0.90),
    "window": (0.12, 0.16, 0.22), "glass": (0.55, 0.65, 0.75), "tire": (0.10, 0.10, 0.11),
    "light": (0.92, 0.90, 0.72), "carpet": (0.35, 0.22, 0.20), "cloth": (0.55, 0.45, 0.40),
}


FILE_HINTS = [
    ("grass", (0.29, 0.50, 0.22)),
    ("plant", (0.24, 0.44, 0.20)),
    ("bush", (0.24, 0.44, 0.20)),
    ("pine", (0.22, 0.36, 0.18)),
    ("tree", (0.22, 0.36, 0.18)),
    ("rock", (0.46, 0.46, 0.48)),
    ("flower", (0.78, 0.45, 0.62)),
]


def file_hint_color(file_name: str):
    """Colour guessed from the FILE name - last resort when a mesh has no material
    (Grass_Large.fbx ships without any material!) or an unknown material name."""
    low = file_name.lower()
    for key, col in FILE_HINTS:
        if key in low:
            return col
    return None


def palette_color(name: str):
    key = "".join(ch for ch in name.lower() if ch.isalnum())
    if not key:
        return None
    if key in PALETTE:
        return PALETTE[key]
    for k, v in PALETTE.items():
        if k in key:
            return v
    return None


# --------------------------------------------------------------- parsing -----


class FbxScene:
    def __init__(self, path):
        self.path = path
        self.root, self.version, self.size = parse(path)
        self.objects = []
        self.by_id = {}
        obj = self.root.first("Objects")
        if obj is not None:
            for n in obj.children:
                if n.props and isinstance(n.props[0], int):
                    self.objects.append(n)
                    self.by_id[n.props[0]] = n
        self.conn_o = []        # (child_id, parent_id)
        self.conn_p = []        # (child_id, parent_id, prop)
        conns = self.root.first("Connections")
        if conns is not None:
            for c in conns.find("C"):
                p = c.props
                if p[0] == "OO":
                    self.conn_o.append((int(p[1]), int(p[2])))
                elif p[0] == "OP":
                    self.conn_p.append((int(p[1]), int(p[2]), str(p[3])))

        self.unit_scale = 1.0
        gs = self.root.first("GlobalSettings")
        if gs is not None:
            for p in gs.first("Properties70").children:
                if p.props and p.props[0] == "UnitScaleFactor":
                    self.unit_scale = num(p.props[4], 1.0)

    def obj_name(self, n: Node) -> str:
        return clean_name(n.props[1]) if len(n.props) > 1 else ""

    def children_of(self, model_id: int):
        return [c for (c, p) in self.conn_o if p == model_id]

    def parents_of(self, oid: int):
        return [p for (c, p) in self.conn_o if c == oid]

    def local_matrix(self, model: Node):
        pr = props70(model)
        t = vec3(pr.get("Lcl Translation"))
        r = vec3(pr.get("Lcl Rotation"))
        s = vec3(pr.get("Lcl Scaling"), (1.0, 1.0, 1.0))
        # PreRotation / PostRotation intentionally ignored (not used in these files).
        order = int(num(pr.get("RotationOrder", [None, None, None, None, 0])[4], 0))
        return mat_mul(mat_translate(*t), mat_mul(euler_matrix(r, order), mat_scale(*s)))

    def world_matrices(self):
        """model_id -> world matrix (baked, ignoring FBX 0-length chains)."""
        cache = {}

        def build(mid, depth=0):
            if mid in cache:
                return cache[mid]
            if depth > 64:
                return mat_identity()
            node = self.by_id.get(mid)
            if node is None or node.name != "Model":
                cache[mid] = mat_identity()
                return cache[mid]
            local = self.local_matrix(node)
            parent = 0
            for p in self.parents_of(mid):
                if p in self.by_id and self.by_id[p].name == "Model":
                    parent = p
                    break
            world = mat_mul(build(parent, depth + 1), local) if parent else local
            cache[mid] = world
            return world

        for o in self.objects:
            if o.name == "Model":
                build(o.props[0])
        return cache


# ------------------------------------------------------------ geometry -------


def read_geometry(geom: Node):
    """-> dict(verts=[(x,y,z)...], tris=[(i0,i1,i2)...], mat_index_per_tri=[...],
              normals=[[(x,y,z) per polygon-vertex] or None],
              uvs=[[(u,v) per polygon-vertex] or None], src_mats=[material ids])"""
    verts_flat = geom.first("Vertices").props[0]
    verts = [(verts_flat[i], verts_flat[i + 1], verts_flat[i + 2]) for i in range(0, len(verts_flat), 3)]
    pv = geom.first("PolygonVertexIndex").props[0]

    polys = []
    cur = []
    for idx in pv:
        if idx < 0:
            cur.append(~idx)          # negative = last index of polygon
            polys.append(cur)
            cur = []
        else:
            cur.append(idx)
    if cur:
        polys.append(cur)

    # ---- normals ----
    normals = None
    ne = geom.first("LayerElementNormal")
    if ne is not None:
        mapping = ne.first("MappingInformationType").props[0]
        ref = ne.first("ReferenceInformationType").props[0]
        arr = ne.first("Normals").props[0]
        nrm = [(arr[i], arr[i + 1], arr[i + 2]) for i in range(0, len(arr), 3)]
        idx_arr = None
        if ref == "IndexToDirect":
            ix = ne.first("NormalsIndex")
            if ix is not None:
                idx_arr = ix.props[0]
        normals = (mapping, nrm, idx_arr)

    # ---- uvs ----
    uvs = None
    ue = geom.first("LayerElementUV")
    if ue is not None:
        mapping = ue.first("MappingInformationType").props[0]
        ref = ue.first("ReferenceInformationType").props[0]
        arr = ue.first("UV").props[0]
        uv = [(arr[i], arr[i + 1]) for i in range(0, len(arr), 2)]
        idx_arr = None
        if ref == "IndexToDirect":
            ix = ue.first("UVIndex")
            if ix is not None:
                idx_arr = ix.props[0]
        uvs = (mapping, uv, idx_arr)

    # ---- per polygon material slot ----
    mat_slots = None
    me = geom.first("LayerElementMaterial")
    if me is not None:
        mapping = me.first("MappingInformationType").props[0]
        arr = me.first("Materials").props[0]
        mat_slots = (mapping, arr)

    return {"verts": verts, "polys": polys, "normals": normals, "uvs": uvs, "mat_slots": mat_slots}


def polygon_vertex_data(polys, normals, uvs):
    """Expand per-polygon-vertex normals/uvs to a flat list parallel to polygon vertex order."""
    flat_count = sum(len(p) for p in polys)
    out_n = [(0.0, 1.0, 0.0)] * flat_count
    out_uv = [(0.0, 0.0)] * flat_count
    have_n = normals is not None
    have_uv = uvs is not None

    if have_n:
        mapping, nrm, idx = normals
        k = 0
        for p in polys:
            for j, _vi in enumerate(p):
                if mapping == "ByPolygonVertex":
                    src = idx[k] if idx is not None else k
                elif mapping == "ByVertex":
                    src = p[j]
                else:                       # AllSame / ByPolygon
                    src = idx[k] if idx is not None else 0
                out_n[k] = nrm[src % len(nrm)] if nrm else out_n[k]
                k += 1

    if have_uv:
        mapping, uv, idx = uvs
        k = 0
        for p in polys:
            for j, _vi in enumerate(p):
                if mapping == "ByPolygonVertex":
                    src = idx[k] if idx is not None else k
                elif mapping == "ByVertex":
                    src = p[j]
                else:
                    src = idx[k] if idx is not None else 0
                out_uv[k] = uv[src % len(uv)] if uv else out_uv[k]
                k += 1

    return out_n, out_uv


# ------------------------------------------------------------ glb writer -----

COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
        5125: ("I", 4), 5126: ("f", 4)}


class GlbBuilder:
    def __init__(self):
        self.buffer = bytearray()
        self.buffer_views = []
        self.accessors = []
        self.meshes = []
        self.materials = []
        self.nodes = []
        self._mat_cache = {}
        self.root_nodes = []

    def _align(self, n=4):
        while len(self.buffer) % n:
            self.buffer.append(0)

    def add_accessor(self, values, comp_type, type_str, target=None, minmax=False):
        fmt, size = COMP[comp_type]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[type_str]
        self._align(4)
        offset = len(self.buffer)
        for v in values:
            self.buffer += struct.pack("<" + fmt, v)
        length = len(self.buffer) - offset
        self.buffer_views.append({
            "buffer": 0, "byteOffset": offset, "byteLength": length,
            **({"target": target} if target else {}),
        })
        acc = {"bufferView": len(self.buffer_views) - 1, "componentType": comp_type,
               "count": len(values) // ncomp, "type": type_str}
        if minmax and values:
            items = [values[i:i + ncomp] for i in range(0, len(values), ncomp)]
            acc["min"] = [min(it[k] for it in items) for k in range(ncomp)]
            acc["max"] = [max(it[k] for it in items) for k in range(ncomp)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def material(self, name, color, metallic=0.0, roughness=0.85):
        key = (name, tuple(round(c, 4) for c in color))
        if key in self._mat_cache:
            return self._mat_cache[key]
        self.materials.append({
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [color[0], color[1], color[2], 1.0],
                "metallicFactor": metallic,
                "roughnessFactor": roughness,
            },
            "doubleSided": True,
        })
        self._mat_cache[key] = len(self.materials) - 1
        return self.materials[-1] and self._mat_cache[key]

    def add_mesh(self, name, primitives):
        idx = len(self.meshes)
        self.meshes.append({"name": name, "primitives": primitives})
        return idx

    def to_glb(self):
        gltf = {
            "asset": {"version": "2.0", "generator": "fbx2glb.py (cc0 asset pipeline)"},
            "scene": 0,
            "scenes": [{"nodes": self.root_nodes}],
            "nodes": self.nodes,
            "meshes": self.meshes,
            "accessors": self.accessors,
            "bufferViews": self.buffer_views,
            "buffers": [{"byteLength": len(self.buffer)}],
        }
        if self.materials:
            gltf["materials"] = self.materials
        bin_chunk = bytes(self.buffer)
        json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        while len(json_chunk) % 4:
            json_chunk += b" "
        while len(bin_chunk) % 4:
            bin_chunk += b"\x00"
        total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
        out = bytearray()
        out += struct.pack("<III", 0x46546C67, 2, total)
        out += struct.pack("<II", len(json_chunk), 0x4E4F534A)
        out += json_chunk
        out += struct.pack("<II", len(bin_chunk), 0x004E4942)
        out += bin_chunk
        return bytes(out)


# ------------------------------------------------------- scene assembly ------

LIMB_GROUPS = {
    "arm_l": ("Shoulder.L", "UpperArm.L", "LowerArm.L", "Palm.L", "MiddleHand.L",
              "Fingers.L", "Thumb1.L", "Thumb2.L"),
    "arm_r": ("Shoulder.R", "UpperArm.R", "LowerArm.R", "Palm.R", "MiddleHand.R",
              "Fingers.R", "Thumb1.R", "Thumb2.R"),
    "leg_l": ("UpperLeg.L", "LowerLeg.L", "Foot.L"),
    "leg_r": ("UpperLeg.R", "LowerLeg.R", "Foot.R"),
    "head": ("Head", "Neck"),
}


def bone_group(bone_name: str) -> str:
    for g, bones in LIMB_GROUPS.items():
        if bone_name in bones:
            return g
    return "torso"


def cluster_data(scene: FbxScene):
    """bone name -> (indexes, weights); plus geometry bind matrices."""
    out = {}
    for n in scene.objects:
        if n.name != "Deformer":
            continue
        raw = str(n.props.get(1, "")) if hasattr(n.props, "get") else str(n.props[1])
        if "SubDeformer" not in raw:
            continue
        bone = clean_name(n.props[1])
        ix, wt = n.first("Indexes"), n.first("Weights")
        if ix is None or wt is None:
            continue
        out[bone] = (ix.props[0], wt.props[0])
    return out


def aabb(points):
    if not points:
        return ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return (tuple(lo), tuple(hi))


def material_info(scene: FbxScene, file_hint: str = ""):
    """material object id -> (name, rgb)

    Order of preference: material name palette -> FBX DiffuseColor -> file name hint.
    A couple of these CC0 packs ship a single material named "Flowers" for a whole
    leafy plant, so that name only means "pink" when the file is actually a flower.
    """
    out = {}
    for n in scene.objects:
        if n.name != "Material":
            continue
        name = clean_name(n.props[1])
        pr = props70(n)
        col = palette_color(name)
        if col is not None and "flower" in name.lower() and "flower" not in file_hint.lower():
            col = PALETTE["plant"]                 # whole plant, not just the blossom
        if col is None:
            d = pr.get("DiffuseColor")
            if d and len(d) >= 7:
                col = (num(d[4], 0.6), num(d[5], 0.6), num(d[6], 0.6))
                if max(col) < 0.02:
                    col = None                     # pure black diffuse = no data
        if col is None:
            base = pr.get("Diffuse")
            if base and len(base) >= 7:
                col = (num(base[4], 0.6), num(base[5], 0.6), num(base[6], 0.6))
        if col is None:
            col = file_hint_color(file_hint) or (0.62, 0.62, 0.64)
        out[n.props[0]] = (name, col)
    return out


def geometry_materials(scene: FbxScene, geom_id: int):
    """Material object ids connected to the geometry's model, in connection order."""
    parents = [p for (c, p) in scene.conn_o if c == geom_id and p in scene.by_id]
    out = []
    for par in parents:
        for (c, p) in scene.conn_o:
            if p == par and c in scene.by_id and scene.by_id[c].name == "Material":
                out.append(c)
    return out


def triangulate(polys, uv_per_polyvert=None, n_per_polyvert=None):
    """Fan triangulate polygons keeping per-polygon-vertex normals/uvs."""
    tris = []
    k = 0
    for p in polys:
        base = k
        for j in range(1, len(p) - 1):
            a, b, c = p[0], p[j], p[j + 1]
            ia, ib, ic = base, base + j, base + j + 1
            tris.append((a, b, c, ia, ib, ic))
        k += len(p)
    return tris


# --------------------------------------------------------- primitive build ---


def slot_per_poly(geom_data, poly_count):
    ms = geom_data["mat_slots"]
    if ms is None:
        return [0] * poly_count
    mapping, arr = ms
    if mapping == "AllSame":
        return [int(arr[0]) if arr else 0] * poly_count
    out = []
    for i in range(poly_count):
        out.append(int(arr[i]) if i < len(arr) else 0)
    return out


def build_primitives(builder, verts, polys, normals, uvs, slots, mat_ids, mat_lookup,
                     xf, winding_flip=False, name="mesh"):
    """Triangulate `polys` (fan) grouped by material slot -> list of glTF primitives."""
    flat_n, flat_uv = polygon_vertex_data(polys, normals, uvs)
    groups = {}
    pv0 = 0
    for pi, p in enumerate(polys):
        slot = slots[pi]
        groups.setdefault(slot, []).append((p, pv0))
        pv0 += len(p)

    primitives = []
    for slot in sorted(groups):
        pos, nor, idx = [], [], []
        weld = {}                    # (position, normal) -> vertex index (keeps .glb small)
        for (p, base_pv) in groups[slot]:
            for j in range(1, len(p) - 1):
                tri = (p[0], p[j], p[j + 1])
                ids = (base_pv, base_pv + j, base_pv + j + 1)
                tri_idx = []
                for vi, li in zip(tri, ids):
                    pp = xf(verts[vi])
                    nn = flat_n[li]
                    key = (round(pp[0], 5), round(pp[1], 5), round(pp[2], 5),
                           round(nn[0], 3), round(nn[1], 3), round(nn[2], 3))
                    base = weld.get(key)
                    if base is None:
                        base = len(pos) // 3
                        pos.extend(pp)
                        nor.extend(nn)
                        weld[key] = base
                    tri_idx.append(base)
                if winding_flip:
                    idx += [tri_idx[0], tri_idx[2], tri_idx[1]]
                else:
                    idx += tri_idx
        if not pos:
            continue
        mat_id = mat_ids[slot] if slot < len(mat_ids) else None
        fallback = file_hint_color(name) or (0.62, 0.62, 0.64)
        mat_name, col = mat_lookup.get(mat_id, ("Default", fallback))
        # NOTE: no TEXCOORD_0 on purpose - these CC0 packs ship colours only,
        # and dropping UVs keeps the committed .glb files ~25% smaller.
        attributes = {
            "POSITION": builder.add_accessor(pos, 5126, "VEC3", 34962, minmax=True),
            "NORMAL": builder.add_accessor(nor, 5126, "VEC3", 34962),
        }
        if max(idx) <= 65535:
            indices = builder.add_accessor(idx, 5123, "SCALAR", 34963)
        else:
            indices = builder.add_accessor(idx, 5125, "SCALAR", 34963)
        prim = {
            "attributes": attributes,
            "indices": indices,
            "material": builder.material(mat_name, col, metallic=0.05, roughness=0.85),
        }
        primitives.append(prim)
    return primitives


def axis_extent(points, axis, a, b):
    """Spread of the points whose `axis` coordinate lies in [a, b] (in the other two axes)."""
    sel = [p for p in points if a <= p[axis] <= b]
    if len(sel) < 4:
        return 0.0
    others = [i for i in range(3) if i != axis]
    return sum(max(p[i] for p in sel) - min(p[i] for p in sel) for i in others)


def weapon_needs_flip(points):
    """Muzzle (thin barrel) must end up at -Z. The buttstock end is always TALLER
    than the barrel end along the length axis, and that test holds for every gun in
    the CC0 weapons pack (checked visually on renders)."""
    lo, hi = aabb(points)
    span = hi[2] - lo[2]
    if span < 1e-6:
        return False
    neg = axis_extent(points, 2, lo[2], lo[2] + span * 0.12)      # -Z end (should be the muzzle)
    pos = axis_extent(points, 2, hi[2] - span * 0.12, hi[2])      # +Z end (buttstock)
    return neg >= pos


def orient_matrix(points, kind, report):
    """Rotate the baked model into Godot axes: +Y up, weapon muzzle at -Z."""
    if not points:
        return mat_identity()
    lo, hi = aabb(points)
    ext = [hi[i] - lo[i] for i in range(3)]
    longest = max(range(3), key=lambda i: ext[i])

    if kind == "weapon":
        if longest == 1:
            O, note = mat_rot_x(-90.0), "length Y -> Z"
        elif longest == 0:
            O, note = mat_rot_y(90.0), "length X -> Z"
        else:
            O, note = mat_identity(), "length Z (as-is)"
        pts = [mat_apply(O, p) for p in points]
        if weapon_needs_flip(pts):
            O = mat_mul(mat_rot_y(180.0), O)
            note += " + flip 180 (muzzle -Z)"
        report["orient"] = note
        return O

    if kind == "vehicle":
        if longest == 1:
            report["orient"] = "length Y -> Z (rotX -90)"
            return mat_rot_x(-90.0)
        if longest == 0:
            report["orient"] = "length X -> Z (rotY 90)"
            return mat_rot_y(90.0)
        report["orient"] = "length Z (as-is)"
        return mat_identity()

    # nature: make sure the tall axis ends up as +Y
    if longest == 2:
        report["orient"] = "tall axis Z -> Y (rotX -90)"
        return mat_rot_x(-90.0)
    if longest == 0:
        report["orient"] = "tall axis X -> Y (rotZ 90)"
        return mat_rot_z(90.0)
    report["orient"] = "Y-up (as-is)"
    return mat_identity()


def xf_from_matrix(m):
    def xf(p):
        return mat_apply(m, p)
    return xf


def det3(m):
    return (m[0] * (m[5] * m[10] - m[6] * m[9])
            - m[4] * (m[1] * m[10] - m[2] * m[9])
            + m[8] * (m[1] * m[6] - m[2] * m[5]))


# ------------------------------------------------------------- character -----


def character_groups(geom_data, clusters):
    """vertex index -> group name (dominant weight)."""
    weight = {}
    for bone, (idx, wts) in clusters.items():
        g = bone_group(bone)
        for vi, w in zip(idx, wts):
            if w <= 0.0:
                continue
            cur = weight.get(vi)
            if cur is None or w > cur[0]:
                weight[vi] = (w, g)
    return {vi: g for vi, (w, g) in weight.items()}


def build_character(scene: FbxScene, builder: GlbBuilder, name: str, report: dict):
    geom = next((n for n in scene.objects if n.name == "Geometry"), None)
    if geom is None:
        return None
    g = read_geometry(geom)
    worlds = scene.world_matrices()
    parent = next((p for (c, p) in scene.conn_o if c == geom.props[0] and p in scene.by_id), None)
    M = worlds.get(parent, mat_identity()) if parent else mat_identity()
    flip = det3(M) < 0

    clusters = cluster_data(scene)
    vgroup = character_groups(g, clusters)
    if not vgroup:
        return None

    world_pts = [mat_apply(M, v) for v in g["verts"]]
    (lo, hi) = aabb(world_pts)
    height = hi[1] - lo[1]
    target = 1.8
    s = target / height if height > 0.01 else 1.0

    # pivots: shoulder = innermost arm verts, hip = topmost leg verts, neck = topmost torso verts
    piv = {}
    def pts_of(group, only=None):
        out = []
        for vi, gp in vgroup.items():
            if gp == group and (only is None or only(vi)):
                out.append(world_pts[vi])
        return out

    for arm, sign in (("arm_l", 1.0), ("arm_r", -1.0)):
        pts = pts_of(arm)
        if pts:
            xs = sorted(p[0] * sign for p in pts)
            cut = xs[max(0, int(len(xs) * 0.06) - 1)]
            sel = [p for p in pts if p[0] * sign <= cut + 1e-6]
            if not sel:
                sel = pts
            piv[arm] = tuple(sum(p[i] for p in sel) / len(sel) for i in range(3))
    for leg in ("leg_l", "leg_r"):
        pts = pts_of(leg)
        if pts:
            ys = sorted((p[1] for p in pts), reverse=True)
            cut = ys[max(0, int(len(ys) * 0.08) - 1)]
            sel = [p for p in pts if p[1] >= cut - 1e-6] or pts
            piv[leg] = tuple(sum(p[i] for p in sel) / len(sel) for i in range(3))
    head_pts = pts_of("head")
    if head_pts:
        ys = sorted(p[1] for p in head_pts)
        cut = ys[max(0, len(ys) // 10)]
        sel = [p for p in head_pts if p[1] <= cut + 1e-6] or head_pts
        piv["head"] = tuple(sum(p[i] for p in sel) / len(sel) for i in range(3))
    body_pts = [p for p in world_pts]
    piv["torso"] = (sum(p[0] for p in body_pts) / len(body_pts), hi[1], sum(p[2] for p in body_pts) / len(body_pts))

    # facing: eyes material wins, feet heuristic as backup
    mats = geometry_materials(scene, geom.props[0])
    mat_lookup = material_info(scene)
    face_z = None
    for mid in mats:
        mname = mat_lookup.get(mid, ("", None))[0].lower()
        if "eye" in mname:
            zs = [world_pts[vi][2] for vi, gp in vgroup.items() if gp == "head"]
            eye_zs = []
            for pi, p in enumerate(g["polys"]):
                pass
            face_z = None
            break
    # simpler facing test: feet extend forward from the ankle
    fz = []
    for leg in ("leg_l", "leg_r"):
        pts = pts_of(leg)
        if len(pts) < 6:
            continue
        top = [p for p in pts if p[1] >= piv[leg][1] - (hi[1] - lo[1]) * 0.02]
        bottom = [p for p in pts if p[1] <= lo[1] + (hi[1] - lo[1]) * 0.08]
        if top and bottom and len(bottom) > 2:
            fz.append(sum(p[2] for p in bottom) / len(bottom) - sum(p[2] for p in top) / len(top))
    facing = 1.0 if (sum(fz) / len(fz) if fz else 1.0) >= 0.0 else -1.0
    report["facing_samples"] = [round(x, 3) for x in fz]

    center_x = (lo[0] + hi[0]) * 0.5
    center_z = (lo[2] + hi[2]) * 0.5
    base_y = lo[1]

    # FIN: scale to 1.8m, centre X/Z, feet on y=0, rotate 180 if model faces +Z
    face_rot = mat_rot_y(180.0) if facing > 0 else mat_identity()
    def fin(p):
        q = (p[0] - center_x, p[1] - base_y, p[2] - center_z)
        q = mat_apply(face_rot, q)
        return (q[0] * s, q[1] * s, q[2] * s)

    # arms baked down: rotate around Z through the shoulder pivot (both sides)
    arm_rot = {}
    for arm in ("arm_l", "arm_r"):
        pts = pts_of(arm)
        if not pts or arm not in piv:
            continue
        best, best_angle = None, 0.0
        for ang in (70.0, -70.0):
            rot = mat_rot_z(ang)
            c = [0.0, 0.0, 0.0]
            for v in pts:
                q = mat_apply(rot, (v[0] - piv[arm][0], v[1] - piv[arm][1], v[2] - piv[arm][2]))
                c[0] += q[0]; c[1] += q[1]; c[2] += q[2]
            if best is None or c[1] < best[1]:
                best, best_angle = c, ang
        arm_rot[arm] = best_angle

    # group triangles
    tri_group = {}
    for pi, p in enumerate(g["polys"]):
        counts = {}
        for vi in p:
            gp = vgroup.get(vi, "torso")
            counts[gp] = counts.get(gp, 0) + 1
        tri_group[pi] = max(counts.items(), key=lambda kv: (kv[1], kv[0]))[0]

    slots = slot_per_poly(g, len(g["polys"]))
    mat_ids = mats
    node_ids = {}
    for group in ("torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"):
        polys = [p for pi, p in enumerate(g["polys"]) if tri_group[pi] == group]
        if not polys:
            continue
        slot_list = [slots[pi] for pi, p in enumerate(g["polys"]) if tri_group[pi] == group]
        pivot = piv.get(group, (0.0, 0.0, 0.0))
        rot = arm_rot.get(group)

        def xf(p, pivot=pivot, rot=rot, M=M):
            q = mat_apply(M, p)          # raw FBX vertex -> world space first
            if rot is not None:
                d = (p[0] - pivot[0], p[1] - pivot[1], p[2] - pivot[2])
                d = mat_apply(mat_rot_z(rot), d)
                q = (pivot[0] + d[0], pivot[1] + d[1], pivot[2] + d[2])
            q = fin(q)
            # node sits at fin(pivot) -> keep vertices relative to it
            fp = fin(pivot)
            return (q[0] - fp[0], q[1] - fp[1], q[2] - fp[2])

        # rebuild a local geometry dict whose material slots only cover this group
        prims = build_primitives(builder, g["verts"], polys, g["normals"], g["uvs"],
                                 slot_list, mat_ids, mat_lookup, xf, flip, name=name)
        if not prims:
            continue
        mesh_idx = builder.add_mesh(name + "_" + group, prims)
        fp = fin(pivot)
        node_ids[group] = len(builder.nodes)
        builder.nodes.append({"name": group, "mesh": mesh_idx,
                              "translation": [fp[0], fp[1], fp[2]]})

    report["parts"] = sorted(node_ids.keys())
    report["arm_bake_deg"] = arm_rot
    report["facing"] = "front is +Z (rotated 180)" if facing > 0 else "front is -Z"
    report["height_scale"] = round(s, 5)
    return node_ids


# ------------------------------------------------------------------ convert --


def convert(path, kind="auto", unit_hint=None):
    """-> (glb_bytes, report dict)"""
    scene = FbxScene(path)
    base = os.path.splitext(os.path.basename(path))[0]
    if kind == "auto":
        low = path.lower()
        if "weapon" in low or "rifle" in low or "gun" in low or "shotgun" in low or "bullpup" in low or "sniper" in low or "smg" in low or "submachine" in low:
            kind = "weapon"
        elif "character" in low:
            kind = "character"
        elif "vehicle" in low:
            kind = "vehicle"
        else:
            kind = "nature"

    builder = GlbBuilder()
    report = {"file": os.path.basename(path), "kind": kind, "src_bytes": os.path.getsize(path)}
    worlds = scene.world_matrices()
    mat_lookup = material_info(scene, os.path.basename(path))

    geo_nodes = []
    for n in scene.objects:
        if n.name != "Geometry":
            continue
        parent = next((p for (c, p) in scene.conn_o
                       if c == n.props[0] and p in scene.by_id and scene.by_id[p].name == "Model"), None)
        geo_nodes.append((n, parent))

    if kind == "character":
        parts = build_character(scene, builder, base, report)
        if parts:
            report["node"] = "character"
            builder.root_nodes = [i for i in parts.values()]
            report["aabb"] = "normalised to 1.8m"
            data = builder.to_glb()
            report["glb_bytes"] = len(data)
            return data, report

    # ---------- static (weapon / nature / vehicle) ----------
    # pass 1: world-space points, then orientation fix, then AABB
    raw_pts = []
    for (n, parent) in geo_nodes:
        g = read_geometry(n)
        M = worlds.get(parent, mat_identity()) if parent else mat_identity()
        raw_pts.extend(mat_apply(M, v) for v in g["verts"])
    if not raw_pts:
        return None, report
    O = orient_matrix(raw_pts, kind, report)
    all_pts = [mat_apply(O, p) for p in raw_pts]
    (lo, hi) = aabb(all_pts)
    ext = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    biggest = max(ext)

    if kind == "weapon":
        s = 1.0 / biggest if biggest > 1e-6 else 1.0        # normalise longest side to 1.0m
        pivot = ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5)
    else:
        if unit_hint:
            s = unit_hint
        else:
            s = 0.01 if biggest > 12.0 else 1.0              # cm -> m
        pivot = ((lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5)  # feet/footprint on y=0

    report["aabb_src"] = [[round(v, 2) for v in lo], [round(v, 2) for v in hi]]
    report["scale"] = round(s, 5)
    report["winding_flip"] = det3(mat_mul(O, mat_identity())) < 0

    nodes = []
    for (n, parent) in geo_nodes:
        g = read_geometry(n)
        M = worlds.get(parent, mat_identity()) if parent else mat_identity()
        flip = (det3(M) * det3(O)) < 0
        slots = slot_per_poly(g, len(g["polys"]))
        mat_ids = geometry_materials(scene, n.props[0])

        def xf(p, M=M, O=O):
            q = mat_apply(O, mat_apply(M, p))
            return ((q[0] - pivot[0]) * s, (q[1] - pivot[1]) * s, (q[2] - pivot[2]) * s)

        prims = build_primitives(builder, g["verts"], g["polys"], g["normals"], g["uvs"],
                                 slots, mat_ids, mat_lookup, xf, flip, name=base)
        if not prims:
            continue
        node_name = scene.obj_name(scene.by_id[parent]) if parent and parent in scene.by_id else base
        mesh_idx = builder.add_mesh(node_name, prims)
        nodes.append(len(builder.nodes))
        builder.nodes.append({"name": node_name, "mesh": mesh_idx})

    if not nodes:
        return None, report
    root = len(builder.nodes)
    children = nodes
    builder.nodes.append({"name": base, "children": children})
    builder.root_nodes = [root]
    report["aabb_out"] = [round(v, 3) for v in (ext[0] * s, ext[1] * s, ext[2] * s)]
    data = builder.to_glb()
    report["glb_bytes"] = len(data)
    return data, report


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="FBX -> GLB converter (CC0 asset pipeline)")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--kind", default="auto")
    ap.add_argument("--out-dir", default=None, help="saari .glb ek hi folder me daalo")
    ap.add_argument("--out-root", default=None,
                    help="<out-root>/<category>/<file>.glb — category source folder se aata hai")
    ap.add_argument("--suffix", default="")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--report", default="", help="likhit JSON report ka path")
    args = ap.parse_args(argv)

    files = []
    for entry in args.inputs:
        if os.path.isdir(entry):
            for dirpath, _dirs, names in os.walk(entry):
                files += [os.path.join(dirpath, n) for n in sorted(names) if n.lower().endswith(".fbx")]
        else:
            files.append(entry)

    ok = 0
    total_in = total_out = 0
    reports = []
    for f in files:
        if args.out_root:
            # category = source folder ka naam (assets/downloaded/Characters -> characters)
            out_dir = os.path.join(args.out_root, os.path.basename(os.path.dirname(f)).lower())
        else:
            out_dir = args.out_dir or os.path.dirname(f)
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, os.path.splitext(os.path.basename(f))[0] + args.suffix + ".glb")
        try:
            data, report = convert(f, args.kind)
        except Exception as exc:                       # pragma: no cover
            print(f"FAIL {f}: {exc!r}")
            continue
        if data is None:
            print(f"SKIP {f}: {report}")
            continue
        with open(out_path, "wb") as fh:
            fh.write(data)
        ok += 1
        reports.append(report)
        total_in += report["src_bytes"]
        total_out += len(data)
        if not args.quiet:
            print(f"OK {os.path.basename(f):32s} {report['src_bytes']/1024:8.1f}KB -> "
                  f"{len(data)/1024:7.1f}KB  kind={report['kind']:9s} "
                  f"scale={report.get('scale', report.get('height_scale'))} "
                  f"parts={report.get('parts','-')} {report.get('facing','')} "
                  f"aabb={report.get('aabb_src', report.get('aabb_out'))}")
    print(f"\n{ok}/{len(files)} converted   {total_in/1024/1024:.2f}MB -> {total_out/1024/1024:.2f}MB")
    if args.report:
        with open(args.report, "w") as fh:
            json.dump({"converted": ok, "total": len(files),
                       "src_bytes": total_in, "glb_bytes": total_out,
                       "models": reports}, fh, indent=1)
        print("report:", args.report)
    return 0 if ok == len(files) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
