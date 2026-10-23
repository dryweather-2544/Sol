"""Rear three-quarter and side views of the big-ship hulls in ship space with engine marks.  python3 tools/hull_review.py out.png [engines.json]"""
import sys, math, json, os
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from hull_tris import load
from find_engines import to_ship
from fighter_eye import render_tris
from engine_pick import cam
HULLS = {'meridian': ('cargo_spaceship', 140.0, 0.0), 'talon': ('heavy_vtol_gunship', 56.0, math.pi),
         'argent': ('space_cargo_ship_transporter', 118.0, 0.0), 'halo': ('space_cargo_transporter', 52.0, 0.0)}

def view(ship, marks, theta, phi, size=(640, 420), keep=1):
    n = len(ship)
    t = ship[::keep]
    cols = np.full((len(t), 3), 170.0)
    ext = ship.reshape(-1, 3).max(0) - ship.reshape(-1, 3).min(0)
    R = max(ext) * 1.5
    th, ph = math.radians(theta), math.radians(phi)
    eye = np.array([math.sin(th) * math.cos(ph), math.sin(ph), math.cos(th) * math.cos(ph)]) * R   # ship space, tail is +z
    yaw, pitch = 180.0 + theta, -phi
    W, H = size; fov = 40.0
    img = render_tris(t, cols, eye, yaw, pitch, fov=fov, size=size, cull=False)
    fwd, right, up = cam(eye, yaw, pitch)
    f = (H / 2) / math.tan(math.radians(fov) / 2)
    d = ImageDraw.Draw(img)
    for m in marks:
        rel = np.array(m[:3]) - eye; z = rel @ fwd
        if z <= 0: continue
        sx, sy = W / 2 + f * (rel @ right) / z, H / 2 - f * (rel @ up) / z
        d.ellipse((sx - 8, sy - 8, sx + 8, sy + 8), outline=(255, 60, 60), width=2)
        d.line((sx - 12, sy, sx + 12, sy), fill=(255, 60, 60)); d.line((sx, sy - 12, sx, sy + 12), fill=(255, 60, 60))
    return img

if __name__ == "__main__":
    out = sys.argv[1]
    marks = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}
    sheet = Image.new("RGB", (1280, 840 * 1))
    for i, (k, (d, size, yaw)) in enumerate(HULLS.items()):
        tris, lo, hi = load('assets/ships/hulls/%s/scene.gltf' % d)
        ship, s, c = to_ship(tris, lo, hi, size, yaw)
        keep = max(1, len(ship) // 25000)
        img = view(ship, marks.get(k, []), 35.0, 22.0, keep=keep)
        ImageDraw.Draw(img).text((4, 3), k, fill=(255, 255, 0))
        sheet.paste(img, ((i % 2) * 640, (i // 2) * 420))
    sheet.save(out)
