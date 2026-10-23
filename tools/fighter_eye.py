#!/usr/bin/env python3
"""What the pilot's eye sees of the fighter's OWN hull model in the cockpit view: loads the fighter's .glb the way FighterModel does (scaled to
FighterDef.size, centred, turned half a revolution), puts a camera at the catalogue's cockpit offset looking down the nose, and draws the
back-face-culled triangles flat-shaded. Anything drawn is hull that would stand between the pilot and the cockpit interior.

  python3 tools/fighter_eye.py <fighter id | all> out.png [yaw_deg] [pitch_deg]      (all = a contact sheet of every fighter)
"""
import json
import math
import os
import re
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from gltf_views import node_matrix  # noqa: E402


def catalogue():
    text = open(os.path.join(ROOT, "src/combat/fighter_catalog.gd")).read()
    rows = {}
    for m in re.finditer(r'_make\(&"(\w+)", "([^"]+)", FighterDef\.Role\.(\w+), "([^"]+)", ([\d.]+),.*?Color\([^)]*\), Vector3\(([^)]*)\), &"(\w+)"', text):
        fid, name, role, model, size, cockpit, cid = m.groups()
        rows[fid] = dict(id=fid, name=name, role=role, model=model, size=float(size), cockpit=[float(v) for v in cockpit.split(",")], cockpit_id=cid)
    return rows


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    return json.loads(d[20:20 + jl]), d[20 + jl + 8:]


def triangles(path):
    """World-space triangles (n,3,3) in the file's space, with a flat colour each (n,3), and Godot's merged AABB of the mesh bounds."""
    j, b = read_glb(path)
    tris, cols, boxes = [], [], []

    def acc(i):
        a = j["accessors"][i]; bv = j["bufferViews"][a["bufferView"]]
        n = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        dt = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
        size = np.dtype(dt).itemsize
        stride = bv.get("byteStride", n * size)
        raw = np.frombuffer(b, np.uint8, count=a["count"] * stride, offset=off).reshape(a["count"], stride)[:, :n * size].copy().view(dt).reshape(-1, n)
        return raw, a

    def walk(i, parent):
        node = j["nodes"][i]; m = parent @ node_matrix(node)
        if "mesh" in node:
            for p in j["meshes"][node["mesh"]]["primitives"]:
                pos, a = acc(p["attributes"]["POSITION"])
                pos = pos.astype(float)
                lo, hi = np.array(a["min"]), np.array(a["max"])
                corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
                world_corners = (m[:3, :3] @ corners.T).T + m[:3, 3]
                boxes.append((world_corners.min(0), world_corners.max(0)))
                if "indices" in p:
                    ids = acc(p["indices"])[0].reshape(-1)
                    pos = pos[ids]
                w = (m[:3, :3] @ pos.T).T + m[:3, 3]
                t = w.reshape(-1, 3, 3)
                tris.append(t)
                mat = j.get("materials", [{}])[p.get("material", 0)] if j.get("materials") else {}
                f = mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.7, 0.7, 0.7])[:3]
                cols.append(np.tile(np.array(f) * 255, (len(t), 1)))
        for c in node.get("children", []):
            walk(c, m)

    for r in j["scenes"][0]["nodes"]:
        walk(r, np.eye(4))
    lo = np.min([x[0] for x in boxes], axis=0); hi = np.max([x[1] for x in boxes], axis=0)
    return np.vstack(tris), np.vstack(cols), lo, hi


def render_tris(tris, cols, eye, yaw=0.0, pitch=0.0, fov=75.0, size=(480, 300), cull=True):
    W, H = size
    f = (H / 2) / math.tan(math.radians(fov) / 2)
    yw, pt = math.radians(yaw), math.radians(pitch)
    fwd = np.array([math.sin(yw) * math.cos(pt), math.sin(pt), math.cos(yw) * math.cos(pt)])  # looks down +z (the nose), yaw turns toward +x
    right = np.cross(np.array([0.0, 1.0, 0.0]), fwd); right /= np.linalg.norm(right)
    up = np.cross(fwd, right)
    img = np.zeros((H, W, 3), np.float32); img[:] = (14, 18, 30)
    zbuf = np.full((H, W), 1e9, np.float32)
    rel = tris - np.asarray(eye)
    cam = np.stack([rel @ right, rel @ up, rel @ fwd], axis=-1)  # (n,3,3): x right, y up, z forward
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    ln = np.linalg.norm(n, axis=1, keepdims=True); n = n / np.maximum(ln, 1e-12)
    light = np.array([0.3, 0.8, -0.5]); light /= np.linalg.norm(light)
    shade = 0.35 + 0.65 * np.abs(n @ light)
    centre = tris.mean(1)
    facing = np.einsum("ij,ij->i", n, np.asarray(eye) - centre) > 0   # glTF front faces are counter-clockwise: the normal points out
    for k in range(len(tris)):
        if cull and not facing[k]:
            continue
        c = cam[k]
        if (c[:, 2] < 0.04).any():
            continue
        sx = W / 2 + f * c[:, 0] / c[:, 2]
        sy = H / 2 - f * c[:, 1] / c[:, 2]
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(W - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(H - 1, math.ceil(sy.max())))
        if x0 > x1 or y0 > y1:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
        if abs(d) < 1e-9:
            continue
        l0 = ((sy[1] - sy[2]) * (xs - sx[2]) + (sx[2] - sx[1]) * (ys - sy[2])) / d
        l1 = ((sy[2] - sy[0]) * (xs - sx[2]) + (sx[0] - sx[2]) * (ys - sy[2])) / d
        l2 = 1 - l0 - l1
        inside = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not inside.any():
            continue
        depth = 1.0 / np.maximum(l0 / c[0, 2] + l1 / c[1, 2] + l2 / c[2, 2], 1e-9)
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        ok = inside & (depth < sub)
        if ok.any():
            sub[ok] = depth[ok]
            img[y0:y1 + 1, x0:x1 + 1][ok] = cols[k] * shade[k]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def eye_in_model_space(row, lo, hi):
    """FighterModel: scale = size / longest side of the merged AABB, position = -centre*scale, holder turned PI about y. The ship-space point (x,y,z)
    maps back to the file's space as ((-x, y, -z) - position) / scale."""
    size = hi - lo
    scale = row["size"] / max(size)
    centre = (lo + hi) / 2
    cx, cy, cz = row["cockpit"]
    return np.array([-cx, cy, -cz]) / scale + centre, scale


def view(row, yaw=0.0, pitch=0.0, size=(480, 300)):
    path = os.path.join(ROOT, "assets/fighters", row["model"])
    tris, cols, lo, hi = triangles(path)
    eye, scale = eye_in_model_space(row, lo, hi)
    img = render_tris(tris, cols, eye, yaw, pitch, size=size)
    inside = bool(((eye > lo) & (eye < hi)).all())
    return img, eye, scale, inside


if __name__ == "__main__":
    rows = catalogue()
    which, out = sys.argv[1], sys.argv[2]
    yaw = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    pitch = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
    if which == "all":
        ids = list(rows)
        tiles = []
        for fid in ids:
            img, eye, scale, inside = view(rows[fid], yaw, pitch, size=(320, 200))
            d = ImageDraw.Draw(img)
            d.text((4, 3), "%s %s  eye in bounds: %s" % (fid, rows[fid]["model"], inside), fill=(255, 255, 0))
            tiles.append(img)
            print(fid, rows[fid]["model"], "eye(model)", np.round(eye, 2), "inside bbox", inside, flush=True)
        cols_n = 5
        sheet = Image.new("RGB", (320 * cols_n, 200 * math.ceil(len(tiles) / cols_n)))
        for i, t in enumerate(tiles):
            sheet.paste(t, ((i % cols_n) * 320, (i // cols_n) * 200))
        sheet.save(out)
    else:
        img, eye, scale, inside = view(rows[which], yaw, pitch)
        img.save(out)
        print(which, "eye(model)", np.round(eye, 2), "scale", round(scale, 4), "inside bbox", inside)
