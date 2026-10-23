#!/usr/bin/env python3
"""Finds each hull model's engine nozzles from its geometry and writes them in ship space (nose -z, tail +z, as FighterModel places the model).

An engine is a cluster of tail-facing surface (normal toward +z) near the very back of the hull. Output: engines.json {fighter id: [[x, y, z], ...]}.
  python3 tools/find_engines.py engines.json [sheet.png]
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fighter_eye import catalogue, triangles, render_tris


def to_ship(tris, lo, hi, size, yaw=math.pi):
    """File space -> ship space, as FighterModel does: scale to `size` by the longest side, centre, turn `yaw` about y."""
    ext = hi - lo; scale = size / max(ext); centre = (lo + hi) / 2
    p = (tris - centre) * scale
    c, s = math.cos(yaw), math.sin(yaw)
    rot = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return p @ rot.T, scale, centre


def detect(ship_tris, length):
    """ship_tris (n,3,3) in ship space. Returns [(x, y, z, area)], one per engine nozzle."""
    a, b, c = ship_tris[:, 0], ship_tris[:, 1], ship_tris[:, 2]
    n = np.cross(b - a, c - a); area = np.linalg.norm(n, axis=1) / 2
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    centroid = ship_tris.mean(1)
    # winding is not trusted: orient each normal away from the hull's middle, then keep what faces the tail
    outward = np.einsum("ij,ij->i", n, centroid - centroid.mean(0)) >= 0
    n = np.where(outward[:, None], n, -n)
    rear = (n[:, 2] > 0.55) & (area > 1e-6)
    zmax = centroid[rear, 2].max() if rear.any() else centroid[:, 2].max()
    zone = rear & (centroid[:, 2] > zmax - 0.22 * length)
    pts = centroid[zone]; w = area[zone]
    if len(pts) == 0:
        return []
    # cluster the tail-facing triangles by (x, y) distance
    radius = 0.07 * length
    order = np.argsort(-w)
    clusters = []
    for i in order:
        for cl in clusters:
            if np.hypot(pts[i, 0] - cl["x"], pts[i, 1] - cl["y"]) < radius:
                cl["idx"].append(i); tw = sum(w[j] for j in cl["idx"])
                cl["x"] = sum(pts[j, 0] * w[j] for j in cl["idx"]) / tw; cl["y"] = sum(pts[j, 1] * w[j] for j in cl["idx"]) / tw
                break
        else:
            clusters.append({"x": pts[i, 0], "y": pts[i, 1], "idx": [i]})
    out = []
    total = w.sum()
    for cl in clusters:
        ids = cl["idx"]; cw = w[ids].sum()
        z = float(np.average(pts[ids, 2], weights=w[ids]))
        zfar = float(pts[ids, 2].max())
        out.append((float(cl["x"]), float(cl["y"]), zfar, float(cw), z))
    out.sort(key=lambda e: -e[3])
    # keep clusters with a real share of the tail area and that reach (nearly) as far back as the furthest one
    best = out[0][3]; far = max(e[2] for e in out)
    keep = [e for e in out if e[3] >= 0.25 * best and e[2] > far - 0.12 * length]
    return keep


def tile(row, found, size=(450, 300), view="back"):
    tris, cols, lo, hi = triangles(os.path.join(ROOT, "assets/fighters", row["model"]))
    ext = hi - lo; scale = row["size"] / max(ext); centre = (lo + hi) / 2
    W, H = size
    fov = 40.0; f = (H / 2) / math.tan(math.radians(fov) / 2)
    span = max(ext[0] * W / H, ext[1]) * 0.6 / math.tan(math.radians(fov) / 2)
    eye = np.array([centre[0], centre[1], lo[2] - span])
    img = render_tris(tris, cols, eye, 0.0, 0.0, fov=fov, size=size)
    d = ImageDraw.Draw(img)
    for (x, y, z) in found:
        pf = np.array([-x, y, -z]) / scale + centre
        rel = pf - eye
        sx = W / 2 + f * rel[0] / rel[2]; sy = H / 2 - f * rel[1] / rel[2]
        d.ellipse((sx - 8, sy - 8, sx + 8, sy + 8), outline=(255, 40, 40), width=2)
    d.text((4, 3), "%s %s n=%d" % (row["id"], row["model"], len(found)), fill=(255, 255, 0))
    return img


def main():
    out = sys.argv[1]
    rows = catalogue(); result = {}
    tiles = []
    for fid, row in rows.items():
        tris, cols, lo, hi = triangles(os.path.join(ROOT, "assets/fighters", row["model"]))
        ship, scale, centre = to_ship(tris, lo, hi, row["size"])
        found = detect(ship, row["size"])
        result[fid] = [[round(e[0], 2), round(e[1], 2), round(e[2], 2)] for e in found]
        print(fid, result[fid], flush=True)
        if len(sys.argv) > 2:
            tiles.append(tile(row, result[fid]))
    json.dump(result, open(out, "w"), indent=1)
    if tiles:
        n = 4
        sheet = Image.new("RGB", (450 * n, 300 * math.ceil(len(tiles) / n)))
        for i, t in enumerate(tiles):
            sheet.paste(t, ((i % n) * 450, (i // n) * 300))
        base = sys.argv[2]
        half = math.ceil(len(tiles) / n / 2) * 300
        sheet.crop((0, 0, sheet.width, half)).save(base.replace(".png", "_a.png"))
        sheet.crop((0, half, sheet.width, sheet.height)).save(base.replace(".png", "_b.png"))


if __name__ == "__main__":
    main()
