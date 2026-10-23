#!/usr/bin/env python3
"""Rear three-quarter and side views of fighters with their engine nozzles (catalogue, or an engines.json override) ringed.
  python3 tools/engine_review.py out_prefix [--json engines.json] id [id ...]"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fighter_eye import catalogue, triangles, render_tris
from engine_pick import cam
from engine_sheet import catalogue_engines

def tile(row, engines, size=(480, 320), theta=35.0, phi=22.0):
    tris, cols, lo, hi = triangles(os.path.join(ROOT, "assets/fighters", row["model"]))
    ext = hi - lo; scale = row["size"] / max(ext); centre = (lo + hi) / 2
    th, ph = math.radians(theta), math.radians(phi)
    R = max(ext) * 1.5
    eye = centre + np.array([math.sin(th) * math.cos(ph), math.sin(ph), -math.cos(th) * math.cos(ph)]) * R
    W, H = size; fov = 40.0
    img = render_tris(tris, cols, eye, -theta, -phi, fov=fov, size=size)
    fwd, right, up = cam(eye, -theta, -phi)
    f = (H / 2) / math.tan(math.radians(fov) / 2)
    d = ImageDraw.Draw(img)
    for e in engines:
        pf = np.array([-e[0], e[1], -e[2]]) / scale + centre
        rel = pf - eye; z = rel @ fwd
        sx, sy = W / 2 + f * (rel @ right) / z, H / 2 - f * (rel @ up) / z
        d.ellipse((sx - 8, sy - 8, sx + 8, sy + 8), outline=(255, 60, 60), width=2)
        d.line((sx - 12, sy, sx + 12, sy), fill=(255, 60, 60)); d.line((sx, sy - 12, sx, sy + 12), fill=(255, 60, 60))
    d.text((4, 3), "%s %s" % (row["id"], row["model"]), fill=(255, 255, 0))
    return img

if __name__ == "__main__":
    args = sys.argv[1:]; prefix = args.pop(0)
    engines = catalogue_engines()
    if args and args[0] == "--json":
        engines.update(json.load(open(args[1]))); args = args[2:]
    rows = catalogue()
    ids = args or list(rows)
    for k in range(0, len(ids), 6):
        sheet = Image.new("RGB", (1440, 640))
        for i, fid in enumerate(ids[k:k + 6]):
            sheet.paste(tile(rows[fid], engines[fid]), ((i % 3) * 480, (i // 3) * 320))
        sheet.save("%s_%d.png" % (prefix, k // 6))
