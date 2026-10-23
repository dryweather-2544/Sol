#!/usr/bin/env python3
"""A first-person software view of a big ship's interior, to eyeball the geometry without Godot. It builds the same boxes BigShipInterior builds
(floors, ceilings, walls cut for doors and windows, furniture, door leaves) and draws them flat-shaded, nearest last.

  python3 tools/ship_view.py meridian out.png  x,z  yaw_deg  [pitch_deg] [fov]      (yaw 0 faces the nose, positive turns left; eye 1.65 m up)
"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

import gen_big_ships as gen
from shipkit import GAP

COLOURS = {"console": (40, 48, 64), "steel": (140, 148, 158), "white": (220, 224, 230), "wood": (115, 76, 46), "linen": (204, 199, 179), "screen": (30, 190, 170),
           "crate": (128, 102, 64), "glow_teal": (60, 240, 240), "glow_green": (70, 220, 80), "glow_amber": (255, 170, 40), "glow_red": (255, 60, 40), "glass": (150, 200, 240),
           "fabric": (50, 76, 128), "carpet": (90, 46, 52), "planter": (76, 56, 38), "pipe": (153, 128, 90), "dark": (30, 33, 38), "grey_fabric": (102, 107, 115),
           "red_fabric": (140, 30, 30), "wall": (153, 163, 179), "ceiling": (107, 115, 128), "door": (128, 138, 153), "lamp_panel": (255, 247, 230)}
FLOORS = {"bridge": (36, 46, 71), "captain": (77, 51, 36), "corridor": (66, 69, 77), "quarters": (82, 69, 51), "galley": (102, 97, 92), "mess": (92, 77, 66), "medical": (140, 158, 153),
          "cargo": (56, 51, 43), "engineering": (77, 66, 46), "lab": (115, 140, 148), "armoury": (51, 43, 43), "lounge": (87, 51, 77), "greenhouse": (51, 77, 46), "workshop": (77, 71, 51),
          "ops": (41, 48, 77), "airlock": (89, 51, 46), "hangar": (61, 64, 77), "core": (87, 61, 41), "atrium": (77, 97, 71), "storage": (69, 66, 56), "brig": (77, 77, 82),
          "comms": (51, 66, 87), "observation": (56, 71, 97), "troop": (66, 71, 51)}
DOOR_H = 2.1


def boxes_for(plan):
    out = []   # (cx, cy, cz, sx, sy, sz, colour)
    fy, cy = plan.floor_y, plan.ceiling_y

    def box(c, s, col):
        if min(s) > 1e-6:
            out.append((c[0], c[1], c[2], s[0], s[1], s[2], col))

    for rid, (x, z, w, d) in plan.rooms.items():
        box((x + w / 2, fy - 0.06, z + d / 2), (w, 0.12, d), FLOORS.get(plan.kinds[rid], (80, 80, 80)))
        box((x + w / 2, cy + 0.06, z + d / 2), (w, 0.12, d), COLOURS["ceiling"])
        cols, rows = max(1, round(w / 7)), max(1, round(d / 7))
        for i in range(cols):
            for j in range(rows):
                box((x + (i + 0.5) * w / cols, cy - 0.03, z + (j + 0.5) * d / rows), (min(1.2, w / cols * 0.4), 0.05, 0.4), COLOURS["lamp_panel"])
    for p in plan.portals:
        x, z, w, d = p["rect"]
        box((x + w / 2, fy - 0.06, z + d / 2), (w, 0.12, d), FLOORS["corridor"])
        box((x + w / 2, cy + 0.06, z + d / 2), (w, 0.12, d), COLOURS["ceiling"])
        along_x = w > d
        col = COLOURS["glow_red"] if p["kind"] == "airlock_outer" else COLOURS["glow_amber"] if p["kind"] == "airlock_inner" else COLOURS["glow_teal"]
        box((x + w / 2, fy + DOOR_H - 0.05, z + d / 2), (w, 0.05, d + 0.04) if along_x else (w + 0.04, 0.05, d), col)
        if p["kind"] == "airlock_outer":
            box((x + w / 2, fy + DOOR_H / 2, z + d / 2), (w, DOOR_H, d * 0.7) if along_x else (w * 0.7, DOOR_H, d), COLOURS["door"])
        elif OPEN.get("all"):
            pass
        else:
            span = w if along_x else d
            for sgn in (-1, 1):
                off = span * 0.25 * sgn
                box((x + w / 2 + (off if along_x else 0), fy + DOOR_H / 2, z + d / 2 + (0 if along_x else off)),
                    (span * 0.5, DOOR_H, d * 0.6) if along_x else (w * 0.6, DOOR_H, span * 0.5), COLOURS["door"])
    t = GAP
    for rid, (x, z, w, d) in plan.rooms.items():
        for side in ("nose", "tail", "left", "right"):
            skin = {"nose": (x - t, z - t, w + 2 * t, t), "tail": (x - t, z + d, w + 2 * t, t), "left": (x - t, z, t, d), "right": (x + w, z, t, d)}[side]
            along_x = side in ("nose", "tail")
            holes = []
            for p in plan.portals:
                px, pz, pw, pd = p["rect"]
                if px < skin[0] + skin[2] and skin[0] < px + pw and pz < skin[1] + skin[3] and skin[1] < pz + pd:
                    lo = px if along_x else pz
                    holes.append((lo, lo + (pw if along_x else pd), fy, fy + DOOR_H, False))
            for wdw in plan.windows:
                if wdw["room"] == rid and wdw["side"] == side:
                    holes.append((wdw["center"] - wdw["width"] / 2, wdw["center"] + wdw["width"] / 2, fy + wdw["sill"], fy + wdw["sill"] + wdw["height"], True))
            holes.sort()
            run_lo = skin[0] if along_x else skin[1]
            run_hi = run_lo + (skin[2] if along_x else skin[3])
            cross_lo = skin[1] if along_x else skin[0]
            thick = skin[3] if along_x else skin[2]

            def piece(lo, hi, y0, y1, col=COLOURS["wall"], th=thick, cl=cross_lo):
                mid_a, mid_c, mid_y = (lo + hi) / 2, cl + th / 2, (y0 + y1) / 2
                if along_x:
                    box((mid_a, mid_y, mid_c), (hi - lo, y1 - y0, th), col)
                else:
                    box((mid_c, mid_y, mid_a), (th, y1 - y0, hi - lo), col)

            cursor = run_lo
            for (lo, hi, bottom, top, glass) in holes:
                lo, hi = max(lo, run_lo), min(hi, run_hi)
                if hi <= lo:
                    continue
                if lo > cursor:
                    piece(cursor, lo, fy, cy)
                if bottom > fy + 0.001:
                    piece(lo, hi, fy, bottom)
                if top < cy - 0.001:
                    piece(lo, hi, top, cy)
                if glass:
                    piece(lo, hi, bottom, top, COLOURS["glass"], thick * 0.2, cross_lo + thick * 0.4)
                cursor = max(cursor, hi)
            if cursor < run_hi:
                piece(cursor, run_hi, fy, cy)
    for f in plan.furniture:
        sx, sy, sz = f["size"]
        box((f["x"], fy + f["lift"] + sy / 2, f["z"]), (sx, sy, sz), COLOURS[f["mat"]])
    return out


FACES = [((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]), ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
         ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]), ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
         ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]), ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)])]
OPEN = {}


def render(plan, out, eye, yaw_deg, pitch_deg=0.0, fov=75.0, size=(800, 500), max_dist=60.0):
    boxes = boxes_for(plan)
    W, H = size
    f = (H / 2) / math.tan(math.radians(fov) / 2)
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    # forward = (-sin yaw, 0, -cos yaw); camera space: x right, y up, z forward
    fwd = np.array([-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
    right = np.array([math.cos(yaw), 0.0, -math.sin(yaw)])
    up = np.cross(right, fwd)
    eye = np.array(eye, float)
    polys = []
    light = np.array([0.35, 0.8, 0.45]); light /= np.linalg.norm(light)
    for (cx, cy_, cz, sx, sy, sz, col) in boxes:
        c = np.array([cx, cy_, cz]); half = np.array([sx, sy, sz]) / 2
        if np.linalg.norm(c - eye) - np.linalg.norm(half) > max_dist:
            continue
        for n, corners in FACES:
            n = np.array(n, float)
            if np.dot(n, eye - (c + n * half)) <= 0:
                continue
            pts = [c + np.array(k, float) * half for k in corners]
            cam = [np.array([np.dot(p - eye, right), np.dot(p - eye, up), np.dot(p - eye, fwd)]) for p in pts]
            if any(v[2] < 0.05 for v in cam):
                continue
            xy = [(W / 2 + f * v[0] / v[2], H / 2 - f * v[1] / v[2]) for v in cam]
            depth = np.mean([v[2] for v in cam])
            shade = 0.45 + 0.55 * max(0.0, float(np.dot(n, light)))
            colour = tuple(int(min(255, ch * shade)) for ch in col)
            if col in (COLOURS["glow_teal"], COLOURS["glow_amber"], COLOURS["glow_red"], COLOURS["screen"], COLOURS["lamp_panel"], COLOURS["glow_green"]):
                colour = col
            polys.append((depth, xy, colour))
    img = Image.new("RGB", size, (6, 8, 14))
    draw = ImageDraw.Draw(img)
    for depth, xy, colour in sorted(polys, key=lambda p: -p[0]):
        draw.polygon(xy, fill=colour)
    img.save(out)


if __name__ == "__main__":
    plan = gen.SHIPS[sys.argv[1]]()
    ex, ez = (float(v) for v in sys.argv[3].split(","))
    render(plan, sys.argv[2], (ex, plan.floor_y + 1.65, ez), float(sys.argv[4]), float(sys.argv[5]) if len(sys.argv) > 5 else 0.0, float(sys.argv[6]) if len(sys.argv) > 6 else 75.0)
