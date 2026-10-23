#!/usr/bin/env python3
"""Three orthographic point-cloud views (top, side, front) of a .gltf with a .bin next to it, to see which way a hull faces.
  python3 tools/gltf_views.py scene.gltf out.png
Prints the world bounds. Axes are the file's own (gltf: +y up, usually -z or +z forward)."""
import json, sys, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    t = np.eye(4); t[:3, 3] = n.get("translation", [0, 0, 0])
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    r = np.eye(4)
    r[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return t @ r @ np.diag(list(n.get("scale", [1, 1, 1])) + [1])


def points(path):
    g = json.load(open(path)); b = open(os.path.join(os.path.dirname(path), g["buffers"][0]["uri"]), "rb").read()
    out = []

    def walk(i, parent):
        n = g["nodes"][i]; m = parent @ node_matrix(n)
        if "mesh" in n:
            for p in g["meshes"][n["mesh"]]["primitives"]:
                a = g["accessors"][p["attributes"]["POSITION"]]; bv = g["bufferViews"][a["bufferView"]]
                off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
                stride = bv.get("byteStride", 12)
                raw = np.frombuffer(b, np.uint8, count=a["count"] * stride, offset=off).reshape(a["count"], stride)[:, :12].copy().view("<f4").reshape(-1, 3)
                out.append((m[:3, :3] @ raw.T).T + m[:3, 3])
        for c in n.get("children", []):
            walk(c, m)

    for r in g["scenes"][0]["nodes"]:
        walk(r, np.eye(4))
    return np.vstack(out)


if __name__ == "__main__":
    p = points(sys.argv[1])
    print("min", np.round(p.min(0), 2), "max", np.round(p.max(0), 2), "size", np.round(p.max(0) - p.min(0), 2))
    fig, ax = plt.subplots(1, 3, figsize=(15, 5))
    idx = np.random.default_rng(1).choice(len(p), min(len(p), 60000), replace=False)
    q = p[idx]
    for a, (i, j, name) in zip(ax, [(0, 2, "top x/z"), (2, 1, "side z/y"), (0, 1, "front x/y")]):
        a.scatter(q[:, i], q[:, j], s=0.3, c="k"); a.set_aspect("equal"); a.set_title(name)
    plt.tight_layout(); plt.savefig(sys.argv[2], dpi=70)
