#!/usr/bin/env python3
"""Rear three-quarter views of fighters with numbered candidate nozzle clusters, to choose the real engines by eye.
  python3 tools/engine_pick.py out_prefix id [id ...]"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fighter_eye import catalogue, triangles, render_tris
from find_engines import to_ship, detect

def cam(eye, yaw, pitch):
    yw, pt = math.radians(yaw), math.radians(pitch)
    fwd = np.array([math.sin(yw) * math.cos(pt), math.sin(pt), math.cos(yw) * math.cos(pt)])
    right = np.cross(np.array([0.0, 1.0, 0.0]), fwd); right /= np.linalg.norm(right)
    up = np.cross(fwd, right)
    return fwd, right, up

def tile(row, size=(640, 420), theta=35.0, phi=22.0, extra=()):
    tris, cols, lo, hi = triangles(os.path.join(ROOT, "assets/fighters", row["model"]))
    ship, scale, centre = to_ship(tris, lo, hi, row["size"])
    cand = detect(ship, row["size"])[:9]
    ext = hi - lo
    R = max(ext) * 1.55
    th, ph = math.radians(theta), math.radians(phi)
    d = np.array([math.sin(th) * math.cos(ph), math.sin(ph), -math.cos(th) * math.cos(ph)])
    eye = centre + d * R
    yaw, pitch = -theta, -phi
    fov = 40.0
    W, H = size
    img = render_tris(tris, cols, eye, yaw, pitch, fov=fov, size=size)
    fwd, right, up = cam(eye, yaw, pitch)
    f = (H / 2) / math.tan(math.radians(fov) / 2)
    dr = ImageDraw.Draw(img)
    def proj(pship):
        pf = np.array([-pship[0], pship[1], -pship[2]]) / scale + centre
        rel = pf - eye; z = rel @ fwd
        return W / 2 + f * (rel @ right) / z, H / 2 - f * (rel @ up) / z
    for i, c in enumerate(cand):
        sx, sy = proj((c[0], c[1], c[2]))
        dr.ellipse((sx - 9, sy - 9, sx + 9, sy + 9), outline=(255, 60, 60), width=2)
        dr.text((sx + 10, sy - 6), str(i), fill=(255, 255, 80))
    dr.text((4, 3), "%s %s  (x right when seen from behind; z tail+)" % (row["id"], row["model"]), fill=(255, 255, 0))
    return img, cand

if __name__ == "__main__":
    rows = catalogue(); prefix = sys.argv[1]; ids = sys.argv[2:]
    for k in range(0, len(ids), 4):
        sheet = Image.new("RGB", (1280, 840))
        for i, fid in enumerate(ids[k:k + 4]):
            img, cand = tile(rows[fid])
            sheet.paste(img, ((i % 2) * 640, (i // 2) * 420))
            print(fid, [(j, round(c[0], 1), round(c[1], 1), round(c[2], 1), round(c[3], 2)) for j, c in enumerate(cand)])
        sheet.save("%s_%d.png" % (prefix, k // 4))
