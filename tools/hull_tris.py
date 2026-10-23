"""Triangles of a .gltf (external .bin) in the file's world space, plus Godot's merged-AABB (every mesh's AABB corners through its node transform)."""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gltf_views import node_matrix


def load(path):
    g = json.load(open(path)); base = os.path.dirname(path)
    bufs = [open(os.path.join(base, b["uri"]), "rb").read() for b in g["buffers"]]
    tris, boxes = [], []

    def acc(i, ncomp):
        a = g["accessors"][i]; bv = g["bufferViews"][a["bufferView"]]
        dt = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
        size = np.dtype(dt).itemsize
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", ncomp * size)
        raw = np.frombuffer(bufs[bv["buffer"]], np.uint8, count=a["count"] * stride, offset=off).reshape(a["count"], stride)[:, :ncomp * size].copy().view(dt).reshape(-1, ncomp)
        return raw, a

    def walk(i, parent):
        n = g["nodes"][i]; m = parent @ node_matrix(n)
        if "mesh" in n:
            for p in g["meshes"][n["mesh"]]["primitives"]:
                if p.get("mode", 4) != 4:
                    continue
                pos, a = acc(p["attributes"]["POSITION"], 3)
                lo, hi = np.array(a["min"]), np.array(a["max"])
                corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
                wc = (m[:3, :3] @ corners.T).T + m[:3, 3]
                boxes.append((wc.min(0), wc.max(0)))
                ids = acc(p["indices"], 1)[0].reshape(-1) if "indices" in p else np.arange(len(pos))
                w = (m[:3, :3] @ pos[ids].astype(float).T).T + m[:3, 3]
                tris.append(w.reshape(-1, 3, 3))
        for c in n.get("children", []):
            walk(c, m)

    for r in g["scenes"][g.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    lo = np.min([b[0] for b in boxes], axis=0); hi = np.max([b[1] for b in boxes], axis=0)
    return np.vstack(tris), lo, hi
