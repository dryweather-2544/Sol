#!/usr/bin/env python3
"""Contact sheet of every fighter seen from behind (the tail), with the catalogue's engine nozzles drawn as red rings, to check where the flames start.

  python3 tools/engine_sheet.py out.png [engines.json]     engines.json = {fighter id: [[x, y, z], ...]} in ship space, overriding the catalogue
"""
import json, math, os, re, sys
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fighter_eye import catalogue, triangles, render_tris


def catalogue_engines():
    text = open(os.path.join(ROOT, "src/combat/fighter_catalog.gd")).read()
    out = {}
    for m in re.finditer(r'_make\(&"(\w+)".*?\[((?:Vector3\([^)]*\),?\s*)*)\]', text):
        out[m.group(1)] = [[float(v) for v in p.split(",")] for p in re.findall(r'Vector3\(([^)]*)\)', m.group(2))]
    return out


def project(point_file, eye, fwd, f, W, H):
    rel = point_file - eye
    right = np.array([1.0, 0, 0]); up = np.array([0, 1.0, 0])
    z = rel @ fwd
    return W / 2 + f * (rel @ right) / z, H / 2 - f * (rel @ up) / z


def tile(row, engines, size=(360, 240), view="back"):
    tris, cols, lo, hi = triangles(os.path.join(ROOT, "assets/fighters", row["model"]))
    ext = hi - lo; scale = row["size"] / max(ext); centre = (lo + hi) / 2
    W, H = size
    if view == "back":
        eye = np.array([centre[0], centre[1], lo[2] - max(ext) * 1.1]); yaw = 0.0
        fwd = np.array([0, 0, 1.0])
    else:  # side from +x of the file
        eye = np.array([hi[0] + max(ext) * 1.1, centre[1], centre[2]]); yaw = -90.0
        fwd = np.array([-1.0, 0, 0])
    img = render_tris(tris, cols, eye, yaw, 0.0, fov=60.0, size=size)
    d = ImageDraw.Draw(img)
    f = (H / 2) / math.tan(math.radians(60.0) / 2)
    for e in engines:
        pf = np.array([-e[0], e[1], -e[2]]) / scale + centre
        if view == "back":
            x, y = project(pf, eye, fwd, f, W, H)
        else:
            rel = pf - eye; z = rel @ fwd; x = W / 2 - f * rel[2] / z; y = H / 2 - f * rel[1] / z
        d.ellipse((x - 7, y - 7, x + 7, y + 7), outline=(255, 40, 40), width=2)
        d.line((x - 10, y, x + 10, y), fill=(255, 40, 40)); d.line((x, y - 10, x, y + 10), fill=(255, 40, 40))
    d.text((4, 3), "%s %s" % (row["id"], row["model"]), fill=(255, 255, 0))
    return img


if __name__ == "__main__":
    out = sys.argv[1]
    rows = catalogue(); engines = catalogue_engines()
    if len(sys.argv) > 2:
        engines.update(json.load(open(sys.argv[2])))
    view = sys.argv[3] if len(sys.argv) > 3 else "back"
    ids = [i for i in rows if i in engines]
    tiles = [tile(rows[i], engines[i], view=view) for i in ids]
    n = 5
    sheet = Image.new("RGB", (360 * n, 240 * math.ceil(len(tiles) / n)))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % n) * 360, (i // n) * 240))
    sheet.save(out)
    print(len(tiles), "fighters")
